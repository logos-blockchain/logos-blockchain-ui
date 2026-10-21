#pragma once

#include <QAbstractTableModel>
#include <QStringList>
#include <QVariantList>

// Keep integer strings and blob hex intact across Qt Remote Objects and QML.
class QueryResultModel : public QAbstractTableModel
{
    Q_OBJECT

public:
    enum Role { ValueType = Qt::UserRole + 1 };

    explicit QueryResultModel(QObject* parent = nullptr);
    int rowCount(const QModelIndex& parent = {}) const override;
    int columnCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool setResult(const QVariantMap& result);
    void clear();
    QStringList columns() const { return m_columns; }

private:
    QStringList m_columns;
    QVariantList m_rows;
};
