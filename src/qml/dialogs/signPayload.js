.pragma library

// What other apps may ask the node for, one entry per intent: the Uplink referral
// programme's (logos-blockchain/uplink). The node app builds every byte itself from the
// request's fields and its own key, so what the user reads is exactly what gets signed,
// and the backend signs only if it builds the same bytes (answerReferralRequest).
//
// The bytes are the programme's own, not a wrapper around them: the programme checks the
// node's signature over them.

// "Uplink/AuthorizeParticipant/v1\0", as hex.
const authorizationDomainHex = "55706c696e6b2f417574686f72697a655061727469636970616e742f763100"

const intents = {
    "node.sign_referral_enrolment": {
        domain: "Uplink/AuthorizeParticipant/v1",
        // Shown in this order.
        fields: [
            { name: "program", label: "Referral program" },
            { name: "participant_account", label: "Your referral account" },
            { name: "referrer", label: "Invited by", optional: true }
        ]
    },
    "node.sign_referral_payout": {
        domain: "payout code",
        fields: [
            { name: "program_account", label: "Referral program" },
            { name: "blinding_factor", label: "Payout reference" }
        ]
    },
    // Not a signature: a key derived from the node's (SHA256("Uplink/ReceiptSecret/v1\0" ||
    // key)), with which the wallet cashes out and finds its receipts again.
    "node.referral_receipt_secret": {
        domain: "",
        secret: true,
        fields: []
    }
}

// Accounts, nodes and references: 32 bytes as hex.
const valueRule = /^[0-9a-fA-F]{64}$/

// The node a request is signed for: the config's, or the keystore's when the config can't be
// read (one written for an older or newer node). Signing reads the keystore either way.
function nodeKey(configKey, keystoreKey) {
    return String(configKey || keystoreKey || "")
}

function isKnown(intent) {
    return intents.hasOwnProperty(intent)
}

function hexOf(text) {
    const bytes = unescape(encodeURIComponent(text))
    let out = ""
    for (let i = 0; i < bytes.length; ++i)
        out += ("0" + bytes.charCodeAt(i).toString(16)).slice(-2)
    return out
}

// { problem, domain, secret, rows: [{ label, value }], message, payloadHex }
// problem: "" | "intent" | "params" | "key"; nothing else is set unless "".
// message is what the dialog shows as signed: the bytes as hex, or the payout opening's
// JSON; payloadHex the bytes; both "" for the receipt secret.
function build(intent, params, nodeKey) {
    if (!isKnown(intent))
        return { problem: "intent" }
    const spec = intents[intent]
    nodeKey = String(nodeKey).toLowerCase()
    const values = {}
    const rows = []
    for (const field of spec.fields) {
        const v = params ? params[field.name] : undefined
        if (field.optional && (v === undefined || v === ""))  {
            values[field.name] = ""
            rows.push({ label: field.label, value: "" })
            continue
        }
        if (typeof v !== "string" || !valueRule.test(v))
            return { problem: "params" }
        values[field.name] = v.toLowerCase()
        rows.push({ label: field.label, value: values[field.name] })
    }
    if (!valueRule.test(nodeKey))
        return { problem: "key" }

    let message = ""
    let payloadHex = ""
    if (intent === "node.sign_referral_enrolment") {
        // The programme's ParticipantAuthorizationV1: domain, program, node, participant,
        // then the referrer as a borsh Option (0x00, or 0x01 and the node).
        payloadHex = authorizationDomainHex + values.program + nodeKey + values.participant_account
                     + (values.referrer === "" ? "00" : "01" + values.referrer)
        message = payloadHex
    } else if (intent === "node.sign_referral_payout") {
        // The payout code's opening, as uplink_module checks it: compact JSON, keys sorted.
        message = JSON.stringify({ blinding_factor: values.blinding_factor, node: nodeKey,
                                   program_account: values.program_account })
        payloadHex = hexOf(message)
    }
    return { problem: "", domain: spec.domain, secret: !!spec.secret, rows: rows,
             message: message, payloadHex: payloadHex }
}
