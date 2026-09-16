pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import Logos.BlockchainBackend 1.0

// The node dashboard: a full-width status hero carrying the lifecycle lane,
// over a responsive grid of metric tiles.
Item {
    id: root

    // --- Public API ---
    required property var accountsModel
    property int status: -1                 // backend.status; -1 = not connected
    // Whether we currently have a live link to the backend, and whether we ever
    // had one. `status` freezes at its last value when the link drops, so
    // without these a dead node process reads as a confident "Online".
    property bool connected: false
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
    property string peerId: ""
    property int blendRole: BlockchainBackend.Unknown
    // Debounced in BlockchainView — a single blip in `mode` must not repaint
    // the card. `hasBeenOnline` separates a first bootstrap from a node that
    // fell behind; the node reports the same `mode` for both.
    property bool synced: false
    property bool hasBeenOnline: false
    // The status poll has gone quiet. Modifies the hero; never replaces a state.
    property bool statusStale: false
    property int statusNextPollSeconds: 0
    // Catching up but demonstrably not progressing, or the push stream died.
    // Unlike statusStale these are substantiated, and the user has to act.
    property bool syncStalled: false
    property bool blockStreamEnded: false
    // The node's genesis time hasn't arrived, so it can never reach Online.
    property bool genesisPending: false
    property double genesisUnixMs: 0

    QtObject {
        id: d

        readonly property bool running: root.status === BlockchainBackend.Running

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

        function hash(key) {
            const v = field(key)
            return (v === undefined || v === null) ? "" : String(v)
        }

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

        // ---- Accounts ------------------------------------------------------
        readonly property int accountCount: accounts.count

        function balanceAt(i) {
            const row = (i >= 0 && i < accountCount) ? accounts.objectAt(i) : null
            // objectAt() is typed QObject, so qmllint cannot see the delegate's
            // required properties; `balance` is declared on it just below.
            // qmllint disable missing-property
            return row ? String(row.balance || "").trim() : ""
            // qmllint enable missing-property
        }

        // Balances are u64 rendered as decimal strings, and a u64 runs past
        // 2^53 where Number() silently loses precision. BigInt literals don't
        // parse in QML, so add the decimal strings directly — schoolbook
        // addition, right to left, exact at any width.
        function addDecimal(a, b) {
            let out = ""
            let carry = 0
            let i = a.length - 1
            let j = b.length - 1
            while (i >= 0 || j >= 0 || carry > 0) {
                const digit = (i >= 0 ? a.charCodeAt(i) - 48 : 0)
                            + (j >= 0 ? b.charCodeAt(j) - 48 : 0)
                            + carry
                out = String(digit % 10) + out
                carry = digit >= 10 ? 1 : 0
                i -= 1
                j -= 1
            }
            return out.length > 0 ? out : "0"
        }

        function stripLeadingZeros(v) {
            const trimmed = v.replace(/^0+/, "")
            return trimmed.length > 0 ? trimmed : "0"
        }

        readonly property var totals: {
            let sum = "0"
            let known = 0
            for (let i = 0; i < accountCount; i++) {
                const b = balanceAt(i)
                if (!/^[0-9]+$/.test(b))
                    continue
                sum = addDecimal(sum, b)
                known += 1
            }
            return { text: known > 0 ? stripLeadingZeros(sum) : "", known: known }
        }

        // A balance stays empty when its lookup failed, so a total built from a
        // subset would read as the whole holding. Say so rather than imply it.
        readonly property bool partialTotal: totals.known > 0 && totals.known < accountCount

        // Shortens a long figure to K/M/B/T so it fits a tile instead of
        // eliding to a meaningless prefix. Done here rather than in
        // LogosStatCard because the suffixes are English — a design system
        // cannot pick them for every locale. The exact figure stays one click
        // away on the tile's copy button.
        readonly property int balanceMaxChars: 9

        function tierNum(v) {
            return v >= 100 ? String(Math.round(v))
                 : v >= 10 ? v.toFixed(0)
                 : v.toFixed(1)
        }

        function abbreviate(s) {
            if (!s || s.length <= balanceMaxChars)
                return s
            const n = parseFloat(s)
            if (!isFinite(n))
                return s
            const tiers = [[1, ""], [1e3, "K"], [1e6, "M"], [1e9, "B"], [1e12, "T"]]
            const candidates = []
            for (let i = 0; i < tiers.length; i++) {
                const v = n / tiers[i][0]
                if (i === 0 || v >= 1)
                    candidates.push(tierNum(v) + tiers[i][1])
            }
            for (let j = 0; j < candidates.length; j++)
                if (candidates[j].length <= balanceMaxChars)
                    return candidates[j]
            return candidates[candidates.length - 1]
        }

        // ---- Vouchers ------------------------------------------------------
        readonly property var vouchers: parseJson(root.vouchersJson)
        readonly property int voucherCount:
            (vouchers && vouchers.vouchers) ? vouchers.vouchers.length : 0

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
                        sub: qsTr("Lost contact with the node module — restart the app to reconnect."),
                        color: Theme.palette.error, dots: false, isError: true }
                    : { label: qsTr("Not started"), sub: "",
                        color: Theme.palette.textSecondary, dots: false, isError: false }
            if (root.status === BlockchainBackend.Error)
                return { label: qsTr("Error"),
                         sub: root.statusMessage || qsTr("Node error."),
                         color: Theme.palette.error, dots: false, isError: true }
            // Above the recovery branch on purpose: the backend leaves
            // nodeRecovering set when you stop a replaying node, so testing it
            // first would swallow the Stop and leave the click without feedback.
            if (root.status === BlockchainBackend.Stopping)
                return { label: qsTr("Stopping"), sub: "",
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
                              ? (root.statusMessage
                                 || qsTr("Catching up — replaying stored blocks."))
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
        // one. A diagnosed recovery outranks it: "replaying stored blocks" is a
        // reason for the silence, and beats reporting no reason at all.
        readonly property var display: (!root.statusStale || root.nodeRecovering)
            ? state
            : ({ label: state.label,
                 sub: qsTr("Status unavailable — retrying in %1s")
                          .arg(root.statusNextPollSeconds),
                 color: Theme.palette.textSecondary, dots: false, isError: false })

        // ---- Lifecycle -----------------------------------------------------
        // Only the stages the node genuinely reports. Funded, Aged, Proposing
        // and Earning stay out until their backend signals exist, rather than
        // sitting permanently dark in the lane.
        // LogosStageLane's position model: stages before `currentIndex` are
        // complete, the one at it is in progress. -1 = nothing started.
        readonly property int lifeCurrentIndex: {
            if (root.status < 0 || root.status === BlockchainBackend.NotStarted)
                return -1
            if (root.status === BlockchainBackend.Error)
                return 0                        // failed while starting
            if (root.status === BlockchainBackend.Starting)
                return 0                        // Started, itself in progress
            if (root.nodeRecovering)
                return 1                        // Started done, working toward Online
            if (running)
                return 1                        // Online — busy while it syncs
            return -1
        }

        // The stage at the frontier is actively working.
        readonly property bool lifeBusy:
            root.status === BlockchainBackend.Starting
            || root.nodeRecovering
            || (running && !synced)

        readonly property bool lifeFailed:
            root.status === BlockchainBackend.Error

        // ---- Blend ---------------------------------------------------------
        // Unknown means blend hasn't reported. No running/synced gate here: the
        // backend only acquires a role while the node reports Online, and clears
        // it on any other mode or on leaving Running. Re-checking those two
        // could only ever hide a role the node has actually reported.
        readonly property bool blendKnown: root.blendRole !== BlockchainBackend.Unknown

        readonly property string blendLabel: {
            switch (root.blendRole) {
            case BlockchainBackend.Core: return qsTr("Core")
            case BlockchainBackend.Edge: return qsTr("Edge")
            default:                     return qsTr("—")
            }
        }

        // Tiles fed by the status poll go dim when it stops answering. Without
        // this the hero says "I can't see the node" while four tiles carry on
        // presenting frozen numbers as though they were live. Only the
        // poll-derived ones: Balance, Vouchers, Blend, Peer ID and Epoch come
        // from elsewhere and are not stale just because this poll is.
        readonly property real infoOpacity: root.statusStale ? 0.45 : 1.0

        // The longest value a tile has to hold decides the column count: below
        // this the grid drops a column instead of squeezing the number.
        readonly property int minTileWidth: 210
    }

    Instantiator {
        id: accounts
        model: root.accountsModel
        delegate: QtObject {
            required property string address
            required property string balance
        }
    }

    LogosScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: Theme.spacing.large

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

                        LogosText {
                            text: d.display.label
                            color: d.display.color
                            font.pixelSize: 32
                            font.weight: Theme.typography.weightBold
                            elide: Text.ElideRight
                        }

                        // Reserved-width ellipsis for the transitional states:
                        // only opacity animates, so the headline never shifts.
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

                        Item { Layout.fillWidth: true }

                        LogosText {
                            Layout.alignment: Qt.AlignTop
                            Layout.maximumWidth: root.width * 0.45
                            visible: d.display.sub.length > 0
                            text: d.display.sub
                            // Red is the state's call, not the string's. Keying
                            // this off "is statusMessage non-empty" reddened the
                            // sub-line of every healthy state that happened to
                            // have a stale poll error sitting behind it.
                            color: d.display.isError ? Theme.palette.error
                                                     : Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    LogosStageLane {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.medium
                        currentIndex: d.lifeCurrentIndex
                        busy: d.lifeBusy
                        failed: d.lifeFailed
                        stages: [
                            LogosStage { label: qsTr("Started") },
                            LogosStage {
                                label: qsTr("Online")
                                busyLabel: qsTr("Syncing…")
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
                    label: qsTr("Total Balance")
                    value: d.totals.text.length > 0
                           ? d.abbreviate(d.totals.text) : qsTr("—")
                    // A total built from a subset would read as the whole
                    // holding, so the figure itself is flagged, not just noted.
                    severity: d.partialTotal ? LogosStatCard.Warning
                                             : LogosStatCard.None
                    caption: d.partialTotal
                             ? qsTr("%1 of %2 accounts reported").arg(d.totals.known).arg(d.accountCount)
                             : ""
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Total Balance")
                            text: qsTr("Sum of the balances of every known wallet account, in base units. The node does not publish a token denomination, so this is not converted to LGO. Long figures are shortened — copy for the exact value.")
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.totals.text }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Vouchers Ready to Claim")
                    value: String(d.voucherCount)
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Vouchers Ready to Claim")
                            text: qsTr("Leader reward vouchers this wallet can claim. A voucher carries no value of its own — the reward it redeems lives on the ledger. Claim them from the Rewards tab.")
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("Blend")
                    value: d.blendKnown ? d.blendLabel : qsTr("—")
                    // A role is a fact, not a verdict, so tint it rather than
                    // flag it. `severity: Info` also plants an ⓘ beside the
                    // label, which is indistinguishable from the info button
                    // already sitting there.
                    valueColor: d.blendKnown ? Theme.palette.info
                                             : Theme.palette.text
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("Blend")
                            text: qsTr("This node's role in the blend network, which mixes proposals. Reported only once the node is online and blend has announced itself.")
                        }
                    ]
                }

                // The design draws a progress caption here too ("6h of 10h").
                // That needs the epoch length in slots, which get_time_info does
                // not report — it could be inferred from current_slot /
                // current_epoch, but that assumes epoch 0 starts at slot 0 and
                // that epochs are fixed-length. Ship the number; ask the node
                // for the length rather than guessing it.
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
                            text: qsTr("The consensus epoch the chain is currently in, derived from the genesis time and slot duration. Stake eligibility is decided per epoch: a note becomes able to lead roughly two epochs after it is minted.")
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
                            text: qsTr("Consensus slot of the current tip.")
                        }
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
                            text: qsTr("Number of blocks in the chain up to the current tip.")
                        }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("LiB")
                    opacity: d.infoOpacity
                    value: d.shorten(d.hash("lib"))
                    // lib_slot rides along with the hash it belongs to: both
                    // describe the last irreversible block.
                    caption: d.field("lib_slot") !== undefined
                             ? qsTr("slot %1").arg(d.num("lib_slot")) : ""
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("LiB")
                            text: qsTr("Header id of the last irreversible block — the point the chain can no longer reorganise past.")
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.hash("lib") }
                    ]
                }

                LogosStatCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: d.minTileWidth
                    label: qsTr("TiP")
                    opacity: d.infoOpacity
                    value: d.shorten(d.hash("tip"))
                    labelTrailing: [
                        LogosInfoButton {
                            title: qsTr("TiP")
                            text: qsTr("Header id of the current chain tip — the most recent block this node has applied.")
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: d.hash("tip") }
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
                            text: qsTr("This node's libp2p identity, derived from the selected user config. It does not need a running node.")
                        }
                    ]
                    captionTrailing: [
                        LogosCopyButton { value: root.peerId }
                    ]
                }
            }
        }
    }
}
