#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include "logos_api.h"
#include "logos_api_client.h"
#include "LogModel.h"

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
    Q_PROPERTY(QString userConfig READ userConfig WRITE setUserConfig NOTIFY userConfigChanged)
    Q_PROPERTY(QString deploymentConfig READ deploymentConfig WRITE setDeploymentConfig NOTIFY deploymentConfigChanged)
    Q_PROPERTY(LogModel* logModel READ logModel CONSTANT)
    Q_PROPERTY(QStringList knownAddresses READ knownAddresses NOTIFY knownAddressesChanged)

    explicit BlockchainBackend(LogosAPI* logosAPI = nullptr, QObject* parent = nullptr);
    ~BlockchainBackend();

    BlockchainStatus status() const { return m_status; }
    QString userConfig() const { return m_userConfig; }
    QString deploymentConfig() const { return m_deploymentConfig; }
    LogModel* logModel() const { return m_logModel; }
    QStringList knownAddresses() const { return m_knownAddresses; }

    void setUserConfig(const QString& path);
    void setDeploymentConfig(const QString& path);
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE void copyToClipboard(const QString& text);
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
    void userConfigChanged();
    void deploymentConfigChanged();
    void knownAddressesChanged();

private:
    void setStatus(BlockchainStatus newStatus);

    BlockchainStatus m_status;
    QString m_userConfig;
    QString m_deploymentConfig;
    LogModel* m_logModel;
    QStringList m_knownAddresses;

    LogosAPI* m_logosAPI;
    LogosAPIClient* m_blockchainClient;
};
