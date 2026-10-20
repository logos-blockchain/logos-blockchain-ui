import QtQuick
import QtQuick.Controls

import Logos.Theme
import Logos.Controls

// The last step before the node signs. There's no password, so this is the
// one chance to back out; the host signs on `confirmed`.
LogosDialog {
    id: root

    // Who receives the signature, as SignRequestState.requester names it.
    property string requester: ""
    property bool canConfirm: false
    // The receipt secret: shared, not signed.
    property bool secret: false

    signal confirmed()

    objectName: "signConfirmDialog"
    title: root.secret ? qsTr("Share your receipt key?") : qsTr("Sign with your node's key?")
    message: root.secret
             ? qsTr("There's no password: %1 receives your node's receipt key as soon as you "
                    + "confirm.").arg(root.requester)
             : qsTr("There's no password: your node signs as soon as you confirm, and %1 "
                    + "receives the signature.").arg(root.requester)
    backgroundColor: Theme.palette.surface
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: parent ? Math.min(420, parent.width - 2 * Theme.spacing.xxlarge) : 420

    rightActions: [
        LogosButton {
            objectName: "signConfirmCancelButton"
            text: qsTr("Cancel")
            onClicked: root.close()
        },
        LogosButton {
            objectName: "signConfirmButton"
            variant: LogosButton.Variant.Primary
            enabled: root.canConfirm
            text: root.secret ? qsTr("Share") : qsTr("Sign")
            onClicked: {
                root.close()
                root.confirmed()
            }
        }
    ]
}
