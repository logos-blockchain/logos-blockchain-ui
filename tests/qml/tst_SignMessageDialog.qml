import QtQuick
import QtQuick.Controls
import QtTest

import "../../src/qml/dialogs"

// The signing dialog's layout, and the confirm step after it, with a SignRequestState
// fed directly. No backend, no intents.
Item {
    id: host
    width: 440
    height: 700

    SignRequestState {
        id: state
        nodeRunning: true
        signingKey: "a1ee7c1a79aa778692f23de269d3f79fcf17a4a9b596d42675fd7bb386e72f09"
    }

    SignMessageDialog {
        id: dialog
        request: state
    }

    SignConfirmDialog {
        id: confirm
        requester: state.requester
        canConfirm: state.canSign
    }

    SignalSpy { id: signSpy; target: dialog; signalName: "signRequested" }
    SignalSpy { id: confirmedSpy; target: confirm; signalName: "confirmed" }
    SignalSpy { id: declineSpy; target: dialog; signalName: "declineRequested" }

    TestCase {
        name: "SignMessageDialog"
        when: windowShown

        function findAll(item, pred, out) {
            out = out || []
            if (pred(item))
                out.push(item)
            for (let i = 0; i < item.children.length; ++i)
                findAll(item.children[i], pred, out)
            return out
        }

        function byName(item, name) {
            return findAll(item, i => i.objectName === name)[0]
        }

        function init() {
            while (state.current !== null)
                state.next()
            signSpy.clear()
            confirmedSpy.clear()
            declineSpy.clear()
            state.add("r1", "node.sign_referral_enrolment",
                      { program: "LezReferralProgram1", participant_account: "LezAccount7xKq2",
                        referrer: "f10c55c16abbe8cc14ed1dec6b207ee6b72d6d73e9e057b3186300d98e8389b8" },
                      "uplink_ui")
            dialog.open()
            tryCompare(dialog, "opened", true)
            waitForRendering(dialog.contentItem)
        }

        function cleanup() {
            state.next()   // so closing isn't a decline
            dialog.close()
            tryCompare(dialog, "visible", false)
        }

        function test_title_says_what_happens() {
            compare(dialog.title, "Sign message")
            compare(state.purpose, "To join the referral program")
        }

        // Every label/value pair: the value starts after the widest label, with a gap.
        function test_values_never_touch_their_labels() {
            const rows = findAll(dialog.contentItem, i => i.hasOwnProperty("label") && i.hasOwnProperty("mono")
                                                         && i.visible)
            verify(rows.length >= 4, "requester, three fields, node")
            for (const row of rows) {
                const label = row.children[0]
                const value = row.children[1]
                verify(label.width >= label.implicitWidth, row.label + " is not cut short")
                verify(value.x >= label.x + label.implicitWidth + 8, row.label + " has a gap before its value")
            }
            // One column for all of them.
            for (const row of rows)
                compare(row.children[1].x, rows[0].children[1].x)
        }

        function test_message_frame_has_even_padding() {
            const frame = byName(dialog.contentItem, "signMessageBody")
            const column = byName(frame, "signMessageColumn")
            verify(frame.visible)
            const top = column.mapToItem(frame, 0, 0).y
            const bottom = frame.height - (top + column.height)
            verify(top > 0)
            compare(bottom, top)
            // Squeezed below its content, the text overruns the bottom edge.
            verify(column.height >= column.implicitHeight)
        }

        function test_sign_asks_the_host_to_confirm() {
            const signButton = findAll(dialog.footer, i => i.objectName === "signApproveButton")[0]
            mouseClick(signButton)
            compare(signSpy.count, 1)
            compare(declineSpy.count, 0)
            compare(dialog.visible, true)
        }

        function test_confirming_signs() {
            confirm.open()
            tryCompare(confirm, "opened", true)
            compare(confirm.message.indexOf("uplink_ui") >= 0, true)
            mouseClick(findAll(confirm.footer, i => i.objectName === "signConfirmButton")[0])
            compare(confirmedSpy.count, 1)
            tryCompare(confirm, "visible", false)
        }

        function test_cancelling_the_confirmation_signs_nothing() {
            confirm.open()
            tryCompare(confirm, "opened", true)
            mouseClick(findAll(confirm.footer, i => i.objectName === "signConfirmCancelButton")[0])
            compare(confirmedSpy.count, 0)
            tryCompare(confirm, "visible", false)
            compare(dialog.visible, true)
            compare(declineSpy.count, 0)
        }

        function test_confirm_is_disabled_when_signing_is_not_allowed() {
            state.nodeRunning = false
            const button = findAll(confirm.footer, i => i.objectName === "signConfirmButton")[0]
            compare(button.enabled, false)
            state.nodeRunning = true
            compare(button.enabled, true)
        }
    }
}
