#include "ClaimLedger.h"

#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>

namespace {

constexpr int kFormatVersion = 1;

// Whether a value is the plain non-negative decimal the ledger stores. Values
// the app writes always are; values read back from the file have been outside
// its control since.
bool isDecimal(const QString& value)
{
    if (value.isEmpty())
        return false;
    for (const QChar c : value) {
        if (c.digitValue() < 0)
            return false;
    }
    return true;
}

QString kindToString(ClaimLedger::Kind kind)
{
    return kind == ClaimLedger::Kind::Mining ? QStringLiteral("mining")
                                             : QStringLiteral("staking");
}

// Staking is the default on purpose: it is what a ledger written before mining
// joined it contains, and those files carry no kind at all.
ClaimLedger::Kind kindFromString(const QString& text)
{
    return text == QLatin1String("mining") ? ClaimLedger::Kind::Mining
                                           : ClaimLedger::Kind::Staking;
}

QString recordKey(ClaimLedger::Kind kind, const QString& nullifier)
{
    return kindToString(kind) + QLatin1Char(':') + nullifier;
}

} // namespace

const QString ClaimLedger::kAnyTx = QStringLiteral("*");

const ClaimLedger::Pending::TxClaim* ClaimLedger::Pending::claimFor(const QString& txHash) const
{
    const auto exact = claims.constFind(txHash);
    if (exact != claims.constEnd())
        return &*exact;
    const auto wildcard = claims.constFind(kAnyTx);
    return wildcard != claims.constEnd() ? &*wildcard : nullptr;
}

QString ClaimLedger::addLepta(const QString& a, const QString& b)
{
    if (a.isEmpty())
        return b;
    if (b.isEmpty())
        return a;

    QString sum;
    sum.reserve(std::max(a.size(), b.size()) + 1);

    int carry = 0;
    for (qsizetype i = a.size() - 1, j = b.size() - 1; i >= 0 || j >= 0 || carry; --i, --j) {
        const int lhs = i >= 0 ? a.at(i).digitValue() : 0;
        const int rhs = j >= 0 ? b.at(j).digitValue() : 0;
        // A non-digit means the value was not what the node said it was. Bail
        // rather than silently reading it as a zero and under-reporting.
        if (lhs < 0 || rhs < 0)
            return QStringLiteral("0");
        const int digit = lhs + rhs + carry;
        sum.prepend(QChar(u'0' + digit % 10));
        carry = digit / 10;
    }
    return sum.isEmpty() ? QStringLiteral("0") : sum;
}

void ClaimLedger::load(const QString& path, const QString& chainId)
{
    m_records.clear();
    m_byKey.clear();
    m_pending.clear();
    m_countingSince.clear();
    m_chainId = chainId;

    QFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::ReadOnly))
        return;

    // A truncated or hand-edited file starts the tally from zero, which is
    // indistinguishable on the tile from having earned nothing. Nothing here
    // can recover it, but it should not pass in silence.
    QJsonParseError parseError{};
    const QJsonObject root = QJsonDocument::fromJson(file.readAll(), &parseError).object();
    if (parseError.error != QJsonParseError::NoError) {
        qWarning() << "ClaimLedger: unreadable, starting a new tally -" << path
                   << parseError.errorString();
        return;
    }
    if (root.value(QStringLiteral("version")).toInt() != kFormatVersion) {
        qWarning() << "ClaimLedger: unsupported format version, starting a new tally -" << path;
        return;
    }

    const QString fileChain = root.value(QStringLiteral("chain_id")).toString();
    if (fileChain != chainId) {
        qInfo() << "ClaimLedger: discarding records for chain" << fileChain
                << "- node is on" << chainId;
        return;
    }

    m_countingSince = root.value(QStringLiteral("counting_since")).toString();

    const QJsonArray records = root.value(QStringLiteral("records")).toArray();
    for (const QJsonValue& entry : records) {
        const QJsonObject o = entry.toObject();
        Record record;
        record.kind = kindFromString(o.value(QStringLiteral("kind")).toString());
        record.nullifier = o.value(QStringLiteral("nullifier")).toString();
        record.value = o.value(QStringLiteral("value")).toString();
        record.payee = o.value(QStringLiteral("pk")).toString();
        record.blockId = o.value(QStringLiteral("block")).toString();
        record.txHash = o.value(QStringLiteral("tx")).toString();
        record.slot = static_cast<quint64>(o.value(QStringLiteral("slot")).toInteger());
        add(record);
    }

    const QJsonArray pending = root.value(QStringLiteral("pending")).toArray();
    for (const QJsonValue& entry : pending) {
        const QJsonObject o = entry.toObject();
        Pending block;
        block.blockId = o.value(QStringLiteral("block")).toString();
        if (block.blockId.isEmpty())
            continue;
        block.slot = static_cast<quint64>(o.value(QStringLiteral("slot")).toInteger());
        block.attempts = o.value(QStringLiteral("attempts")).toInt();

        const QJsonObject claims = o.value(QStringLiteral("claims")).toObject();
        for (auto it = claims.constBegin(); it != claims.constEnd(); ++it) {
            Pending::TxClaim claim;
            const QJsonObject c = it.value().toObject();
            for (const QJsonValue& pk : c.value(QStringLiteral("payees")).toArray())
                claim.payees << pk.toString();
            block.claims.insert(it.key(), claim);
        }

        const QJsonArray legacy = o.value(QStringLiteral("beneficiaries")).toArray();
        if (!legacy.isEmpty() && block.claims.isEmpty()) {
            Pending::TxClaim claim;
            for (const QJsonValue& pk : legacy)
                claim.payees << pk.toString();
            block.claims.insert(kAnyTx, claim);
        }

        m_pending.append(block);
    }
}

bool ClaimLedger::save(const QString& path) const
{
    if (path.isEmpty())
        return false;

    QJsonArray records;
    for (const Record& record : m_records) {
        QJsonObject o;
        o[QStringLiteral("kind")] = kindToString(record.kind);
        o[QStringLiteral("nullifier")] = record.nullifier;
        o[QStringLiteral("value")] = record.value;
        o[QStringLiteral("pk")] = record.payee;
        o[QStringLiteral("block")] = record.blockId;
        o[QStringLiteral("tx")] = record.txHash;
        o[QStringLiteral("slot")] = static_cast<qint64>(record.slot);
        records.append(o);
    }

    QJsonArray pending;
    for (const Pending& block : m_pending) {
        QJsonObject o;
        o[QStringLiteral("block")] = block.blockId;
        o[QStringLiteral("slot")] = static_cast<qint64>(block.slot);
        o[QStringLiteral("attempts")] = block.attempts;

        QJsonObject claims;
        for (auto it = block.claims.constBegin(); it != block.claims.constEnd(); ++it) {
            QJsonObject c;
            QJsonArray payees;
            for (const QString& pk : it.value().payees)
                payees.append(pk);
            c[QStringLiteral("payees")] = payees;
            claims.insert(it.key(), c);
        }
        o[QStringLiteral("claims")] = claims;
        pending.append(o);
    }

    QJsonObject root;
    root[QStringLiteral("version")] = kFormatVersion;
    root[QStringLiteral("chain_id")] = m_chainId;
    if (!m_countingSince.isEmpty())
        root[QStringLiteral("counting_since")] = m_countingSince;
    root[QStringLiteral("records")] = records;
    root[QStringLiteral("pending")] = pending;

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "ClaimLedger: cannot write" << path << file.errorString();
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!file.commit()) {
        qWarning() << "ClaimLedger: failed to commit" << path << file.errorString();
        return false;
    }

    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

bool ClaimLedger::add(const Record& record)
{
    if (record.nullifier.isEmpty() || record.value.isEmpty())
        return false;

    const QString key = recordKey(record.kind, record.nullifier);
    const auto existing = m_byKey.constFind(key);
    if (existing != m_byKey.constEnd()) {
        m_records[*existing].blockId = record.blockId;
        m_records[*existing].txHash = record.txHash;
        m_records[*existing].slot = record.slot;
        return false;
    }

    m_byKey.insert(key, static_cast<int>(m_records.size()));
    m_records.append(record);
    return true;
}

int ClaimLedger::confirmedCount(Kind kind, quint64 libSlot) const
{
    int count = 0;
    for (const Record& record : m_records) {
        if (record.kind == kind && record.slot <= libSlot)
            ++count;
    }
    return count;
}

QString ClaimLedger::confirmedTotal(Kind kind, quint64 libSlot) const
{
    QString total = QStringLiteral("0");
    for (const Record& record : m_records) {
        if (record.kind != kind || record.slot > libSlot)
            continue;
        if (!isDecimal(record.value)) {
            qWarning() << "ClaimLedger: skipping claim with unreadable value -" << record.nullifier
                       << record.value;
            continue;
        }
        total = addLepta(total, record.value);
    }
    return total;
}

