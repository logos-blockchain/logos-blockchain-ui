#include "BlockchainBackend.h"
#include "logos_api.h"
#include "logos_api_client.h"
// logos_api_client.h only forward-declares LogosObject, and the probe below has
// to destroy one. Deleting through the forward declaration compiles (with a
// warning) and silently skips the destructor, leaking the replica it wraps.
#include "logos_object.h"
// TODO(logos-co/logos-liblogos#219): the library liblogos uses for the same
// numbers. Linked here only because liblogos does not expose them to modules.
#include <process_stats/process_stats.h>

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
#include <QDirIterator>
#include <QSettings>
#include <QPointer>
#include <QSignalBlocker>
#include <QStorageInfo>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <algorithm>

const QString BlockchainBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("blockchain_module");
const QString BlockchainBackend::MODULES_STATE_MODULE_NAME =
    QStringLiteral("modules_state");

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
// One LOGOS is 10^9 lepta. The node publishes no denomination, so this scale is
// the app's assertion — kept in step with DECIMALS in qml/Units.js, which
// converts the other way.
constexpr int kLgoDecimals = 9;
constexpr auto kMaxLepta = "18446744073709551615"; // u64, as the wire carries it

// Canonical LOGOS ("1.5", as qml/Units.js normalizeInput leaves it) to lepta.
// All string work: the result can exceed what a double holds exactly, and
// scaling through one would move the user's money. Returns false with a reason
// rather than truncating an over-precise figure.
bool leptaFromLgo(const QString& canonical, QString* lepta, QString* error)
{
    const QString text = canonical.trimmed();
    static const QRegularExpression shape(QStringLiteral("^[0-9]*\\.?[0-9]*$"));
    if (text.isEmpty() || text == QStringLiteral(".") || !shape.match(text).hasMatch()) {
        *error = QObject::tr("Enter an amount in LGO, for example 1.5.");
        return false;
    }

    const int dot = text.indexOf(QLatin1Char('.'));
    const QString whole = (dot < 0) ? text : text.left(dot);
    const QString frac = (dot < 0) ? QString() : text.mid(dot + 1);
    if (frac.size() > kLgoDecimals) {
        *error = QObject::tr("LGO has at most %1 decimals.").arg(kLgoDecimals);
        return false;
    }

    QString digits = whole + frac + QString(kLgoDecimals - frac.size(), QLatin1Char('0'));
    qsizetype first = 0;
    while (first + 1 < digits.size() && digits.at(first) == QLatin1Char('0'))
        ++first;
    digits = digits.mid(first);

    // Wider than a double, so compare as text: length first, then lexically.
    const QLatin1String maxLepta(kMaxLepta);
    if (digits.size() > maxLepta.size()
        || (digits.size() == maxLepta.size() && digits > maxLepta)) {
        *error = QObject::tr("That is more LGO than can exist.");
        return false;
    }

    *lepta = digits;
    return true;
}
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
// How often the node's data directory is walked. Slower than the status poll by
// an order of magnitude: the walk touches every file the chain db holds, and
// disk moves slowly enough that a 20-second figure is never misleading.
constexpr int kDiskSampleIntervalMs = 20 * 1000;
// The PID lookup runs on the status-poll path, so it gets a short deadline and
// a small number of attempts: modules_state is either there or it is not, and
// two tiles must never cost the dashboard its responsiveness.
constexpr int kPidLookupTimeoutMs = 1500;
constexpr int kPidLookupAttempts = 3;
// A stop pressed while the node is already Running has nothing queued ahead of
// it — the start it would have waited for has already returned. Only a stop
// pressed during Starting can be stuck behind a replay, and only that one needs
// the long deadline. Giving both the 15-minute one left the button dead and
// silent for a quarter of an hour on a node that was merely refusing.
constexpr int kStopWhenRunningTimeoutMs = 60 * 1000;
// How long the claimable count may climb without ever falling before we call
// claiming stalled. The node's auto-claim ticker defaults to 300s and a ticket's
// reward window is the same 300 slots, so one missed tick is already a
// generation of tickets lost; this is that period plus a minute of slack, and
// short enough to warn while the next generation can still be saved.
//
// Both numbers are the node's and neither is readable from here yet — see the
// pow_status() request — so this is a floor, not a derivation.
constexpr qint64 kClaimStallMs = 360 * 1000;
// Floor between balance re-reads. One auto-claim drain settles many claims back
// to back; re-reading every key for each would be dozens of blocking calls.
constexpr qint64 kBalanceRefreshMinMs = 30 * 1000;
// How long the claimable count may sit perfectly still before PoW is called
// idle. Two background poll intervals: at any real mining rate the count moves
// by hundreds between readings, so a genuinely unchanged figure means the search
// is not running rather than that we looked at an unlucky moment.
constexpr qint64 kPowIdleMs = 60 * 1000;
constexpr int kLivenessProbeMs = 1500;
// One missed probe means nothing. The probe is free while the shared replica
// implementation is Valid, but when it is not it degrades into a real
// acquisition against a module that may simply be busy — a node replaying tens
// of thousands of blocks will not answer inside the probe timeout. Three misses
// in a row is the same shape as kOfflineReadingsBeforeDrop below: believe good
// news at once, make bad news prove itself.
constexpr int kLivenessMissesBeforeGone = 3;
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

// Hex as the node writes it: lower case, no 0x. Claim beneficiaries arrive from
// block JSON and known addresses from the wallet, so both are normalised before
// being compared.
QString normalizeHex(const QString& hex)
{
    QString out = hex.trimmed();
    if (out.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive))
        out = out.mid(2);
    return out.toLower();
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

// The case moduleIsAlive() cannot settle: a module buried under a block replay
// answers nothing — not the poll, not the probe — while its process is plainly
// alive and writing hundreds of log lines a second. The transport says gone and
// the filesystem says working, and the filesystem is right.
//
// Only a *fresh* write counts. A dead node leaves its last log file behind, so
// the mtime has to have moved since we last looked; the reading is seeded when
// the node starts so the first verdict has a baseline to compare against.
bool BlockchainBackend::nodeLogAdvanced()
{
    const QString path = newestNodeLogPath();
    if (path.isEmpty())
        return false;

    const QDateTime written = QFileInfo(path).lastModified();
    if (!written.isValid())
        return false;

    const bool advanced = m_lastNodeLogWrite.isValid() && written > m_lastNodeLogWrite;
    m_lastNodeLogWrite = written;
    return advanced;
}

void BlockchainBackend::declareModuleGone()
{
    m_consecutivePollFailures = 0;
    m_livenessMisses = 0;
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

} // namespace result

// A failed call the transport could actually diagnose. The codes are the
// canonical ones from logos_call_error.h; the message underneath them names the
// module and the method, which is worth keeping because none of this reaches the
// node — there is nothing in its log to cross-reference.
static QString describeCallError(const logos::CallError& error)
{
    const QString detail = QString::fromStdString(error.message);
    const QString code = QString::fromStdString(error.code);

    if (code == QLatin1String("timeout"))
        return QObject::tr("The node module did not answer in time. It is most likely busy "
                           "replaying blocks — the reading will come back on its own.");
    if (code == QLatin1String("object_unavailable"))
        return QObject::tr("The node module is not reachable. Its process may have stopped.");
    if (code == QLatin1String("transport_error"))
        return QObject::tr("The connection to the node module failed: %1").arg(detail);
    if (code == QLatin1String("unauthorized"))
        return QObject::tr("The node module refused the call: %1").arg(detail);
    if (code == QLatin1String("dispatch_failed"))
        return QObject::tr("The node module could not dispatch the call: %1").arg(detail);
    // call_failed, and anything added to the vocabulary later. The detail still
    // names the module and method, which beats the bare code.
    return detail.isEmpty() ? QObject::tr("The call failed for an unreported reason.")
                            : QObject::tr("The call failed: %1").arg(detail);
}

namespace result {

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
    clearNetwork();
    // TODO(logos-co/logos-liblogos#219). -1, not 0: the first CPU sample of a
    // PID has nothing to diff against and reads 0.0, and an idle-looking node is
    // a worse lie than an empty tile. Core count is fixed for the process.
    setNodeCpuPercent(-1.0);
    setNodeMemoryMb(-1.0);
    setNodeDiskUsedMb(-1.0);
    setNodeDiskFreeMb(-1.0);
    setCpuCount(QThread::idealThreadCount());
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
        if (moduleIsAlive()) {
            m_livenessMisses = 0;
            return;
        }
        // A missed probe is not a verdict. Only a run of them is, and even then
        // only if no block has arrived to contradict it in the meantime — see
        // countPowClaims' sibling below, where the block stream resets this.
        if (++m_livenessMisses < kLivenessMissesBeforeGone) {
            qWarning() << "liveness: probe missed" << m_livenessMisses << "of"
                       << kLivenessMissesBeforeGone << "- the module may just be busy";
            return;
        }
        // Last word before the verdict: a log that is still growing outranks a
        // run of missed probes, because it is evidence about the process rather
        // than about the transport. Start the run again so a node that really
        // does die still has to be caught, just one more round later.
        if (nodeLogAdvanced()) {
            qWarning() << "liveness: probes missed but the node log is still growing"
                       << "- treating the module as busy, not gone";
            m_livenessMisses = 0;
            return;
        }
        declareModuleGone();
    });
    connect(this, &BlockchainBackendSimpleSource::statusChanged, this, [this]() {
        // Starting counts: start does not return until the node is fully up, so
        // a module that dies mid-replay would otherwise sit unchallenged behind
        // a headline that is only true because nothing can correct it.
        if (status() == Running || status() == Starting) {
            // A fresh run of probes for a fresh run of the node: misses carried
            // over from the last one would count towards this one's verdict.
            m_livenessMisses = 0;
            m_livenessTimer->start();
        } else {
            m_livenessTimer->stop();
        }
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
        // A different config means different keys and different jobs for them.
        refreshAccountRoles();
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
            clearNetwork();
            setChainId(QString());
            // The sampler only runs from the status poll, so leaving these up
            // would freeze the last reading on screen and present it as live —
            // the same trap the network counters fell into. Disk is deliberately
            // left alone: it describes a directory, which outlives the node.
            setNodeCpuPercent(-1.0);
            setNodeMemoryMb(-1.0);
            m_cpuSampledOnce = false;
            // The node does not persist mining: stopping it, or losing it,
            // leaves mining off
            setMiningRequested(false);
            // Auto-claim is not persisted either.
            setAutoClaimRunning(false);
        }
    });

    // The block model parses every incoming block already, so it reports the
    // claims it sees rather than making us walk the same payload twice.
    connect(m_blockModel, &BlockModel::powClaimsFound,
            this, &BlockchainBackend::countPowClaims);

    if (!m_logosAPI) {
        qWarning() << "BlockchainBackend: constructed without LogosAPI";
        return;
    }

    m_blockchainClient = m_logosAPI->getClient(BLOCKCHAIN_MODULE_NAME);

    // Fires as soon as it is switched on, not one interval later: opening the
    // Mining tab used to show the previous visit's number for five seconds with
    // nothing marking it as stale.
    m_claimablePollTimer = new QTimer(this);
    m_claimablePollTimer->setInterval(5000);
    connect(m_claimablePollTimer, &QTimer::timeout, this,
            &BlockchainBackend::pollClaimableRewards);
    // Two reasons to poll, and they are not the same reason. Someone watching the
    // Mining tab wants a live number; a mining node needs watching whether anyone
    // is looking or not, because the stall this feeds is a thing you want to be
    // told about, not a thing you have to go and check. The background cadence is
    // slower because a stall is measured in minutes.
    auto syncClaimablePolling = [this]() {
        const bool watching = claimablePollActive();
        const bool wanted = watching || miningRequested();
        if (!wanted) {
            m_claimablePollTimer->stop();
            // Nothing is producing tickets, so a count that stopped falling says
            // nothing. Leaving the flags up would strand them on screen.
            setClaimsStalled(false);
            setPowActive(false);
            return;
        }

        m_claimablePollTimer->setInterval(watching ? 5000 : 30000);
        if (!m_claimablePollTimer->isActive())
            pollClaimableRewards();
        m_claimablePollTimer->start();
    };
    connect(this, &BlockchainBackendSimpleSource::claimablePollActiveChanged, this,
            syncClaimablePolling);
    connect(this, &BlockchainBackendSimpleSource::miningRequestedChanged, this, syncClaimablePolling);

    // The restored config was set before this client existed and before the
    // handler above was connected, so neither fired for it. Everything needed
    // is in place now.
    refreshAccountRoles();
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        qWarning() << "BlockchainBackend: failed to get blockchain module client";
        return;
    }

    // TODO(logos-co/logos-liblogos#219): for the node module's PID, nothing else.
    // A missing modules_state costs the CPU and memory tiles and nothing more,
    // so it warns rather than setError()ing the whole backend.
    m_modulesStateClient = m_logosAPI->getClient(MODULES_STATE_MODULE_NAME);
    if (!m_modulesStateClient)
        qWarning() << "BlockchainBackend: no modules_state client; "
                      "CPU and memory will read as unavailable";

    LogosObject* replica =
        m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME);
    if (replica) {

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
                // A module pushing blocks is alive, whatever the liveness probe
                // makes of it. The probe can only ask the transport; this is the
                // module itself doing work, so it outranks a missed probe and
                // clears the run before it can reach a verdict.
                //
                // Both runs, not just the timer's: the poll path reaches the
                // same declareModuleGone() from its own counter, so leaving that
                // one standing lets a busy node be condemned by the poll while
                // the blocks that disprove it are still arriving.
                m_livenessMisses = 0;
                m_consecutivePollFailures = 0;
                setProcessedBlockCount(processedBlockCount() + 1);

                // The blocks themselves, from this stream rather than newBlock.
                // Same underlying subscription and the same storage read, so
                // nothing arrives later — but this one drops a lagged item and
                // carries on where newBlock's reader exits its loop for good,
                // which is why the Blocks view used to freeze partway through
                // every initial sync and only a node restart brought it back.
                // It also announces its own end, which newBlock never did.
                m_blockModel->appendRaw(
                    QDateTime::currentDateTime().toString("HH:mm:ss"), raw);
            });
    } else {
        setError(QStringLiteral("Failed to subscribe to events"));
    }

    setClaimStallSeconds(static_cast<int>(kClaimStallMs / 1000));

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

// Whether a reading taken a moment ago still describes a running node.
bool BlockchainBackend::stillRunning() const
{
    return status() == Running;
}

// blend_info answers with JSON:
//   { "node_id": "<blend PeerId>", "core_info": null | { ... } }
void BlockchainBackend::refreshBlendRole()
{
    if (!m_blockchainClient || status() != Running)
        return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("blend_info")));
    if (!r.success || !stillRunning())
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(r.value.toString().toUtf8());
    if (!doc.isObject())
        return;

    setBlendRole(doc.object().value(QStringLiteral("core_info")).isObject() ? Core : Edge);
}

void BlockchainBackend::clearNetwork()
{
    setPeerCount(-1);
    setConnectionCount(-1);
}

// get_network_info answers with JSON:
//   { n_peers, n_connections, n_pending_connections, n_discovered_peers }
// Peers and connections are not the same count — one peer can hold several
// connections — so both are reported rather than collapsed into one number
void BlockchainBackend::refreshNetwork()
{
    if (!m_blockchainClient || status() != Running)
        return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_network_info")));
    if (!r.success || !stillRunning())
        return;

    const QJsonObject payload =
        QJsonDocument::fromJson(r.value.toString().toUtf8()).object();
    setPeerCount(payload.value(QStringLiteral("n_peers")).toInt(-1));
    setConnectionCount(payload.value(QStringLiteral("n_connections")).toInt(-1));
}

// TODO(logos-co/logos-liblogos#219): delete this pair once liblogos publishes
// per-module stats to modules. It already computes them — logos_core_get_module_stats
// feeds Basecamp's Core Inspector — but only a host can call that, and this
// backend is a module. So the PID comes from modules_state, and process-stats
// (the library behind that host API) turns it into the same numbers, which is
// what keeps this tile and the inspector from disagreeing.
//
// The PID belongs to the module's PROCESS: it survives a node stop/start and
// only changes if the module itself is reloaded. Resolved on demand, not polled.
//
// modules_state is deliberately NOT in metadata.json's dependencies, even
// though this calls it. liblogos bundles it as a built-in (flake.nix:118-122,
// beside capability_module), so it is always loaded — and declaring it makes
// mkStandaloneApp try to install it a second time over the read-only copy it
// already made of the host's modules, which fails the standalone build outright.
// The cost of leaving it undeclared: under `--access-policy enforce` this call
// is denied and the two tiles read as unavailable. Enforcement is off by
// default, and the whole path is temporary.
void BlockchainBackend::resolveNodePid()
{
    if (!m_modulesStateClient)
        return;

    // Deliberately NOT result::toLogosResult: that casts the reply to
    // LogosResult, which is only correct for modules whose methods return one.
    // blockchain_module does; modules_state answers with the ModuleRecord
    // itself. The cast on a record yields a default-constructed — and therefore
    // failed — result, so the PID never arrives and both tiles read as
    // unavailable for ever, with the node perfectly healthy behind them.
    // Short timeout, and it gives up after a few tries. Both matter: this runs
    // on the status-poll path, so an unreachable modules_state would otherwise
    // stall every poll for the default 20 seconds — costing the whole dashboard
    // to light two tiles.
    const QVariant reply = m_modulesStateClient->invokeRemoteMethod(
        MODULES_STATE_MODULE_NAME, QStringLiteral("module_record"),
        QVariantList{BLOCKCHAIN_MODULE_NAME}, Timeout(kPidLookupTimeoutMs));
    if (!reply.isValid()) {
        if (++m_pidLookupFailures >= kPidLookupAttempts)
            qWarning() << "BlockchainBackend: modules_state.module_record got no reply after"
                       << kPidLookupAttempts << "tries; CPU and memory stay unavailable";
        return;
    }

    // The record arrives either already decoded into a map, or as the JSON the
    // wire format carries (recToWire_ModulesState_ModuleRecord builds an object
    // with a "pid" key). Accept both rather than betting on one.
    QVariantMap record = reply.toMap();
    if (record.isEmpty())
        record = QJsonDocument::fromJson(reply.toString().toUtf8()).object().toVariantMap();

    const qint64 pid = record.value(QStringLiteral("pid")).toLongLong();
    if (pid <= 0) {
        // Says what came back, so the next shape surprise is diagnosed from the
        // log rather than guessed at.
        if (++m_pidLookupFailures >= kPidLookupAttempts)
            qWarning() << "BlockchainBackend: no PID in the modules_state record for"
                       << BLOCKCHAIN_MODULE_NAME << "— reply type" << reply.typeName()
                       << "payload" << reply.toString().left(200);
        return;
    }
    m_nodePid = pid;
    m_pidLookupFailures = 0;
}

// The node's data directory: where its chain db, state and logs live. Derived
// from the config path the same way newestNodeLogPath derives the log dir — the
// config's own directory, then its parent, and no further, so an unrelated tree
// higher up cannot be mistaken for the node's.
//
// Unlike CPU and memory this is NOT covered by liblogos-co#219: nothing in the
// stack measures disk, so this stays after that lands.
QString BlockchainBackend::nodeDataDir() const
{
    const QString cfg = userConfig();
    if (cfg.trimmed().isEmpty())
        return {};
    const QString local = toLocalPath(cfg);
    QDir dir = QFileInfo(local.isEmpty() ? cfg : local).absoluteDir();

    for (int level = 0; level < 2; ++level) {
        // "db" is the node's own name for its storage dir; the other two are
        // its siblings. Any one of them identifies the base.
        for (const QString& marker : {QStringLiteral("db"), QStringLiteral("state"),
                                      QStringLiteral("logs")}) {
            if (dir.exists(marker))
                return dir.absolutePath();
        }
        if (!dir.cdUp())
            break;
    }
    return {};
}

// Apparent size, summed recursively. Not `du`: that reports blocks allocated,
// which differs on a compressing filesystem, and the figure here is meant to
// answer "how much is this node keeping" rather than to reconcile with df.
void BlockchainBackend::refreshDiskUsage()
{
    // The walk is the expensive part — thousands of SST files on a long chain —
    // so it runs on its own slow cadence rather than every status poll.
    if (m_diskSampled.isValid() && m_diskSampled.elapsed() < kDiskSampleIntervalMs)
        return;

    const QString base = nodeDataDir();
    if (base.isEmpty()) {
        setNodeDiskUsedMb(-1.0);
        setNodeDiskFreeMb(-1.0);
        return;
    }
    m_diskSampled.restart();

    qint64 total = 0;
    QDirIterator it(base, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        total += it.fileInfo().size();
    }
    setNodeDiskUsedMb(static_cast<double>(total) / (1024.0 * 1024.0));

    // Free space is the number that matters: running out does not slow the node
    // down, it corrupts the chain db (see the "Storage backend error" rule).
    const QStorageInfo storage(base);
    setNodeDiskFreeMb(storage.isValid()
                          ? static_cast<double>(storage.bytesAvailable()) / (1024.0 * 1024.0)
                          : -1.0);
}

void BlockchainBackend::refreshResourceUsage()
{
    if (m_nodePid <= 0) {
        // Stop asking once it is clearly not coming. Without this the poll pays
        // a failed IPC round trip every two seconds, for ever.
        if (m_pidLookupFailures >= kPidLookupAttempts)
            return;
        resolveNodePid();
        if (m_nodePid <= 0)
            return; // Tiles stay at "no sample"; the log says why.
    }

    const ProcessStats::ProcessStatsData s = ProcessStats::getProcessStats(m_nodePid);

    // Everything reads zero when the PID is gone — a module that was reloaded
    // under us. Re-resolve once rather than reporting an idle node for ever.
    if (s.memoryMB <= 0.0 && s.cpuTimeSeconds <= 0.0) {
        m_nodePid = 0;
        return;
    }

    setNodeMemoryMb(s.memoryMB);

    // cpuPercent is a delta against the previous sample of this PID, so the
    // very first one is structurally 0.0 and means "not measured yet" rather
    // than "idle". Track that we have taken one instead of inferring it from
    // the value: keying off `> 0.0` would hold an idle node at "—" for ever,
    // since a node doing nothing reports a genuine 0.0 on every sample.
    if (m_cpuSampledOnce)
        setNodeCpuPercent(s.cpuPercent);
    m_cpuSampledOnce = true;
}

// get_chain_id answers with a bare string — the only module call here that is
// not JSON, so do not reach for QJsonDocument on the way out.
void BlockchainBackend::refreshChainId()
{
    if (!m_blockchainClient || status() != Running || !chainId().isEmpty())
        return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_chain_id")));
    if (!r.success || !stillRunning())
        return;

    setChainId(r.value.toString().trimmed());
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
    // Keep the last known stake on a transient failure; it is still true. A stop
    // that landed mid-call is the opposite case — the stake was cleared on the
    // way out of Running and must stay cleared.
    if (!r.success || !stillRunning())
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
        // Everything below describes a running node, and this call blocked in a
        // nested event loop long enough for the node to have been stopped inside
        // it (see stillRunning). applyOnlineReading is the one that bites: fed a
        // stale "Online" it restarts the uptime clock that statusChanged just
        // stopped, and a stopped node sits there counting up.
        //
        // Skipping the else branch is safe — statusChanged clears the blend role
        // and the stake on the way out of Running, which is the same work.
        if (stillRunning()) {
            // One reading, two consumers: the uptime clock and the blend role. The
            // view debounces the same reading again for the headline — it has to,
            // the poll is its own — but the clock has no reason to make a round trip
            // for a verdict already in hand here.
            applyOnlineReading(modeOnline);
            refreshNetwork();
            refreshChainId();
            // TODO(logos-co/logos-liblogos#219). Rides the status poll rather
            // than owning a timer: the poll's cadence is already what the tiles
            // render at, and the sample is a local syscall, not a module call —
            // it cannot block on a busy node the way the calls above can.
            refreshResourceUsage();
            refreshDiskUsage();
            if (modeOnline) {
                refreshBalancesIfStale();
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
        }
    } else if (r.error.toString().contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        const Rule* cause = diagnoseNode();
        if (cause) {
            r.error = tr(cause->message);
            setNodeRecovering(cause->recovering);
        }

        if (++m_consecutivePollFailures >= kFailuresBeforeProbe) {
            if (!moduleIsAlive() && !nodeLogAdvanced()) {
                declareModuleGone();
                r.error = lastErrorMessage();
            } else {
                // Either the module answered or its log is still growing, so
                // the run of failures was a busy node, not a missing one. Start
                // the count again: without this the gate only delays the first
                // probe and then runs one on every subsequent failed poll,
                // which is what it exists to avoid.
                m_consecutivePollFailures = 0;
            }
        }
    }
    return result::toVariantMap(r);
}

// Mining is a fire-and-forget toggle with no readback, so `mining` only moves
// when the node accepts the call. A failed start therefore leaves the button
// offering Fund again rather than lying about what the node is doing.
QVariantMap BlockchainBackend::powStartMining()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_start_mining")));
    if (r.success) {
        setMiningRequested(true);
        // The tickets this run mines are the ones the stall watch is about, and
        // the previous run's backlog must not count against it.
        restartClaimStallWatch();
    }
    return result::toVariantMap(r);
}

QVariantMap BlockchainBackend::powStopMining()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_stop_mining")));
    if (r.success)
        setMiningRequested(false);
    return result::toVariantMap(r);
}

// Polled by the mining view. Left as a plain call rather than a pushed property
// because the count moves thousands of times a second while mining, and the view
// is the only thing that knows how often it can usefully redraw.
QVariantMap BlockchainBackend::powClaimableRewards()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_claimable_rewards"))));
}

// An empty address pays whichever auto-claim target is furthest below its
// threshold — the same choice auto-claim itself makes, and the right default
// when the operator has not picked one.
QVariantMap BlockchainBackend::powClaim(QString claimAddressHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const QVariantMap reply = result::toVariantMap(result::toLogosResult(
        m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_claim"), claimAddressHex.trimmed())));

    // The count has moved either way — a claim can fail after consuming tickets
    // — and waiting a full interval makes a successful claim look inert.
    if (claimablePollActive())
        pollClaimableRewards();

    return reply;
}

// Like mining, these only move the flag when the node accepts the call, so a
// refused toggle leaves the switch showing what the node is actually doing.
QVariantMap BlockchainBackend::powStartAutoClaim()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_start_auto_claim")));
    if (r.success)
        setAutoClaimRunning(true);
    return result::toVariantMap(r);
}

QVariantMap BlockchainBackend::powStopAutoClaim()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_stop_auto_claim")));
    if (r.success)
        setAutoClaimRunning(false);
    return result::toVariantMap(r);
}

// Claims are counted from blocks, because a claim transaction is the only place
// a settled PoW reward is visible: pow_claimable_rewards reports tickets waiting
// to be claimed, not ones already paid. Blocks carry every node's claims, so
// only transactions paying a key this wallet tracks are ours — and auto-claim
// picks whichever of our keys is furthest below its threshold, so the payee is
// not fixed and the whole known set has to be matched.
//
// A claim transaction pays one address, so matching any of its payout keys
// makes the whole batch ours.
void BlockchainBackend::countPowClaims(
    const QStringList& payoutKeys, int claimCount, quint64 lepta)
{
    if (m_knownAddresses.isEmpty() || claimCount <= 0)
        return;

    for (const QString& payoutKey : payoutKeys) {
        if (m_knownAddresses.contains(normalizeHex(payoutKey))) {
            setPowRewardsClaimed(powRewardsClaimed() + claimCount);
            m_powRewardsLepta += lepta;
            setPowRewardsLepta(QString::number(m_powRewardsLepta));
            // Tokens just landed on a key we track, so the cached balances — and
            // walletFunded with them — are now wrong.
            refreshBalancesIfStale();
            return;
        }
    }
}

// Wallet keys from the config file, with the jobs that config gives each one.
// From the file rather than the wallet because this also answers before a node
// exists — wallet_get_known_addresses needs a live one. The module reports each
// job as its own field and one key often holds several, so the cross-reference
// is resolved here rather than by every view that wants it.
//
// Key titles, from the module's one keystore-reading call. Public half only.
//
// Optional by design: titles are decoration, and the keystore is expected to
// become password-protected. A failure here is not reported — every caller
// renders without titles, falling back to the config's roles and then to the
// address itself. When the file locks, the labels quietly stop appearing and
// nothing else changes.
QHash<QString, QString> BlockchainBackend::readKeyTitles(const QString& configPath)
{
    QHash<QString, QString> namesByAddress;
    if (!m_blockchainClient)
        return namesByAddress;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_key_titles"),
        toLocalPath(configPath.trimmed())));
    if (!r.success)
        return namesByAddress;

    const QJsonDocument doc = QJsonDocument::fromJson(r.value.toString().toUtf8());
    if (!doc.isObject())
        return namesByAddress;

    const QJsonObject titles = doc.object();
    for (auto it = titles.constBegin(); it != titles.constEnd(); ++it) {
        const QString name = it.value().toString();
        if (!name.isEmpty())
            namesByAddress.insert(normalizeHex(it.key()), name);
    }
    return namesByAddress;
}

// Returns rows: { address, roles, roleLabel, label }.
QVariantMap BlockchainBackend::readAccountRoles(const QString& configPath)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("config_get_wallet_keys"),
        toLocalPath(configPath.trimmed())));
    if (!r.success)
        return result::toVariantMap(r);

    const QJsonDocument doc = QJsonDocument::fromJson(r.value.toString().toUtf8());
    if (!doc.isObject())
        return result::toVariantMap(
            result::err(QStringLiteral("Could not read accounts from the config.")));
    const QJsonObject obj = doc.object();

    const QJsonArray knownKeys = obj.value(QStringLiteral("known_keys")).toArray();
    QHash<QString, QStringList> rolesByAddress;
    for (const QJsonValue& keyValue : knownKeys) {
        const QString key = keyValue.toString();
        if (key.isEmpty())
            continue;
        const QString normalized = normalizeHex(key);

        QStringList roles;
        for (auto field = obj.constBegin(); field != obj.constEnd(); ++field) {
            if (field.key() == QLatin1String("known_keys") || !field.value().isString())
                continue;
            const QString holder = field.value().toString();
            if (!holder.isEmpty() && normalizeHex(holder) == normalized)
                roles << field.key();
        }
        roles.sort();
        rolesByAddress.insert(key, roles);
    }

    // Titles come from their own call — see readKeyTitles. Kept separate so a
    // keystore that cannot be read never disturbs the config read.
    const QHash<QString, QString> namesByAddress = readKeyTitles(configPath);

    // Both, from one composition. The model is what AccountsView renders and
    // what a later node refresh keeps roles on; the returned rows are what a
    // picker needs, because the model reaches QML as a QtRO replica that
    // fetches row data in batches after reporting its count — a combo box asks
    // once as it opens and draws whatever arrived, so it comes up empty the
    // first time and corrects itself on the second.
    m_accountsModel->setRoles(rolesByAddress);
    m_accountsModel->setNames(namesByAddress);
    publishAccountRows();

    QVariantList accounts;
    accounts.reserve(knownKeys.size());
    for (const QJsonValue& keyValue : knownKeys) {
        const QString key = keyValue.toString();
        if (key.isEmpty())
            continue;
        accounts.append(AccountsModel::describe(
            key, rolesByAddress.value(key), namesByAddress.value(normalizeHex(key))));
    }

    return result::toVariantMap(LogosResult{true, accounts, QVariant()});
}

// The wizard's entry point: the same read, with the rows handed back.
QVariantMap BlockchainBackend::getConfigWalletKeys(QString configPath)
{
    return readAccountRoles(configPath);
}

// Five seconds, and only while a view says someone is looking. The cadence is
// the view's; the derivation is ours, because we hold the payload.
void BlockchainBackend::pollClaimableRewards()
{
    if (!m_blockchainClient || status() != Running) {
        setClaimableLoaded(false);
        // A node that is not running is not failing to answer — it was not
        // asked. Leaving the last failure up outlives whatever caused it and
        // strands the notice on screen for the rest of the session.
        setClaimableError(QString());
        return;
    }

    logos::CallError callError;
    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_claimable_rewards"),
        QVariantList(), Timeout(), &callError));
    if (!r.success) {
        // The last good count stays on screen behind the error: a failed poll
        // says nothing about how many tickets exist, and blanking the figure
        // would claim it had gone to zero.
        setClaimableError(callError.ok() ? result::toErrorMessage(r)
                                         : describeCallError(callError));
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(r.value.toString().toUtf8());
    if (!doc.isObject()) {
        setClaimableError(tr("Could not read the claimable count."));
        return;
    }
    const QJsonObject obj = doc.object();

    // One pass for both: the soonest deadline, and how many tickets sit on it. A
    // new minimum restarts the tally rather than adding to it — the count
    // belongs to the deadline, not to the scan.
    int soonest = -1;
    int atSoonest = 0;
    // Not `slots`: that is a Qt macro (qobjectdefs.h) and expands to nothing,
    // which turns the declaration into a syntax error several lines later.
    const QJsonArray expirySlots = obj.value(QStringLiteral("slots_until_expiry")).toArray();
    for (const QJsonValue& slot : expirySlots) {
        if (!slot.isDouble())
            continue;
        const int v = slot.toInt();
        if (soonest < 0 || v < soonest) {
            soonest = v;
            atSoonest = 1;
        } else if (v == soonest) {
            ++atSoonest;
        }
    }

    setClaimableError(QString());
    const int tickets = obj.value(QStringLiteral("claimable_tickets")).toInt();
    noteClaimableReading(tickets);
    setClaimableTickets(tickets);
    setSoonestExpirySlots(soonest);
    setSoonestExpiryCount(atSoonest);
    setClaimableLoaded(true);
}

// Opens a fresh stall window. Called when mining starts and when the poll is
// armed, so the count has a full window to fall before anything is claimed about
// it — the first auto-claim tick can be a whole period away.
void BlockchainBackend::restartClaimStallWatch()
{
    m_lastClaimableTickets = -1;
    m_sinceClaimableFell.restart();
    m_sinceClaimableMoved.restart();
    setClaimsStalled(false);
    setPowActive(false);
}

// A claim is the only thing that takes tickets *out* of the claimable set while
// mining continues, so a count that falls is proof claiming works and a count
// that never falls is proof it does not. Expiry also removes tickets, which is
// why a fall is treated as good news rather than counted: it makes this
// forgiving in the one direction that matters, and it still cannot stay quiet
// through a run where nothing is claimed at all.
void BlockchainBackend::noteClaimableReading(int tickets)
{
    const bool fell = m_lastClaimableTickets >= 0 && tickets < m_lastClaimableTickets;
    // Movement either way is the evidence: up means the search is finding
    // tickets, down means a claim was paid. Only a count that does not budge at
    // all says nothing is happening.
    const bool moved = m_lastClaimableTickets >= 0 && tickets != m_lastClaimableTickets;
    if (moved)
        m_sinceClaimableMoved.restart();
    setPowActive(m_sinceClaimableMoved.isValid()
                 && m_sinceClaimableMoved.elapsed() <= kPowIdleMs);
    m_lastClaimableTickets = tickets;

    if (fell || tickets <= 0) {
        m_sinceClaimableFell.restart();
        setClaimsStalled(false);
        // A falling count means tickets were redeemed, which the block stream
        // may not tell us about — see the dead-feed problem. Balances are the
        // one place the payout still shows up.
        if (fell)
            refreshBalancesIfStale();
        return;
    }

    if (!m_sinceClaimableFell.isValid()) {
        m_sinceClaimableFell.restart();
        return;
    }

    setClaimsStalled(miningRequested() && m_sinceClaimableFell.elapsed() > kClaimStallMs);
}

// Flattens the model into the rows a picker binds to. Balances deliberately do
// not trigger it: they change constantly, a picker only cares which accounts
// exist, and republishing per tick would be a QtRO push per account for nothing.
void BlockchainBackend::publishAccountRows()
{
    QVariantList rows;
    const int count = m_accountsModel->rowCount();
    rows.reserve(count);
    for (int i = 0; i < count; ++i) {
        const QModelIndex idx = m_accountsModel->index(i, 0);
        rows.append(AccountsModel::describe(
            m_accountsModel->data(idx, AccountsModel::AddressRole).toString(),
            m_accountsModel->data(idx, AccountsModel::RolesRole).toStringList(),
            m_accountsModel->data(idx, AccountsModel::NameRole).toString()));
    }
    setAccountRows(rows);
}

// The ambient one. The PoW wizard is the only other caller and an operator with
// a working node never walks it again, so without this every picker shows bare
// hex. Failure is logged, not surfaced: an address without a label still works.
void BlockchainBackend::refreshAccountRoles()
{
    if (!m_blockchainClient || userConfig().isEmpty())
        return;
    const QVariantMap r = readAccountRoles(userConfig());
    if (!r.value(QStringLiteral("success")).toBool()) {
        qWarning() << "refreshAccountRoles: failed:"
                   << r.value(QStringLiteral("error")).toString();
    }
}

// Writes the whole PoW section in one module call. Failure is reported rather
// than warned about and dropped: the operator chose these settings, and the
// module validates everything before writing anything, so a rejection means the
// config is untouched and saying so is the only honest answer.
//
// An empty auto_claim_targets array is meaningful rather than a no-op — the node
// arms auto-claim exactly when the list is non-empty, so clearing it is how
// auto-claim is turned off.
QVariantMap BlockchainBackend::powConfigure(QString configPath, QString configJson)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("pow_configure"),
        toLocalPath(configPath.trimmed()), configJson)));
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
    // stream verdict must not carry over into this one. The reward count is
    // session-scoped for the same reason: it is built from the blocks this
    // subscription delivers, which start again from the current tip.
    setProcessedBlockCount(0);
    setBlockStreamEnded(false);
    setPowRewardsClaimed(0);
    m_powRewardsLepta = 0;
    setPowRewardsLepta(QString());
    m_diagnosisAge.invalidate();
    // Baseline for nodeLogAdvanced(), so the first verdict of this run has
    // something to compare against instead of having to spend a round
    // establishing one.
    m_lastNodeLogWrite = QFileInfo(newestNodeLogPath()).lastModified();
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
    // Only a stop issued while the node is still Starting can be queued behind a
    // replay; from Running there is nothing ahead of it, so it gets a deadline a
    // person can wait out rather than the fifteen-minute one.
    const int timeoutMs =
        previous == Starting ? kNodeCallTimeoutMs : kStopWhenRunningTimeoutMs;
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
        Timeout(timeoutMs));
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
    publishAccountRows();

    // Node truth about which keys are ours, which is what a claim in a block is
    // matched against. It also covers manual claims to any tracked key, not just
    // the configured auto-claim target.
    m_knownAddresses.clear();
    for (const QString& address : list)
        m_knownAddresses.insert(normalizeHex(address));

    m_balancesSampled.restart();
    QPointer<BlockchainBackend> self(this);
    QTimer::singleShot(0, this, [self, list]() {
        if (self)
            self->fetchBalancesForAccounts(list);
    });
}

// Balances were fetched exactly once, right after refreshAccounts, so
// walletFunded described the wallet as it stood seconds after the node came up
// and never moved again — a node that mined its first tokens an hour later still
// showed "Fund your wallet".
//
// Driven by events that mean tokens actually arrived rather than by a timer:
// wallet_get_balance is a synchronous remote call and there is one per key, so a
// steady poll would put six blocking calls on the status path of a node that may
// already be too busy to answer. Throttled because a single auto-claim drain
// settles many claims in a row, and deferred because the caller is usually the
// block stream, which should not wait on this.
void BlockchainBackend::refreshBalancesIfStale()
{
    if (!m_blockchainClient || status() != Running)
        return;
    if (m_balancesSampled.isValid() && m_balancesSampled.elapsed() < kBalanceRefreshMinMs)
        return;
    m_balancesSampled.restart();

    QStringList addresses;
    const int count = m_accountsModel->rowCount();
    addresses.reserve(count);
    for (int i = 0; i < count; ++i) {
        const QString address =
            m_accountsModel->data(m_accountsModel->index(i, 0), AccountsModel::AddressRole)
                .toString();
        if (!address.isEmpty())
            addresses << address;
    }
    if (addresses.isEmpty())
        return;

    QPointer<BlockchainBackend> self(this);
    QTimer::singleShot(0, this, [self, addresses]() {
        if (self)
            self->fetchBalancesForAccounts(addresses);
    });
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

    // Only a successful read writes. A failed one says nothing about the
    // balance, and blanking the cached figure would make a busy module look like
    // an empty wallet — which is exactly what it did once this started being
    // re-read periodically: the lifecycle lane reached Aged and then fell back
    // to "Fund your wallet" on the first refresh the node was too busy to
    // answer. Same rule the claimable poll follows: keep the last good reading
    // behind the failure.
    if (lr.success)
        m_accountsModel->setBalanceForAddress(addressHex, lr.value.toString());
    setWalletFunded(m_accountsModel->hasFunds());
    return result::toVariantMap(lr);
}

QVariantMap BlockchainBackend::transferFunds(
    QString fromKeyHex, QString toKeyHex, QString amountStr)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // amountStr is canonical LOGOS from the view; the module takes lepta.
    QString amountLepta;
    QString amountError;
    if (!leptaFromLgo(amountStr, &amountLepta, &amountError))
        return result::toVariantMap(result::err(amountError));

    QStringList senders{fromKeyHex};
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_transfer_funds",
        fromKeyHex, senders, toKeyHex, amountLepta, QString())));
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

    // PoW is deliberately not set up here. The wizard's PoW step owns that
    // section and writes it with one powConfigure call, so nothing arms
    // auto-claim behind a user who has not reached — or has abandoned — that
    // step. The result value is the absolute path the module wrote to, which is
    // what that step edits.
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

    // maxTxFee is canonical LOGOS from the view; the module takes lepta.
    QString feeLepta;
    QString feeError;
    if (!leptaFromLgo(maxTxFee, &feeLepta, &feeError))
        return result::toVariantMap(result::err(feeError));

    // 7 positional args exceed the variadic invokeRemoteMethod overloads
    // (max 5), so pass them through the QVariantList form.
    QVariantList args;
    args << channelIdHex << inputNoteIdHexes << metadataHex << changePublicKeyHex
         << fundingPublicKeyHexes << feeLepta << optionalTipHex;

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
