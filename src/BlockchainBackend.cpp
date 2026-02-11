#include "BlockchainBackend.h"
#include <QDebug>
#include <QDateTime>
#include <QUrl>

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : QObject(parent),
      m_status(NotStarted),
      m_configPath(""),
      m_logos(nullptr),
      m_blockchainModule(nullptr)
{

    m_configPath =  QString::fromUtf8(qgetenv("LB_CONFIG_PATH"));

    if (!logosAPI) {
        logosAPI = new LogosAPI("core", this);
    }

    m_logos = new LogosModules(logosAPI);

    if (!m_logos) {
        setStatus(ErrorNotInitialized);
        return;
    }

    m_blockchainModule = &m_logos->liblogos_blockchain_module;

    if (m_blockchainModule && !m_blockchainModule->on("newBlock", [this](const QVariantList& data) {
        onNewBlock(data);
    })) {
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

void BlockchainBackend::clearLogs()
{
    emit logsCleared();
}

void BlockchainBackend::setConfigPath(const QString& path)
{
    const QString localPath = QUrl::fromUserInput(path).toLocalFile();
    if (m_configPath != localPath) {
        m_configPath = localPath;
        emit configPathChanged();
    }
}

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainModule) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Starting);

    int result = m_blockchainModule->start(m_configPath, QString());

    if (result == 0 || result == 1) {
        setStatus(Running);
    } else if (result == 2) {
        setStatus(ErrorConfigMissing);
    } else if (result == 3) {
        setStatus(ErrorStartFailed);
    } else {
        setStatus(ErrorStartFailed);
    }
}

void BlockchainBackend::stopBlockchain()
{
    if (m_status != Running && m_status != Starting) {
        return;
    }

    if (!m_blockchainModule) {
        setStatus(ErrorNotInitialized);
        return;
    }

    setStatus(Stopping);

    int result = m_blockchainModule->stop();

    if (result == 0 || result == 1) {
        setStatus(Stopped);
    } else {
        setStatus(ErrorStopFailed);
    }
}

void BlockchainBackend::onNewBlock(const QVariantList& data)
{
    QString timestamp = QDateTime::currentDateTime().toString("HH:mm:ss");
    if (!data.isEmpty()) {
        QString blockInfo = data.first().toString();
        QString shortInfo = blockInfo.left(80);
        if (blockInfo.length() > 80) {
            shortInfo += "...";
        }
        emit newBlockMessage(QString("[%1] 📦 New block: %2\n").arg(timestamp, shortInfo));
    } else {
        emit newBlockMessage(QString("[%1] 📦 New block (no data)\n").arg(timestamp));
    }
}
