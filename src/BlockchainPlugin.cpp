#include "BlockchainPlugin.h"
#include "BlockchainBackend.h"
#include "LogModel.h"
#include <QQuickWidget>
#include <QQmlContext>
#include <QQmlEngine>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

QWidget* BlockchainPlugin::createWidget(LogosAPI* logosAPI) {
    qDebug() << "BlockchainPlugin::createWidget called";

    QQuickWidget* quickWidget = new QQuickWidget();
    quickWidget->setResizeMode(QQuickWidget::SizeRootObjectToView);

    qmlRegisterType<BlockchainBackend>("BlockchainBackend", 1, 0, "BlockchainBackend");
    qmlRegisterType<LogModel>("BlockchainBackend", 1, 0, "LogModel");

    BlockchainBackend* backend = new BlockchainBackend(logosAPI, quickWidget);
    quickWidget->rootContext()->setContextProperty("backend", backend);

    QString qmlSource = "qrc:/qml/BlockchainView.qml";
    QString importPath = "qrc:/qml";

    QString envPath = QString::fromUtf8(qgetenv("BLOCKCHAIN_UI_QML_PATH")).trimmed();
    if (!envPath.isEmpty()) {
        QFileInfo info(envPath);
        if (info.isDir()) {
            QString main = QDir(info.absoluteFilePath()).absoluteFilePath("BlockchainView.qml");
            if (QFile::exists(main)) {
                importPath = info.absoluteFilePath();
                qmlSource = QUrl::fromLocalFile(main).toString();
            } else {
                qWarning() << "BLOCKCHAIN_UI_QML_PATH: BlockchainView.qml not found in" << info.absoluteFilePath();
            }
        }
    }

    quickWidget->engine()->addImportPath(importPath);
    quickWidget->setSource(QUrl(qmlSource));

    if (quickWidget->status() == QQuickWidget::Error) {
        qWarning() << "BlockchainPlugin: Failed to load QML:" << quickWidget->errors();
    }

    return quickWidget;
}

void BlockchainPlugin::destroyWidget(QWidget* widget) {
    delete widget;
}
