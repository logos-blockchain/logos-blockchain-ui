#include "LogModel.h"

int LogModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_lines.size();
}

QVariant LogModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_lines.size())
        return QVariant();
    if (role == TextRole || role == Qt::DisplayRole)
        return m_lines.at(index.row());
    return QVariant();
}

QHash<int, QByteArray> LogModel::roleNames() const
{
    QHash<int, QByteArray> names;
    names[TextRole] = "text";
    return names;
}

void LogModel::append(const QString& line)
{
    const int row = m_lines.size();
    beginInsertRows(QModelIndex(), row, row);
    m_lines.append(line);
    endInsertRows();
    emit countChanged();
}

void LogModel::clear()
{
    if (m_lines.isEmpty())
        return;
    beginResetModel();
    m_lines.clear();
    endResetModel();
    emit countChanged();
}
