#pragma once

#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

// The app's own record of settled reward claims — both kinds the chain pays.
//
// The node has no "how much have I earned" call for either. 

// For staking,wallet_get_claimable_vouchers reports what is *unclaimed* and 
// drops to zero the moment a claim settles; 

// For mining, the counter it replaces was rebuilt from scratch on every start. 
// What the chain does have is events:
// LeaderRewardClaimed and PoWRewardClaimed each carry the reward note, so the
// settled value is on the wire. This accumulates those, one record per claim,
// and persists them so the figures survive a restart.
class ClaimLedger
{
public:
    enum class Kind {
        Staking, // LeaderRewardClaimed — minted straight to a wallet key
        Mining,  // PoWRewardClaimed — minted to a per-ticket key, then transferred
    };

    struct Record {
        Kind kind = Kind::Staking;
        QString nullifier; // voucher_nullifier | pow_nullifier — chain-unique either way
        QString value;
        QString payee; // the wallet key it was attributed to, normalized
        QString blockId;
        QString txHash;
        quint64 slot = 0;
    };

    struct Pending {
        struct TxClaim {
            QStringList payees;
        };

        QString blockId;
        quint64 slot = 0;
        int attempts = 0;
        QHash<QString, TxClaim> claims; // txHash -> what that transaction claims

        // Claims for a transaction, or the wildcard entry a ledger written
        // before claims were keyed by transaction leaves behind.
        [[nodiscard]] const TxClaim* claimFor(const QString& txHash) const;
    };

    // The wildcard key. Only ever written by the migration in load().
    static const QString kAnyTx;

    void load(const QString& path, const QString& chainId);
    bool save(const QString& path) const;
    bool add(const Record& record);

    [[nodiscard]] int confirmedCount(Kind kind, quint64 libSlot) const;
    [[nodiscard]] QString confirmedTotal(Kind kind, quint64 libSlot) const;

    [[nodiscard]] const QVector<Pending>& pending() const { return m_pending; }
    void setPending(QVector<Pending> pending) { m_pending = std::move(pending); }

    [[nodiscard]] QString countingSince() const { return m_countingSince; }
    void setCountingSince(const QString& iso) { m_countingSince = iso; }

    // Sum of two non-negative decimal integers given as text.
    [[nodiscard]] static QString addLepta(const QString& a, const QString& b);

private:
    QVector<Record> m_records;
    QHash<QString, int> m_byKey; // "<kind>:<nullifier>" -> index into m_records
    QVector<Pending> m_pending;
    QString m_chainId;
    QString m_countingSince;
};
