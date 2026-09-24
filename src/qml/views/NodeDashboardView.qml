pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import Logos.BlockchainBackend 1.0

import "infoContent.js" as InfoContent
import "../Units.js" as Units

// The node dashboard: a full-width status hero carrying the lifecycle lane,
// over a responsive grid of metric tiles.
Item {
    id: root

    // --- Public API ---
    property int status: -1                 // backend.status; -1 = not connected
    // Whether we currently have a live link to the backend, and whether we ever
    // had one. `status` freezes at its last value when the link drops, so
    // without these a dead node process reads as a confident "Online".
    property bool connected: false
    property bool moduleReachable: true
    property bool everConnected: false
    property string statusMessage: ""
    property bool nodeRecovering: false
    // get_cryptarchia_info payload, polled by BlockchainView.
    property string infoJson: ""
    // get_time_info payload: { slot_duration_ms, genesis_time_unix_ms,
    // current_slot, current_epoch }. Only current_epoch is read.
    property string timeInfoJson: ""
    // wallet_get_claimable_vouchers payload: { tip, vouchers: [...] }.
    property string vouchersJson: ""
    // Stake, already shaped by the backend from wallet_get_leader_aged_notes.
    // Empty total means "not reported"; a reported "0" means nothing has aged.
    property string stakeTotal: ""
    property int stakeNoteCount: 0
    // What this node has earned leading blocks, tallied by the backend from the
    // chain's own claim events — see EarnedLedger. Empty total means "not
    // counted yet"; a reported "0" means nothing has been claimed.
    property string earnedTotal: ""
    property int earnedClaimCount: 0
    // ISO 8601 date the tally began, or empty. Neither reward figure is a
    // lifetime total — nothing hands the app one — so both say what they cover.
    property string claimsCountingSince: ""
    // Any known address holds tokens. Drives the lane's Funded stage only —
    // the figure itself belongs to the Accounts view.
    property bool walletFunded: false
    property var stakeAddresses: []
    property string peerId: ""
    // libp2p connectivity, shaped by the backend from get_network_info.
    // -1 = not reported; 0 is a real reading and the usual reason a node never
    // finishes bootstrapping.
    property int peerCount: -1
    property int connectionCount: -1
    property double nodeCpuPercent: -1
    property double nodeMemoryMb: -1
    property int cpuCount: 1
    property double nodeDiskUsedMb: -1
    property double nodeDiskFreeMb: -1
    property int blendRole: BlockchainBackend.Unknown
    // Debounced in BlockchainView — a single blip in `mode` must not repaint
    // the card. `hasBeenOnline` separates a first bootstrap from a node that
    // fell behind; the node reports the same `mode` for both.
    property bool synced: false
    property bool hasBeenOnline: false
    // The status poll has gone quiet. Modifies the hero; never replaces a state.
    property bool statusStale: false
    property int statusNextPollSeconds: 0
    // Seconds since the status RPC last answered. Sizes the gap in the stale
    // sub-line; never a verdict on the node's health.
    property int statusSilentSeconds: 0
    // Catching up but demonstrably not progressing, or the push stream died.
    // Unlike statusStale these are substantiated, and the user has to act.
    property bool syncStalled: false
    property bool blockStreamEnded: false
    // The node's genesis time hasn't arrived, so it can never reach Online.
    property bool genesisPending: false
    property double genesisUnixMs: 0
    // Seconds the node has been online, ticked by the backend and reset by it
    // whenever the view stops reporting Online — see the .rep.
    property int uptimeSeconds: 0
    // PoW mining, as last toggled from the Fund button, and the failure that
    // stopped it if there was one.
    property bool miningRequested: false
    property string miningError: ""
    // Tickets mined and not yet claimed. Sits under the reward figure rather than
    // replacing it: a ticket is not a reward until it is claimed, and a large
    // number here with a zero above it is the symptom, not the achievement.
    property int claimableTickets: 0
    // The node is demonstrably doing PoW work — the claimable count moved
    // recently. Not `mining`, which is only what was last asked for.
    property bool powActive: false
    // PoW reward claims paid to this wallet, counted from the blocks seen since
    // the node started.
    property int powRewardsClaimed: 0
    // Lepta, decimal string. The value those claims paid; powRewardsClaimed is
    // only how many tickets produced it.
    property string powRewardsLepta: ""
    property int powClaimsPending: 0
    // The keystore exists and whether a copy of it has been saved. Together
    // they drive the reminder banner — see the top of the layout.
    property bool keystorePresent: false
    property bool keysBackedUp: false
    // "Not now", not "done". Local to this view on purpose: dismissing hides
    // the reminder, it does not record anything, so the reminder is back next
    // time you open the dashboard and Settings still says nothing.
    property bool keysNoticeDismissed: false

    // Take the user to where the backup is done, which is Settings.
    // The user says the keystore is safe without downloading it here.

    QtObject {
        id: d

        readonly property bool running: root.status === BlockchainBackend.Running

        // Under the reward count, in order of how much the user needs to know it:
        // a mining failure, then claims settling, then the plain backlog.
        readonly property string miningCaption: {
            if (root.miningError.length > 0)
                return root.miningError
            if (root.powClaimsPending > 0)
                return root.claimableTickets > 0
                    ? qsTr("%1 settling \u00b7 %2 waiting")
                          .arg(root.powClaimsPending).arg(root.claimableTickets)
                    : qsTr("%n claim(s) settling", "", root.powClaimsPending)
            if (root.claimableTickets > 0)
                return qsTr("%1 claimed \u00b7 %2 waiting")
                           .arg(root.powRewardsClaimed).arg(root.claimableTickets)
            if (root.powRewardsClaimed > 0) {
                var mined = [qsTr("%n ticket(s)", "", root.powRewardsClaimed)]
                if (d.countingSince.length > 0)
                    mined.push(d.countingSince)
                return mined.join(" \u00b7 ")
            }
            return root.miningRequested ? qsTr("no tickets claimed") : ""
        }

        function parseJson(text) {
            if (!text || text.length === 0)
                return null
            try {
                return JSON.parse(text)
            } catch (e) {
                return null
            }
        }

        readonly property var info: parseJson(root.infoJson)

        // The payload arrives either nested under "cryptarchia_info" or flat.
        function field(key) {
            if (!info) return undefined
            if (info.cryptarchia_info && info.cryptarchia_info[key] !== undefined)
                return info.cryptarchia_info[key]
            return info[key]
        }

        function num(key) {
            const v = field(key)
            return (v === undefined || v === null) ? qsTr("—") : String(v)
        }

        // The field as plain text, empty when absent — what a copy button has to
        // carry. num()'s "—" is a thing to read, not a thing to paste.
        function raw(key) {
            const v = field(key)
            return (v === undefined || v === null) ? "" : String(v)
        }

        // ---- Resource usage -------------------------------------------------
        readonly property bool cpuSampled: root.nodeCpuPercent >= 0
        readonly property real cpuMachineShare:
            Math.min(100, root.nodeCpuPercent / Math.max(1, root.cpuCount))

        // Whole percent, as the prototype shows it — except below 1%, where
        // rounding would print "0%" for a node that is demonstrably working. On
        // a many-core machine a whole busy core is already under 1%.
        readonly property string cpuText: {
            if (!cpuSampled)
                return qsTr("—")
            if (cpuMachineShare > 0 && cpuMachineShare < 1)
                return qsTr("<1%")
            return qsTr("%1%").arg(Math.round(cpuMachineShare))
        }

        // The prototype's format is one-decimal GB, but its fixtures are all
        // above a gigabyte. A node holding 80 MB would render as "0.1GB", and a
        // starting one as "0.0GB", so below a gigabyte this says MB.
        function sizeText(mb) {
            return mb >= 1024 ? qsTr("%1GB").arg((mb / 1024).toFixed(1))
                              : qsTr("%1MB").arg(Math.round(mb))
        }

        // Free space is what kills a node — running out corrupts the chain db
        // rather than slowing it. Both floors are about rocksdb compaction
        // headroom, not about the node's own footprint.
        readonly property bool diskCritical:
            root.nodeDiskFreeMb >= 0 && root.nodeDiskFreeMb < 2048
        readonly property bool diskLow:
            root.nodeDiskFreeMb >= 0 && root.nodeDiskFreeMb < 5120

        // Hashes are far too long for a tile; show head and tail, copy the whole.
        function shorten(s) {
            if (!s || s.length === 0)
                return qsTr("—")
            return s.length > 14 ? (s.substring(0, 6) + "…" + s.substring(s.length - 4)) : s
        }

        // ---- Sync ----------------------------------------------------------
        // Trust the node's own verdict. It reports Online once it is caught up
        // and following the chain; a slot-gap check here false-fires on a
        // sparse chain, where the tip legitimately trails wall-clock between
        // blocks — which made the headline flap Online↔Bootstrapping on every
        // block that landed. BlockchainView owns the reading and debounces the
        // fall from Online; this is just the view of it.
        readonly property bool synced: root.synced

        // ---- Consensus clock -----------------------------------------------
        // Date only: the exact second of a genesis years away is noise, and the
        // point of showing it at all is "that is not now".
        readonly property string genesisText:
            root.genesisUnixMs > 0
            ? new Date(root.genesisUnixMs).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
            : qsTr("in the future")

        readonly property var timeInfo: parseJson(root.timeInfoJson)
        readonly property string epoch: {
            const v = timeInfo ? timeInfo.current_epoch : undefined
            return (v === undefined || v === null) ? qsTr("—") : String(v)
        }

        // ---- Stake ---------------------------------------------------------
        readonly property string stakeCaption: {
            if (root.stakeTotal.length === 0)
                return ""
            if (root.stakeNoteCount === 0)
                return qsTr("Nothing has aged yet")
            const parts = []
            if (root.stakeAddresses.length === 1)
                parts.push(shorten(root.stakeAddresses[0]))
            parts.push(qsTr("%n note(s)", "", root.stakeNoteCount))
            if (root.stakeAddresses.length > 1)
                parts.push(qsTr("%n key(s)", "", root.stakeAddresses.length))
            return parts.join(" · ")
        }

        // ---- Rewards -------------------------------------------------------
        // "since 14 Mar", or empty while the date is unknown. Both reward tiles
        // carry it: they count claims the app saw settle, and a figure that
        // cannot say when it started counting is implying it counted everything.
        readonly property string countingSince: {
            if (root.claimsCountingSince.length === 0)
                return ""
            var d = new Date(root.claimsCountingSince)
            if (isNaN(d.getTime()))
                return ""
            return qsTr("since %1").arg(d.toLocaleDateString(Qt.locale(), Locale.ShortFormat))
        }

        readonly property string earnedCaption: {
            if (root.earnedTotal.length === 0)
                return ""
            if (root.earnedClaimCount === 0)
                return qsTr("No rewards claimed yet")
            // "before fees" lives in the info dialog, not here: three segments
            // elide on a tile this wide, and the segment that gets cut is the
            // date — which is the one thing the caption exists to say.
            var parts = [qsTr("%n voucher(s)", "", root.earnedClaimCount)]
            if (d.countingSince.length > 0)
                parts.push(d.countingSince)
            return parts.join(" \u00b7 ")
        }

        // ---- Stopping ------------------------------------------------------
        // A stop is outstanding for long enough that silence reads as a dead
        // button rather than as work in progress.
        property bool stopSlow: false
        // What the node was doing when the stop was asked for. Captured on the
        // way in, because the stop clears the backend flags that describe it.
        // Read off `synced` rather than nodeRecovering for exactly that reason:
        // it belongs to the monitor, so the stop cannot race it.
        property bool stopBehindCatchUp: false

        // ---- Uptime --------------------------------------------------------
        // The units here are the contract the backend ticks against: it widens
        // uptimeSeconds' push interval to match the smallest unit shown, so
        // adding seconds back at an hour would show a frozen seconds field.
        // See uptimeTickMs in BlockchainBackend.cpp.
        function uptimeText(s) {
            if (s < 60)
                return qsTr("%1s").arg(s)
            const m = Math.floor(s / 60)
            if (m < 60)
                return qsTr("%1m %2s").arg(m).arg(s % 60)
            const h = Math.floor(m / 60)
            if (h < 24)
                return qsTr("%1h %2m").arg(h).arg(m % 60)
            return qsTr("%1d %2h").arg(Math.floor(h / 24)).arg(h % 24)
        }
        readonly property bool showUptime: root.connected && root.uptimeSeconds > 0

        // ---- Vouchers ------------------------------------------------------
        readonly property var vouchers: parseJson(root.vouchersJson)
        readonly property int voucherCount:
            (vouchers && vouchers.vouchers) ? vouchers.vouchers.length : -1

        readonly property string voucherCaption: {
            if (voucherCount <= 0)
                return ""
            const total = vouchers ? vouchers.total_claimable : undefined
            if (total === undefined || total === null)
                return ""
            const formatted = Units.format(String(total))
            return formatted.length > 0 ? qsTr("≈%1 before fees").arg(formatted) : ""
        }

        // ---- Status hero ---------------------------------------------------
        // Six states, most specific first. `label` is the headline, `sub` the
        // line beside it, `dots` animates a reserved-width ellipsis on the
        // transitional ones, `isError` is the only thing that reddens the sub.
        //
        // Losing contact with the node is deliberately NOT a state here — see
        // `display` below.
        readonly property var state: {
            // First, because every branch below reads `status`, and `status`
            // freezes at whatever it was when the link dropped. Reporting a
            // frozen "Online" — or falling through to "Not started" as though
            // the node was never launched — are both inventions.
            if (!root.connected)
                return root.everConnected
                    ? { label: qsTr("Disconnected"),
                        sub: qsTr("Lost contact with the backend — restart the app to reconnect."),
                        color: Theme.palette.error, dots: false, isError: true }
                    : { label: qsTr("Not started"), sub: "",
                        color: Theme.palette.textSecondary, dots: false, isError: false }
            if (!root.moduleReachable)
                return { label: qsTr("Node stopped"),
                         // The backend diagnoses the cause from the node's log
                         // where it can; the generic line is the fallback for
                         // when it knows nothing.
                         sub: root.statusMessage
                              || qsTr("The node process stopped unexpectedly. Start it again."),
                         color: Theme.palette.error, dots: false, isError: true }
            if (root.status === BlockchainBackend.Error)
                return { label: qsTr("Error"),
                         sub: root.statusMessage || qsTr("Node error."),
                         color: Theme.palette.error, dots: false, isError: true }
            // Above the recovery branch on purpose: the backend leaves
            // nodeRecovering set when you stop a replaying node, so testing it
            // first would swallow the Stop and leave the click without feedback.
            if (root.status === BlockchainBackend.Stopping)
                return { label: qsTr("Stopping"),
                         sub: !d.stopSlow ? ""
                              : d.stopBehindCatchUp
                                ? qsTr("The node is busy catching up — stopping can take a while.")
                                : qsTr("Still waiting on the node to shut down."),
                         color: Theme.palette.warning, dots: true, isError: false }
            // Replay (from disk) and bootstrap (from peers) are one wait to the
            // user: catching up. The sub-line names the source, because that is
            // what differs if it stalls — replay is disk-bound, sync is
            // peer-bound. Note nodeRecovering runs at status Starting, so this
            // must sit above the Starting branch.
            if (root.nodeRecovering || (running && !synced)) {
                // Stalling does not get its own headline: the node genuinely is
                // bootstrapping, it just isn't getting anywhere. What has to
                // change is the *colour* — a sub-line edit under an amber card
                // still reads "working, wait", which is the opposite of what
                // the user should do. So the headline stays and goes red.
                // Genesis first: it is the one case that can never resolve on
                // its own, so it outranks "not progressing" and "stream died".
                // Without it the module's flattening of every non-Online state
                // into "Bootstrapping" leaves a misconfigured node claiming to
                // sync forever — and if blocks keep arriving, the stall
                // detector never fires either.
                if (running && root.genesisPending)
                    return { label: qsTr("Bootstrapping"),
                             sub: qsTr("Genesis is %1 — the node can't finish syncing until then. Its config likely points at the wrong network.")
                                      .arg(d.genesisText),
                             color: Theme.palette.error, dots: false, isError: true }
                if (running && (root.blockStreamEnded || root.syncStalled))
                    return { label: qsTr("Bootstrapping"),
                             sub: root.blockStreamEnded
                                  ? qsTr("Block updates have stopped arriving — restart the node to resubscribe.")
                                  : qsTr("No block progress for 10 minutes — the node may have lost its peers. Try stopping and starting it."),
                             color: Theme.palette.error, dots: false, isError: true }
                return { label: qsTr("Bootstrapping"),
                         sub: root.nodeRecovering
                              ? qsTr("Catching up — replaying stored blocks.")
                              // Same `mode` from the node either way; only we
                              // know it was caught up a moment ago, and that
                              // changes the diagnosis entirely.
                              : root.hasBeenOnline
                                ? qsTr("Fell behind — catching up")
                                : qsTr("Syncing with the chain"),
                         color: Theme.palette.warning, dots: true, isError: false }
            }
            if (root.status === BlockchainBackend.Starting)
                return { label: qsTr("Starting"), sub: qsTr("Checking configuration"),
                         color: Theme.palette.warning, dots: true, isError: false }
            if (running) {
                // The node is genuinely fine here — the poll still answers, so
                // every tile but the Blocks tab keeps updating. Green headline,
                // red note: nothing is broken, but something needs doing.
                if (root.blockStreamEnded)
                    return { label: qsTr("Online"),
                             sub: qsTr("Block updates have stopped arriving — restart the node to resubscribe."),
                             color: Theme.palette.success, dots: false, isError: true }
                return { label: qsTr("Online"), sub: qsTr("Following the chain"),
                         color: Theme.palette.success, dots: false, isError: false }
            }
            // NotStarted, Stopped and "replica not valid yet" all read the same
            // to the user: it isn't running.
            // The doc-test asserts this caption on the landing view.
            return { label: qsTr("Not started"), sub: root.statusMessage,
                     color: Theme.palette.textSecondary, dots: false, isError: false }
        }

        // What the hero actually renders. Losing the status RPC is a gap in our
        // knowledge, not a change in the node's: it can be perfectly alive and
        // merely too busy to answer. So keep the last known headline, grey it,
        // stop the pulse, and say so underneath — never replace it with a scarier
        // one.
        readonly property var display: !root.statusStale
            ? state
            : ({ label: state.label,
                 sub: root.statusSilentSeconds >= d.longSilenceSeconds
                      ? qsTr("No response from the node for %1 — it may be busy replaying, or the connection may have dropped.")
                            .arg(d.silenceText(root.statusSilentSeconds))
                      : qsTr("Status unavailable — retrying in %1s")
                            .arg(root.statusNextPollSeconds),
                 color: Theme.palette.textSecondary, dots: false, isError: false })

        readonly property int longSilenceSeconds: 120

        function silenceText(seconds) {
            if (seconds < 120)
                return qsTr("%1 seconds").arg(seconds)
            const minutes = Math.floor(seconds / 60)
            if (minutes < 120)
                return qsTr("%1 minutes").arg(minutes)
            return qsTr("%1 hours").arg(Math.floor(minutes / 60))
        }

        // ---- Lifecycle -----------------------------------------------------
        // LogosStageLane's position model: stages before `currentIndex` are
        // complete, the one at it is in progress. -1 = nothing started.
        //
        // Two halves, governed differently. The node stages (Started, Online)
        // are always live — a stopped node is not "proposing", whatever it
        // reached last session. The wallet stages (Funded, Aged, Proposing,
        // Earning) are steps: they hold at their high-water mark, because
        // claiming a reward empties the voucher list and must not walk the lane
        // backwards.
        //
        // Proposing carries no evidence of its own, and needs none: once notes
        // have aged, the leader tests them every slot, so the node genuinely is
        // competing for a block. It is the stage you sit in while waiting for a
        // first voucher — which is why its busy label says so rather than
        // claiming blocks are being produced.

        // Where the wallet stands right now, 2..5. Later conditions imply the
        // earlier ones: a node reporting aged notes is funded whether or not
        // the per-address balance fetch has caught up with it.
        readonly property int walletStage: {
            if (d.voucherCount > 0) return 5    // Earning
            if (root.stakeNoteCount > 0) return 4  // Proposing — aged, in the lottery
            if (root.walletFunded) return 3     // Aged — aging in
            return 2                            // Funded — waiting for tokens
        }

        // The node saying the stake is gone
        readonly property bool stakeReportedGone:
            running && root.stakeTotal.length > 0 && root.stakeNoteCount === 0

        property int walletHighWater: 2

        // Stake going away pulls the mark down; anything else only pushes it up.
        function advanceWallet() {
            if (stakeReportedGone && walletStage < walletHighWater) {
                walletHighWater = walletStage
                return
            }
            if (walletStage > walletHighWater)
                walletHighWater = walletStage
        }

        onWalletStageChanged: advanceWallet()
        onStakeReportedGoneChanged: advanceWallet()

        readonly property int lifeCurrentIndex: {
            if (root.status < 0 || root.status === BlockchainBackend.NotStarted)
                return -1
            if (root.status === BlockchainBackend.Error)
                return 0                        // failed while starting
            // Recovery outranks Starting, exactly as it does in the hero above.
            // The backend leaves status at Starting while it replays, so
            // testing Starting first pinned the lane on "Started" while the
            // headline already said Bootstrapping — the two reading the same
            // two facts in opposite orders and disagreeing on screen.
            if (root.nodeRecovering)
                return 1                        // Started done, working toward Online
            if (root.status === BlockchainBackend.Starting)
                return 0                        // Started, itself in progress
            if (!running)
                return -1
            if (!synced)
                return 1                        // Online — busy while it syncs
            return Math.max(2, walletHighWater)
        }

        readonly property bool lifeBusy:
            lifeCurrentIndex >= 0 && lifeCurrentIndex < 5

        readonly property bool lifeFailed:
            root.status === BlockchainBackend.Error

        // ---- Blend ---------------------------------------------------------
        // Unknown means blend hasn't reported. No running/synced gate here: the
        // backend only acquires a role while the node reports Online, and clears
        // it on any other mode or on leaving Running. Re-checking those two
        // could only ever hide a role the node has actually reported.
        readonly property string blendLabel: {
            switch (root.blendRole) {
            case BlockchainBackend.Core:     return qsTr("Core")
            case BlockchainBackend.Edge:     return qsTr("Edge")
            case BlockchainBackend.Inactive: return qsTr("Not active")
            default:                         return qsTr("—")
            }
        }

        readonly property string blendCaption: {
            switch (root.blendRole) {
            case BlockchainBackend.Core:     return qsTr("Mixing your proposals")
            case BlockchainBackend.Edge:     return qsTr("Mixed by the core network")
            case BlockchainBackend.Inactive: return qsTr("Proposals not mixed")
            default:                         return ""
            }
        }

        // Core is declared and earns for it; Edge is what every running node
        // gets for free. Tinting both `info` blue made the role that took work
        // look identical to the one that took none.
        readonly property color blendColor: {
            switch (root.blendRole) {
            case BlockchainBackend.Core:     return Theme.palette.accentYellowSoft
            case BlockchainBackend.Edge:     return Theme.palette.info
            // Off is not an error and not an achievement — state it plainly.
            case BlockchainBackend.Inactive: return Theme.palette.textSecondary
            default:                         return Theme.palette.text
            }
        }

        // Tiles fed by the status poll go dim when it stops answering. Without
        // this the hero says "I can't see the node" while four tiles carry on
        // presenting frozen numbers as though they were live. Peers rides along
        // with them — the backend refreshes it from the same poll. Only the
        // poll-derived ones: Balance, Vouchers, Blend, Peer ID and Epoch come
        // from elsewhere and are not stale just because this poll is.
        readonly property real infoOpacity: root.statusStale ? 0.45 : 1.0

        // The longest value a tile has to hold decides the column count: below
        // this the grid drops a column instead of squeezing the number.
        readonly property int minTileWidth: 210
    }

    onStatusChanged: {
        d.stopSlow = false
        if (root.status === BlockchainBackend.Stopping) {
            d.stopBehindCatchUp = !root.synced
            stopSlowTimer.restart()
        } else {
            stopSlowTimer.stop()
        }
    }

    Timer {
        id: stopSlowTimer
        interval: 4000
        onTriggered: d.stopSlow = true
    }

    LogosScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: Theme.spacing.large

            // ---- Back up your keys ----
            LogosNotice {
                objectName: "keysBackupBanner"
                Layout.fillWidth: true
                shown: root.keystorePresent && !root.keysBackedUp
                       && !root.keysNoticeDismissed
                closable: true
                // hide() assigns shown, which would destroy the binding above
                // and wedge the notice hidden even once a new config needs it.
                onDismissed: {
                    root.keysNoticeDismissed = true
                    shown = Qt.binding(function () {
                        return root.keystorePresent && !root.keysBackedUp
                               && !root.keysNoticeDismissed
                    })
                }
                severity: LogosNotice.Error
                title: qsTr("Back up your keys")
                message: qsTr("Your keystore has not been saved anywhere else. Nothing can "
                              + "reissue these keys, and the rewards this node earns are only "
                              + "reachable with them. Settings → Back up your keys has the "
                              + "download.")
            }

            // ---- Node hero: status headline + lifecycle lane ----
            // Deliberately NOT a LogosStatCard. The headline is larger than a
            // stat value, the sub-line sits in the corner instead of under it,
            // and the lane runs across the bottom — three rows of label/value/
            // caption is the wrong shape. LogosFrame is the right primitive.
            LogosFrame {
                Layout.fillWidth: true
                padding: Theme.spacing.medium
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: "transparent"
                radius: Theme.spacing.radiusLarge

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            LogosText {
                                text: d.display.label
                                color: d.display.color
                                font.pixelSize: 32
                                font.weight: Theme.typography.weightBold
                                elide: Text.ElideRight
                            }

                            Row {
                                visible: d.display.dots
                                spacing: 0

                                Repeater {
                                    model: 3

                                    LogosText {
                                        id: dot

                                        required property int index

                                        text: "."
                                        color: d.display.color
                                        font.pixelSize: 32
                                        font.weight: Theme.typography.weightBold

                                        SequentialAnimation on opacity {
                                            running: d.display.dots
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.25; duration: 0 }
                                            PauseAnimation { duration: dot.index * 260 }
                                            NumberAnimation { to: 1.0; duration: 180 }
                                            NumberAnimation { to: 0.25; duration: 180 }
                                            PauseAnimation { duration: (2 - dot.index) * 260 + 520 }
                                        }
                                    }
                                }
                            }

                        }

                        Item { Layout.fillWidth: true }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Layout.maximumWidth: root.width * 0.45
                            spacing: Theme.spacing.tiny

                            LogosText {
                                Layout.alignment: Qt.AlignRight
                                visible: d.showUptime
                                text: qsTr("Uptime: %1").arg(d.uptimeText(root.uptimeSeconds))
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText    
                                opacity: d.infoOpacity
                            }

                            LogosText {
                                Layout.fillWidth: true
                                visible: d.display.sub.length > 0
                                text: d.display.sub
                                // Red is the state's call, not the string's.
                                // Keying this off "is statusMessage non-empty"
                                // reddened the sub-line of every healthy state
                                // that happened to have a stale poll error
                                // sitting behind it.
                                color: d.display.isError ? Theme.palette.error
                                                         : Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        LogosInfoButton {
                            Layout.alignment: Qt.AlignTop
                            Layout.leftMargin: Theme.spacing.small
                            title: qsTr("Status")
                            dialogContentItem: InfoSections { info: InfoContent.status }
                        }
                    }

                    LogosStageLane {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.medium
                        currentIndex: d.lifeCurrentIndex
                        busy: d.lifeBusy
                        failed: d.lifeFailed
                        stages: [
                            LogosStage {
                                label: qsTr("Started")
                                busyLabel: qsTr("Starting")
                            },
                            LogosStage {
                                label: qsTr("Online")
                                busyLabel: qsTr("Syncing…")
                            },
                            LogosStage {
                                label: qsTr("Funded")               
                                busyLabel: root.miningRequested ? qsTr("Funding")
                                                       : qsTr("Fund your wallet")
                            },
                            LogosStage {
                                label: qsTr("Aged")
                                busyLabel: qsTr("Aging")
                            },
                            LogosStage {
                                label: qsTr("Proposing")
                                busyLabel: qsTr("Waiting for a slot")
                            },
                            LogosStage {
                                label: qsTr("Earning")
                            }
                        ]
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, Math.min(4, Math.floor(
                    width / (d.minTileWidth + Theme.spacing.large))))
                columnSpacing: Theme.spacing.large
                rowSpacing: Theme.spacing.large

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Stake")
                    value: root.stakeTotal.length > 0
                           ? Units.format(root.stakeTotal) : qsTr("—")
                    valueFontSizeMode: Text.HorizontalFit
                    caption: d.stakeCaption
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Stake")
                            dialogContentItem: InfoSections { info: InfoContent.stake }
                        }
                    ]
                    // Only while the caption IS an address — the figure is
                    // already shown in full, and counts have nothing to copy.
                    captionTrailing: [
                        LogosCopyButton {
                            visible: root.stakeAddresses.length === 1
                            value: root.stakeAddresses.length === 1
                                   ? root.stakeAddresses[0] : ""
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Earned")
                    value: root.earnedTotal.length > 0
                           ? Units.format(root.earnedTotal) : qsTr("—")
                    valueFontSizeMode: Text.HorizontalFit
                    caption: d.earnedCaption
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Earned")
                            dialogContentItem: InfoSections { info: InfoContent.earned }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Blend")
                    value: d.blendLabel
                    // A role is a fact, not a verdict, so tint it rather than
                    // flag it. `severity: Info` also plants an ⓘ beside the
                    // label, which is indistinguishable from the info button
                    // already sitting there.
                    valueColor: d.blendColor
                    caption: d.blendCaption
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Blend")
                            dialogContentItem: InfoSections { info: InfoContent.blend }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Epoch")
                    value: d.epoch
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Epoch")
                            dialogContentItem: InfoSections { info: InfoContent.epoch }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Ready to Claim")
                    value: d.voucherCount >= 0 ? String(d.voucherCount)
                                               : qsTr("—")
                    caption: d.voucherCaption
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Ready to Claim")
                            dialogContentItem: InfoSections { info: InfoContent.readyToClaim }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Peers")
                    opacity: d.infoOpacity
                    value: root.peerCount >= 0 ? String(root.peerCount) : qsTr("—")
                    valueColor: root.peerCount === 0 ? Theme.palette.error
                                                     : Theme.palette.text
                    caption: root.connectionCount >= 0
                             ? qsTr("%n connection(s)", "", root.connectionCount) : ""
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Peers")
                            dialogContentItem: InfoSections { info: InfoContent.peers }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Peer ID")
                    value: d.shorten(root.peerId)
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Peer ID")
                            dialogContentItem: InfoSections { info: InfoContent.peerId }
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: root.peerId }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Mining Rewards")
                    value: root.powRewardsLepta.length > 0
                           ? Units.compact(root.powRewardsLepta) : Units.compact("0")
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    severity: root.miningError.length > 0
                              ? LogosStatCard.Warning : LogosStatCard.None
                    caption: d.miningCaption
                    captionTrailing: [
                        Rectangle {
                            visible: root.powActive
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: Theme.palette.success
                        }
                    ]
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Mining Rewards")
                            dialogContentItem: InfoSections { info: InfoContent.mining }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("CPU")
                    opacity: d.infoOpacity
                    value: d.cpuText
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("CPU")
                            dialogContentItem: InfoSections { info: InfoContent.cpu }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("RAM")
                    opacity: d.infoOpacity
                    value: root.nodeMemoryMb >= 0 ? d.sizeText(root.nodeMemoryMb)
                                                  : qsTr("—")
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("RAM")
                            dialogContentItem: InfoSections { info: InfoContent.ram }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Disk")
                    value: root.nodeDiskUsedMb >= 0 ? d.sizeText(root.nodeDiskUsedMb)
                                                    : qsTr("—")
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    valueColor: d.diskCritical ? Theme.palette.error
                                : d.diskLow ? Theme.palette.warning
                                            : Theme.palette.text
                    caption: root.nodeDiskFreeMb >= 0
                             ? qsTr("%1 free").arg(d.sizeText(root.nodeDiskFreeMb)) : ""
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Disk")
                            dialogContentItem: InfoSections { info: InfoContent.disk }
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Slot")
                    opacity: d.infoOpacity
                    value: d.num("slot")
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Slot")
                            dialogContentItem: InfoSections { info: InfoContent.slot }
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.raw("slot") }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Height")
                    opacity: d.infoOpacity
                    value: d.num("height")
                    flashOnChange: true
                    flashColor: Theme.palette.success
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Height")
                            dialogContentItem: InfoSections { info: InfoContent.height }
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.raw("height") }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("LiB")
                    opacity: d.infoOpacity
                    value: d.shorten(d.raw("lib"))
                    // lib_slot rides along with the hash it belongs to: both
                    // describe the last irreversible block.
                    caption: d.field("lib_slot") !== undefined
                             ? qsTr("slot %1").arg(d.num("lib_slot")) : ""
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("LiB — Last Immutable Block")
                            dialogContentItem: InfoSections { info: InfoContent.lib }
                        }
                    ]
                    valueTrailing: [
                        LogosCopyButton { value: d.raw("lib") }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.raw("lib_slot") }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("TiP")
                    opacity: d.infoOpacity
                    value: d.shorten(d.raw("tip"))
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("TiP — Tip")
                            dialogContentItem: InfoSections { info: InfoContent.tip }
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.raw("tip") }
                    ]
                }
            }
        }
    }
}
