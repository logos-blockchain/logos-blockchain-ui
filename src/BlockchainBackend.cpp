#include "BlockchainBackend.h"
#include "logos_api.h"
#include "logos_api_client.h"

#include <QByteArray>
#include <QClipboard>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>
#include <QUrl>
#include <QVariant>

const QString BlockchainBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("liblogos_blockchain_module");

void BlockchainBackend::setError(const QString& message)
{
    setLastErrorMessage(message);
    setStatus(Error);
}

static QString toLocalPath(const QString& pathInput)
{
    if (pathInput.trimmed().isEmpty())
        return pathInput;
    return QUrl::fromUserInput(pathInput).toLocalFile();
}

namespace result {

static LogosResult err(const QString& message)
{
    return LogosResult{false, QVariant(), message};
}

// invokeRemoteMethod() returns an invalid QVariant (not a LogosResult) when
// the call itself fails to get a reply (timeout, disconnected module, etc.),
// as opposed to the remote method running and reporting failure normally.
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

// Renders the balance column text in AccountsModel. getBalance() and
// transferFunds() return the LogosResult itself (see toVariantMap) so QML
// branches on success/error directly instead of re-parsing a string.
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

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : BlockchainBackendSimpleSource(parent)
    , m_logosAPI(logosAPI)
    , m_accountsModel(new AccountsModel(this))
    , m_logModel(new LogModel(this))
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

    if (!envConfigPath.isEmpty())
        setUserConfig(toLocalPath(envConfigPath));
    else if (!savedUserConfig.isEmpty())
        setUserConfig(toLocalPath(savedUserConfig));

    if (!savedDeploymentConfig.isEmpty())
        setDeploymentConfig(toLocalPath(savedDeploymentConfig));

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
                QString line;
                if (!data.isEmpty())
                    line = QString("[%1] New block: %2")
                               .arg(timestamp, data.first().toString());
                else
                    line = QString("[%1] New block (no data)").arg(timestamp);
                m_logModel->append(line);
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

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    setStatus(Starting);

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", userConfig(), deploymentConfig()));

    if (r.success) {
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    } else {
        setError(r.error.toString());
    }
}

void BlockchainBackend::stopBlockchain()
{
    if (status() != Running && status() != Starting)
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
    } else {
        setError(r.error.toString());
    }
}

void BlockchainBackend::refreshAccounts()
{
    if (!m_blockchainClient) return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses"));

    QStringList list;
    if (r.success && r.value.canConvert<QStringList>())
        list = r.value.toStringList();

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

    QString out = outputPath.trimmed();
    if (out.isEmpty())
        out = generatedUserConfigPath();
    else
        out = toLocalPath(out);
    normalized.insert("output", out);

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
    if (deploymentMode == 0) {
        QVariantMap deployment;
        deployment.insert("well_known_deployment", "devnet");
        normalized.insert("deployment", deployment);
    } else if (deploymentMode == 1
               && !deploymentConfigPath.trimmed().isEmpty()) {
        QVariantMap deployment;
        deployment.insert("config_path",
                          toLocalPath(deploymentConfigPath.trimmed()));
        normalized.insert("deployment", deployment);
    }
    if (!statePath.trimmed().isEmpty())
        normalized.insert("state_path", toLocalPath(statePath.trimmed()));

    const QJsonDocument doc = QJsonDocument::fromVariant(normalized);
    const QString jsonToSend =
        QString::fromUtf8(doc.toJson(QJsonDocument::Compact));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "generate_user_config", jsonToSend)));
}

void BlockchainBackend::clearLogs()
{
    m_logModel->clear();
}

void BlockchainBackend::copyToClipboard(QString text)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(text);
}
