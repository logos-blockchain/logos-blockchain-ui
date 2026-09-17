#include "AccountsModel.h"

#include <algorithm>

int AccountsModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant AccountsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const Entry& e = m_entries.at(index.row());
    switch (role) {
    case AddressRole:
        return e.address;
    case BalanceRole:
        return e.balance;
    case RolesRole:
        return e.roles;
    case RoleLabelRole:
        return roleLabelOf(e);
    case LabelRole:
        return labelOf(e);
    case Qt::DisplayRole:
        return e.address;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AccountsModel::roleNames() const
{
    QHash<int, QByteArray> names;
    names[AddressRole] = "address";
    names[BalanceRole] = "balance";
    names[RolesRole] = "roles";
    names[RoleLabelRole] = "roleLabel";
    names[LabelRole] = "label";
    return names;
}

QString AccountsModel::normalizeKey(const QString& hex)
{
    QString out = hex.trimmed();
    if (out.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive))
        out = out.mid(2);
    return out.toLower();
}

QString AccountsModel::shortHex(const QString& hex)
{
    return hex.size() > 16 ? hex.left(8) + QStringLiteral("…") + hex.right(6) : hex;
}

QVariantMap AccountsModel::describe(const QString& address, const QStringList& roles)
{
    Entry e;
    e.address = address;
    e.roles = roles;
    return QVariantMap{
        {QStringLiteral("address"), address},
        {QStringLiteral("roles"), roles},
        {QStringLiteral("roleLabel"), roleLabelOf(e)},
        {QStringLiteral("label"), labelOf(e)},
    };
}

QString AccountsModel::roleLabelOf(const Entry& entry)
{
    // Every job, not the first: a generated config points the leader and SDP
    // wallets at the same funding key, and showing only one would hide that.
    return entry.roles.join(QStringLiteral(" · "));
}

QString AccountsModel::labelOf(const Entry& entry)
{
    const QString roles = roleLabelOf(entry);
    // An address the config gives no job is still a perfectly good claim
    // target; it just has nothing to announce, so it shows as itself.
    return roles.isEmpty() ? shortHex(entry.address)
                           : roles + QStringLiteral(" · ") + shortHex(entry.address);
}

void AccountsModel::setAddresses(const QStringList& addresses)
{
    QHash<QString, QString> balanceCache;
    // Roles come from the config, which the node knows nothing about — so a
    // node refresh has to carry them over rather than replace them with
    // nothing. The wizard may have filled them before any node existed.
    QHash<QString, QStringList> roleCache;
    for (const Entry& e : m_entries) {
        balanceCache.insert(e.address, e.balance);
        if (!e.roles.isEmpty())
            roleCache.insert(e.address, e.roles);
    }

    QVector<Entry> newEntries;
    newEntries.reserve(addresses.size());
    for (const QString& addr : addresses) {
        Entry e;
        e.address = addr;
        e.balance = balanceCache.value(addr, QStringLiteral("---"));
        e.roles = roleCache.value(addr);
        newEntries.append(e);
    }

    if (m_entries == newEntries)
        return;

    beginResetModel();
    m_entries = std::move(newEntries);
    endResetModel();
}

void AccountsModel::setRoles(const QHash<QString, QStringList>& rolesByAddress)
{
    // The two sources spell the same key differently — the config file and the
    // node disagree on case and on a leading 0x — so the join runs on a
    // normalised form while the displayed address stays as its source wrote it.
    QHash<QString, QStringList> byNormalized;
    QHash<QString, QString> originalOf;
    for (auto it = rolesByAddress.constBegin(); it != rolesByAddress.constEnd(); ++it) {
        const QString key = normalizeKey(it.key());
        byNormalized.insert(key, it.value());
        originalOf.insert(key, it.key());
    }

    QVector<Entry> newEntries = m_entries;

    for (Entry& e : newEntries) {
        const QString key = normalizeKey(e.address);
        e.roles = byNormalized.value(key);
        byNormalized.remove(key);
    }

    for (auto it = byNormalized.constBegin(); it != byNormalized.constEnd(); ++it) {
        Entry e;
        e.address = originalOf.value(it.key(), it.key());
        e.balance = QStringLiteral("---");
        e.roles = it.value();
        newEntries.append(e);
    }

    if (m_entries == newEntries)
        return;

    beginResetModel();
    m_entries = std::move(newEntries);
    endResetModel();
}

void AccountsModel::setBalanceForAddress(const QString& address, const QString& balance)
{
    const QString valueToSet = balance.trimmed().startsWith(QStringLiteral("Error"))
        ? QStringLiteral("---")
        : balance;
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].address == address) {
            if (m_entries[i].balance != valueToSet) {
                m_entries[i].balance = valueToSet;
                const QModelIndex idx = index(i, 0);
                emit dataChanged(idx, idx, { BalanceRole });
            }
            return;
        }
    }
}

bool AccountsModel::hasFunds() const
{
    for (const Entry& e : m_entries) {
        const QString balance = e.balance.trimmed();
        bool digitsOnly = !balance.isEmpty();
        bool nonZero = false;
        for (const QChar c : balance) {
            if (!c.isDigit()) { digitsOnly = false; break; }
            if (c != QLatin1Char('0')) nonZero = true;
        }
        if (digitsOnly && nonZero)
            return true;
    }
    return false;
}
