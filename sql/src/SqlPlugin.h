#pragma once

#include <QObject>
#include "SqlPluginInterface.h"
#include "LogosViewPluginBase.h"

class LogosAPI;
class SqlBackend;

class SqlPlugin : public QObject,
                  public SqlPluginInterface,
                  public SqlBackendViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID SqlPluginInterface_iid FILE "../metadata.json")
    Q_INTERFACES(SqlPluginInterface)

public:
    explicit SqlPlugin(QObject* parent = nullptr);
    QString name() const override { return "sql_ui"; }
    QString version() const override { return "0.1.0"; }
    Q_INVOKABLE void initLogos(LogosAPI* api);

private:
    SqlBackend* m_backend = nullptr;
};
