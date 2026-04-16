#ifndef BLOCKCHAIN_PLUGIN_H
#define BLOCKCHAIN_PLUGIN_H

#include <QObject>
#include <QString>
#include <QtPlugin>          // for Q_PLUGIN_METADATA, Q_INTERFACES
#include "BlockchainPluginInterface.h"
#include "LogosViewPluginBase.h"

class LogosAPI;
class BlockchainBackend;

// Thin plugin entry point. Holds a BlockchainBackend and lets the
// generated view-plugin base expose it to ui-host.
class BlockchainPlugin : public QObject,
                         public BlockchainPluginInterface,
                         public BlockchainBackendViewPluginBase
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID BlockchainPluginInterface_iid FILE "../metadata.json")
    Q_INTERFACES(BlockchainPluginInterface)

public:
    explicit BlockchainPlugin(QObject* parent = nullptr);
    ~BlockchainPlugin() override;

    QString name()    const override { return "blockchain_ui"; }
    QString version() const override { return "1.0.0"; }

    // Called by ui-host after plugin load. Creates the backend and wires
    // it up with the provided LogosAPI.
    Q_INVOKABLE void initLogos(LogosAPI* api);

private:
    BlockchainBackend* m_backend = nullptr;
};

#endif // BLOCKCHAIN_PLUGIN_H
