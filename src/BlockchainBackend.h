#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include "logos_api.h"
#include "logos_api_client.h"
#include "AccountsModel.h"
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
    Q_PROPERTY(bool useGeneratedConfig READ useGeneratedConfig WRITE setUseGeneratedConfig NOTIFY useGeneratedConfigChanged)
    Q_PROPERTY(LogModel* logModel READ logModel CONSTANT)
    Q_PROPERTY(AccountsModel* accountsModel READ accountsModel CONSTANT)
    Q_PROPERTY(QString generatedUserConfigPath READ generatedUserConfigPath CONSTANT)

    explicit BlockchainBackend(LogosAPI* logosAPI = nullptr, QObject* parent = nullptr);
    ~BlockchainBackend();

    BlockchainStatus status() const { return m_status; }
    QString userConfig() const { return m_userConfig; }
    QString deploymentConfig() const { return m_deploymentConfig; }
    bool useGeneratedConfig() const { return m_useGeneratedConfig; }
    LogModel* logModel() const { return m_logModel; }
    AccountsModel* accountsModel() const { return m_accountsModel; }

    void setUserConfig(const QString& path);
    void setDeploymentConfig(const QString& path);
    void setUseGeneratedConfig(bool useGenerated);
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE void copyToClipboard(const QString& text);
    Q_INVOKABLE QString getBalance(const QString& addressHex);
    Q_INVOKABLE QString transferFunds(
        const QString& fromKeyHex, 
        const QString& toKeyHex, 
        const QString& amountStr);
    Q_INVOKABLE void startBlockchain();
    Q_INVOKABLE void stopBlockchain();
    Q_INVOKABLE void refreshAccounts();
    Q_INVOKABLE int generateConfig(const QString& outputPath,
                                   const QStringList& initialPeers,
                                   int netPort,
                                   int blendPort,
                                   const QString& httpAddr,
                                   const QString& externalAddress,
                                   bool noPublicIpCheck,
                                   int deploymentMode,
                                   const QString& deploymentConfigPath,
                                   const QString& statePath);
    Q_INVOKABLE QString generatedUserConfigPath() const;

public slots:
    void onNewBlock(const QVariantList& data);

signals:
    void statusChanged();
    void userConfigChanged();
    void deploymentConfigChanged();
    void useGeneratedConfigChanged();

private:
    void setStatus(BlockchainStatus newStatus);
    void fetchBalancesForAccounts(const QStringList& list);

    BlockchainStatus m_status;
    QString m_userConfig;
    QString m_deploymentConfig;
    bool m_useGeneratedConfig = false;
    LogModel* m_logModel;
    AccountsModel* m_accountsModel;

    LogosAPI* m_logosAPI;
    LogosAPIClient* m_blockchainClient;
};
