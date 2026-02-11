#include "mainwindow.h"

#include <QApplication>
#include <QDir>
#include <QDebug>
#include <iostream>
#include <memory>

//  CoreManager C API functions
extern "C" {
    void logos_core_set_plugins_dir(const char* plugins_dir);
    void logos_core_start();
    void logos_core_cleanup();
    char** logos_core_get_loaded_plugins();
    int logos_core_load_plugin(const char* plugin_name);
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    QString pluginsDir = QDir::cleanPath(QCoreApplication::applicationDirPath() + "/../modules");
    logos_core_set_plugins_dir(pluginsDir.toUtf8().constData());

    logos_core_start();
    
    if (!logos_core_load_plugin("capability_module")) {
        qWarning() << "Failed to load capability_module plugin";
    }
    
    if (!logos_core_load_plugin("liblogos_blockchain_module")) {
        qWarning() << "Failed to load blockchain module plugin";
    }

    char** loadedPlugins = logos_core_get_loaded_plugins();
    int count = 0;
    if (loadedPlugins) {
        qInfo() << "Currently loaded plugins:";
        for (char** p = loadedPlugins; *p != nullptr; ++p) {
            qInfo() << "  -" << *p;
            ++count;
        }
        qInfo() << "Total plugins:" << count;
    } else {
        qInfo() << "No plugins loaded.";
    }
    
    MainWindow window;
    window.show();
    
    int result = app.exec();
    
    logos_core_cleanup();
    
    return result;
}
