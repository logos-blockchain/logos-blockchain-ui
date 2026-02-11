#pragma once

#include <QAbstractListModel>
#include <QStringList>

class LogModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Roles { TextRole = Qt::UserRole + 1 };

    explicit LogModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void append(const QString& line);
    Q_INVOKABLE void clear();

signals:
    void countChanged();

private:
    QStringList m_lines;
};
