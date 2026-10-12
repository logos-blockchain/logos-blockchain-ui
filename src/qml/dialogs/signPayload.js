.pragma library

// The messages other apps may ask the node to sign, one per intent. The node
// app builds every byte itself from the request's fields and its own key, so
// what the user reads is exactly what gets signed.
//
// A message is compact JSON with its keys sorted and only string values, under
// a domain fixed by the intent. blockchain_module signs
// "logos-node-msg/v1" 0x00 domain 0x00 message with the BlendSigning key.

const intents = {
    "node.sign_referral_enrolment": {
        domain: "lez-referral/register",
        // Shown in this order; signed with the keys sorted.
        fields: [
            { name: "program", label: "Referral program" },
            { name: "participant_account", label: "Your referral account" },
            { name: "referrer", label: "Invited by", optional: true }
        ]
    },
    "node.sign_referral_payout": {
        domain: "lez-referral/payout",
        fields: [
            { name: "program_account", label: "Referral program" },
            { name: "blinding_factor", label: "Payout reference" }
        ]
    }
}

// Accounts, keys and references: printable ASCII with no spaces, so nothing
// can read differently from what is signed.
const valueRule = /^[!-~]{1,128}$/

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

// { problem, domain, rows: [{ label, value }], message, payloadHex }
// problem: "" | "intent" | "params" | "key"; nothing else is set unless "".
function build(intent, params, nodeKey) {
    if (!isKnown(intent))
        return { problem: "intent" }
    const spec = intents[intent]
    nodeKey = String(nodeKey).toLowerCase()
    const values = { node: nodeKey }
    const rows = []
    for (const field of spec.fields) {
        const v = params ? params[field.name] : undefined
        if (typeof v !== "string")
            return { problem: "params" }
        if (!(field.optional && v === "") && !valueRule.test(v))
            return { problem: "params" }
        values[field.name] = v
        rows.push({ label: field.label, value: v })
    }
    if (!/^[0-9a-f]{64}$/.test(nodeKey))
        return { problem: "key" }

    const sorted = {}
    for (const name of Object.keys(values).sort())
        sorted[name] = values[name]
    const message = JSON.stringify(sorted)
    return { problem: "", domain: spec.domain, rows: rows, message: message, payloadHex: hexOf(message) }
}
