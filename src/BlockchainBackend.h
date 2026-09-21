#ifndef BLOCKCHAIN_BACKEND_H
#define BLOCKCHAIN_BACKEND_H

#include <QDateTime>
#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"

#include "AccountsModel.h"
#include "BlockModel.h"
#include "ClaimLedger.h"
#include "ClaimsModel.h"

class LogosAPI;
class LogosAPIClient;
class QJsonObject;
class QTimer;

// Source-side implementation of the BlockchainBackend .rep interface.
//
// Inheriting from BlockchainBackendSimpleSource gives us the generated PROPs,
// SLOTs and SIGNALs from BlockchainBackend.rep.
//
// AccountsModel* / BlockModel* are subclass-only Q_PROPERTYs — QAbstractItemModel*
// can't flow through a .rep, so ui-host auto-remotes each such property as
// "<module>/<propertyName>" (see logos-view-module-runtime/ui-host/main.cpp).
// QML acquires them via logos.model("blockchain_ui",
// "accounts"|"blocks"|"claims"|"miningClaims").
class BlockchainBackend : public BlockchainBackendSimpleSource
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    Q_PROPERTY(BlockModel* blocks READ blocks CONSTANT)
    Q_PROPERTY(ClaimsModel* claims READ claims CONSTANT)
    Q_PROPERTY(ClaimsModel* miningClaims READ miningClaims CONSTANT)

public:
    explicit BlockchainBackend(LogosAPI* logosAPI, QObject* parent = nullptr);
    ~BlockchainBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
    BlockModel* blocks() const { return m_blockModel; }
    ClaimsModel* claims() const { return m_claimsModel; }
    ClaimsModel* miningClaims() const { return m_miningClaimsModel; }

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

    // What the operating system says about the node module's process, which is
    // the thing nodeModuleReachable actually claims to report. Three answers,
    // not two: Unknown is not Gone, and must never be treated as one.
    enum class ProcessEvidence { Alive, Gone, Unknown };

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
    QVariantMap powStartMining() override;
    QVariantMap powStopMining() override;
    QVariantMap powClaimableRewards() override;
    QVariantMap powClaim(QString claimAddressHex) override;
    QVariantMap powStartAutoClaim() override;
    QVariantMap powStopAutoClaim() override;
    QVariantMap getConfigWalletKeys(QString configPath) override;
    void refreshAccountRoles();
    QVariantMap powConfigure(QString configPath, QString configJson) override;
    void setClaimHistoryFilter(int mode) override;
    void setMiningHistoryFilter(int mode) override;
    void clearBlocks() override;
    void copyToClipboard(QString text) override;

private:
    void fetchBalancesForAccounts(const QStringList& list);
    // Re-reads every tracked balance, throttled. Without this walletFunded is a
    // snapshot from node-start and the lifecycle lane never leaves "Fund your
    // wallet", however much the node pays in afterwards.
    void refreshBalancesIfStale();
    QElapsedTimer m_balancesSampled;
    void setError(const QString& message);
    void refreshBlendRole();
    void refreshStake();
    void clearStake();
    void refreshNetwork();
    void clearNetwork();
    void refreshChainId();

    // ---- Claims: the app's own tally of settled rewards, staking and mining ----
    // A block the processed-block stream delivered that might carry a claim,
    // waiting for its events to be fetched. Lives in the ledger so it survives
    // a stop.
    using PendingBlock = ClaimLedger::Pending;
    // What each claim in a block could pay, keyed by transaction. Empty if the
    // block holds no claim of either kind. Finding claims needs only the opcode
    // — no wallet keys — which is what lets a block be judged the moment it
    // arrives rather than kept on the chance it might matter.
    [[nodiscard]] static QHash<QString, PendingBlock::TxClaim> claimPayeesByTx(
        const QJsonObject& block);
    // Parses one processed-block event and queues the block if it could hold a
    // claim. Parsing ONLY: this runs inside the module's own delivery path, so
    // it must not make a module call.
    void noteProcessedBlock(const QString& eventJson);
    // Fetches events for queued blocks and records the claims that are ours.
    // Driven from the status poll for the same reason refreshStake is.
    void drainClaimEvents();
    void recordClaimsFrom(const QString& eventsJson, const PendingBlock& block);
    // Notes a claim this app just sent, so the views can say it is in flight
    // before the chain has anything to say about it. Takes the module's reply
    // verbatim; a reply that is not a transaction hash is ignored.
    void noteSubmittedClaim(ClaimLedger::Kind kind, const QVariantMap& reply);
    // Opens the ledger once the node has said which chain it is on — the file
    // is discarded when that disagrees with what it was written against.
    void loadClaimLedger();
    void publishClaims();
    // Writes records and the pending queue together — they are one state, and a
    // queue that outlived its records would re-count what they already hold.
    // Throttled unless forced; force on the way out of Running.
    void saveClaims(bool force = false);
    [[nodiscard]] QString claimLedgerPath() const;
    // The chain this ledger belongs to. chain_id alone is a release string —
    // "0.3.0-rc.3" — so a devnet rebuilt at the same release would inherit the
    // previous chain's totals. Pairing it with the genesis block id makes the
    // identity actually unique to a chain.
    [[nodiscard]] QString chainIdentity();
    void refreshGenesisId();
    // TODO(logos-co/logos-liblogos#219): both of these go away when liblogos
    // publishes its per-module stats to modules. It already measures them — the
    // same figures Basecamp's Core Inspector shows — but only a host can read
    // them, so until then this resolves the node module's PID through
    // modules_state and samples it here with the library liblogos itself uses.
    void resolveNodePid();
    void refreshResourceUsage();
    // Disk is NOT part of that TODO: nothing in the stack measures it, so this
    // stays once liblogos exposes CPU and memory.
    [[nodiscard]] QString nodeDataDir() const;
    void refreshDiskUsage();
    // Re-checked AFTER every blocking module call, not just before one. See the
    // definition: the sync call spins a nested event loop, so a stop can run to
    // completion while the reply is in flight.
    [[nodiscard]] bool stillRunning() const;
    const Rule* diagnoseNode() const; // cached; call this
    bool moduleIsAlive();
    // True when the node's log has been written to since the last look, which
    // proves the process is alive however unreachable it is over the transport.
    bool nodeLogAdvanced();
    // Whether the module's PROCESS exists, asked of the OS rather than of the
    // transport. This is the authority on "is the module gone": a module buried
    // under a block backlog answers no call and passes no probe while its
    // process is plainly there, and QtRO cannot tell that apart from a crash.
    ProcessEvidence nodeProcessEvidence();
    // The whole verdict, in one place: probe, then the OS, then the log. Every
    // caller of declareModuleGone() goes through this.
    bool moduleConfirmedGone();
    // Record that the module's process is gone: one place, so the poll path and
    // the liveness timer cannot drift into telling different stories.
    void declareModuleGone();
    const Rule* scanNodeLog() const;
    QString newestNodeLogPath() const;

    // One reading of the node's `mode`, debounced. Rising is immediate — good
    // news needs no confirming — while a fall needs three consecutive readings,
    // so one blip cannot reset a clock that has been running for hours.
    void applyOnlineReading(bool modeOnline);
    void startUptime();
    void stopUptime();

    mutable QElapsedTimer m_diagnosisAge;
    mutable const Rule* m_lastDiagnosis = nullptr;

    // Monotonic on purpose: an NTP step or a manual clock change must not make
    // the node look like it has been up for a day, or for negative time.
    // Validity IS the online state: there is no separate flag to disagree with.
    QElapsedTimer m_uptime;
    QTimer* m_uptimeTimer = nullptr;
    int m_offlineReadings = 0;
    int m_consecutivePollFailures = 0;
    // Last mtime seen on the node's log, for nodeLogAdvanced().
    QDateTime m_lastNodeLogWrite;
    // Claim-stall detection. -1 means nothing read yet, which is not the same as
    // a count of zero and must not be mistaken for one.
    int m_lastClaimableTickets = -1;
    QElapsedTimer m_sinceClaimableFell;
    // Since the claimable count last moved in either direction, for powActive.
    QElapsedTimer m_sinceClaimableMoved;
    void noteClaimableReading(int tickets);
    void restartClaimStallWatch();

    // Asks whether the module is still there while the node is meant to be up.
    // The status poll only runs once the node reaches Running, so without this
    // a module that dies mid-start is never contradicted by anything.
    QTimer* m_livenessTimer = nullptr;
    // Consecutive probe misses. Reset by a successful probe and by any block
    // arriving, since a module pushing blocks is alive whatever the probe says.
    int m_livenessMisses = 0;

    LogosAPI* m_logosAPI = nullptr;
    LogosAPIClient* m_blockchainClient = nullptr;
    // TODO(logos-co/logos-liblogos#219): scaffolding for the CPU/memory tiles.
    // The PID belongs to the module's process, not the node, so it outlives a
    // node stop/start and is only re-resolved when sampling starts failing.
    LogosAPIClient* m_modulesStateClient = nullptr;
    qint64 m_nodePid = 0;
    int m_pidLookupFailures = 0;
    // Whether a CPU sample has been taken for the current PID. The first one of
    // any process has nothing to diff against and reports 0.0.
    bool m_cpuSampledOnce = false;
    // When the data-dir walk last ran. Invalid until the first one.
    QElapsedTimer m_diskSampled;
    QVariantMap readAccountRoles(const QString& configPath);
    // Public-half keystore titles, or empty. Never fails loudly: titles are
    // decoration and the keystore is expected to become password-protected.
    QHash<QString, QString> readKeyTitles(const QString& configPath);
    // Republishes accountRows from the model. Called after anything that
    // changes which addresses exist or what they are called.
    void publishAccountRows();
    // One reading of pow_claimable_rewards, straight onto the properties above.
    void pollClaimableRewards();

    QTimer* m_claimablePollTimer = nullptr;

    AccountsModel* m_accountsModel = nullptr;
    BlockModel* m_blockModel = nullptr;
    ClaimsModel* m_claimsModel = nullptr;
    ClaimsModel* m_miningClaimsModel = nullptr;
    // Wallet addresses as the node reports them, normalised for comparison
    // against the claim beneficiaries named in incoming blocks.
    QSet<QString> m_knownAddresses;

    ClaimLedger m_claims;
    bool m_claimsLoaded = false;
    // When the ledger last reached disk. Throttles the rewrite-whole save so a
    // replay that finds many claims does not pay for one write per claim.
    QElapsedTimer m_claimsSaved;
    // Genesis block id, fetched once per run. Empty when the node could not be
    // asked — the guard then falls back to chain_id alone, which is what it
    // used to be, rather than refusing to open the ledger at all.
    QString m_genesisId;
    QVector<PendingBlock> m_pendingEventBlocks;
    // The last irreversible slot, straight off the processed-block stream. What
    // decides whether a recorded claim is counted yet.
    quint64 m_libSlot = 0;

    static const QString BLOCKCHAIN_MODULE_NAME;
    // TODO(logos-co/logos-liblogos#219): only reached for the PID behind the
    // CPU/memory tiles.
    static const QString MODULES_STATE_MODULE_NAME;
};

#endif // BLOCKCHAIN_BACKEND_H
