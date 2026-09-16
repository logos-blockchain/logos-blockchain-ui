import QtQuick

// Watches a running node and reports what it is doing.
//
// This is a *status monitor*, not a liveness verdict. A failed call means "the
// status RPC didn't answer", not "the node is dead" — the node pushes blocks on
// a separate channel, so it can be perfectly alive while a request/reply call
// times out under load. So a failure never stops the node, and never stops the
// monitor either: it backs off and keeps asking. Giving up would save one call a
// minute and cost the user a dead end they have to click out of, usually while a
// healthy node is simply busy bootstrapping.
//
// Non-visual; give it a `backend` and whether the node is `running`, and read
// the properties under "Output" below. Has to be an Item rather than a QtObject
// because QtObject has no default property and so cannot hold the timers.
// Instantiate it outside any layout.
Item {
    id: root

    // --- Input ---
    property var backend: null
    // The node is Running per the backend state machine. Turning this off resets
    // everything: a fresh start monitors from scratch.
    property bool running: false

    // --- Output ---
    // get_cryptarchia_info payload, and the last failure from asking for it.
    readonly property alias infoJson: d.infoJson
    readonly property alias error: d.error
    // get_time_info payload. Only current_epoch is consumed downstream.
    readonly property alias timeInfoJson: d.timeInfoJson

    // The node reports itself caught up. Debounced — see `_applySyncReading`.
    readonly property alias synced: d.synced
    // Whether it has *ever* been caught up this run. The node reports the same
    // `mode` whether it never got there or fell behind after hours online; only
    // we can tell those apart, and the diagnosis differs completely.
    readonly property alias hasBeenOnline: d.hasBeenOnline

    // The status RPC has gone quiet for long enough to be worth showing, and no
    // block has arrived to vouch for the node. A consumer should treat this as a
    // *modifier* — keep the last known state and grey it — never as a state of
    // its own, because losing contact says nothing about the node's health.
    readonly property bool stale: d.retryMs >= d.staleAfterMs && !d.progressFresh
    // Seconds until the next retry. Display only.
    readonly property alias nextPollSeconds: d.nextPollSeconds

    // Catching up, we can see the node perfectly well, and nothing has moved for
    // ten minutes. Unlike `stale` this is substantiated, and the user has to act.
    readonly property bool stalled:
        root.running && !d.synced && d.retryMs === 0 && d.progressStalled
    // The push stream reported its own end, which the module says needs a node
    // restart to recover. Gated on the poll still answering for the same reason
    // `stalled` is: a stream that ended *because the node is shutting down* is a
    // symptom, and "restart to resubscribe" is useless advice for it.
    readonly property bool streamEnded:
        root.running && d.retryMs === 0 && !!root.backend && root.backend.blockStreamEnded

    // --- API ---
    // Call when something independent proves the node is alive (an incoming
    // block). Collapses the backoff instead of waiting the interval out.
    function nodeProvedAlive() {
        d.noteProgress()
        if (d.retryMs === 0 || !root.running)
            return
        d.retryMs = 0
        d.nextPollSeconds = 0
        // Only restart the timer if it is actually counting down: it is
        // single-shot and idle while a call is in flight, and restarting it then
        // would let two polls overlap — the thing the single-shot design exists
        // to prevent.
        if (statusTimer.running)
            statusTimer.restart()
    }

    QtObject {
        id: d

        property string infoJson: ""
        property string error: ""
        property string timeInfoJson: ""

        property bool synced: false
        property bool hasBeenOnline: false
        property int offlineReadings: 0
        readonly property int syncedDropReadings: 3

        // Cadence. While the node is catching up, `mode` is the value we are
        // chasing and it changes under us, so ask often. Once it reports Online
        // the remaining fields move slowly and live block data arrives on the
        // push channel instead, so back right off.
        readonly property int pollBaseMs: synced ? 12000 : 2000
        readonly property int pollMaxMs: 64 * 1000     // 2^6 seconds
        readonly property int retryBaseMs: 2000
        // Don't report staleness over one dropped poll: this is the 4th
        // consecutive failure, ~14s of silence (2s + 4s + 8s).
        readonly property int staleAfterMs: 16000
        property int retryMs: 0
        property int nextPollSeconds: 0

        // Two independent signals say the node is progressing: chain height
        // advancing (pulled) and a processed block arriving (pushed). The pushed
        // one keeps working when the status RPC is too busy to answer — which is
        // exactly the case that used to grey the card under a healthy node.
        property double lastProgressAt: 0
        property string heightSeen: ""
        property bool progressFresh: false
        property bool progressStalled: false

        readonly property int progressFreshMs: 90000   // a block this recent ⇒ alive
        // 10 minutes, matching the prototype. Its comment is the reason: a live
        // bootstrap legitimately advances height only every few minutes during
        // peer churn, so a tight window false-fires on slow sync — and wrongly
        // telling someone to restart a working node is the worse error.
        readonly property int progressStallMs: 600000

        function noteProgress() {
            d.lastProgressAt = Date.now()
        }

        // The payload arrives either nested under "cryptarchia_info" or flat.
        function infoField(json, key) {
            if (!json || json.length === 0)
                return ""
            try {
                const o = JSON.parse(json)
                const v = (o.cryptarchia_info || o)[key]
                return (v === undefined || v === null) ? "" : String(v)
            } catch (e) {
                return ""
            }
        }

        readonly property bool modeOnline: infoField(d.infoJson, "mode") === "Online"

        // Rising is immediate — good news needs no confirming. Falling needs
        // three consecutive readings, because a single blip in `mode` would
        // otherwise repaint the whole card amber, which is the flapping an
        // earlier slot-gap check used to cause.
        function applySyncReading() {
            if (d.modeOnline) {
                d.offlineReadings = 0
                d.synced = true
                d.hasBeenOnline = true
                return
            }
            d.offlineReadings += 1
            if (!d.synced || d.offlineReadings >= d.syncedDropReadings)
                d.synced = false
        }

        function reset() {
            d.infoJson = ""
            d.timeInfoJson = ""
            // Drop the last poll error too. Downstream it outranks the backend's
            // lastErrorMessage, so leaving it set would survive a restart and
            // colour the next run's "Checking configuration" red.
            d.error = ""
            d.synced = false
            d.hasBeenOnline = false
            d.offlineReadings = 0
            d.retryMs = 0
            d.nextPollSeconds = 0
            d.lastProgressAt = 0
            d.heightSeen = ""
            d.progressFresh = false
            d.progressStalled = false
        }

        function onPollSuccess(value) {
            d.infoJson = value
            d.error = ""
            d.retryMs = 0                  // recovered: back to the base cadence
            d.nextPollSeconds = 0
            d.applySyncReading()
            // Height advancing is the pulled half of the progress signal.
            // Compared as a string: it is a u64, and Number() loses precision
            // past 2^53.
            const h = d.infoField(value, "height")
            if (h.length > 0 && h !== d.heightSeen) {
                d.heightSeen = h
                d.noteProgress()
            }
            d.scheduleNext()
        }

        function onPollFailure(message) {
            d.error = (message === undefined || message === null) ? "" : String(message)
            // Exponential backoff: 2s, 4s, 8s, … capped at 2^6 s and held there
            // for as long as it takes. The backoff starts from its own base
            // rather than the (possibly slower) healthy cadence, so recovery is
            // quick either way.
            d.retryMs = d.retryMs === 0
                ? d.retryBaseMs
                : Math.min(d.retryMs * 2, d.pollMaxMs)
            d.nextPollSeconds = Math.ceil(d.retryMs / 1000)
            d.scheduleNext()
        }

        function scheduleNext() {
            // Guard against rescheduling after the node has left Running.
            if (root.running)
                statusTimer.restart()
        }

        function poll() {
            if (!root.running || !root.backend)
                return
            logos.watch(
                root.backend.getCryptarchiaInfo(),
                function(result) {
                    if (result.success)
                        d.onPollSuccess(result.value)
                    else
                        d.onPollFailure(result.error)
                },
                function(error) { d.onPollFailure(error) }
            )
        }

        function pollTimeInfo() {
            if (!root.backend)
                return
            logos.watch(
                root.backend.getTimeInfo(),
                function(result) { d.timeInfoJson = result.success ? result.value : "" },
                function(error) { d.timeInfoJson = "" }
            )
        }
    }

    onRunningChanged: {
        d.reset()
        if (root.running)
            d.poll()                       // immediate first poll
        else
            statusTimer.stop()
    }

    // Single-shot: each poll schedules the next one itself once its reply
    // arrives, so a slow or stuck call can't overlap the following request and
    // the backoff interval is honoured exactly.
    Timer {
        id: statusTimer
        repeat: false
        interval: d.retryMs > 0 ? d.retryMs : d.pollBaseMs
        onTriggered: d.poll()
    }

    // Consensus clock, on its own slow timer rather than chained onto the status
    // poll. Only current_epoch is used and an epoch runs for hours.
    Timer {
        interval: 60000
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: d.pollTimeInfo()
    }

    // "How long since X" needs a clock, not a binding.
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            const since = Date.now() - d.lastProgressAt
            d.progressFresh = d.lastProgressAt > 0 && since < d.progressFreshMs
            d.progressStalled = d.lastProgressAt > 0 && since > d.progressStallMs
        }
    }

    // Live countdown to the next retry, purely for display. The actual poll is
    // driven by statusTimer, not this.
    Timer {
        interval: 1000
        repeat: true
        running: root.stale
        onTriggered: {
            if (d.nextPollSeconds > 0)
                d.nextPollSeconds -= 1
        }
    }
}
