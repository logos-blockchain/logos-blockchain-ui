#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVector>

// Wallet accounts, from whichever source can answer.
class AccountsModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        AddressRole = Qt::UserRole + 1,
        BalanceRole,
        RolesRole,
        RoleLabelRole,
        LabelRole,
        NameRole,
    };

    explicit AccountsModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // From the node. Keeps each address's balance and roles across a refresh.
    void setAddresses(const QStringList& addresses);
    Q_INVOKABLE void setBalanceForAddress(const QString& address, const QString& balance);

    // Whether any account holds tokens. A balance that has not been fetched, or
    // whose fetch failed, is "---" rather than a figure — not zero, which is a
    // reading. Answering this as a bool rather than a total keeps u64 decimal
    // strings out of it: they overflow a double and only need comparing to zero.
    bool hasFunds() const;

    // From the config. Addresses not already present are added, because this
    // runs before any node has reported one — and addresses already present
    // keep their balances.
    void setRoles(const QHash<QString, QStringList>& rolesByAddress);
    void setNames(const QHash<QString, QString>& nameByAddress);

    // One account as a plain map: { address, roles, roleLabel, name, label }.
    //
    // For callers that need the rows *now* rather than through the model. The
    // model reaches QML as a QtRO replica, which reports its row count at once
    // but fetches row data in batches afterwards — fine for a list the user
    // scrolls, wrong for a combo box, which asks once as it opens and renders
    // whatever it got. Same composition either way, so the two can never
    // disagree about what a key is called.
    static QVariantMap describe(const QString& address, const QStringList& roles,
                               const QString& name = QString());

private:
    struct Entry {
        QString address;
        QString balance;
        QStringList roles;
        QString name;
        bool operator==(const Entry& other) const {
            return address == other.address && balance == other.balance
                && roles == other.roles && name == other.name;
        }
    };

    // Case and a leading 0x differ between the config file and the node, so
    // every cross-source comparison runs through this.
    static QString normalizeKey(const QString& hex);
    static QString shortHex(const QString& hex);
    static QString roleLabelOf(const Entry& entry);
    static QString labelOf(const Entry& entry);

    QVector<Entry> m_entries;
};
