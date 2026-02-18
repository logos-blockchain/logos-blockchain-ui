#include "BlockchainBackend.h"
#include <QByteArray>
#include <QDebug>
#include <QDateTime>
#include <QSettings>
#include <QTimer>
#include <QUrl>

namespace {
    const char SETTINGS_ORG[] = "Logos";
    const char SETTINGS_APP[] = "BlockchainUI";
    const char CONFIG_PATH_KEY[] = "configPath";
    const QString BLOCKCHAIN_MODULE_NAME = QStringLiteral("liblogos-blockchain-module");
}

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : QObject(parent),
      m_status(NotStarted),
      m_configPath(""),
      m_logModel(new LogModel(this)),
      m_logosAPI(nullptr),
      m_blockchainClient(nullptr)
{
    QSettings s(SETTINGS_ORG, SETTINGS_APP);
    const QString envConfigPath = QString::fromUtf8(qgetenv("LB_CONFIG_PATH"));
    const QString savedConfigPath = s.value(CONFIG_PATH_KEY).toString();

    if (!envConfigPath.isEmpty()) {
        m_configPath = envConfigPath;
    } else if (!savedConfigPath.isEmpty()) {
        m_configPath = savedConfigPath;
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

void BlockchainBackend::setConfigPath(const QString& path)
{
    const QString localPath = QUrl::fromUserInput(path).toLocalFile();
    if (m_configPath != localPath) {
        m_configPath = localPath;
        QSettings s(SETTINGS_ORG, SETTINGS_APP);
        s.setValue(CONFIG_PATH_KEY, m_configPath);
        emit configPathChanged();
    }
}

void BlockchainBackend::clearLogs()
{
    m_logModel->clear();
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
        BLOCKCHAIN_MODULE_NAME, "start", m_configPath, QString());
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
        QString shortInfo = blockInfo.left(80);
        if (blockInfo.length() > 80) {
            shortInfo += "...";
        }
        line = QString("[%1] 📦 New block: %2").arg(timestamp, shortInfo);
    } else {
        line = QString("[%1] 📦 New block (no data)").arg(timestamp);
    }
    m_logModel->append(line);
}
