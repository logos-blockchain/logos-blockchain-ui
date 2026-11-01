#include "SqlBackend.h"

#include "logos_api.h"
#include "logos_api_client.h"

#include <QCryptographicHash>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <memory>

namespace {

const QString kModuleName = QStringLiteral("sql_module");
constexpr quint64 kOpenTimeoutMs = 30000;
constexpr int kCallTimeoutMs = 45000;
constexpr int kShutdownTimeoutMs = 5000;
constexpr quint64 kResultByteLimit = 16 * 1024 * 1024;
constexpr quint64 kSchemaRowLimit = 10000;
constexpr int kMaxQueryRows = 100000;
constexpr int kRecentConnectionLimit = 10;

QString userDirStateDir()
{
    const QString userDir = qEnvironmentVariable("LOGOS_USER_DIR");
    return userDir.isEmpty() ? QString() : QDir(userDir).filePath(QStringLiteral("SqlExplorer"));
}

std::unique_ptr<QSettings> appSettings()
{
    const QString directory = userDirStateDir();
    if (directory.isEmpty())
        return std::make_unique<QSettings>(QStringLiteral("Logos"), QStringLiteral("SqlExplorer"));

    QDir().mkpath(directory);
    return std::make_unique<QSettings>(QDir(directory).filePath(QStringLiteral("settings.ini")),
                                       QSettings::IniFormat);
}

QString describeCallError(const logos::CallError& error)
{
    if (error.code == "timeout")
        return QObject::tr("The SQL module did not answer in time. The operation may still be running.");
    if (error.code == "object_unavailable")
        return QObject::tr("The SQL module is not available. Check that it is running.");
    if (error.code == "transport_error")
        return QObject::tr("The connection to the SQL module failed: %1")
            .arg(QString::fromStdString(error.message));

    const QString detail = QString::fromStdString(error.message);
    return detail.isEmpty() ? QObject::tr("The SQL module call failed.") : detail;
}

QVariantMap success(const QVariant& value = {})
{
    return {{"success", true}, {"value", value}, {"error", QVariant()}};
}

} // namespace

SqlBackend::SqlBackend(LogosAPI* api, QObject* parent)
    : SqlBackendSimpleSource(parent)
    , m_results(new QueryResultModel(this))
{
    setConnected(false);
    setBusy(false);
    setReadView(QStringLiteral("latest"));
    setReturnedRows(0);
    setTruncated(false);

    const auto settings = appSettings();
    setNodeUrl(settings->value("nodeUrl", "http://127.0.0.1:8080").toString());
    setChannelId(settings->value("channelId").toString());
    setRecentConnections(settings->value("recentConnections").toList());
    if (api)
        m_client = api->getClient(kModuleName);
}

SqlBackend::~SqlBackend()
{
    if (m_client && !m_databaseId.isEmpty()) {
        m_client->invokeRemoteMethod(kModuleName, QStringLiteral("close"),
                                    QVariantList{m_databaseId}, Timeout(kShutdownTimeoutMs));
    }
}

QVariantMap SqlBackend::fail(const QString& message)
{
    setLastError(message);
    return {{"success", false}, {"value", QVariant()}, {"error", message}};
}

QVariantMap SqlBackend::call(const QString& method, const QVariantList& arguments)
{
    logos::CallError error;
    QVariant reply;
    QString message;

    if (!m_client) {
        message = tr("The SQL module is not available.");
    } else {
        reply = m_client->invokeRemoteMethod(kModuleName, method, arguments,
                                            Timeout(kCallTimeoutMs), &error);
        if (!error.ok())
            message = describeCallError(error);
        else if (!reply.isValid() || !reply.canConvert<LogosResult>())
            message = tr("The SQL module returned an invalid reply.");
    }

    if (!message.isEmpty()) {
        QVariantMap failure = fail(message);
        // Without a reply, close may or may not have consumed the handle.
        // Keep the replica ID so the caller can retry rather than lose access.
        failure.insert("transportFailure", true);
        return failure;
    }

    const LogosResult result = reply.value<LogosResult>();
    if (!result.success) {
        const QString error = result.error.toString();
        return fail(error.isEmpty() ? tr("The SQL operation failed.") : error);
    }

    return success(result.value);
}

void SqlBackend::clearResults()
{
    m_results->clear();
    setColumns({});
    setReturnedRows(0);
    setTruncated(false);
}

void SqlBackend::clearChannel()
{
    m_databaseId.clear();
    setConnected(false);
    setStateDirectory({});
    setTables({});
    clearResults();
}

QVariantMap SqlBackend::openChannel(QString nodeUrl, QString channelId)
{
    if (busy())
        return fail(tr("An operation is already running."));

    const QUrl url(nodeUrl.trimmed());
    channelId = channelId.trimmed().toLower();
    static const QRegularExpression channelPattern(QStringLiteral("^[0-9a-f]{64}$"));
    if (!url.isValid() || url.host().isEmpty()
        || !url.userInfo().isEmpty() || url.hasQuery() || url.hasFragment()
        || (url.scheme() != QStringLiteral("http") && url.scheme() != QStringLiteral("https")))
        return fail(tr("Enter an HTTP or HTTPS node URL."));
    if (!channelPattern.match(channelId).hasMatch())
        return fail(tr("The channel ID must contain 64 hexadecimal characters."));

    setBusy(true);
    const auto finished = qScopeGuard([this] { setBusy(false); });
    setLastError({});

    if (!m_databaseId.isEmpty()) {
        const QVariantMap closed = call(QStringLiteral("close"), {m_databaseId});
        if (closed.value("transportFailure").toBool())
            return closed;

        // close consumes the module handle even when shutdown reports an error.
        clearChannel();
        if (!closed.value("success").toBool())
            return closed;
    }

    // Reuse the same replica on later visits, but keep different nodes and
    // channels in separate directories so their checkpoints cannot mix.
    const QString node = url.adjusted(QUrl::StripTrailingSlash).toString();
    const QByteArray key = QCryptographicHash::hash(
        (node + QStringLiteral("/") + channelId).toUtf8(), QCryptographicHash::Sha256).toHex();
    QString root = userDirStateDir();
    if (root.isEmpty()) {
        const QString data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        if (!data.isEmpty())
            root = QDir(data).filePath(QStringLiteral("Logos/SqlExplorer"));
    }
    if (root.isEmpty())
        return fail(tr("No writable application data directory is available."));

    const QString directory = QDir(root).filePath(QStringLiteral("sql-replicas/") + QString::fromLatin1(key));
    const QJsonObject config{
        {"node_url", node},
        {"channel_id", channelId},
        {"state_dir", directory}
    };
    const QVariantMap opened = call(QStringLiteral("open"), {
        QString::fromUtf8(QJsonDocument(config).toJson(QJsonDocument::Compact)),
        QVariant::fromValue(kOpenTimeoutMs)
    });
    if (!opened.value("success").toBool())
        return opened;

    m_databaseId = opened.value("value").toString();
    if (m_databaseId.isEmpty())
        return fail(tr("The SQL module returned no replica ID."));

    setNodeUrl(node);
    setChannelId(channelId);
    setStateDirectory(directory);
    setConnected(true);
    const QVariantMap schema = loadSchema();
    if (schema.value("success").toBool())
        rememberConnection();

    return schema;
}

void SqlBackend::rememberConnection()
{
    const QVariantMap connection{{"nodeUrl", nodeUrl()}, {"channelId", channelId()}};
    QVariantList recent = recentConnections();
    recent.removeAll(connection);
    recent.prepend(connection);

    // Bound the saved list so the connection picker stays useful as channels accumulate.
    while (recent.size() > kRecentConnectionLimit)
        recent.removeLast();

    setRecentConnections(recent);

    const auto settings = appSettings();
    settings->setValue("nodeUrl", nodeUrl());
    settings->setValue("channelId", channelId());
    settings->setValue("recentConnections", recent);
}

QVariantMap SqlBackend::closeChannel()
{
    if (busy())
        return fail(tr("An operation is already running."));

    setBusy(true);
    const auto finished = qScopeGuard([this] { setBusy(false); });
    setLastError({});

    const QVariantMap result = m_databaseId.isEmpty()
        ? success() : call(QStringLiteral("close"), {m_databaseId});
    if (result.value("transportFailure").toBool())
        return result;

    clearChannel();
    return result;
}

QVariantMap SqlBackend::loadSchema()
{
    const QVariantMap result = call(QStringLiteral("query"), {
        m_databaseId,
        readView(),
        QStringLiteral("SELECT name, type, sql FROM sqlite_schema "
                       "WHERE type IN ('table', 'view') AND name NOT GLOB 'sqlite_*' ORDER BY name"),
        QStringLiteral("[]"),
        QVariant::fromValue(kSchemaRowLimit),
        QVariant::fromValue(kResultByteLimit)
    });
    if (!result.value("success").toBool())
        return result;

    const QVariantMap data = result.value("value").toMap();
    if (!data.contains("rows") || data.value("truncated").toBool())
        return fail(tr("The complete table list could not be loaded. Query sqlite_schema directly."));

    QVariantList entries;
    for (const QVariant& row : data.value("rows").toList()) {
        const QVariantList cells = row.toList();
        if (cells.size() != 3)
            return fail(tr("The SQL module returned an invalid schema row."));

        entries.append(QVariantMap{
            {"name", cells[0].toMap().value("value").toString()},
            {"type", cells[1].toMap().value("value").toString()},
            {"sql", cells[2].toMap().value("value").toString()}
        });
    }
    setTables(entries);
    return success();
}

QVariantMap SqlBackend::refreshSchema(QString view)
{
    if (busy())
        return fail(tr("An operation is already running."));
    if (!connected())
        return fail(tr("Open a channel first."));
    if (view != QStringLiteral("latest") && view != QStringLiteral("finalized"))
        return fail(tr("Unknown read view."));

    setBusy(true);
    const auto finished = qScopeGuard([this] { setBusy(false); });
    setLastError({});
    setReadView(view);
    setTables({});
    clearResults();
    return loadSchema();
}

QVariantMap SqlBackend::query(const QString& sql, const QString& parameters, int maxRows)
{
    if (busy())
        return fail(tr("An operation is already running."));
    if (!connected())
        return fail(tr("Open a channel first."));
    if (maxRows < 1 || maxRows > kMaxQueryRows)
        return fail(tr("Row limit must be between 1 and %L1.").arg(kMaxQueryRows));

    setBusy(true);
    const auto finished = qScopeGuard([this] { setBusy(false); });
    setLastError({});
    const QVariantMap result = call(QStringLiteral("query"), {
        m_databaseId,
        readView(),
        sql,
        parameters,
        QVariant::fromValue(quint64(maxRows)),
        QVariant::fromValue(kResultByteLimit)
    });
    if (!result.value("success").toBool())
        return result;

    const QVariantMap data = result.value("value").toMap();
    if (!m_results->setResult(data))
        return fail(tr("The SQL module returned an invalid result."));

    setColumns(m_results->columns());
    setReturnedRows(m_results->rowCount());
    setTruncated(data.value("truncated").toBool());
    return success();
}

QVariantMap SqlBackend::browseTable(QString tableName, int offset, int pageSize)
{
    if (offset < 0)
        return fail(tr("Row offset cannot be negative."));
    if (pageSize < 1 || pageSize > kMaxQueryRows)
        return fail(tr("Page size must be between 1 and %L1.").arg(kMaxQueryRows));

    tableName.replace('"', QStringLiteral("\"\""));
    const QString sql = QStringLiteral("SELECT * FROM \"%1\" LIMIT ?1 OFFSET ?2").arg(tableName);
    // Read one extra row so the bindings can report truncated and enable Next,
    // while returning at most pageSize rows to the table.
    const QJsonArray parameters{
        QJsonObject{{"type", "integer"}, {"value", QString::number(pageSize + 1)}},
        QJsonObject{{"type", "integer"}, {"value", QString::number(offset)}}
    };
    return query(sql, QString::fromUtf8(QJsonDocument(parameters).toJson(QJsonDocument::Compact)), pageSize);
}

QVariantMap SqlBackend::runQuery(QString sql, int maxRows)
{
    return query(sql, QStringLiteral("[]"), maxRows);
}
