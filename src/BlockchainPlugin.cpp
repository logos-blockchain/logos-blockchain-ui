#include "BlockchainPlugin.h"
#include "BlockchainBackend.h"
#include <QQuickWidget>
#include <QQmlContext>
#include <QQmlEngine>
#include <QDebug>
#include <QFileInfo>
#include <QFile>

QWidget* BlockchainPlugin::createWidget(LogosAPI* logosAPI) {
    qDebug() << "BlockchainPlugin::createWidget called";

    QQuickWidget* quickWidget = new QQuickWidget();
    quickWidget->setResizeMode(QQuickWidget::SizeRootObjectToView);

    qmlRegisterType<BlockchainBackend>("BlockchainBackend", 1, 0, "BlockchainBackend");

    BlockchainBackend* backend = new BlockchainBackend(logosAPI, quickWidget);
    
    quickWidget->rootContext()->setContextProperty("backend", backend);

    QString qmlPath = "qrc:/BlockchainView.qml";
    QString envPath = qgetenv("BLOCKCHAIN_UI_QML_PATH");
    if (!envPath.isEmpty() && QFile::exists(envPath)) {
        qmlPath = QUrl::fromLocalFile(QFileInfo(envPath).absoluteFilePath()).toString();
        qDebug() << "Loading QML from file system:" << qmlPath;
    }
    
    quickWidget->setSource(QUrl(qmlPath));
    
    if (quickWidget->status() == QQuickWidget::Error) {
        qWarning() << "BlockchainPlugin: Failed to load QML:" << quickWidget->errors();
    }

    return quickWidget;
}

void BlockchainPlugin::destroyWidget(QWidget* widget) {
    delete widget;
}
