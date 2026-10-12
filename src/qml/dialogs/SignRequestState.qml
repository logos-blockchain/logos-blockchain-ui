import QtQuick

import "signPayload.js" as SignPayload

// Signing requests from other apps (node.sign_referral_*), one shown at a
// time, and everything the signing dialog derives from the current one. No
// backend, no intents: the host feeds it requests and answers them.
QtObject {
    id: root

    // ---- inputs, set by the host ----
    property bool nodeRunning: false
    property bool nodeStarting: false
    // False while there is no config to start a node from.
    property bool canStartNode: true
    // The BlendSigning key from the config (provider_id); "" if unread.
    property string signingKey: ""
    property bool busy: false
    property string actionError: ""

    // { requestId, intent, params, requesterName } or null.
    property var current: null
    property int waiting: 0
    property var _queue: []

    // ---- derived ----
    readonly property string requestId: root.current ? root.current.requestId : ""
    readonly property string intent: root.current ? root.current.intent : ""
    // Host-attested; empty when the shell itself asks.
    readonly property string requester: root.current && root.current.requesterName.length > 0
                                        ? root.current.requesterName : qsTr("Basecamp")

    // { problem, domain, rows, message, payloadHex }
    readonly property var built: root.current
                                 ? SignPayload.build(root.current.intent, root.current.params,
                                                     root.signingKey)
                                 : { problem: "intent" }
    readonly property bool valid: root.current !== null && root.built.problem === ""
    // A request that can never be signed, as opposed to one this node can't sign yet.
    readonly property bool malformed: root.built.problem === "intent" || root.built.problem === "params"

    readonly property string purpose: {
        switch (root.intent) {
        case "node.sign_referral_enrolment": return qsTr("To join the referral program")
        case "node.sign_referral_payout":    return qsTr("For your referral payout code")
        default:                             return ""
        }
    }
    readonly property string summary: {
        switch (root.intent) {
        case "node.sign_referral_enrolment":
            return qsTr("%1 asks your node to confirm that the referral account below gets "
                        + "credit for this node's work. Each node can only join once.")
                   .arg(root.requester)
        case "node.sign_referral_payout":
            return qsTr("%1 asks your node to sign your payout code, so only this node can "
                        + "redeem it.").arg(root.requester)
        default:
            return ""
        }
    }
    readonly property string problem: {
        switch (root.built.problem) {
        case "intent": return qsTr("Your node doesn't sign this kind of request.")
        case "params": return qsTr("The request is incomplete or malformed.")
        case "key":    return qsTr("Your node's signing key couldn't be read from its config.")
        default:       return ""
        }
    }

    // Signing needs the node's key, so a stopped node can't sign; the dialog
    // waits for it instead.
    readonly property bool canSign: root.valid && root.nodeRunning && !root.busy

    function isKnown(intent: string): bool {
        return SignPayload.isKnown(intent)
    }

    function add(requestId: string, intent: string, params: var, requesterName: string): void {
        const request = { requestId: requestId, intent: intent, params: params || {},
                          requesterName: requesterName || "" }
        if (root.current === null) {
            root.current = request
        } else {
            root._queue.push(request)
            root.waiting = root._queue.length
        }
    }

    // Drops the current request, which the host has answered.
    function next(): void {
        root.busy = false
        root.actionError = ""
        root.current = root._queue.length > 0 ? root._queue.shift() : null
        root.waiting = root._queue.length
    }
}
