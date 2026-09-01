import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import Logos.BlockchainBackend 1.0

// The design's node card: process state up top, chain sync in the middle,
// precise state and the start/stop control at the bottom.
Control {
    id: root

    // --- Public API ---
    required property int status
    property string statusMessage: ""
    property bool messageIsNotice: false
    // get_cryptarchia_info / get_time_info payloads, as polled by BlockchainView.
    property string infoJson: ""
    property string timeInfoJson: ""

    property bool canStart: false
    property bool canStop: false

    property string userConfig: ""
    property string deploymentConfig: ""
    property bool useGeneratedConfig: false
    property bool monitoringPaused: false
    property string statusLabelOverride: ""

    signal startRequested()
    signal stopRequested()
    signal changeConfigRequested()
    signal resumeMonitoringRequested()

    readonly property alias _d: d

    QtObject {
        id: d

        readonly property bool running: root.status === BlockchainBackend.Running
        readonly property bool transitioning: root.status === BlockchainBackend.Starting
                                              || root.status === BlockchainBackend.Stopping

        function parse(text) {
            if (!text || text.length === 0)
                return null
            try {
                return JSON.parse(text)
            } catch (e) {
                return null
            }
        }

        readonly property var info: parse(root.infoJson)
        readonly property var timeInfo: parse(root.timeInfoJson)

        readonly property var tipSlot: info && info.slot !== undefined ? Number(info.slot) : undefined
        readonly property var currentSlot:
            timeInfo && timeInfo.current_slot !== undefined ? Number(timeInfo.current_slot) : undefined
        readonly property var slotDurationMs:
            timeInfo && timeInfo.slot_duration_ms !== undefined ? Number(timeInfo.slot_duration_ms) : undefined

        // Slots still to close. Undefined until both payloads have arrived.
        readonly property var remaining: {
            if (tipSlot === undefined || currentSlot === undefined)
                return undefined
            return Math.max(0, currentSlot - tipSlot)
        }

        // The node reports Online / Bootstrapping / NotStarted.
        readonly property string mode: info && info.mode ? String(info.mode) : ""

        // A couple of slots of lag is normal — not every slot produces a block.
        readonly property int syncedSlack: 3
        readonly property bool synced:
            mode === "Online" && remaining !== undefined && remaining <= syncedSlack
        property real emaRate: NaN     // slots/sec, exponentially smoothed
        property real lastTip: NaN
        property real lastAt: 0
        readonly property real smoothing: 0.15

        // The ETA decision boundary sits at closingRate == 0, which is exactly
        // where the noise lives when a node is tracking the head without
        // gaining on it. Without hysteresis the label flips format every poll.
        // Enter only on a sustained gain, leave only when it genuinely stalls.
        readonly property real etaEnterRate: 0.05   // slots/sec
        readonly property real etaExitRate: 0.0
        property bool etaHolding: false

        function resetRate() {
            emaRate = NaN
            lastTip = NaN
            lastAt = 0
            etaHolding = false
        }

        function sampleRate(tip) {
            const now = Date.now() / 1000
            if (!isNaN(lastTip) && now > lastAt) {
                const instant = (tip - lastTip) / (now - lastAt)
                // A backwards tip means a reorg or a restart; drop the history
                // rather than feeding a negative sample into the average.
                if (instant < 0)
                    emaRate = NaN
                else
                    emaRate = isNaN(emaRate) ? instant
                                             : smoothing * instant + (1 - smoothing) * emaRate
            }
            lastTip = tip
            lastAt = now

            const closing = emaRate - headRate
            if (!isNaN(closing)) {
                if (!etaHolding && closing > etaEnterRate)
                    etaHolding = true
                else if (etaHolding && closing <= etaExitRate)
                    etaHolding = false
            }
        }

        // Slots/sec the chain head moves at.
        readonly property real headRate:
            slotDurationMs !== undefined && slotDurationMs > 0 ? 1000 / slotDurationMs : NaN

        // Net rate at which the gap shrinks. <= 0 means we are not converging.
        readonly property real closingRate: {
            if (isNaN(emaRate) || isNaN(headRate))
                return NaN
            return emaRate - headRate
        }

        readonly property var etaSeconds: {
            if (!running || synced || remaining === undefined || remaining <= 0)
                return undefined
            if (!etaHolding || isNaN(closingRate) || closingRate <= 0)
                return undefined
            return remaining / closingRate
        }

        function formatEta(seconds) {
            const total = Math.round(seconds)
            const h = Math.floor(total / 3600)
            const m = Math.floor((total % 3600) / 60)
            const s = total % 60
            const pad = (n) => (n < 10 ? "0" + n : String(n))
            return h > 0 ? "%1:%2:%3".arg(h).arg(pad(m)).arg(pad(s))
                         : "%1:%2".arg(m).arg(pad(s))
        }

        // ---- Presentation --------------------------------------------------
        readonly property color processColor: {
            if (transitioning)
                return Theme.palette.warning
            if (!running)
                return Theme.palette.textMuted
            return Theme.palette.success
        }

        readonly property string statusLabel: {
            if (root.statusLabelOverride.length > 0)
                return root.statusLabelOverride
            switch (root.status) {
            case BlockchainBackend.NotStarted: return qsTr("Not started")
            case BlockchainBackend.Starting:   return qsTr("Starting…")
            case BlockchainBackend.Running:    return qsTr("Running")
            case BlockchainBackend.Stopping:   return qsTr("Stopping…")
            case BlockchainBackend.Stopped:    return qsTr("Stopped")
            case BlockchainBackend.Error:      return qsTr("Error")
            default:                           return qsTr("Not connected")
            }
        }

        readonly property color syncColor: {
            if (!running)
                return Theme.palette.textMuted
            return synced ? Theme.palette.success : Theme.palette.warning
        }

        readonly property string syncLabel: {
            if (!running)
                return qsTr("Not syncing")
            if (synced)
                return qsTr("Synced")
            if (remaining === undefined)
                return qsTr("Syncing")
            if (etaSeconds !== undefined)
                return qsTr("Syncing — %1 Mins").arg(formatEta(etaSeconds))
            // Converging too slowly to time, or not at all. Say how far behind
            // instead of inventing a number.
            return qsTr("Syncing — %1 slots behind").arg(remaining)
        }
    }

    // Sampling is driven by the tip moving, which BlockchainView refreshes on
    // every successful poll.
    onInfoJsonChanged: {
        if (d.tipSlot !== undefined)
            d.sampleRate(d.tipSlot)
    }

    // A stop/start invalidates the rate history: the tip jumps, and a stale
    // average would produce an ETA for a run that is over.
    onStatusChanged: {
        if (root.status !== BlockchainBackend.Running)
            d.resetRate()
    }

    background: Rectangle {
        color: Theme.palette.background
    }

    contentItem: LogosFrame {
        padding: Theme.spacing.large
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: "transparent"
        radius: Theme.spacing.radiusXlarge

        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium

            // ---- Identity + process ornament ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosIcon {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Qt.resolvedUrl("../icons/node-tree.svg")
                    color: Theme.palette.primary
                }

                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Node")
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.panelTitleText
                    font.weight: Theme.typography.weightMedium
                }

                Item { Layout.fillWidth: true }

                LogosDotMatrix {
                    Layout.alignment: Qt.AlignTop
                    pattern: ringPattern
                    animated: d.transitioning
                    dotColor: d.processColor
                }
            }

            LogosText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.statusMessage
                color: root.messageIsNotice ? Theme.palette.textSecondary : Theme.palette.error
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // ---- Chain sync ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: width / 2
                    color: d.syncColor
                }

                LogosText {
                    Layout.fillWidth: true
                    text: d.syncLabel
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.primaryText
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // ---- Process state + control ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: width / 2
                    color: d.processColor
                }

                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    text: d.statusLabel
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.primaryText
                }

                Item { Layout.fillWidth: true }

                LogosButton {
                    visible: root.monitoringPaused
                    text: qsTr("Resume")
                    onClicked: root.resumeMonitoringRequested()
                }

                LogosButton {
                    text: d.running || root.canStop ? qsTr("Stop") : qsTr("Start")
                    enabled: d.running || root.canStop ? root.canStop : root.canStart
                    onClicked: {
                        if (d.running || root.canStop)
                            root.stopRequested()
                        else
                            root.startRequested()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.spacing.tiny
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: qsTr("User Config")
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                    }

                    Item { Layout.fillWidth: true }

                    // Copies the full path, not the elided display string.
                    LogosCopyButton {
                        visible: root.userConfig.length > 0
                        value: root.userConfig
                    }
                }
                LogosText {
                    Layout.fillWidth: true
                    text: (root.userConfig || qsTr("No file selected"))
                          + (root.useGeneratedConfig ? " " + qsTr("(Generated)") : "")
                    color: Theme.palette.textTertiary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideMiddle
                }

                RowLayout {
                    Layout.topMargin: Theme.spacing.small
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        text: qsTr("Deployment Config")
                        color: Theme.palette.text
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                    }

                    Item { Layout.fillWidth: true }

                    LogosCopyButton {
                        visible: root.deploymentConfig.length > 0
                        value: root.deploymentConfig
                    }
                }
                LogosText {
                    Layout.fillWidth: true
                    text: root.useGeneratedConfig && root.deploymentConfig
                              ? root.deploymentConfig
                              : root.useGeneratedConfig
                                  ? qsTr("Default")
                                  : (root.deploymentConfig || qsTr("No file selected"))
                    color: Theme.palette.textTertiary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideMiddle
                }

                Item { Layout.fillHeight: true }

                LogosButton {
                    Layout.topMargin: Theme.spacing.small
                    Layout.alignment: Qt.AlignRight
                    visible: !root.canStop
                    text: qsTr("Change")
                    onClicked: root.changeConfigRequested()
                }
            }
        }
    }
}
