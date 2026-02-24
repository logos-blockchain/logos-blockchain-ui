#include "BlockchainBackend.h"
#include <QByteArray>
#include <QClipboard>
#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QVariant>

namespace {
    const char SETTINGS_ORG[] = "Logos";
    const char SETTINGS_APP[] = "BlockchainUI";
    const char USER_CONFIG_KEY[] = "userConfigPath";
    const char DEPLOYMENT_CONFIG_KEY[] = "deploymentConfigPath";
    const QString BLOCKCHAIN_MODULE_NAME = QStringLiteral("liblogos_blockchain_module");
}

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : QObject(parent),
      m_status(NotStarted),
      m_userConfig(""),
      m_deploymentConfig(""),
      m_logModel(new LogModel(this)),
      m_logosAPI(nullptr),
      m_blockchainClient(nullptr)
{
    QSettings s(SETTINGS_ORG, SETTINGS_APP);
    const QString envConfigPath = QString::fromUtf8(qgetenv("LB_CONFIG_PATH"));
    const QString savedUserConfig = s.value(USER_CONFIG_KEY).toString();
    const QString savedDeploymentConfig = s.value(DEPLOYMENT_CONFIG_KEY).toString();

    if (!envConfigPath.isEmpty()) {
        m_userConfig = envConfigPath;
    } else if (!savedUserConfig.isEmpty()) {
        m_userConfig = savedUserConfig;
    }
    if (!savedDeploymentConfig.isEmpty()) {
        m_deploymentConfig = savedDeploymentConfig;
    }

    if (!logosAPI) {
        logosAPI = new LogosAPI("blockchain_ui", this);
    }

    m_logosAPI = logosAPI;
    m_blockchainClient = m_logosAPI->getClient(BLOCKCHAIN_MODULE_NAME);

    if (!m_blockchainClient) {
        setStatus(ErrorNotInitialized);
        return;
    }

    QObject* replica = m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME);
    if (replica) {
        replica->setParent(this);
        m_blockchainClient->onEvent(replica, this, "newBlock", [this](const QString&, const QVariantList& data) {
            onNewBlock(data);
        });
    } else {
        setStatus(ErrorSubscribeFailed);
    }
}

BlockchainBackend::~BlockchainBackend()
{
    stopBlockchain();
}

void BlockchainBackend::setStatus(BlockchainStatus newStatus)
{
    if (m_status != newStatus) {
        m_status = newStatus;
        emit statusChanged();
    }
}

void BlockchainBackend::setUserConfig(const QString& path)
{
    const QString localPath = QUrl::fromUserInput(path).toLocalFile();
    if (m_userConfig != localPath) {
        m_userConfig = localPath;
        QSettings s(SETTINGS_ORG, SETTINGS_APP);
        s.setValue(USER_CONFIG_KEY, m_userConfig);
        emit userConfigChanged();
    }
}

void BlockchainBackend::setDeploymentConfig(const QString& path)
{
    const QString localPath = QUrl::fromUserInput(path).toLocalFile();
    if (m_deploymentConfig != localPath) {
        m_deploymentConfig = localPath;
        QSettings s(SETTINGS_ORG, SETTINGS_APP);
        s.setValue(DEPLOYMENT_CONFIG_KEY, m_deploymentConfig);
        emit deploymentConfigChanged();
    }
}

void BlockchainBackend::setUseGeneratedConfig(bool useGenerated)
{
    if (m_useGeneratedConfig != useGenerated) {
        m_useGeneratedConfig = useGenerated;
        emit useGeneratedConfigChanged();
    }
}

void BlockchainBackend::clearLogs()
{
    m_logModel->clear();
}

void BlockchainBackend::copyToClipboard(const QString& text)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(text);
}

QString BlockchainBackend::getBalance(const QString& addressHex)
{
    if (!m_blockchainClient) {
        return QStringLiteral("Error: Module not initialized.");
    }
    QVariant result = m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME, "wallet_get_balance", addressHex);
    return result.isValid() ? result.toString() : QStringLiteral("Error: Call failed.");
}

QString BlockchainBackend::transferFunds(const QString& fromKeyHex, const QString& toKeyHex, const QString& amountStr)
{
    if (!m_blockchainClient) {
        return QStringLiteral("Error: Module not initialized.");
    }
    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME,
        "wallet_transfer_funds",
        fromKeyHex,
        fromKeyHex,
        toKeyHex,
        amountStr,
        QString());
    return result.isValid() ? result.toString() : QStringLiteral("Error: Call failed.");
}

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Starting);

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", m_userConfig, m_deploymentConfig);
    int resultCode = result.isValid() ? result.toInt() : -1;

    if (resultCode == 0 || resultCode == 1) {
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshKnownAddresses(); });
    } else if (resultCode == 2) {
        setStatus(ErrorConfigMissing);
    } else if (resultCode == 3) {
        setStatus(ErrorStartFailed);
    } else {
        setStatus(ErrorStartFailed);
    }
}

void BlockchainBackend::refreshKnownAddresses()
{
    if (!m_blockchainClient) return;
    QVariant result = m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses");
    QStringList list = result.isValid() && result.canConvert<QStringList>() ? result.toStringList() : QStringList();
    qDebug() << "BlockchainBackend: received from blockchain lib: type=QStringList, count=" << list.size();
    if (m_knownAddresses != list) {
        m_knownAddresses = std::move(list);
        emit knownAddressesChanged();
    }
}

void BlockchainBackend::stopBlockchain()
{
    if (m_status != Running && m_status != Starting) {
        return;
    }

    if (!m_blockchainClient) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Stopping);

    QVariant result = m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME, "stop");
    int resultCode = result.isValid() ? result.toInt() : -1;

    if (resultCode == 0 || resultCode == 1) {
        setStatus(Stopped);
    } else {
        setStatus(ErrorStopFailed);
    }
}

void BlockchainBackend::onNewBlock(const QVariantList& data)
{
    QString timestamp = QDateTime::currentDateTime().toString("HH:mm:ss");
    QString line;
    if (!data.isEmpty()) {
        QString blockInfo = data.first().toString();
        line = QString("[%1] 📦 New block: %2").arg(timestamp, blockInfo);
    } else {
        line = QString("[%1] 📦 New block (no data)").arg(timestamp);
    }
    m_logModel->append(line);
}

static QString toLocalPath(const QString& pathInput)
{
    if (pathInput.trimmed().isEmpty())
        return pathInput;
    return QUrl::fromUserInput(pathInput).toLocalFile();
}

int BlockchainBackend::generateConfig(const QString& outputPath,
                                      const QStringList& initialPeers,
                                      int netPort,
                                      int blendPort,
                                      const QString& httpAddr,
                                      const QString& externalAddress,
                                      bool noPublicIpCheck,
                                      int deploymentMode,
                                      const QString& deploymentConfigPath,
                                      const QString& statePath)
{
    if (!m_blockchainClient) {
        return -1;
    }
    QVariantMap normalized;

    // Output path: default if empty, then normalize
    QString out = outputPath.trimmed();
    if (out.isEmpty()) {
        out = generatedUserConfigPath();
    } else {
        out = toLocalPath(out);
    }
    normalized.insert(QStringLiteral("output"), out);

    if (!initialPeers.isEmpty()) {
        QVariantList peersList;
        for (const QString& p : initialPeers) {
            if (!p.trimmed().isEmpty())
                peersList.append(p.trimmed());
        }
        if (!peersList.isEmpty())
            normalized.insert(QStringLiteral("initial_peers"), peersList);
    }
    if (netPort > 0)
        normalized.insert(QStringLiteral("net_port"), netPort);
    if (blendPort > 0)
        normalized.insert(QStringLiteral("blend_port"), blendPort);
    if (!httpAddr.trimmed().isEmpty())
        normalized.insert(QStringLiteral("http_addr"), httpAddr.trimmed());
    if (!externalAddress.trimmed().isEmpty())
        normalized.insert(QStringLiteral("external_address"), externalAddress.trimmed());
    if (noPublicIpCheck)
        normalized.insert(QStringLiteral("no_public_ip_check"), true);
    if (deploymentMode == 0) {
        QVariantMap deployment;
        deployment.insert(QStringLiteral("well_known_deployment"), QStringLiteral("devnet"));
        normalized.insert(QStringLiteral("deployment"), deployment);
    } else if (deploymentMode == 1 && !deploymentConfigPath.trimmed().isEmpty()) {
        QVariantMap deployment;
        deployment.insert(QStringLiteral("config_path"), toLocalPath(deploymentConfigPath.trimmed()));
        normalized.insert(QStringLiteral("deployment"), deployment);
    }
    if (!statePath.trimmed().isEmpty())
        normalized.insert(QStringLiteral("state_path"), toLocalPath(statePath.trimmed()));

    const QJsonDocument doc = QJsonDocument::fromVariant(normalized);
    const QByteArray jsonBytes = doc.toJson(QJsonDocument::Compact);
    const QString jsonToSend = QString::fromUtf8(jsonBytes);

    QVariant result = m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "generate_user_config_from_str", jsonToSend);
    return result.isValid() ? result.toInt() : -1;
}

QString BlockchainBackend::generatedUserConfigPath() const
{
    return QDir::currentPath() + QStringLiteral("/user_config.yaml");
}
