#include "BlockchainBackend.h"
#include "logos_api.h"
#include "logos_api_client.h"

// Generated umbrella: completes LogosModules, the typed-dependency aggregate
// behind LogosUiPluginContext::modules(). Its `api` member is the LogosAPI the
// host handed the plugin — the same pointer the hand-written plugin used to
// pass to this constructor.
#include "logos_sdk.h"

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
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
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

// Recovery rules come first so they win within a line: they mean progress, and
// the node logs them at INFO, below the severity gate the failure rules need.
const BlockchainBackend::Rule kRules[] = {
    {"blocks to replay",       QT_TR_NOOP("Catching up — replaying stored blocks."),      true},
    {"Chain recovery",         QT_TR_NOOP("Catching up — replaying stored blocks."),      true},
    {"recovering chain state", QT_TR_NOOP("Catching up — replaying stored blocks."),      true},

    {"crashed (signal",        QT_TR_NOOP("Node crashed. Reset chain state to recover."), false},
    {"panicked",               QT_TR_NOOP("Node crashed. Reset chain state to recover."), false},
    {"SIGABRT",                QT_TR_NOOP("Node crashed. Reset chain state to recover."), false},
    {"SIGSEGV",                QT_TR_NOOP("Node crashed. Reset chain state to recover."), false},
    {"Storage backend error",  QT_TR_NOOP("Chain database corrupted. Reset chain state."), false},
    {"Storage request failed", QT_TR_NOOP("Chain database corrupted. Reset chain state."), false},
    {"AddrInUse",              QT_TR_NOOP("Port already in use."),                        false},
    {"address already in use", QT_TR_NOOP("Port already in use."),                        false},
    {"failed to bind",         QT_TR_NOOP("Port already in use."),                        false},
    {"AllPeersFailed",         QT_TR_NOOP("Can't reach the configured peers."),           false},
    {"No space left",          QT_TR_NOOP("Disk full."),                                  false},
    {"ENOSPC",                 QT_TR_NOOP("Disk full."),                                  false},
    {"missing field",          QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false},
    {"failed to parse",        QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false},
    {"deserialize",            QT_TR_NOOP("Config couldn't be parsed. Regenerate it."),   false},
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

    const QStringList lines = QString::fromUtf8(buf).split(QLatin1Char('\n'));
    for (int i = lines.size() - 1; i >= 0; --i) {
        const QString& line = lines.at(i);
        const bool failureLine = isFailureLine(line);
        for (const Rule& rule : kRules) {
            if (!rule.recovering && !failureLine)
                continue;
            if (line.contains(QLatin1String(rule.needle)))
                return &rule;
        }
    }
    return nullptr;
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

BlockchainBackend::BlockchainBackend(QObject* parent)
    : BlockchainBackendSimpleSource(parent)
    , m_accountsModel(new AccountsModel(this))
    , m_blockModel(new BlockModel(this))
{
    setStatus(NotStarted);
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
}

// Everything below used to be the tail of the constructor, which the
// hand-written BlockchainPlugin::initLogos called with the host's LogosAPI*.
// The generated glue default-constructs the backend instead and calls this hook
// once modules() is live — still before setBackend()/enableRemoting, so the view
// cannot call a slot before the client exists, exactly as before.
void BlockchainBackend::onContextReady()
{
    m_logosAPI = modules().api;

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
    } else {
        setError(QStringLiteral("Failed to subscribe to events"));
    }

    qDebug() << "BlockchainBackend: initialized";
}

BlockchainBackend::~BlockchainBackend()
{
    if (status() == Running || status() == Starting)
        stopBlockchain();
}

QVariantMap BlockchainBackend::claimLeaderRewards()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "leader_claim")));
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
        setNodeRecovering(false);
    } else if (r.error.toString().contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        if (const Rule* cause = diagnoseNode()) {
            r.error = tr(cause->message);
            setNodeRecovering(cause->recovering);
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

    // Starting now renders lastErrorMessage, so clear the previous run's.
    setLastErrorMessage(QString());
    setNodeRecovering(false);
    m_diagnosisAge.invalidate();
    setStatus(Starting);

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", userConfig(), deploymentConfig()));

    if (r.success) {
        setNodeRecovering(false);
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    } else {
        setError(r.error.toString());
    }
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

    setStatus(Stopping);

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "stop"));

    if (r.success) {
        setStatus(Stopped);
    } else if (r.error.toString().contains(QStringLiteral("not running"), Qt::CaseInsensitive)) {
        // The node was already down: "stop" reports it isn't running. Treat as
        // reconciled rather than an error, so we land in a known-stopped state
        // from which Start is safe again (avoids a stuck Error ⇄ "already
        // running" loop).
        setStatus(Stopped);
    } else {
        setError(r.error.toString());
    }
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

    m_accountsModel->setBalanceForAddress(addressHex, result::toDisplayMessage(lr));
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
