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

static QString toLocalPath(const QString& pathInput)
{
    if (pathInput.trimmed().isEmpty())
        return pathInput;
    return QUrl::fromUserInput(pathInput).toLocalFile();
}

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
        setStatus(ErrorNotInitialized);
        qWarning() << "BlockchainBackend: failed to get blockchain module client";
        return;
    }

    // NOTE: do NOT call requestObject() here. ui-host invokes initLogos()
    // (and therefore this constructor) synchronously via Qt::DirectConnection
    // and only signals "READY" once it returns. requestObject() blocks for up
    // to its 20s timeout when the backend module isn't running yet — which is
    // the normal case, since the node is started later from this UI. Blocking
    // here makes ui-host miss its readiness deadline, so the host kills it and
    // the whole view fails to load. The newBlock subscription is only
    // meaningful once the node is running, so it is deferred to
    // subscribeToBlockEvents(), called after a successful startBlockchain().
    qDebug() << "BlockchainBackend: initialized";
}

void BlockchainBackend::subscribeToBlockEvents()
{
    if (m_blockEventsSubscribed || !m_blockchainClient)
        return;

    LogosObject* replica =
        m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME);
    if (!replica)
        return;

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
    m_blockEventsSubscribed = true;
}

BlockchainBackend::~BlockchainBackend()
{
    if (status() == Running || status() == Starting)
        stopBlockchain();
}

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Starting);

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", userConfig(), deploymentConfig());
    int resultCode = result.isValid() ? result.toInt() : -1;

    if (resultCode == 0 || resultCode == 1) {
        setStatus(Running);
        subscribeToBlockEvents();
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    } else if (resultCode == 2) {
        setStatus(ErrorConfigMissing);
    } else {
        setStatus(ErrorStartFailed);
    }
}

void BlockchainBackend::stopBlockchain()
{
    if (status() != Running && status() != Starting)
        return;

    if (!m_blockchainClient) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Stopping);

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "stop");
    int resultCode = result.isValid() ? result.toInt() : -1;

    if (resultCode == 0 || resultCode == 1)
        setStatus(Stopped);
    else
        setStatus(ErrorStopFailed);
}

void BlockchainBackend::refreshAccounts()
{
    if (!m_blockchainClient) return;

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses");
    QStringList list =
        result.isValid() && result.canConvert<QStringList>()
            ? result.toStringList()
            : QStringList();

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

QString BlockchainBackend::getBalance(QString addressHex)
{
    QString result;
    if (!m_blockchainClient) {
        result = QStringLiteral("Error: Module not initialized.");
    } else {
        QVariant v = m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, "wallet_get_balance", addressHex);
        result = v.isValid() ? v.toString()
                             : QStringLiteral("Error: Call failed.");
    }

    m_accountsModel->setBalanceForAddress(addressHex, result);
    return result;
}

QString BlockchainBackend::transferFunds(
    QString fromKeyHex, QString toKeyHex, QString amountStr)
{
    if (!m_blockchainClient)
        return QStringLiteral("Error: Module not initialized.");

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_transfer_funds",
        fromKeyHex, fromKeyHex, toKeyHex, amountStr, QString());
    return result.isValid() ? result.toString()
                            : QStringLiteral("Error: Call failed.");
}

int BlockchainBackend::generateConfig(
    QString outputPath, QStringList initialPeers, int netPort, int blendPort,
    QString httpAddr, QString externalAddress, bool noPublicIpCheck,
    int deploymentMode, QString deploymentConfigPath, QString statePath)
{
    if (!m_blockchainClient)
        return -1;

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

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "generate_user_config_from_str", jsonToSend);
    return result.isValid() ? result.toInt() : -1;
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
