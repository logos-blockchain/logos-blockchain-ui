#include "SqlPlugin.h"
#include "SqlBackend.h"

SqlPlugin::SqlPlugin(QObject* parent)
    : QObject(parent)
{
}

void SqlPlugin::initLogos(LogosAPI* api)
{
    if (m_backend)
        return;

    m_backend = new SqlBackend(api, this);
    setBackend(m_backend);
}
