import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// "The node cannot answer right now, and here is why."
//
// One banner, every view that depends on the node. The reason and its severity
// are computed once in BlockchainView, where the status actually lives — a view
// inferring it from a single `nodeRunning` boolean gets it wrong, because a
// bootstrapping node IS running and a dead module needs the app restarted
// rather than the node started.
//
// Shows nothing when the node is answering, so it can be declared
// unconditionally at the top of a view.
//
//     NodeOffNotice { reason: root.nodeOffReason; reasonSeverity: root.nodeOffSeverity }
LogosNotice {
    id: root

    property string reason: ""
    property int reasonSeverity: LogosNotice.Info

    Layout.fillWidth: true
    objectName: "nodeOffNotice"
    shown: root.reason.length > 0
    severity: root.reasonSeverity
    message: root.reason
}
