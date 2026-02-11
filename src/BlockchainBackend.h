#pragma once

#include <QObject>
#include <QString>
#include <utility>
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_sdk.h"

// Type of the blockchain module proxy (has start(), stop(), on() etc.)
using BlockchainModuleProxy = std::remove_reference_t<decltype(std::declval<LogosModules>().liblogos_blockchain_module)>;

class BlockchainBackend : public QObject {
    Q_OBJECT

public:
    enum BlockchainStatus {
        NotStarted = 0,
        Starting,
        Running,
        Stopping,
        Stopped,
        Error,
        ErrorNotInitialized,
        ErrorConfigMissing,
        ErrorStartFailed,
        ErrorStopFailed,
        ErrorSubscribeFailed
    };
    Q_ENUM(BlockchainStatus)

    Q_PROPERTY(BlockchainStatus status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString configPath READ configPath WRITE setConfigPath NOTIFY configPathChanged)

    explicit BlockchainBackend(LogosAPI* logosAPI = nullptr, QObject* parent = nullptr);
    ~BlockchainBackend();

    BlockchainStatus status() const { return m_status; }
    QString configPath() const { return m_configPath; }

    void setConfigPath(const QString& path);
    Q_INVOKABLE void clearLogs();

public slots:
    Q_INVOKABLE void startBlockchain();
    Q_INVOKABLE void stopBlockchain();
    void onNewBlock(const QVariantList& data);

signals:
    void statusChanged();
    void configPathChanged();
    void newBlockMessage(const QString& message);
    void logsCleared();

private:
    void setStatus(BlockchainStatus newStatus);

    BlockchainStatus m_status;
    QString m_configPath;

    LogosModules* m_logos;
    BlockchainModuleProxy* m_blockchainModule;
};
