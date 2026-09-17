#include "BlockchainBackend.h"
#include "logos_api.h"
#include "logos_api_client.h"
// logos_api_client.h only forward-declares LogosObject, and the probe below has
// to destroy one. Deleting through the forward declaration compiles (with a
// warning) and silently skips the destructor, leaking the replica it wraps.
#include "logos_object.h"

#include <QByteArray>
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QPointer>
#include <QSignalBlocker>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <algorithm>

const QString BlockchainBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("blockchain_module");

void BlockchainBackend::setError(const QString& message)
{
    // If the SDK handed us the opaque no-reply string ("Call failed."), ask the
    // node's own log why, so the UI shows a real cause instead of a dead end.
    if (message.contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        if (const Rule* cause = diagnoseNode()) {
            setLastErrorMessage(tr(cause->message));
            setNodeRecovering(cause->recovering);
            // A recovering node is coming up, not broken.
            setStatus(cause->recovering ? Starting : Error);
            return;
        }
    }
    setLastErrorMessage(message);
    setNodeRecovering(false);
    setStatus(Error);
}

static QString toLocalPath(const QString& pathInput)
{
    if (pathInput.trimmed().isEmpty())
        return pathInput;
    return QUrl::fromUserInput(pathInput).toLocalFile();
}

namespace {

// How much of the log tail to scan, and how long a verdict stays good for.
constexpr qint64 kLogTailBytes = 128 * 1024;
constexpr qint64 kDiagnosisCacheMs = 2000;
constexpr int kFailuresBeforeProbe = 3;
// Start and stop share one deadline because the reasoning is the same: it is a
// bound on our own patience, not a prediction of the node's workload. The module
// services one call at a time, so a stop pressed during a replay waits for the
// start ahead of it, and a first start on a large backlog runs for as long as it
// runs.
//
// It cannot simply be "never". The SDK hands this one value to BOTH the reply
// wait and the replica acquisition, and acquisition is synchronous — against a
// module whose process is gone, an unbounded value parks this source in a nested
// event loop that cannot end. Both call sites pre-flight with moduleIsAlive(),
// which leaves the shared replica implementation valid, so in practice this
// bounds the reply only.
//
// Overrunning it is recoverable, not terminal: the module only pushes blocks
// once start() has returned and subscribed, so the block stream lands the node
// in Running by itself (see the processedBlock handler).
constexpr int kNodeCallTimeoutMs = 15 * 60 * 1000;
// Teardown gets a much shorter one: there is nobody left to tell, and holding
// the process open is worse than exiting with the node still winding down.
constexpr int kShutdownStopTimeoutMs = 30 * 1000;
constexpr int kLivenessProbeMs = 1500;
// How often to ask, while the node is meant to be up.
constexpr int kLivenessIntervalMs = 15 * 1000;
// A fall out of Online has to be confirmed; a rise does not. Mirrors the
// debounce NodeStatusMonitor applies to the same reading for the headline.
constexpr int kOfflineReadingsBeforeDrop = 3;

// How often to push uptimeSeconds, given how long the node has been up. The
// tiers mirror the smallest unit uptimeText() renders in NodeDashboardView.qml
// — seconds below an hour, minutes below a day, hours above it. Ticking faster
// than the view can show costs a QtRO property change per second, for ever,
// against a poll that deliberately backs off to one call every 12 seconds.
int uptimeTickMs(qint64 secondsUp)
{
    if (secondsUp < 60 * 60)
        return 1000;
    if (secondsUp < 24 * 60 * 60)
        return 60 * 1000;
    return 60 * 60 * 1000;
}
// The node reports Online / Bootstrapping / NotStarted in get_cryptarchia_info.
QString cryptarchiaMode(const QVariant& payload)
{
    return QJsonDocument::fromJson(payload.toString().toUtf8())
        .object()
        .value(QStringLiteral("mode"))
        .toString();
}

// Recovery rules come first so they win within a line: they mean progress, and
// the node logs them at INFO, below the severity gate the failure rules need.
using P = BlockchainBackend::RulePriority;

const BlockchainBackend::Rule kRules[] = {
    {"blocks to replay",       QT_TR_NOOP("Catching up — replaying stored blocks."),      true,  P::RootCause},
    {"Chain recovery",         QT_TR_NOOP("Catching up — replaying stored blocks."),      true,  P::RootCause},
    {"recovering chain state", QT_TR_NOOP("Catching up — replaying stored blocks."),      true,  P::RootCause},

    // Peers were reachable and dialled fine; they refused the protocol version.
    // "Can't reach the configured peers" would be flatly wrong here, and a dev
    // build whose version is still the literal placeholder hits this every time.
    {"does not support /logos-blockchain/chainsync",
                               QT_TR_NOOP("Peers rejected this node's chain-sync protocol version — the node build doesn't match the network."),
                                                                                          false, P::RootCause},
    {"Storage backend error",  QT_TR_NOOP("Chain database corrupted. Reset chain state."), false, P::RootCause},
    {"Storage request failed", QT_TR_NOOP("Chain database corrupted. Reset chain state."), false, P::RootCause},
    {"AddrInUse",              QT_TR_NOOP("Port already in use."),                        false, P::RootCause},
    {"address already in use", QT_TR_NOOP("Port already in use."),                        false, P::RootCause},
    {"failed to bind",         QT_TR_NOOP("Port already in use."),                        false, P::RootCause},
    {"No space left",          QT_TR_NOOP("Disk full."),                                  false, P::RootCause},
    {"ENOSPC",                 QT_TR_NOOP("Disk full."),                                  false, P::RootCause},
    {"missing field",          QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false, P::RootCause},
    {"failed to parse",        QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false, P::RootCause},
    {"deserialize",            QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false, P::RootCause},

    // A roll-up: it says every peer failed, not why. Beaten by any root cause.
    {"AllPeersFailed",         QT_TR_NOOP("Can't reach the configured peers."),           false, P::Summary},

    {"crashed (signal",        QT_TR_NOOP("Node crashed. Reset chain state to recover."), false, P::Consequence},
    {"panicked",               QT_TR_NOOP("Node crashed. Reset chain state to recover."), false, P::Consequence},
    {"SIGABRT",                QT_TR_NOOP("Node crashed. Reset chain state to recover."), false, P::Consequence},
    {"SIGSEGV",                QT_TR_NOOP("Node crashed. Reset chain state to recover."), false, P::Consequence},
};

// `tracing` writes the level as a bare uppercase token ("...Z ERROR target: ...").
// Failure needles are short substrings, so they are only matched against such
// lines — a routine "loaded block from storage" at INFO must not read as
// database corruption.
bool isFailureLine(const QString& line)
{
    static const QRegularExpression levelRe(
        QStringLiteral("(?:^|\\s)(?:ERROR|WARN|FATAL)(?:\\s|:)"));
    return levelRe.match(line).hasMatch();
}

} // namespace

// The module routes logs to "<persistence>/logs" while the config goes to
// "<persistence>/<output>", so the log dir is a sibling of the config only when
// the config sits at the persistence root (the default, empty-output case). A
// relative output pushes the config a level down — probe both.
QString BlockchainBackend::newestNodeLogPath() const
{
    const QString cfg = userConfig();
    if (cfg.trimmed().isEmpty())
        return {};
    const QString local = toLocalPath(cfg);
    QDir dir = QFileInfo(local.isEmpty() ? cfg : local).absoluteDir();

    // The config's own directory, then its parent. No further: an unrelated
    // "logs" higher up the tree must not be mistaken for the node's.
    QFileInfo newest;
    for (int level = 0; level < 2; ++level) {
        const QFileInfoList files = QDir(dir.filePath(QStringLiteral("logs")))
                                        .entryInfoList(QDir::Files, QDir::Time);
        if (!files.isEmpty()
            && (!newest.exists() || files.first().lastModified() > newest.lastModified()))
            newest = files.first();
        if (!dir.cdUp())
            break;
    }

    return newest.exists() ? newest.absoluteFilePath() : QString();
}

// A dead module and a busy one both surface as the same opaque "Call failed.",
// which is why a crashed node used to sit on "retrying in Ns" forever. Asking
// the transport settles it, and the two cases genuinely differ there.
//
// The mechanism is worth stating, because it is what makes this cheap AND
// correct. requestObject does not stand up an independent replica: QtRO shares
// one implementation per source name, and the event subscription taken in the
// constructor holds one for the node module's whole lifetime. So while the
// module is merely blocked inside a long start(), that implementation is still
// Valid and this returns immediately without touching the module. It only waits
// — and only up to the short timeout — once the connection has actually dropped,
// which is the answer we came for. The corollary: if that constructor-time
// subscription ever fails, this degrades into a real acquisition against a
// possibly-blocked module and can report a busy node as gone.
//
// Synchronous, hence the short timeout: it runs on the poll path.
bool BlockchainBackend::moduleIsAlive()
{
    if (!m_blockchainClient)
        return false;

    LogosObject* probe =
        m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME, Timeout(kLivenessProbeMs));
    if (!probe)
        return false;

    // release(), not delete: the handle owns a QtRO replica and an event helper
    // that are torn down in a deferred order this call knows and we do not.
    probe->release();
    return true;
}

void BlockchainBackend::declareModuleGone()
{
    m_consecutivePollFailures = 0;
    m_livenessTimer->stop();
    setNodeModuleReachable(false);
    setNodeRecovering(false);

    // Prefer the log's account of why, but only when it is not a recovery: the
    // tail says "replaying stored blocks" right up to the moment the process
    // dies, and reporting that for a dead node relabels a failure as progress.
    const Rule* cause = diagnoseNode();
    setLastErrorMessage(
        (cause && !cause->recovering)
            ? tr(cause->message)
            : tr("The node process stopped unexpectedly. Start it again."));
    setStatus(Error);
}

void BlockchainBackend::startUptime()
{
    if (m_uptime.isValid())
        return;
    m_uptime.start();
    m_offlineReadings = 0;
    setUptimeSeconds(0);
    m_uptimeTimer->start(uptimeTickMs(0));
}

void BlockchainBackend::stopUptime()
{
    m_uptimeTimer->stop();
    m_uptime.invalidate();
    m_offlineReadings = 0;
    setUptimeSeconds(0);
}

void BlockchainBackend::applyOnlineReading(bool modeOnline)
{
    if (modeOnline) {
        m_offlineReadings = 0;
        startUptime();
        return;
    }

    m_offlineReadings += 1;
    if (!m_uptime.isValid() || m_offlineReadings >= kOfflineReadingsBeforeDrop)
        stopUptime();
}

// Tail the node's newest log and map a known signature to a cause. Null when
// nothing recognisable is found (the caller then keeps the original message).
const BlockchainBackend::Rule* BlockchainBackend::scanNodeLog() const
{
    QFile f(newestNodeLogPath());
    if (f.fileName().isEmpty() || !f.open(QIODevice::ReadOnly))
        return nullptr;

    const qint64 size = f.size();
    const qint64 tail = qMin<qint64>(size, kLogTailBytes);
    if (!f.seek(size - tail))
        return nullptr;
    QByteArray buf = f.readAll();

    // A mid-file seek can land inside a multi-byte sequence; drop the partial
    // first line rather than decoding it into replacement characters.
    if (tail < size)
        buf = buf.mid(buf.indexOf('\n') + 1);

    // Once something matches, keep looking back this far for a more specific
    // verdict — the reason a node died is logged just before the crash. Bounded
    // so a stale cause from an earlier run in the same tail can't win.
    constexpr int kLookbackLines = 300;

    const QStringList lines = QString::fromUtf8(buf).split(QLatin1Char('\n'));
    const Rule* best = nullptr;
    int bestLine = -1;

    for (int i = lines.size() - 1; i >= 0; --i) {
        if (best && bestLine - i > kLookbackLines)
            break;
        const QString& line = lines.at(i);
        const bool failureLine = isFailureLine(line);
        for (const Rule& rule : kRules) {
            if (!rule.recovering && !failureLine)
                continue;
            if (!line.contains(QLatin1String(rule.needle)))
                continue;
            // Recovery means the node is coming up — but only if it is still
            // the newest word. A failure logged *after* a replay line means the
            // replay is over, and returning "catching up" for a node that has
            // since crashed turns a hard failure into a reassuring progress
            // message. A replay line is also a boundary: anything older than it
            // belongs to a previous phase, so stop rather than keep looking.
            if (rule.recovering)
                return best ? best : &rule;
            // Lower priority wins outright; newest wins within a priority,
            // which the newest-first walk already gives us.
            if (!best || rule.priority < best->priority) {
                best = &rule;
                bestLine = i;
            }
            break;
        }
        if (best && best->priority == RootCause)
            break;
    }
    return best;
}

// The node view polls getCryptarchiaInfo on a timer; without this cache every
// failed tick would re-read and re-scan the log tail.
const BlockchainBackend::Rule* BlockchainBackend::diagnoseNode() const
{
    if (m_diagnosisAge.isValid() && m_diagnosisAge.elapsed() < kDiagnosisCacheMs)
        return m_lastDiagnosis;
    m_lastDiagnosis = scanNodeLog();
    m_diagnosisAge.restart();
    return m_lastDiagnosis;
}

namespace result {

static LogosResult err(const QString& message)
{
    return LogosResult{false, QVariant(), message};
}

// Normalises a `QVariant` (e.g. from a `invokeRemoteMethod()`) call to a `LogosResult`.
//
// `invokeRemoteMethod()` might return an invalid `QVariant` when the call itself fails to get a reply (e.g.: timeout).
// This function normalises the reply for the `LogosResult` case.
static LogosResult toLogosResult(const QVariant& reply)
{
    if (!reply.isValid())
        return err(QStringLiteral("Call failed."));
    return reply.value<LogosResult>();
}

static QString toErrorMessage(const LogosResult& result)
{
    return QStringLiteral("Error: %1").arg(result.error.toString());
}

// Returns a stringified version of a `LogosResult`.
//
// Used in some places that consume the success and error properties in the same manner.
static QString toDisplayMessage(const LogosResult& result)
{
    return result.success ? result.value.toString() : toErrorMessage(result);
}

static QVariantMap toVariantMap(const LogosResult& result)
{
    return QVariantMap{
        {"success", result.success},
        {"value", result.value},
        {"error", result.error},
    };
}

} // namespace result

// Decode a base58 (Bitcoin alphabet) string to raw bytes. On an invalid
// character *ok is set to false and an empty array is returned.
static QByteArray decodeBase58(const QString& input, bool* ok)
{
    static const QByteArray kAlphabet =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    const QByteArray s = input.trimmed().toLatin1();
    QByteArray bytes; // little-endian while building, reversed at the end
    bytes.append('\0');

    for (const char c : s) {
        const int value = kAlphabet.indexOf(c);
        if (value < 0) {
            if (ok) *ok = false;
            return {};
        }
        int carry = value;
        for (int j = 0; j < bytes.size(); ++j) {
            carry += static_cast<unsigned char>(bytes[j]) * 58;
            bytes[j] = static_cast<char>(carry & 0xff);
            carry >>= 8;
        }
        while (carry > 0) {
            bytes.append(static_cast<char>(carry & 0xff));
            carry >>= 8;
        }
    }

    // Each leading '1' maps to a leading zero byte.
    for (int i = 0; i < s.size() && s[i] == '1'; ++i)
        bytes.append('\0');

    std::reverse(bytes.begin(), bytes.end());
    if (ok) *ok = true;
    return bytes;
}

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : BlockchainBackendSimpleSource(parent)
    , m_logosAPI(logosAPI)
    , m_accountsModel(new AccountsModel(this))
    , m_blockModel(new BlockModel(this))
{
    setStatus(NotStarted);
    // Nothing has contradicted it yet; only a failed probe may say otherwise.
    setNodeModuleReachable(true);
    setBlendRole(Unknown);
    setUseGeneratedConfig(false);
    setGeneratedUserConfigPath(
        QDir::currentPath() + QStringLiteral("/user_config.yaml"));

    // Restore saved config paths
    QSettings s("Logos", "BlockchainUI");
    const QString envConfigPath =
        QString::fromUtf8(qgetenv("LB_CONFIG_PATH"));
    const QString savedUserConfig =
        s.value("userConfigPath").toString();
    const QString savedDeploymentConfig =
        s.value("deploymentConfigPath").toString();

    const auto restorableOr = [](const QString& saved, const char* what) -> QString {
        if (saved.isEmpty())
            return QString();
        const QString local = toLocalPath(saved);
        if (QFile::exists(local))
            return local;
        qWarning() << "BlockchainBackend: ignoring saved" << what
                   << "- file no longer exists:" << local;
        return QString();
    };

    const QString restoredUserConfig = restorableOr(savedUserConfig, "user config");
    const QString restoredDeploymentConfig =
        restorableOr(savedDeploymentConfig, "deployment config");

    if (!envConfigPath.isEmpty())
        setUserConfig(toLocalPath(envConfigPath));
    else if (!restoredUserConfig.isEmpty())
        setUserConfig(restoredUserConfig);

    if (!restoredDeploymentConfig.isEmpty())
        setDeploymentConfig(restoredDeploymentConfig);

    // Uptime. The clock itself is driven by applyOnlineReading off the status
    // poll; this only widens the tick as the number grows, so the property is
    // never pushed faster than the view can render it.
    m_uptimeTimer = new QTimer(this);
    connect(m_uptimeTimer, &QTimer::timeout, this, [this]() {
        const qint64 secondsUp = m_uptime.elapsed() / 1000;
        setUptimeSeconds(static_cast<int>(secondsUp));
        const int next = uptimeTickMs(secondsUp);
        if (m_uptimeTimer->interval() != next)
            m_uptimeTimer->setInterval(next);
    });
    // Driven off the status transition rather than each setStatus call site, so
    // every path that leaves Running — a stop, an error, a module that vanished
    // — stops the clock without having to remember to.
    connect(this, &BlockchainBackendSimpleSource::statusChanged, this, [this]() {
        if (status() != Running)
            stopUptime();
    });

    // nodeRecovering describes a node on its way up. Any state that is not on
    // its way up has to clear it, or a node you stopped mid-replay stays at
    // Stopped while the hero keeps reporting "Bootstrapping" from the leftover
    // flag — the recovery branch outranks the stopped one.
    connect(this, &BlockchainBackendSimpleSource::statusChanged, this, [this]() {
        if (status() != Running && status() != Starting)
            setNodeRecovering(false);
    });

    // Cheap while the module is healthy — the shared replica implementation is
    // already valid, so this returns without a round trip — and only costs its
    // timeout when there is nothing there, which is exactly when we are about to
    // report it.
    m_livenessTimer = new QTimer(this);
    m_livenessTimer->setInterval(kLivenessIntervalMs);
    connect(m_livenessTimer, &QTimer::timeout, this, [this]() {
        if (!moduleIsAlive())
            declareModuleGone();
    });
    connect(this, &BlockchainBackendSimpleSource::statusChanged, this, [this]() {
        // Starting counts: start does not return until the node is fully up, so
        // a module that dies mid-replay would otherwise sit unchallenged behind
        // a headline that is only true because nothing can correct it.
        if (status() == Running || status() == Starting)
            m_livenessTimer->start();
        else
            m_livenessTimer->stop();
    });

    // Re-apply pre-.rep behavior: normalize file URLs, then persist (as master did in setters).
    connect(this, &BlockchainBackendSimpleSource::userConfigChanged, this, [this]() {
        const QString p = userConfig();
        const QString n = toLocalPath(p);
        if (n != p) {
            QSignalBlocker b(this);
            setUserConfig(n);
        }
        QSettings("Logos", "BlockchainUI")
            .setValue("userConfigPath", userConfig());
    });
    connect(this, &BlockchainBackendSimpleSource::deploymentConfigChanged, this, [this]() {
        const QString p = deploymentConfig();
        const QString n = toLocalPath(p);
        if (n != p) {
            QSignalBlocker b(this);
            setDeploymentConfig(n);
        }
        QSettings("Logos", "BlockchainUI")
            .setValue("deploymentConfigPath", deploymentConfig());
    });

    // A node that isn't running has no blend role. Acquiring one is driven from
    // getCryptarchiaInfo, which is where the readiness edge is visible.
    connect(this, &BlockchainBackendSimpleSource::statusChanged, this, [this]() {
        if (status() != Running) {
            setBlendRole(Unknown);
            clearStake();
        }
    });

    if (!m_logosAPI) {
        qWarning() << "BlockchainBackend: constructed without LogosAPI";
        return;
    }

    m_blockchainClient = m_logosAPI->getClient(BLOCKCHAIN_MODULE_NAME);
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        qWarning() << "BlockchainBackend: failed to get blockchain module client";
        return;
    }

    LogosObject* replica =
        m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME);
    if (replica) {
        m_blockchainClient->onEvent(
            replica, "newBlock",
            [this](const QString&, const QVariantList& data) {
                const QString timestamp =
                    QDateTime::currentDateTime().toString("HH:mm:ss");
                const QString raw = data.isEmpty() ? QString() : data.first().toString();
                m_blockModel->appendRaw(timestamp, raw);
            });

        // Fires per block the node *processes*, which includes the blocks it
        // applies while catching up — the phase where get_cryptarchia_info is
        // most likely to be too busy to answer. Only the arrival is consumed
        // here; the event's chain-state payload is left unparsed until its
        // schema is confirmed against the node's /cryptarchia/blocks/stream.
        m_blockchainClient->onEvent(
            replica, "processedBlock",
            [this](const QString&, const QVariantList& data) {
                // The module subscribes to this stream only after start() has
                // returned, so anything arriving on it while we still believe we
                // are Starting is proof the call finished — whatever became of
                // its reply. This is what keeps a start that outran its deadline
                // from leaving the node up and the UI stuck on "Bootstrapping".
                if (status() == Starting)
                    setStatus(Running);

                const QString raw = data.isEmpty() ? QString() : data.first().toString();
                // The stream reports its own end exactly once, as the JSON
                // literal `null`. It cannot be resubscribed without restarting
                // the node, so the silence that follows is terminal — say so
                // rather than letting it read as a slow node.
                if (raw.trimmed() == QLatin1String("null")) {
                    setBlockStreamEnded(true);
                    return;
                }
                setProcessedBlockCount(processedBlockCount() + 1);
            });
    } else {
        setError(QStringLiteral("Failed to subscribe to events"));
    }

    qDebug() << "BlockchainBackend: initialized";
}

BlockchainBackend::~BlockchainBackend()
{
    if (status() != Running && status() != Starting)
        return;
    if (!m_blockchainClient || !moduleIsAlive())
        return;

    // Synchronous, unlike stopBlockchain(). This is teardown: there is nobody
    // left to deliver a callback to, and the object is already dying, so the
    // asynchronous version's QPointer guard drops the reply and the process can
    // exit with the request still in flight — leaving the node running after the
    // app is gone. Bounded, because a wedged module must not hold up shutdown.
    m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME,
                                           QStringLiteral("stop"),
                                           QVariantList{},
                                           Timeout(kShutdownStopTimeoutMs));
}

QVariantMap BlockchainBackend::claimLeaderRewards()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "leader_claim")));
}

// Consensus time info as JSON: { slot_duration_ms, genesis_time_unix_ms,
// current_slot, current_epoch }. The node view pairs current_slot with the
// chain tip's slot to show how far behind the head the chain is.
QVariantMap BlockchainBackend::getTimeInfo()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_time_info"))));
}

// blend_info answers with JSON:
//   { "node_id": "<blend PeerId>", "core_info": null | { ... } }
void BlockchainBackend::refreshBlendRole()
{
    if (!m_blockchainClient || status() != Running)
        return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("blend_info")));
    if (!r.success)
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(r.value.toString().toUtf8());
    if (!doc.isObject())
        return;

    setBlendRole(doc.object().value(QStringLiteral("core_info")).isObject() ? Core : Edge);
}

void BlockchainBackend::clearStake()
{
    setStakeTotal(QString());
    setStakeNoteCount(0);
    setStakeAddresses({});
}

// Shaped here rather than in the view, where a renamed field would arrive as
// `undefined` instead of as a compile error. Driven from the status poll like
// refreshBlendRole — never from the processed-block callback, which would issue
// a blocking module call from inside the module's own delivery path.
void BlockchainBackend::refreshStake()
{
    if (!m_blockchainClient || status() != Running)
        return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_leader_aged_notes"), QString()));
    // Keep the last known stake on a transient failure; it is still true.
    if (!r.success)
        return;

    const QJsonObject payload =
        QJsonDocument::fromJson(r.value.toString().toUtf8()).object();
    const QJsonArray notes = payload.value(QStringLiteral("notes")).toArray();

    QStringList addresses;
    for (const QJsonValue& note : notes) {
        const QString pk =
            note.toObject().value(QStringLiteral("public_key")).toString();
        if (!pk.isEmpty() && !addresses.contains(pk))
            addresses.append(pk);
    }

    setStakeTotal(payload.value(QStringLiteral("total_value")).toString());
    setStakeNoteCount(notes.size());
    setStakeAddresses(addresses);
}

QVariantMap BlockchainBackend::getCryptarchiaInfo()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info")));
    // The node view polls this; swap the opaque no-reply string for the node's
    // real reason from its log.
    if (r.success) {
        m_consecutivePollFailures = 0;
        setNodeModuleReachable(true);
        setNodeRecovering(false);
        const bool modeOnline = cryptarchiaMode(r.value) == QLatin1String("Online");
        // One reading, two consumers: the uptime clock and the blend role. The
        // view debounces the same reading again for the headline — it has to,
        // the poll is its own — but the clock has no reason to make a round trip
        // for a verdict already in hand here.
        applyOnlineReading(modeOnline);
        if (modeOnline) {
            if (blendRole() == Unknown)
                refreshBlendRole();
            // Unlike the blend role, stake is not acquired once: it moves with
            // every epoch.
            refreshStake();
        } else {
            if (blendRole() != Unknown)
                setBlendRole(Unknown);
            // Not online means no stake: leaving the last figure up would
            // credit the node with weight it no longer has.
            clearStake();
        }
    } else if (r.error.toString().contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        const Rule* cause = diagnoseNode();
        if (cause) {
            r.error = tr(cause->message);
            setNodeRecovering(cause->recovering);
        }

        if (++m_consecutivePollFailures >= kFailuresBeforeProbe) {
            if (!moduleIsAlive()) {
                declareModuleGone();
                r.error = lastErrorMessage();
            } else {
                // The module answered, so the run of failures was a busy node,
                // not a missing one. Start the count again: without this the
                // gate only delays the first probe and then runs one on every
                // subsequent failed poll, which is what it exists to avoid.
                m_consecutivePollFailures = 0;
            }
        }
    }
    return result::toVariantMap(r);
}

QVariantMap BlockchainBackend::getBlock(QString headerIdHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_block"), headerIdHex.trimmed())));
}

QVariantMap BlockchainBackend::getTransaction(QString txHashHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_transaction"), txHashHex.trimmed())));
}

QVariantMap BlockchainBackend::findTransactionInBlocks(QString txHashHex)
{
    // Local, in-memory resolution against the blocks currently held by the
    // model. The node's get_transaction only serves mempool (pending / very
    // recently mined) transactions, so a tx copied from the blocks view — which
    // is already mined — is looked up here instead. Returns the same shape as
    // the remote calls: { success, value, ... } with block context on success.
    const QVariantMap hit = m_blockModel->findTransaction(txHashHex);
    QVariantMap out;
    out.insert("success", hit.value("found").toBool());
    out.insert("value", hit.value("value"));
    out.insert("blockId", hit.value("blockId"));
    out.insert("slot", hit.value("slot"));
    out.insert("timestamp", hit.value("timestamp"));
    if (!out.value("success").toBool())
        out.insert("error", QStringLiteral("Not in loaded blocks."));
    return out;
}

QVariantMap BlockchainBackend::getPeerId()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // Derived from the node key in the user config; available without the node
    // running.
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_peer_id"), userConfig())));
}

QVariantMap BlockchainBackend::getClaimableVouchers()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_claimable_vouchers"))));
}

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    // Before anything else, and before the long deadline below is handed to a
    // synchronous replica acquisition: settle whether there is a module there at
    // all. A gone module is reported as gone immediately rather than after a
    // quarter-hour of "Starting", and a module that came back re-arms the flag
    // that nothing else ever clears.
    if (!moduleIsAlive()) {
        declareModuleGone();
        return;
    }
    setNodeModuleReachable(true);

    // Starting now renders lastErrorMessage, so clear the previous run's.
    setLastErrorMessage(QString());
    setNodeRecovering(false);
    // The streams are resubscribed below, so last run's progress and end-of-
    // stream verdict must not carry over into this one.
    setProcessedBlockCount(0);
    setBlockStreamEnded(false);
    m_diagnosisAge.invalidate();
    setStatus(Starting);

    // Asynchronous for the same reason stop is: this parks the whole source for
    // the duration otherwise, and "the duration" here is however long the node
    // takes to replay its backlog.
    QPointer<BlockchainBackend> self(this);
    m_blockchainClient->invokeRemoteMethodAsync(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("start"),
        QVariantList{ userConfig(), deploymentConfig() },
        [self](QVariant reply) {
            if (!self)
                return;

            // A stop pressed while this was in flight is already queued behind
            // it on the module and lands next. Whatever this reply says, the
            // user is watching a stop — repainting Running (or Error) on top of
            // Stopping would flash a state nobody asked for, and the stop's own
            // reply would immediately overwrite it anyway.
            if (self->status() == Stopping)
                return;

            const LogosResult r = result::toLogosResult(reply);
            if (r.success) {
                self->setNodeRecovering(false);
                self->setStatus(Running);
                QTimer::singleShot(500, self.data(), [self]() {
                    if (self)
                        self->refreshAccounts();
                });
            } else {
                self->setError(r.error.toString());
            }
        },
        Timeout(kNodeCallTimeoutMs));
}

void BlockchainBackend::stopBlockchain()
{
    // Error is included deliberately: it's an ambiguous state where the node
    // may still be running (e.g. a request/reply call errored while the node
    // kept producing blocks). Allowing Stop from Error lets it double as a
    // reconcile so the UI can return to a known-stopped state.
    if (status() != Running && status() != Starting && status() != Error)
        return;

    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    // Same pre-flight as start, and for the same reason: the deadline below is
    // also the replica-acquisition timeout, and acquisition is synchronous.
    // Without this, stopping a node whose module has died parks this source in a
    // nested event loop for the whole deadline — from a button the crash path
    // itself puts in front of the user.
    if (!moduleIsAlive()) {
        declareModuleGone();
        return;
    }

    const BlockchainStatus previous = status();
    setStatus(Stopping);

    QPointer<BlockchainBackend> self(this);
    m_blockchainClient->invokeRemoteMethodAsync(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("stop"), QVariantList{},
        [self, previous](QVariant reply) {
            if (!self)
                return;

            const LogosResult r = result::toLogosResult(reply);
            if (r.success) {
                self->setStatus(Stopped);
            } else if (r.error.toString().contains(QStringLiteral("not running"),
                                                   Qt::CaseInsensitive)) {
                self->setStatus(Stopped);
            } else {
                // Announce the refusal and hand the node back its previous
                // state, so the hero tells the truth about what it is doing and
                // the button comes back for another try.
                emit self->stopFailed(r.error.toString());
                self->setStatus(previous);
            }
        },
        Timeout(kNodeCallTimeoutMs));
}

void BlockchainBackend::refreshAccounts()
{
    if (!m_blockchainClient) return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses"));

    if (!r.success) {
        qWarning() << "refreshAccounts: failed:" << r.error.toString();
        return;
    }

    // The SDK marshals the JSON array into a QVariantList; rely on toList()
    // rather than canConvert<QStringList>() (which is unreliable for a
    // QVariantList under Qt6), and fall back to toStringList() for the rare
    // case where the value already arrives as a QStringList.
    QStringList list;
    const QVariantList items = r.value.toList();
    if (!items.isEmpty()) {
        for (const QVariant& item : items) {
            const QString addr = item.toString();
            if (!addr.isEmpty())
                list << addr;
        }
    } else {
        list = r.value.toStringList();
    }

    qDebug() << "refreshAccounts: loaded" << list.size() << "addresses";

    m_accountsModel->setAddresses(list);

    QTimer::singleShot(0, this,
                       [this, list]() { fetchBalancesForAccounts(list); });
}

void BlockchainBackend::fetchBalancesForAccounts(const QStringList& list)
{
    if (!m_blockchainClient) return;
    for (const QString& address : list) {
        if (address.isEmpty()) continue;
        getBalance(address);
    }
}

QVariantMap BlockchainBackend::getBalance(QString addressHex)
{
    const LogosResult lr = m_blockchainClient
        ? result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
              BLOCKCHAIN_MODULE_NAME, "wallet_get_balance", addressHex))
        : result::err(QStringLiteral("Module not initialized."));

    m_accountsModel->setBalanceForAddress(
        addressHex, lr.success ? lr.value.toString() : QString());
    return result::toVariantMap(lr);
}

QVariantMap BlockchainBackend::transferFunds(
    QString fromKeyHex, QString toKeyHex, QString amountStr)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    QStringList senders{fromKeyHex};
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_transfer_funds",
        fromKeyHex, senders, toKeyHex, amountStr, QString())));
}

QVariantMap BlockchainBackend::generateConfig(
    QString outputPath, QStringList initialPeers, int netPort, int blendPort,
    QString httpAddr, QString externalAddress, bool noPublicIpCheck,
    int deploymentMode, QString deploymentConfigPath, QString statePath)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    QVariantMap normalized;

    // The output path drives persistence routing through the module's single
    // switch (use_persistence_paths), which routes output + state + storage +
    // logs under the host-provisioned per-instance dir:
    //   - empty    → omit "output"; module writes "<persistence>/user_config.yaml".
    //   - relative → pass it through; module resolves it under <persistence>.
    //   - absolute → write exactly there; no persistence routing.
    const QString rawOut = outputPath.trimmed();
    const QString localOut = rawOut.isEmpty() ? QString() : toLocalPath(rawOut);
    const QString chosenOut = !localOut.isEmpty() ? localOut : rawOut;
    const bool absoluteOut = !chosenOut.isEmpty() && QDir::isAbsolutePath(chosenOut);
    if (!rawOut.isEmpty())
        normalized.insert("output", absoluteOut ? chosenOut : rawOut);
    if (!absoluteOut)
        normalized.insert("use_persistence_paths", true);

    if (!initialPeers.isEmpty()) {
        QVariantList peersList;
        for (const QString& p : initialPeers) {
            if (!p.trimmed().isEmpty())
                peersList.append(p.trimmed());
        }
        if (!peersList.isEmpty())
            normalized.insert("initial_peers", peersList);
    }
    if (netPort > 0)
        normalized.insert("net_port", netPort);
    if (blendPort > 0)
        normalized.insert("blend_port", blendPort);
    if (!httpAddr.trimmed().isEmpty())
        normalized.insert("http_addr", httpAddr.trimmed());
    if (!externalAddress.trimmed().isEmpty())
        normalized.insert("external_address", externalAddress.trimmed());
    if (noPublicIpCheck)
        normalized.insert("no_public_ip_check", true);
    // An explicit node state dir still wins: the module leaves a pinned path
    // untouched even when use_persistence_paths routing is on.
    if (!statePath.trimmed().isEmpty())
        normalized.insert("state_path", toLocalPath(statePath.trimmed()));

    const QJsonDocument doc = QJsonDocument::fromVariant(normalized);
    const QString jsonToSend =
        QString::fromUtf8(doc.toJson(QJsonDocument::Compact));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "generate_user_config", jsonToSend)));
}

QVariantMap BlockchainBackend::getNotes(QString walletAddressHex, QString optionalTipHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_notes",
        walletAddressHex, optionalTipHex)));
}

QVariantMap BlockchainBackend::channelDepositWithNotes(
    QString channelIdHex, QStringList inputNoteIdHexes, QString metadataBase58,
    QString changePublicKeyHex, QStringList fundingPublicKeyHexes,
    QString maxTxFee, QString optionalTipHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // The metadata arrives base58-encoded; the module expects metadata_hex, so
    // decode to bytes and hex-encode. Empty stays empty (metadata is optional).
    QString metadataHex;
    if (!metadataBase58.trimmed().isEmpty()) {
        bool ok = false;
        const QByteArray bytes = decodeBase58(metadataBase58, &ok);
        if (!ok)
            return result::toVariantMap(result::err(QStringLiteral("Invalid base58 metadata.")));
        metadataHex = QString::fromLatin1(bytes.toHex());
    }

    // 7 positional args exceed the variadic invokeRemoteMethod overloads
    // (max 5), so pass them through the QVariantList form.
    QVariantList args;
    args << channelIdHex << inputNoteIdHexes << metadataHex << changePublicKeyHex
         << fundingPublicKeyHexes << maxTxFee << optionalTipHex;

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("channel_deposit_with_notes"),
        args)));
}

void BlockchainBackend::clearBlocks()
{
    m_blockModel->clear();
}

void BlockchainBackend::copyToClipboard(QString text)
{
    // The backend runs in a non-GUI ViewModuleHost subprocess, where there is
    // no QGuiApplication and accessing the clipboard segfaults. Clipboard is
    // handled QML-side (see BlockchainView.copyText); guard here so any stray
    // call is a no-op rather than a crash.
    if (!qobject_cast<QGuiApplication*>(QCoreApplication::instance())) {
        qWarning() << "copyToClipboard: no GUI application; ignoring";
        return;
    }
    if (QClipboard* clipboard = QGuiApplication::clipboard())
        clipboard->setText(text);
}
