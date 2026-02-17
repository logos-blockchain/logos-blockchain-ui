#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <utility>
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_sdk.h"
#include "LogModel.h"

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
    Q_PROPERTY(LogModel* logModel READ logModel CONSTANT)
    Q_PROPERTY(QStringList knownAddresses READ knownAddresses NOTIFY knownAddressesChanged)

    explicit BlockchainBackend(LogosAPI* logosAPI = nullptr, QObject* parent = nullptr);
    ~BlockchainBackend();

    BlockchainStatus status() const { return m_status; }
    QString configPath() const { return m_configPath; }
    LogModel* logModel() const { return m_logModel; }
    QStringList knownAddresses() const { return m_knownAddresses; }

    void setConfigPath(const QString& path);
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE QString getBalance(const QString& addressHex);
    Q_INVOKABLE QString transferFunds(
        const QString& fromKeyHex, 
        const QString& toKeyHex, 
        const QString& amountStr);
    Q_INVOKABLE void startBlockchain();
    Q_INVOKABLE void stopBlockchain();
    Q_INVOKABLE void refreshKnownAddresses();

public slots:
    void onNewBlock(const QVariantList& data);

signals:
    void statusChanged();
    void configPathChanged();
    void knownAddressesChanged();

private:
    void setStatus(BlockchainStatus newStatus);

    BlockchainStatus m_status;
    QString m_configPath;
    LogModel* m_logModel;
    QStringList m_knownAddresses;

    LogosModules* m_logos;
    BlockchainModuleProxy* m_blockchainModule;
};
