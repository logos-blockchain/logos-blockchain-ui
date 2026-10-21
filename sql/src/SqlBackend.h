#pragma once

#include "rep_SqlBackend_source.h"
#include "QueryResultModel.h"

class LogosAPI;
class LogosAPIClient;

// Like the node UI, this backend runs in the view-module host. QML calls its
// slots asynchronously with logos.watch(), keeping SQL off the render thread.
class SqlBackend : public SqlBackendSimpleSource
{
    Q_OBJECT
    Q_PROPERTY(QueryResultModel* results READ results CONSTANT)

public:
    explicit SqlBackend(LogosAPI* api, QObject* parent = nullptr);
    ~SqlBackend() override;
    QueryResultModel* results() const { return m_results; }

    QVariantMap openChannel(QString nodeUrl, QString channelId) override;
    QVariantMap closeChannel() override;
    QVariantMap refreshSchema(QString view) override;
    QVariantMap browseTable(QString tableName, int offset, int pageSize) override;
    QVariantMap runQuery(QString sql, int maxRows) override;

private:
    QVariantMap call(const QString& method, const QVariantList& arguments);
    QVariantMap query(const QString& sql, const QString& parameters, int maxRows);
    QVariantMap loadSchema();
    QVariantMap fail(const QString& message);
    void clearResults();
    void clearChannel();
    void rememberConnection();

    LogosAPIClient* m_client = nullptr;
    QueryResultModel* m_results;
    QString m_databaseId;
};
