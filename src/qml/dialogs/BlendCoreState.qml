import QtQuick

import Logos.BlockchainBackend 1.0

import "../Units.js" as Units

// What the Blend Core dialog knows: its inputs, its page, and every value the
// pages derive from them. The host owns one, binds the node's values into it,
// writes the wallet and reachability reads to it, and hands it to the dialog.
QtObject {
    id: root

    // ---- inputs, from the host ----
    property bool nodeOnline: false
    property bool nodeRunning: false
    property var blendStatus: ({})
    property int blendState: BlockchainBackend.BlendUnknown
    property var requirements: ({})
    property var reachability: ({})
    property var blendConfig: ({})
    property bool apiAvailable: false
    property var zkNotes: null
    property string sdpFundingBalance: ""
    property bool coreFromRole: false
    property string configPath: ""
    property string timeInfoJson: ""
    property bool busy: false
    property string actionError: ""

    // Forgets what was read while the dialog was open.
    function clearReads(): void {
        root.reachability = ({})
        root.zkNotes = null
        root.sdpFundingBalance = ""
        root.actionError = ""
    }

    // The smallest unlocked BlendZk note meeting min_stake: lock no more than
    // the rule asks. null when there is none.
    readonly property var stakeNote: {
        if (!root.zkNotes)
            return null
        const locked = root.declaration ? root.declaration.locked_note_id || "" : ""
        let best = null
        for (const note of root.zkNotes) {
            if (note.id === locked || Units.compareLepta(note.value, root.minStake) < 0)
                continue
            if (!best || Units.compareLepta(note.value, best.value) < 0)
                best = note
        }
        return best
    }
    readonly property bool stakeChecked: root.zkNotes !== null
    readonly property string stakeNoteId: root.stakeNote ? root.stakeNote.id : ""
    readonly property string stakeNoteValue: root.stakeNote ? root.stakeNote.value : ""

    readonly property string docsUrl:
        "https://docs.logos.co/blockchain/blend/join-the-blend-network-as-a-core-node"

    // ---- the dialog's own state, and everything derived ----

    property string page: "gates"   // gates | confirm
    property bool attested: false

    // A check that can't run while the node is stopped: "idle", not spinning.
    function checked(ok) { return root.nodeRunning ? ok : "idle" }
    // Declared: asking "leave Blend Core?" before withdrawing.
    property bool confirmingLeave: false

    readonly property bool inactive: root.blendState === BlockchainBackend.BlendInactive
    readonly property bool withdrawn: root.blendState === BlockchainBackend.BlendWithdrawn
    readonly property var declaration: root.blendStatus.declaration || null
    readonly property var activity: root.blendStatus.activity || null
    // Without blend_status, Core from blend_info is the only sign of a declaration.
    readonly property bool active: root.blendState === BlockchainBackend.BlendActive
                                   || (!root.apiAvailable && root.coreFromRole)
    readonly property bool declared: root.joining || root.active || root.inactive
                                     || root.withdrawn
    // On-chain and not already leaving: what Disable Blend Core needs.
    readonly property bool canLeave: root.declared
                                     && root.blendState !== BlockchainBackend.BlendPending
                                     && !root.withdrawn
    // Set once the withdrawal is on-chain: serves through withdrawAt - 1,
    // the stake unlocks when withdrawAt + 1 starts.
    readonly property var withdrawAt: root.declaration && root.declaration.withdraw_at !== undefined
                                      ? root.declaration.withdraw_at : null
    readonly property int unlockDelay: root.requirements.unlock_delay_epochs || 3

    // Joining: submitted (pending), then on-chain and activating. Both
    // stay on the stepper until the node is in the core set.
    readonly property bool joining: root.blendState === BlockchainBackend.BlendPending
                                    || root.blendState === BlockchainBackend.BlendActivating
    readonly property int step: root.blendState === BlockchainBackend.BlendActivating ? 1 : 0
    readonly property int activeFrom: root.declaration ? root.declaration.active_from_epoch : -1
    // Ticks while the stepper shows, so the countdown moves.
    property real now: Date.now()
    // "~20h" / "~4 min" until activeFrom starts; empty when the epoch
    // length or the clock isn't known.
    readonly property string activationEta: {
        const slots = Number(root.requirements.epoch_slots || 0)
        let t = null
        try { t = JSON.parse(root.timeInfoJson || "null") } catch (e) {}
        if (!slots || !t || !t.slot_duration_ms || root.activeFrom < 0)
            return ""
        const start = Number(t.genesis_time_unix_ms)
                    + root.activeFrom * slots * Number(t.slot_duration_ms)
        const minutes = Math.max(0, Math.round((start - root.now) / 60000))
        return minutes >= 60 ? qsTr("~%1h").arg(Math.round(minutes / 60))
                             : qsTr("~%1 min").arg(Math.max(1, minutes))
    }

    readonly property string minStake: root.requirements.min_stake || "1000000000"
    readonly property int localPort: root.blendConfig.port || 0
    readonly property string zkKey: root.blendConfig.zk_id || ""
    readonly property string sdpKey: root.blendConfig.sdp_funding_pk || ""

    // One activity fee is about 2,000 lepta at genesis gas prices. The gate
    // only asks that the key can pay one; the copy says it must stay funded.
    readonly property string minFeeLepta: "2000"

    // Where the IP comes from: what the node's peers see it at
    // (blend_reachability), else a static NAT address someone put in the
    // config. Either way on the Blend port, the way the node's own
    // participate command builds the locator.
    readonly property var observed: {
        const list = root.reachability.confirmed_external_addresses || []
        for (let i = 0; i < list.length; ++i) {
            const m = /^\/(ip4|ip6)\/([^/]+)/.exec(list[i])
            if (m)
                return m
        }
        return null
    }
    readonly property bool fromConfig: !root.observed && !!root.configured
    readonly property var configured: /^\/(ip4|ip6|dns4|dns6|dns)\/([^/]+)/
                                          .exec(root.blendConfig.external_address || "")
    readonly property var external: root.observed || root.configured
    readonly property string hostValue: root.external ? root.external[2] : ""
    readonly property string portText: root.localPort > 0 ? String(root.localPort) : ""
    readonly property string locator: root.external && root.portText.length > 0
        ? "/" + root.external[1] + "/" + root.hostValue + "/udp/" + root.portText + "/quic-v1"
        : ""

    // Addresses the node would accept but no one outside could reach.
    readonly property string addressProblem: {
        const h = root.hostValue
        if (h.length === 0)
            return qsTr("This node can't report your public address yet. Add it to your "
                        + "config file to join now.")
        if (root.locator.length === 0)
            return qsTr("Your config file has no Blend port.")
        const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h)
        if (m) {
            const a = Number(m[1]), b = Number(m[2])
            if (m.slice(1).some(x => Number(x) > 255))
                return qsTr("That isn't a valid IPv4 address.")
            if (a === 0 || a === 10 || a === 127 || (a === 169 && b === 254)
                    || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168))
                return qsTr("%1 is a private address. Other nodes need your router's "
                            + "public one.").arg(h)
            if (a === 100 && b >= 64 && b <= 127)
                return qsTr("That's a carrier-shared address (CGNAT): your provider "
                            + "doesn't give you a public address, so incoming "
                            + "connections can't reach this machine.")
        }
        return ""
    }

    // ---- requirements: true = met, false = not met, null = not known ----
    // Bootstrapping is progress, not a fault: it spins.
    readonly property var onlineOk: root.nodeOnline ? true : null
    readonly property var stakeOk: !root.stakeChecked ? null : root.stakeNoteValue.length > 0
    readonly property var feeOk: root.sdpFundingBalance.length === 0 ? null
                               : Units.compareLepta(root.sdpFundingBalance, root.minFeeLepta) >= 0
    // No address yet on a node that can report one: its peers haven't yet.
    readonly property var addressOk: root.hostValue.length === 0 && root.apiAvailable ? null
                                   : root.addressProblem.length === 0
    readonly property var reachOk: !root.apiAvailable ? root.attested
                                 : root.reachability.reachable === undefined
                                   || root.reachability.reachable === null
                                   ? null : root.reachability.reachable
    readonly property var networkOk: !root.apiAvailable ? null
                                   : root.blendStatus.network_size === undefined ? null
                                   : root.blendStatus.network_size
                                     >= (root.requirements.minimum_network_size || 0)

    // An unknown network size can't block a node that can't report one;
    // an unknown reachability verdict waits for the check.
    readonly property bool allMet: root.onlineOk === true && root.stakeOk === true
                                   && root.feeOk === true && root.addressOk === true
                                   && root.reachOk === true
                                   && (root.networkOk === true || !root.apiAvailable)

    readonly property string heading:
          root.withdrawn ? qsTr("Leaving Blend Core")
        : root.confirmingLeave ? qsTr("Disable Blend Core")
        : root.joining ? qsTr("Joining Blend Core")
        : root.declared ? qsTr("Blend Core")
        : root.page === "confirm" ? qsTr("Confirm Blend Core")
        : qsTr("Enable Blend Core")

    // The prototype's gold, for "active": no palette token matches it.
    readonly property color gold: "#d9a521"
}
