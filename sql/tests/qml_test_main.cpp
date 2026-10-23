#include "QueryResultModel.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QtQuickTest>

class Setup : public QObject
{
    Q_OBJECT
    QueryResultModel m_results;

public slots:
    void qmlEngineAvailable(QQmlEngine* engine)
    {
        const QVariantList row{
            QVariantMap{{"type", "integer"}, {"value", "9223372036854775807"}},
            QVariantMap{{"type", "text"}, {"value", "Useful read-only SQL explorer"}},
            QVariantMap{{"type", "null"}}
        };
        m_results.setResult({{"columns", QStringList{"id", "review", "notes"}},
                             {"rows", QVariantList{QVariant(row)}}});
        engine->rootContext()->setContextProperty("testResults", &m_results);
        engine->rootContext()->setContextProperty("previewPath", qEnvironmentVariable("SQL_EXPLORER_PREVIEW"));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(sql_explorer, Setup)
#include "qml_test_main.moc"
