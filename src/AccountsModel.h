#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVector>

class AccountsModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles { AddressRole = Qt::UserRole + 1, BalanceRole };

    explicit AccountsModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setAddresses(const QStringList& addresses);
    Q_INVOKABLE void setBalanceForAddress(const QString& address, const QString& balance);

private:
    struct Entry {
        QString address;
        QString balance;
        bool operator==(const Entry& other) const {
            return address == other.address && balance == other.balance;
        }
    };
    QVector<Entry> m_entries;
};
