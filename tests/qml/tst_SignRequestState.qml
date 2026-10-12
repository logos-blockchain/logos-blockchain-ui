import QtQuick
import QtTest

import "../../src/qml/dialogs"

// SignRequestState on its own: what the signing dialog shows and allows for a
// node.sign_referral_* request. No backend, no intents.
TestCase {
    id: testCase
    name: "SignRequestState"

    readonly property string nodeKey: "a1ee7c1a79aa778692f23de269d3f79fcf17a4a9b596d42675fd7bb386e72f09"
    readonly property string referrer: "f10c55c16abbe8cc14ed1dec6b207ee6b72d6d73e9e057b3186300d98e8389b8"

    Component {
        id: stateComponent
        SignRequestState {}
    }

    function make(props) {
        const s = createTemporaryObject(stateComponent, testCase,
                                        Object.assign({ nodeRunning: true, signingKey: nodeKey }, props || {}))
        verify(s, "SignRequestState created")
        return s
    }

    function enrolment(s, params) {
        s.add("r1", "node.sign_referral_enrolment",
              params || { program: "Prog1", participant_account: "Acct1", referrer: referrer }, "uplink_ui")
    }

    function payout(s, params) {
        s.add("r1", "node.sign_referral_payout",
              params || { program_account: "Prog1", blinding_factor: "ff00" }, "uplink_ui")
    }

    function hexOf(text) {
        let out = ""
        for (let i = 0; i < text.length; ++i)
            out += ("0" + text.charCodeAt(i).toString(16)).slice(-2)
        return out
    }

    // ---- queue ----

    function test_nothing_to_show_until_a_request() {
        const s = make()
        compare(s.current, null)
        compare(s.valid, false)
        compare(s.canSign, false)
    }

    function test_requests_wait_their_turn() {
        const s = make()
        s.add("a", "node.sign_referral_enrolment", {}, "x")
        s.add("b", "node.sign_referral_payout", {}, "x")
        s.add("c", "node.sign_referral_payout", {}, "x")
        compare(s.requestId, "a")
        compare(s.waiting, 2)
        s.busy = true
        s.actionError = "boom"
        s.next()
        compare(s.requestId, "b")
        compare(s.intent, "node.sign_referral_payout")
        compare(s.waiting, 1)
        compare(s.busy, false)
        compare(s.actionError, "")
        s.next()
        s.next()
        compare(s.current, null)
        compare(s.waiting, 0)
    }

    function test_the_shell_as_requester() {
        const s = make()
        s.add("r1", "node.sign_referral_payout", {}, "")
        compare(s.requester, "Basecamp")
    }

    function test_only_the_referral_intents() {
        const s = make()
        verify(s.isKnown("node.sign_referral_enrolment"))
        verify(s.isKnown("node.sign_referral_payout"))
        verify(!s.isKnown("node.sign_message"))
        verify(!s.isKnown("toString"))
        s.add("r1", "node.sign_message", { domain: "x", payload_hex: "00" }, "x")
        compare(s.built.problem, "intent")
        compare(s.malformed, true)
    }

    // ---- the messages, built here and nowhere else ----

    // Uplink's payout code is checked against exactly these bytes
    // (payout_code::signedPayload: QJsonDocument, compact, keys sorted).
    function test_payout_message() {
        const s = make()
        payout(s)
        compare(s.valid, true)
        compare(s.built.domain, "lez-referral/payout")
        const message = '{"blinding_factor":"ff00","node":"' + nodeKey + '","program_account":"Prog1"}'
        compare(s.built.message, message)
        compare(s.built.payloadHex, hexOf(message))
        compare(s.built.rows.length, 2)
        compare(s.built.rows[0].value, "Prog1")
    }

    function test_enrolment_message() {
        const s = make()
        enrolment(s)
        compare(s.valid, true)
        compare(s.built.domain, "lez-referral/register")
        compare(s.built.message, '{"node":"' + nodeKey + '","participant_account":"Acct1","program":"Prog1","referrer":"'
                                 + referrer + '"}')
        compare(s.built.rows.map(r => r.value), ["Prog1", "Acct1", referrer])
    }

    function test_enrolment_without_a_referrer() {
        const s = make()
        enrolment(s, { program: "Prog1", participant_account: "Acct1", referrer: "" })
        compare(s.valid, true)
        verify(s.built.message.endsWith('"referrer":""}'))
    }

    // The requester can't name another node: the node's own key goes in.
    function test_the_node_is_always_this_one() {
        const s = make({ signingKey: nodeKey.toUpperCase() })
        payout(s, { program_account: "Prog1", blinding_factor: "ff00", node: referrer })
        compare(s.valid, true)
        verify(s.built.message.indexOf(nodeKey) >= 0)
        verify(s.built.message.indexOf(referrer) < 0)
    }

    function test_extra_params_are_not_signed() {
        const s = make()
        payout(s, { program_account: "Prog1", blinding_factor: "ff00", amount: "1000000" })
        verify(s.built.message.indexOf("amount") < 0)
    }

    // ---- refusals ----

    function test_missing_or_wrong_typed_fields() {
        for (const params of [{}, { program_account: "Prog1" }, { program_account: "Prog1", blinding_factor: 5 },
                              { program_account: "", blinding_factor: "ff00" }]) {
            const s = make()
            payout(s, params)
            compare(s.built.problem, "params", JSON.stringify(params))
            compare(s.malformed, true)
            compare(s.canSign, false)
        }
    }

    function test_values_are_printable_ascii_without_spaces() {
        for (const v of ["has space", "tab\there", "new\nline", "café", "a\u202eb", "x".repeat(129)]) {
            const s = make()
            payout(s, { program_account: v, blinding_factor: "ff00" })
            compare(s.built.problem, "params", JSON.stringify(v))
        }
        const longest = make()
        payout(longest, { program_account: "x".repeat(128), blinding_factor: "ff00" })
        compare(longest.valid, true)
    }

    // A request that's fine, on a node that can't name its key yet: not the requester's fault.
    function test_unknown_signing_key() {
        for (const key of ["", "abc", nodeKey + "00"]) {
            const s = make({ signingKey: key })
            payout(s)
            compare(s.built.problem, "key", key)
            compare(s.malformed, false)
            compare(s.canSign, false)
        }
    }

    // ---- when signing is allowed ----

    function test_a_stopped_node_cannot_sign() {
        const s = make({ nodeRunning: false })
        payout(s)
        compare(s.valid, true)
        compare(s.canSign, false)
        s.nodeRunning = true
        compare(s.canSign, true)
    }

    function test_not_while_busy() {
        const s = make()
        payout(s)
        s.busy = true
        compare(s.canSign, false)
    }

    function test_purposes() {
        const s = make()
        enrolment(s)
        compare(s.purpose, "To join the referral program")
        verify(s.summary.indexOf("uplink_ui") >= 0)
        s.next()
        payout(s)
        compare(s.purpose, "For your referral payout code")
    }
}
