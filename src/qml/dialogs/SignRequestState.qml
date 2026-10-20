import QtQuick

import "signPayload.js" as SignPayload

// Requests from other apps (node.sign_referral_*, node.referral_receipt_secret), one
// shown at a time, and everything the signing dialog derives from the current one. No
// backend, no intents: the host feeds it requests and answers them.
QtObject {
    id: root

    // ---- inputs, set by the host ----
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
    // Why the receipt secret is asked for: "find_cash_outs" (cash-outs made before this
    // Basecamp's data was reset), else cashing out, as for an app that doesn't say.
    readonly property bool findingCashOuts: root.intent === "node.referral_receipt_secret"
                                            && !!root.current && !!root.current.params
                                            && root.current.params.purpose === "find_cash_outs"
    // Host-attested; empty when the shell itself asks.
    readonly property string requester: root.current && root.current.requesterName.length > 0
                                        ? root.current.requesterName : qsTr("Basecamp")

    // { problem, domain, secret, rows, message, payloadHex }
    readonly property var built: root.current
                                 ? SignPayload.build(root.current.intent, root.current.params,
                                                     root.signingKey)
                                 : { problem: "intent" }
    readonly property bool valid: root.current !== null && root.built.problem === ""
    // A request that can never be signed, as opposed to one this node can't sign yet.
    readonly property bool malformed: root.built.problem === "intent" || root.built.problem === "params"
    // The receipt secret: shared, not signed.
    readonly property bool secret: root.valid && root.built.secret === true

    readonly property string purpose: {
        switch (root.intent) {
        case "node.sign_referral_enrolment": return qsTr("To join the referral program")
        case "node.sign_referral_payout":    return qsTr("For your referral payout code")
        case "node.referral_receipt_secret":
            return root.findingCashOuts ? qsTr("To find your past cash-outs")
                                        : qsTr("To cash out your referral points")
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
        case "node.referral_receipt_secret":
            return root.findingCashOuts
                ? qsTr("%1 asks for your node's referral receipt key, to find the cash-outs you "
                       + "made before on chain so you can get their payout codes.").arg(root.requester)
                : qsTr("%1 asks for your node's referral receipt key. It's used to cash out "
                       + "your referral points and to find your receipts again.").arg(root.requester)
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

    // The key comes from the node's keystore file, so the node needn't be running.
    readonly property bool canSign: root.valid && !root.busy

    function nodeKey(configKey: var, keystoreKey: var): string {
        return SignPayload.nodeKey(configKey, keystoreKey)
    }

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
