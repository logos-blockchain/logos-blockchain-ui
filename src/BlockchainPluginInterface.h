#ifndef BLOCKCHAIN_PLUGIN_INTERFACE_H
#define BLOCKCHAIN_PLUGIN_INTERFACE_H

#include <QtPlugin>          // for Q_DECLARE_INTERFACE
#include "interface.h"

// Marker interface used by Qt's plugin loader to identify the blockchain UI
// plugin. The actual API surface (Q_INVOKABLE methods, properties, signals)
// lives in BlockchainBackend.rep — this header only carries the IID.
class BlockchainPluginInterface : public PluginInterface
{
public:
    virtual ~BlockchainPluginInterface() = default;
};

#define BlockchainPluginInterface_iid "org.logos.BlockchainPluginInterface"
Q_DECLARE_INTERFACE(BlockchainPluginInterface, BlockchainPluginInterface_iid)

#endif // BLOCKCHAIN_PLUGIN_INTERFACE_H
