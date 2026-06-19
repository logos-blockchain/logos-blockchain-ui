#ifndef BLOCKCHAIN_BACKEND_H
#define BLOCKCHAIN_BACKEND_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"

#include "AccountsModel.h"
#include "LogModel.h"

class LogosAPI;
class LogosAPIClient;

// Source-side implementation of the BlockchainBackend .rep interface.
//
// Inheriting from BlockchainBackendSimpleSource gives us the generated PROPs,
// SLOTs and SIGNALs from BlockchainBackend.rep.
//
// AccountsModel* / LogModel* are subclass-only Q_PROPERTYs — QAbstractItemModel*
// can't flow through a .rep, so ui-host auto-remotes each such property as
// "<module>/<propertyName>" (see logos-view-module-runtime/ui-host/main.cpp).
// QML acquires them via logos.model("blockchain_ui", "accounts"|"logs").
class BlockchainBackend : public BlockchainBackendSimpleSource
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    Q_PROPERTY(LogModel* logs READ logs CONSTANT)

public:
    explicit BlockchainBackend(LogosAPI* logosAPI, QObject* parent = nullptr);
    ~BlockchainBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
    LogModel* logs() const { return m_logModel; }

public slots:
    // Overrides of the pure-virtual slots generated from the .rep.
    void startBlockchain() override;
    void stopBlockchain() override;
    void refreshAccounts() override;
    QVariantMap getBalance(QString addressHex) override;
    QVariantMap transferFunds(QString fromKeyHex, QString toKeyHex, QString amountStr) override;
    QVariantMap claimLeaderRewards() override;
    QVariantMap generateConfig(QString outputPath, QStringList initialPeers, int netPort,
                       int blendPort, QString httpAddr, QString externalAddress,
                       bool noPublicIpCheck, int deploymentMode,
                       QString deploymentConfigPath, QString statePath) override;
    void clearLogs() override;
    void copyToClipboard(QString text) override;

private:
    void fetchBalancesForAccounts(const QStringList& list);
    void setError(const QString& message);

    LogosAPI* m_logosAPI = nullptr;
    LogosAPIClient* m_blockchainClient = nullptr;
    AccountsModel* m_accountsModel = nullptr;
    LogModel* m_logModel = nullptr;

    static const QString BLOCKCHAIN_MODULE_NAME;
};

#endif // BLOCKCHAIN_BACKEND_H
