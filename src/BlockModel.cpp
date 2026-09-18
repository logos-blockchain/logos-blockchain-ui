#include "BlockModel.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>

namespace {

// Consensus versions are a closed enum on the node side (core/src/header:
// `BEDROCK_VERSION = 1`). An unknown discriminant is reported as its number
// rather than guessed at or dropped — a block from a newer node should still
// say something truthful.
QString versionName(int discriminant)
{
    switch (discriminant) {
    case 1:  return QStringLiteral("Bedrock");
    default: return QString::number(discriminant);
    }
}

QString prettify(const QJsonValue& value)
{
    if (value.isObject())
        return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Indented));
    if (value.isArray())
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Indented));
    return value.toVariant().toString();
}

// TRANSFER and CLAIM_POW_REWARD. Mantle ops share one `{ opcode, payload }`
// wire shape, so the opcode is what identifies the operation.
constexpr int kTransferOpcode = 0x00;
constexpr int kClaimPowRewardOpcode = 0x40;

// One claim transaction: the keys it pays, how many mined tickets it redeems,
// and what it actually pays out.
struct PowClaimBatch {
    QStringList payoutKeys;
    int claimCount = 0;
    quint64 lepta = 0;
};

// Appends the claim batch a transaction carries, if any. Each transaction in a
// `newBlock` payload is `{ id, mantle_tx: { ops: [...] }, ops_proofs }` — the id
// is flattened in beside the signed transaction, which is why the ops sit one
// level down under `mantle_tx`.
//
// The payee is not on the claim op. `ClaimPowRewardOp.public_key` is the
// per-ticket key the puzzle was solved against — one per mined ticket, so it
// never matches a wallet — and the note it mints is spent in the same
// transaction by transfer ops paying the node's claim address. So the payee
// comes from the transfer outputs, and every claim in the transaction is paid
// to it.
void collectPowClaims(const QJsonObject& transaction, QList<PowClaimBatch>& out)
{
    const QJsonArray ops = transaction.value(QStringLiteral("mantle_tx"))
                               .toObject()
                               .value(QStringLiteral("ops"))
                               .toArray();
    PowClaimBatch batch;
    for (const QJsonValue op : ops) {
        const QJsonObject fields = op.toObject();
        switch (fields.value(QStringLiteral("opcode")).toInt(-1)) {
        case kClaimPowRewardOpcode:
            ++batch.claimCount;
            break;
        case kTransferOpcode: {
            // Change is paid back to the claim address too, so every output is
            // a candidate payee rather than just the first.
            const QJsonArray outputs = fields.value(QStringLiteral("payload"))
                                           .toObject()
                                           .value(QStringLiteral("outputs"))
                                           .toArray();
            for (const QJsonValue output : outputs) {
                const QJsonObject entry = output.toObject();
                const QString pk = entry.value(QStringLiteral("pk")).toString();
                if (pk.isEmpty())
                    continue;
                if (!batch.payoutKeys.contains(pk))
                    batch.payoutKeys << pk;
                const qint64 value = entry.value(QStringLiteral("value")).toInteger(0);
                if (value > 0)
                    batch.lepta += static_cast<quint64>(value);
            }
            break;
        }
        default:
            break;
        }
    }
    // A transfer with no claims is an ordinary payment, and a claim whose payee
    // cannot be read is one we could not attribute either way.
    if (batch.claimCount > 0 && !batch.payoutKeys.isEmpty())
        out << batch;
}

} // namespace

int BlockModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant BlockModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();

    const Entry& e = m_entries.at(index.row());
    switch (role) {
    case TimestampRole:    return e.timestamp;
    case SlotRole:         return e.slot;
    case VersionRole:      return e.version;
    case ParentBlockRole:  return e.parentBlock;
    case BlockRootRole:    return e.blockRoot;
    case LeaderKeyRole:    return e.leaderKey;
    case EntropyRole:      return e.entropy;
    case ProofRole:        return e.proof;
    case VoucherCmRole:    return e.voucherCm;
    case SignatureRole:    return e.signature;
    case TxCountRole:      return e.txCount;
    case TransactionsRole: return e.transactions;
    case RawJsonRole:      return e.rawJson;
    case ParsedRole:       return e.parsed;
    default:               return QVariant();
    }
}

QHash<int, QByteArray> BlockModel::roleNames() const
{
    QHash<int, QByteArray> names;
    names[TimestampRole]    = "timestamp";
    names[SlotRole]         = "slot";
    names[VersionRole]      = "version";
    names[ParentBlockRole]  = "parentBlock";
    names[BlockRootRole]    = "blockRoot";
    names[LeaderKeyRole]    = "leaderKey";
    names[EntropyRole]      = "entropy";
    names[ProofRole]        = "proof";
    names[VoucherCmRole]    = "voucherCm";
    names[SignatureRole]    = "signature";
    names[TxCountRole]      = "txCount";
    names[TransactionsRole] = "transactions";
    names[RawJsonRole]      = "rawJson";
    names[ParsedRole]       = "parsed";
    return names;
}

void BlockModel::appendRaw(const QString& timestamp, const QString& rawJson)
{
    Entry e;
    QList<PowClaimBatch> powClaims;
    e.timestamp = timestamp;

    // Tolerated shapes:
    //   { "block": {...}, "tip", "tip_slot", "lib", "lib_slot" }  processed-block
    //   { "block": "<stringified block>" }                        legacy, stringified
    //   { "block": { ... } }                                      legacy, object
    //   { "header": ..., "transactions": ... }                    block sent directly
    //
    // The processed-block form is the one subscribed to: it survives a lagged
    // item where the legacy new-block stream ends permanently, and it signals
    // its own end. Its block sits under the same "block" key the legacy object
    // form used, so the branch below covers both.
    QJsonObject block;
    bool ok = false;

    QJsonParseError err{};
    const QJsonDocument outer = QJsonDocument::fromJson(rawJson.toUtf8(), &err);
    if (err.error == QJsonParseError::NoError && outer.isObject()) {
        const QJsonObject o = outer.object();
        if (o.contains(QStringLiteral("block"))) {
            const QJsonValue bv = o.value(QStringLiteral("block"));
            if (bv.isString()) {
                const QJsonDocument inner =
                    QJsonDocument::fromJson(bv.toString().toUtf8(), &err);
                if (err.error == QJsonParseError::NoError && inner.isObject()) {
                    block = inner.object();
                    ok = true;
                }
            } else if (bv.isObject()) {
                block = bv.toObject();
                ok = true;
            }
        } else if (o.contains(QStringLiteral("header"))) {
            block = o;
            ok = true;
        }
    }

    if (ok) {
        e.parsed = true;

        const QJsonObject header = block.value(QStringLiteral("header")).toObject();

        // `version` is the consensus version. The node serialises it as a name
        // ("Bedrock") over JSON, but the wire carries the raw discriminant and
        // not every build agrees — and QJsonValue::toString() returns an EMPTY
        // string for a number rather than converting, which blanks the whole
        // Consensus column silently. Parse both shapes, as `slot` does below.
        const QJsonValue versionV = header.value(QStringLiteral("version"));
        e.version = versionV.isDouble()
            ? versionName(static_cast<int>(versionV.toDouble()))
            : versionV.toString();
        e.blockId = header.value(QStringLiteral("id")).toString();
        e.parentBlock = header.value(QStringLiteral("parent_block")).toString();

        const QJsonValue slotV = header.value(QStringLiteral("slot"));
        e.slot = slotV.isDouble()
            ? QString::number(static_cast<qlonglong>(slotV.toDouble()))
            : slotV.toString();

        // The node's field is `body_root` (core/src/header: it commits to the
        // block body). `block_root` was never a header field, so this row read
        // empty on every block; the old name is still accepted in case an
        // older node is on the other end.
        e.blockRoot = header.contains(QStringLiteral("body_root"))
            ? header.value(QStringLiteral("body_root")).toString()
            : header.value(QStringLiteral("block_root")).toString();

        const QJsonObject pol =
            header.value(QStringLiteral("proof_of_leadership")).toObject();
        e.proof = pol.value(QStringLiteral("proof")).toString();
        e.entropy = pol.value(QStringLiteral("entropy_contribution")).toString();
        e.leaderKey = pol.value(QStringLiteral("leader_key")).toString();
        e.voucherCm = pol.value(QStringLiteral("voucher_cm")).toString();

        e.signature = block.value(QStringLiteral("signature")).toString();

        const QJsonArray txs = block.value(QStringLiteral("transactions")).toArray();
        e.txCount = txs.size();
        for (const QJsonValue tx : txs) {
            e.transactions << prettify(tx);
            collectPowClaims(tx.toObject(), powClaims);
        }

        e.rawJson = QString::fromUtf8(QJsonDocument(block).toJson(QJsonDocument::Indented));
    } else {
        // Keep the raw text so an unexpected format is still inspectable.
        e.parsed = false;
        e.rawJson = rawJson;
    }

    if (!e.blockId.isEmpty() && !m_entries.isEmpty()
        && m_entries.first().blockId == e.blockId) {
        return;
    }

    beginInsertRows(QModelIndex(), 0, 0);
    m_entries.prepend(e);
    endInsertRows();

    if (m_entries.size() > kMaxBlocks) {
        const int last = m_entries.size() - 1;
        beginRemoveRows(QModelIndex(), last, last);
        m_entries.remove(last);
        endRemoveRows();
    }

    emit countChanged();

    // After the insertion: a consumer reacting to this may want to look the
    // block up, and eviction must not race the lookup.
    for (const PowClaimBatch& batch : powClaims)
        emit powClaimsFound(batch.payoutKeys, batch.claimCount, batch.lepta);
}

QVariantMap BlockModel::findTransaction(const QString& txId) const
{
    // Normalise for comparison: trim, drop an optional 0x prefix, lowercase.
    auto normalize = [](const QString& s) {
        QString t = s.trimmed();
        if (t.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive))
            t = t.mid(2);
        return t.toLower();
    };

    const QString needle = normalize(txId);
    if (needle.isEmpty())
        return QVariantMap{{"found", false}};

    for (const Entry& e : m_entries) {
        for (const QString& txJson : e.transactions) {
            QJsonParseError err{};
            const QJsonDocument doc = QJsonDocument::fromJson(txJson.toUtf8(), &err);
            if (err.error != QJsonParseError::NoError || !doc.isObject())
                continue;
            // Flattened `id` on the legacy new-block payload; `mantle_tx.hash`
            // on the processed-block one. Both shapes are accepted so a tx id
            // copied from either still resolves.
            const QJsonObject txObj = doc.object();
            QString id = txObj.value(QStringLiteral("id")).toString();
            if (id.isEmpty())
                id = txObj.value(QStringLiteral("mantle_tx")).toObject()
                          .value(QStringLiteral("hash")).toString();
            if (!id.isEmpty() && normalize(id) == needle) {
                return QVariantMap{
                    {"found", true},
                    {"value", txJson},
                    {"blockId", e.blockId},
                    {"slot", e.slot},
                    {"timestamp", e.timestamp},
                };
            }
        }
    }
    return QVariantMap{{"found", false}};
}

void BlockModel::clear()
{
    if (m_entries.isEmpty())
        return;
    beginResetModel();
    m_entries.clear();
    endResetModel();
    emit countChanged();
}
