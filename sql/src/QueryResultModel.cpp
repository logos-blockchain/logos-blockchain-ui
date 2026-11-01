#include "QueryResultModel.h"

#include <QVariantMap>
#include <QLocale>

QueryResultModel::QueryResultModel(QObject* parent)
    : QAbstractTableModel(parent)
{
}

int QueryResultModel::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : m_rows.size();
}

int QueryResultModel::columnCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : m_columns.size();
}

QVariant QueryResultModel::data(const QModelIndex& index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};

    const QVariantMap cell = m_rows.at(index.row()).toList().at(index.column()).toMap();
    const QString type = cell.value("type").toString();
    if (role == ValueType)
        return type;
    if (role != Qt::DisplayRole)
        return {};

    if (type == QStringLiteral("null"))
        return QStringLiteral("NULL");
    if (type == QStringLiteral("blob"))
        return QStringLiteral("X'%1'").arg(cell.value("value").toString());
    if (type == QStringLiteral("real"))
        return QString::number(cell.value("value").toDouble(), 'g', QLocale::FloatingPointShortest);

    return cell.value("value").toString();
}

QVariant QueryResultModel::headerData(int section, Qt::Orientation orientation, int role) const
{
    if (role != Qt::DisplayRole)
        return {};
    if (orientation == Qt::Horizontal && section >= 0 && section < m_columns.size())
        return m_columns.at(section);
    if (orientation == Qt::Vertical)
        return section + 1;

    return {};
}

QHash<int, QByteArray> QueryResultModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}, {ValueType, "valueType"}};
}

bool QueryResultModel::setResult(const QVariantMap& result)
{
    if (!result.contains("columns") || !result.contains("rows"))
        return false;

    const QStringList columns = result.value("columns").toStringList();
    const QVariantList rows = result.value("rows").toList();
    for (const QVariant& row : rows) {
        const QVariantList cells = row.toList();
        if (cells.size() != columns.size())
            return false;

        for (const QVariant& value : cells) {
            const QVariantMap cell = value.toMap();
            const QString type = cell.value("type").toString();
            if (type != QStringLiteral("null") && type != QStringLiteral("integer")
                && type != QStringLiteral("real") && type != QStringLiteral("text")
                && type != QStringLiteral("blob"))
                return false;
            if (type != QStringLiteral("null") && !cell.contains("value"))
                return false;
        }
    }

    beginResetModel();
    m_columns = columns;
    m_rows = rows;
    endResetModel();
    return true;
}

void QueryResultModel::clear()
{
    beginResetModel();
    m_columns.clear();
    m_rows.clear();
    endResetModel();
}
