#ifndef BLOCKCHAIN_BACKEND_H
#define BLOCKCHAIN_BACKEND_H

#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"

#include "AccountsModel.h"
#include "BlockModel.h"

class LogosAPI;
class LogosAPIClient;
class QTimer;

// Source-side implementation of the BlockchainBackend .rep interface.
//
// Inheriting from BlockchainBackendSimpleSource gives us the generated PROPs,
// SLOTs and SIGNALs from BlockchainBackend.rep.
//
// AccountsModel* / BlockModel* are subclass-only Q_PROPERTYs — QAbstractItemModel*
// can't flow through a .rep, so ui-host auto-remotes each such property as
// "<module>/<propertyName>" (see logos-view-module-runtime/ui-host/main.cpp).
// QML acquires them via logos.model("blockchain_ui", "accounts"|"blocks").
class BlockchainBackend : public BlockchainBackendSimpleSource
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    Q_PROPERTY(BlockModel* blocks READ blocks CONSTANT)

public:
    explicit BlockchainBackend(LogosAPI* logosAPI, QObject* parent = nullptr);
    ~BlockchainBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
    BlockModel* blocks() const { return m_blockModel; }

    // One node-log signature and what to tell the user when it is seen.
    // `recovering` marks progress rather than failure (replaying stored
    // blocks): those match at any log level, failures only on ERROR/WARN.
    // How specific a rule's verdict is. A dying node logs the reason and then
    // the crash, and the crash line is newer — so newest-match-wins reports the
    // consequence and buries the cause. Lower priority wins regardless of age;
    // newest wins within a priority.
    enum RulePriority {
        RootCause = 0,    // the thing that actually went wrong
        Summary = 1,      // a roll-up of root causes ("all peers failed")
        Consequence = 2,  // what happened next (crash, panic)
    };

    struct Rule {
        const char* needle;
        const char* message;
        bool recovering;
        int priority;
    };

public slots:
    // Overrides of the pure-virtual slots generated from the .rep.
    void startBlockchain() override;
    void stopBlockchain() override;
    void refreshAccounts() override;
    QVariantMap getBalance(QString addressHex) override;
    QVariantMap transferFunds(QString fromKeyHex, QString toKeyHex, QString amountStr) override;
    QVariantMap claimLeaderRewards() override;
    QVariantMap getCryptarchiaInfo() override;
    QVariantMap getTimeInfo() override;
    QVariantMap getBlock(QString headerIdHex) override;
    QVariantMap getTransaction(QString txHashHex) override;
    QVariantMap findTransactionInBlocks(QString txHashHex) override;
    QVariantMap getPeerId() override;
    QVariantMap getClaimableVouchers() override;
    QVariantMap generateConfig(QString outputPath, QStringList initialPeers, int netPort,
                       int blendPort, QString httpAddr, QString externalAddress,
                       bool noPublicIpCheck, int deploymentMode,
                       QString deploymentConfigPath, QString statePath) override;
    QVariantMap getNotes(QString walletAddressHex, QString optionalTipHex) override;
    QVariantMap channelDepositWithNotes(QString channelIdHex,
                                    QStringList inputNoteIdHexes,
                                    QString metadataBase58,
                                    QString changePublicKeyHex,
                                    QStringList fundingPublicKeyHexes,
                                    QString maxTxFee,
                                    QString optionalTipHex) override;
    void clearBlocks() override;
    void copyToClipboard(QString text) override;

private:
    void fetchBalancesForAccounts(const QStringList& list);
    void setError(const QString& message);
    void refreshBlendRole();
    const Rule* diagnoseNode() const; // cached; call this
    const Rule* scanNodeLog() const;
    QString newestNodeLogPath() const;

    mutable QElapsedTimer m_diagnosisAge;
    mutable const Rule* m_lastDiagnosis = nullptr;

    // Monotonic on purpose: an NTP step or a manual clock change must not make
    // the node look like it has been up for a day, or for negative time.
    QElapsedTimer m_uptime;
    QTimer* m_uptimeTimer = nullptr;

    LogosAPI* m_logosAPI = nullptr;
    LogosAPIClient* m_blockchainClient = nullptr;
    AccountsModel* m_accountsModel = nullptr;
    BlockModel* m_blockModel = nullptr;

    static const QString BLOCKCHAIN_MODULE_NAME;
};

#endif // BLOCKCHAIN_BACKEND_H
