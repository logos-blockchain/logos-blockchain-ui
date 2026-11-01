#include "SqlBackend.h"
#include "logos_api.h"

#include <QAbstractItemModelTester>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

namespace {
QVariant cell(const QString& type, QVariant value = {})
{
    return QVariantMap{{"type", type}, {"value", value}};
}

QVariantMap result(const QStringList& columns, const QVariantList& rows, bool truncated = false)
{
    return {{"columns", columns}, {"rows", rows}, {"truncated", truncated}};
}

void open(SqlBackend& backend, LogosAPIClient& client, const QString& channel = QString(64, 'a'))
{
    client.succeed("replica-1");
    client.succeed(result({"name", "type", "sql"}, {}));
    QVERIFY(backend.openChannel("http://localhost:8080", channel).value("success").toBool());
}
}

class ExplorerTest : public QObject
{
    Q_OBJECT
    QTemporaryDir m_settings;
    QByteArray m_previousUserDir;

private slots:
    void initTestCase()
    {
        QVERIFY(m_settings.isValid());
        QStandardPaths::setTestModeEnabled(true);
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settings.path());
        m_previousUserDir = qgetenv("LOGOS_USER_DIR");
        qputenv("LOGOS_USER_DIR", m_settings.path().toUtf8());
    }

    void cleanupTestCase()
    {
        if (m_previousUserDir.isNull())
            qunsetenv("LOGOS_USER_DIR");
        else
            qputenv("LOGOS_USER_DIR", m_previousUserDir);
    }

    void init()
    {
        QSettings settings(m_settings.path() + "/SqlExplorer/settings.ini", QSettings::IniFormat);
        settings.clear();
    }

    void displaysSqlValuesWithoutLosingPrecision()
    {
        QueryResultModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        const QVariantList row{cell("integer", "9223372036854775807"), cell("null"),
                               cell("blob", "00ff"), cell("text", "hello"), cell("real", 0.1)};
        QVERIFY(model.setResult(result({"id", "empty", "bytes", "label", "number"}, {QVariant(row)})));
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.columnCount(), 5);
        QCOMPARE(model.data(model.index(0, 0)).toString(), QString("9223372036854775807"));
        QCOMPARE(model.data(model.index(0, 1)).toString(), QString("NULL"));
        QCOMPARE(model.data(model.index(0, 1), QueryResultModel::ValueType).toString(), QString("null"));
        QCOMPARE(model.data(model.index(0, 2)).toString(), QString("X'00ff'"));
        QCOMPARE(model.data(model.index(0, 4)).toString(), QString("0.1"));
        QCOMPARE(model.headerData(0, Qt::Horizontal, Qt::DisplayRole).toString(), QString("id"));
        QVERIFY(!model.setResult(result({"id"}, {QVariant(row)})));
        QCOMPARE(model.rowCount(), 1);
        model.clear();
        QCOMPARE(model.rowCount(), 0);
    }

    void opensReplicaAndSelectsFinalizedView()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        open(backend, api.client);
        QVERIFY(backend.connected());
        const QJsonObject config = QJsonDocument::fromJson(api.client.calls[0].arguments[0].toString().toUtf8()).object();
        QCOMPARE(config.value("channel_id").toString(), QString(64, 'a'));
        QVERIFY(!config.contains("writer"));
        QVERIFY(config.value("state_dir").toString().contains("sql-replicas/"));
        QVERIFY(backend.stateDirectory().startsWith(m_settings.path() + "/SqlExplorer/"));
        const QSettings settings(m_settings.path() + "/SqlExplorer/settings.ini", QSettings::IniFormat);
        QCOMPARE(settings.value("channelId").toString(), QString(64, 'a'));

        api.client.succeed(result({"name", "type", "sql"}, {}));
        const QVariantMap reply = backend.refreshSchema("finalized");
        QVERIFY(reply.value("success").toBool());
        QVERIFY(reply.contains("value"));
        QVERIFY(reply.contains("error"));
        QCOMPARE(api.client.calls.last().arguments[1].toString(), QString("finalized"));
        QCOMPARE(backend.readView(), QString("finalized"));
    }

    void quotesTableNamesAndBindsPagination()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        open(backend, api.client);
        api.client.succeed(result({"id"}, {QVariant(QVariantList{cell("integer", "1")})}, true));
        QVERIFY(backend.browseTable("a\"b", 200, 200).value("success").toBool());
        const QVariantList arguments = api.client.calls.last().arguments;
        QCOMPARE(arguments[2].toString(), QString("SELECT * FROM \"a\"\"b\" LIMIT ?1 OFFSET ?2"));
        const QJsonArray parameters = QJsonDocument::fromJson(arguments[3].toString().toUtf8()).array();
        QCOMPARE(parameters[0].toObject().value("value").toString(), QString("201"));
        QCOMPARE(parameters[1].toObject().value("value").toString(), QString("200"));
        QCOMPARE(arguments[4].toULongLong(), quint64(200));
        QCOMPARE(backend.returnedRows(), 1);
        QVERIFY(backend.truncated());

        api.client.fail("read-only query required");
        QVERIFY(!backend.runQuery("DELETE FROM x", 200).value("success").toBool());
        QCOMPARE(backend.results()->rowCount(), 1);
        QVERIFY(backend.truncated());
        QCOMPARE(backend.lastError(), QString("read-only query required"));
        QVERIFY(!backend.busy());
    }

    void remembersOnlySuccessfulConnections()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        const QString channel(64, 'a');

        auto openAt = [&](const QString& node) {
            if (backend.connected())
                api.client.succeed();

            api.client.succeed("replica");
            api.client.succeed(result({"name", "type", "sql"}, {}));
            QVERIFY(backend.openChannel(node, channel).value("success").toBool());
        };

        openAt("http://localhost:8080");
        openAt("http://localhost:8081");
        QCOMPARE(backend.recentConnections().size(), 2);

        // Reopening moves the pair to the front rather than adding a duplicate.
        openAt("http://localhost:8080");
        const QVariantList recent = backend.recentConnections();
        QCOMPARE(recent.size(), 2);
        QCOMPARE(recent[0].toMap().value("nodeUrl").toString(), QString("http://localhost:8080"));
        QCOMPARE(recent[0].toMap().value("channelId").toString(), channel);
        QCOMPARE(recent[1].toMap().value("nodeUrl").toString(), QString("http://localhost:8081"));

        api.client.succeed();
        api.client.fail("could not open channel");
        QVERIFY(!backend.openChannel("http://localhost:8082", channel).value("success").toBool());
        QCOMPARE(backend.recentConnections(), recent);

        SqlBackend restored(nullptr);
        QCOMPARE(restored.recentConnections(), recent);
        QCOMPARE(restored.nodeUrl(), QString("http://localhost:8080"));
    }

    void transportFailureDoesNotForgetAnOpenReplica()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        open(backend, api.client);

        api.client.failTransport("timeout");
        const QVariantMap reply = backend.closeChannel();
        QVERIFY(!reply.value("success").toBool());
        QVERIFY(reply.contains("value"));
        QVERIFY(reply.contains("error"));
        QVERIFY(reply.value("transportFailure").toBool());
        QVERIFY(backend.connected());
        QVERIFY(backend.lastError().contains("may still be running"));

        api.client.failTransport("object_unavailable");
        QVERIFY(!backend.openChannel("http://localhost:8080", QString(64, 'b')).value("success").toBool());
        QVERIFY(backend.connected());
        QCOMPARE(backend.channelId(), QString(64, 'a'));
        QVERIFY(backend.lastError().contains("not available"));

        api.client.succeed();
        QVERIFY(backend.closeChannel().value("success").toBool());
        QCOMPARE(api.client.calls.last().arguments[0].toString(), QString("replica-1"));
        QVERIFY(!backend.connected());
    }

    void switchesChannelsAndClearsClosedReplica()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        open(backend, api.client);
        const QString previousDirectory = backend.stateDirectory();
        api.client.succeed();
        open(backend, api.client, QString(64, 'b'));
        QCOMPARE(api.client.calls[2].method, QString("close"));
        QVERIFY(backend.stateDirectory() != previousDirectory);

        api.client.fail("shutdown error");
        QVERIFY(!backend.closeChannel().value("success").toBool());
        QVERIFY(!backend.connected());
        QVERIFY(backend.tables().isEmpty());
        QVERIFY(backend.stateDirectory().isEmpty());
    }

    void invalidConnectionDoesNotCloseCurrentChannel()
    {
        LogosAPI api;
        SqlBackend backend(&api);
        open(backend, api.client);
        const qsizetype calls = api.client.calls.size();
        QVERIFY(!backend.openChannel("file:///tmp/db", QString(64, 'a')).value("success").toBool());
        QVERIFY(!backend.openChannel("http://localhost:8080", "not-a-channel").value("success").toBool());
        QCOMPARE(api.client.calls.size(), calls);
        QVERIFY(backend.connected());
    }
};

QTEST_GUILESS_MAIN(ExplorerTest)
#include "test_explorer.moc"
