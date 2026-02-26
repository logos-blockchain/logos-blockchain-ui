#include "AccountsModel.h"

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
    return names;
}

void AccountsModel::setAddresses(const QStringList& addresses)
{
    QHash<QString, QString> balanceCache;
    for (const Entry& e : m_entries)
        balanceCache.insert(e.address, e.balance);

    QVector<Entry> newEntries;
    newEntries.reserve(addresses.size());
    for (const QString& addr : addresses) {
        Entry e;
        e.address = addr;
        e.balance = balanceCache.value(addr, QStringLiteral("---"));
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
