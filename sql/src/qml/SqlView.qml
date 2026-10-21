import QtQuick
import Logos.Theme

// Basecamp entry point: connects the Explorer to its remote backend and result model.
Rectangle {
    id: root
    color: Theme.palette.background

    readonly property var backend: logos.module("sql_ui")
    property bool ready: false

    Component.onCompleted: ready = backend !== null && logos.isViewModuleReady("sql_ui")

    Connections {
        target: logos
        function onViewModuleReadyChanged(name, available) {
            if (name === "sql_ui")
                root.ready = available && root.backend !== null
        }
    }

    Explorer {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        backend: root.backend
        ready: root.ready
        resultModel: logos.model("sql_ui", "results")
        watch: function(reply, completed, failed) { logos.watch(reply, completed, failed) }
    }
}
