#include "BlockchainPlugin.h"
#include "BlockchainBackend.h"

#include <QDebug>

BlockchainPlugin::BlockchainPlugin(QObject* parent)
    : QObject(parent)
{
}

BlockchainPlugin::~BlockchainPlugin() = default;

void BlockchainPlugin::initModuleContext(const QString& modulePath)
{
    m_modulePath = modulePath;
}

void BlockchainPlugin::initLogos(LogosAPI* api)
{
    if (m_backend) return;
    m_backend = new BlockchainBackend(api, this);
    // Before anything reads it: the backend's own startup work includes
    // publishing the bootstrap peers this carries.
    m_backend->setModuleContext(m_modulePath);
    setBackend(m_backend);
    qDebug() << "BlockchainPlugin: backend initialized";
}
