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

    // Whether any account holds tokens. A balance that has not been fetched, or
    // whose fetch failed, is "---" rather than a figure — not zero, which is a
    // reading. Answering this as a bool rather than a total keeps u64 decimal
    // strings out of it: they overflow a double and only need comparing to zero.
    bool hasFunds() const;

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
