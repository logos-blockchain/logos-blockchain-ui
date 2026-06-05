#include "BlockchainPlugin.h"
#include "BlockchainBackend.h"

#include <QDebug>

BlockchainPlugin::BlockchainPlugin(QObject* parent)
    : QObject(parent)
{
}

BlockchainPlugin::~BlockchainPlugin() = default;

void BlockchainPlugin::initLogos(LogosAPI* api)
{
    if (m_backend) return;
    m_backend = new BlockchainBackend(api, this);
    setBackend(m_backend);
    qDebug() << "BlockchainPlugin: backend initialized";
}
