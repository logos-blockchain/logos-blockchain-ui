#pragma once

#include <QtPlugin>
#include "interface.h"

class SqlPluginInterface : public PluginInterface
{
public:
    ~SqlPluginInterface() override = default;
};

#define SqlPluginInterface_iid "org.logos.SqlPluginInterface"
Q_DECLARE_INTERFACE(SqlPluginInterface, SqlPluginInterface_iid)
