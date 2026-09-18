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
    case NameRole:
        return e.name;
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
    names[NameRole] = "name";
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

QVariantMap AccountsModel::describe(const QString& address, const QStringList& roles,
                                    const QString& name)
{
    Entry e;
    e.address = address;
    e.roles = roles;
    e.name = name;
    return QVariantMap{
        {QStringLiteral("address"), address},
        {QStringLiteral("roles"), roles},
        {QStringLiteral("roleLabel"), roleLabelOf(e)},
        {QStringLiteral("name"), name},
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
    // The keystore titles every key; the config only titles the ones it wires
    // to a job. Prefer the title, so a picker reads "Stake · 8aebe859" rather
    // than bare hex for the keys an operator most needs to recognise.
    const QString title = entry.name.isEmpty() ? roleLabelOf(entry) : entry.name;
    // An address neither source names is still a perfectly good claim target;
    // it just has nothing to announce, so it shows as itself.
    return title.isEmpty() ? shortHex(entry.address)
                           : title + QStringLiteral(" · ") + shortHex(entry.address);
}

void AccountsModel::setAddresses(const QStringList& addresses)
{
    QHash<QString, QString> balanceCache;
    // Roles come from the config, which the node knows nothing about — so a
    // node refresh has to carry them over rather than replace them with
    // nothing. The wizard may have filled them before any node existed.
    QHash<QString, QStringList> roleCache;
    QHash<QString, QString> nameCache;
    for (const Entry& e : m_entries) {
        const QString key = normalizeKey(e.address);
        balanceCache.insert(key, e.balance);
        if (!e.roles.isEmpty())
            roleCache.insert(key, e.roles);
        if (!e.name.isEmpty())
            nameCache.insert(key, e.name);
    }

    QVector<Entry> newEntries;
    newEntries.reserve(addresses.size());
    for (const QString& addr : addresses) {
        const QString key = normalizeKey(addr);
        Entry e;
        e.address = addr;
        e.balance = balanceCache.value(key, QStringLiteral("---"));
        e.roles = roleCache.value(key);
        e.name = nameCache.value(key);
        newEntries.append(e);
    }

    if (m_entries == newEntries)
        return;

    beginResetModel();
    m_entries = std::move(newEntries);
    endResetModel();
}

void AccountsModel::setNames(const QHash<QString, QString>& nameByAddress)
{
    // Same normalised join as setRoles: the keystore and the node spell a key
    // differently (case, and a leading 0x).
    QHash<QString, QString> byNormalized;
    for (auto it = nameByAddress.constBegin(); it != nameByAddress.constEnd(); ++it)
        byNormalized.insert(normalizeKey(it.key()), it.value());

    QVector<Entry> newEntries = m_entries;
    bool changed = false;
    for (Entry& e : newEntries) {
        const QString name = byNormalized.value(normalizeKey(e.address));
        if (e.name != name) {
            e.name = name;
            changed = true;
        }
    }
    // Deliberately no rows added for keystore keys the node never reports: the
    // keystore holds keys that are not wallet accounts (the Blend signing key,
    // the network swarm key), and listing them as accounts would be wrong.
    if (!changed)
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
    // `e.name` is left alone: it comes from the keystore, which this read knows
    // nothing about.

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
