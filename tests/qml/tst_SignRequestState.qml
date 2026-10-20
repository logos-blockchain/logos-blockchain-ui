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
    readonly property string program: "09".repeat(32)
    readonly property string account: "03".repeat(32)
    readonly property string blinding: "04".repeat(32)
    // "Uplink/AuthorizeParticipant/v1\0"
    readonly property string authorizationDomainHex: "55706c696e6b2f417574686f72697a655061727469636970616e742f763100"

    Component {
        id: stateComponent
        SignRequestState {}
    }

    function make(props) {
        const s = createTemporaryObject(stateComponent, testCase,
                                        Object.assign({ signingKey: nodeKey }, props || {}))
        verify(s, "SignRequestState created")
        return s
    }

    function enrolment(s, params) {
        s.add("r1", "node.sign_referral_enrolment",
              params || { program: program, participant_account: account, referrer: referrer }, "uplink_ui")
    }

    function payout(s, params) {
        s.add("r1", "node.sign_referral_payout",
              params || { program_account: program, blinding_factor: blinding }, "uplink_ui")
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
        verify(s.isKnown("node.referral_receipt_secret"))
        verify(!s.isKnown("node.sign_message"))
        verify(!s.isKnown("toString"))
        s.add("r1", "node.sign_message", { domain: "x", payload_hex: "00" }, "x")
        compare(s.built.problem, "intent")
        compare(s.malformed, true)
    }

    // ---- the messages, built here and nowhere else ----

    // uplink_module rebuilds the payout code's opening and checks the node's signature over
    // exactly these bytes: compact JSON, keys sorted, no wrapper.
    function test_payout_message() {
        const s = make()
        payout(s)
        compare(s.valid, true)
        compare(s.secret, false)
        compare(s.built.domain, "payout code")
        const message = '{"blinding_factor":"' + blinding + '","node":"' + nodeKey + '","program_account":"' + program + '"}'
        compare(s.built.message, message)
        compare(s.built.payloadHex, hexOf(message))
        compare(s.built.rows.length, 2)
        compare(s.built.rows[0].value, program)
    }

    // The programme checks the node's signature over its ParticipantAuthorizationV1 bytes:
    // domain, program, node, participant, then the referrer as a borsh Option.
    function test_enrolment_message() {
        const s = make()
        enrolment(s)
        compare(s.valid, true)
        compare(s.built.domain, "Uplink/AuthorizeParticipant/v1")
        compare(s.built.payloadHex, authorizationDomainHex + program + nodeKey + account + "01" + referrer)
        compare(s.built.payloadHex.length, 2 * 160)
        compare(s.built.message, s.built.payloadHex)
        compare(s.built.rows.map(r => r.value), [program, account, referrer])
    }

    function test_enrolment_without_a_referrer() {
        const s = make()
        enrolment(s, { program: program, participant_account: account, referrer: "" })
        compare(s.valid, true)
        compare(s.built.payloadHex, authorizationDomainHex + program + nodeKey + account + "00")
        compare(s.built.payloadHex.length, 2 * 128)
        compare(s.built.rows[2].value, "")
    }

    // Not a signature: nothing to show as signed.
    function test_receipt_secret() {
        const s = make()
        s.add("r1", "node.referral_receipt_secret", {}, "uplink_ui")
        compare(s.valid, true)
        compare(s.secret, true)
        compare(s.built.payloadHex, "")
        compare(s.built.rows.length, 0)
        compare(s.purpose, "To cash out your referral points")
    }

    // The requester can't name another node: the node's own key goes in.
    function test_the_node_is_always_this_one() {
        const s = make({ signingKey: nodeKey.toUpperCase() })
        payout(s, { program_account: program, blinding_factor: blinding, node: referrer })
        compare(s.valid, true)
        verify(s.built.message.indexOf(nodeKey) >= 0)
        verify(s.built.message.indexOf(referrer) < 0)
    }

    function test_extra_params_are_not_signed() {
        const s = make()
        payout(s, { program_account: program, blinding_factor: blinding, amount: "1000000" })
        compare(s.valid, true)
        verify(s.built.message.indexOf("amount") < 0)
    }

    // ---- refusals ----

    function test_missing_or_wrong_typed_fields() {
        for (const params of [{}, { program_account: program }, { program_account: program, blinding_factor: 5 },
                              { program_account: "", blinding_factor: blinding }]) {
            const s = make()
            payout(s, params)
            compare(s.built.problem, "params", JSON.stringify(params))
            compare(s.malformed, true)
            compare(s.canSign, false)
        }
    }

    // Accounts, nodes and references are 32 bytes of hex, nothing else.
    function test_values_are_32_bytes_of_hex() {
        for (const v of ["Prog1", "has space", "ab".repeat(31), "ab".repeat(33), "zz".repeat(32), " " + program]) {
            const s = make()
            payout(s, { program_account: v, blinding_factor: blinding })
            compare(s.built.problem, "params", JSON.stringify(v))
        }
        const upper = make()
        payout(upper, { program_account: "AB".repeat(32), blinding_factor: blinding })
        compare(upper.valid, true)
        verify(upper.built.message.indexOf("ab".repeat(32)) >= 0, "signed as lowercase hex")
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

    // The config can't be read (one for an older or newer node, as on uplink's devnet): the
    // dialog used to have no key and refused every request. The keystore's key stands in.
    function test_the_keystores_key_when_the_config_cant_be_read() {
        const s = make({ signingKey: "" })
        compare(s.nodeKey(undefined, nodeKey), nodeKey)
        compare(s.nodeKey("", nodeKey), nodeKey)
        compare(s.nodeKey(nodeKey, "ff".repeat(32)), nodeKey, "the config's key comes first")
        compare(s.nodeKey(undefined, ""), "")

        s.signingKey = s.nodeKey(undefined, nodeKey)
        enrolment(s)
        compare(s.built.problem, "")
        compare(s.canSign, true)
    }

    // The receipt key is asked for to cash out, or to find past cash-outs (Uplink says which
    // with `purpose`); the dialog used to say "cash out" for both.
    function test_the_receipt_key_request_is_worded_by_its_purpose() {
        const cash = make()
        cash.add("r1", "node.referral_receipt_secret", {}, "uplink_ui")
        compare(cash.purpose, "To cash out your referral points")

        const find = make()
        find.add("r1", "node.referral_receipt_secret", { purpose: "find_cash_outs" }, "uplink_ui")
        compare(find.purpose, "To find your past cash-outs")
        verify(find.summary.indexOf("cash-outs you made before") >= 0, find.summary)
        compare(find.valid, true)
        compare(find.canSign, true)

        const unknown = make()
        unknown.add("r1", "node.referral_receipt_secret", { purpose: "something_newer" }, "uplink_ui")
        compare(unknown.purpose, "To cash out your referral points")
    }

    // ---- when signing is allowed ----

    // The key comes from the keystore file: a stopped node signs too.
    function test_the_node_needn_t_run() {
        const s = make()
        payout(s)
        compare(s.valid, true)
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
