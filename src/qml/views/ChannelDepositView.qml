import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls
import Logos.Icons

import "../controls"
import "../Units.js" as Units

// Multi-step wizard for channel_deposit_with_notes:
//   1. Select notes  → wallet_get_notes, pick UTXOs to consume
//   2. Fill fields   → channel id, change/funding keys, fee, metadata, tip
//   3. Confirm       → review the exact payload
//   4. Result        → tx hash (copyable) or error
ColumnLayout {
    id: root

    // Rows, not the remoted model: a combo reads currentValue at currentIndex,
    // and the replica lands count-first. Rows also carry the name and balance,
    // so a picker can show what an account IS rather than bare hex.
    property var accountRows: []
    property bool nodeRunning: false
    // A known LEZ channel id this build ships, or empty. Nothing on the LEZ side
    // publishes it — not the wallet, not the indexer — so without a configured
    // value there is nothing to offer and the preset is absent rather than
    // disabled.
    property string lezChannelId: ""
    // Why the node cannot answer, or empty when it can.
    property string nodeOffReason: ""
    // A LogosNotice.Severity for the banner above.
    property int nodeOffSeverity: LogosNotice.Info

    signal getNotesRequested(string addressHex, string optionalTipHex)
    signal submitRequested(string channelIdHex, var inputNoteIdHexes, string metadataBase58, string changePublicKeyHex, var fundingPublicKeyHexes, string maxTxFee, string optionalTipHex)
    signal copyToClipboard(string text)

    // --- Called by the parent after async backend calls return ---

    function setNotesLoading() {
        noteSelector.loading = true
        noteSelector.errorText = ""
    }

    function setNotes(jsonStr) {
        noteSelector.loading = false
        var s = jsonStr || ""
        try {
            var parsed = JSON.parse(s)
            d.notesTip = parsed.tip || ""
            noteSelector.errorText = ""
            noteSelector.notes = parsed.notes || []
        } catch (e) {
            noteSelector.errorText = qsTr("Failed to parse notes: %1").arg(s)
            noteSelector.notes = []
        }
    }

    function setNotesError(message) {
        noteSelector.loading = false
        noteSelector.errorText = message
        noteSelector.notes = []
    }

    function setSubmitResult(success, text) {
        d.resultPending = false
        d.resultSuccess = success
        d.resultText = text
    }

    spacing: Theme.spacing.large

    // The accounts chosen to fund the gas fee.
    ListModel { id: fundingKeysModel }

    QtObject {
        id: d

        property int step: 0
        readonly property int stepCount: 4
        property string notesTip: ""

        readonly property var addressHexRegExp: /^(0x)?[0-9a-fA-F]{64}$/

        property string selectedAddress: ""
        property string changeKey: ""

        // Row index for an address, so a combo can show what `d` holds.
        function indexOfAddress(addr) {
            const a = (addr || "").trim().toLowerCase()
            if (a.length === 0) return -1
            for (var i = 0; i < root.accountRows.length; ++i) {
                if (String(root.accountRows[i].address || "").toLowerCase() === a)
                    return i
            }
            return -1
        }

        // Address whose notes are currently loaded. Selecting a different
        // address clears the old notes and loads the new ones.
        property string loadedAddress: ""

        // result state
        property bool resultPending: false
        property bool resultSuccess: false
        property string resultText: ""

        // Clear any loaded notes and (re)load for `addr` — but only when it
        // actually differs from what's already loaded.
        function loadNotesFor(addr) {
            var a = (addr || "").trim()
            if (a === "" || a === loadedAddress)
                return
            loadedAddress = a
            noteSelector.clearSelection()
            noteSelector.notes = []
            noteSelector.errorText = ""
            notesTip = ""
            if (!root.nodeRunning)
                return
            root.setNotesLoading()
            root.getNotesRequested(a, "")
        }

        function fundingKeyList() {
            var out = []
            for (var i = 0; i < fundingKeysModel.count; ++i)
                out.push(fundingKeysModel.get(i).publicKey)
            return out
        }

        function fundingHas(key) {
            const k = String(key || "").trim().toLowerCase()
            if (k.length === 0) return false
            for (var i = 0; i < fundingKeysModel.count; ++i) {
                if (String(fundingKeysModel.get(i).publicKey).toLowerCase() === k)
                    return true
            }
            return false
        }

        function addFundingKey(key, label) {
            const k = String(key || "").trim()
            if (k.length === 0 || fundingHas(k))
                return
            fundingKeysModel.append({
                publicKey: k,
                label: String(label || "").trim()
            })
        }

        // --- Metadata (base58-encoded bytes) ---

        // The actual base58 → bytes decoding happens in the C++ backend; here we
        // only check the input uses the base58 (Bitcoin) alphabet. Plain base58
        // has no checksum, so a valid-alphabet string always decodes.
        function metadataIsValid() {
            var s = metadataField.text.trim()
            if (s === "")
                return true // optional
            return /^[1-9A-HJ-NP-Za-km-z]+$/.test(s)
        }

        function tipIsValid() {
            return tipField.text.trim() === "" || tipField.textInput.acceptableInput
        }

        function canAdvance() {
            switch (step) {
            case 0:
                return noteSelector.selectedCount > 0
            case 1:
                return channelIdField.textInput.acceptableInput
                    && d.changeKey.trim().length > 0
                    && fundingKeyList().length > 0
                    && maxFeeField.text.trim().length > 0
                    && metadataIsValid()
                    && tipIsValid()
            default:
                return true
            }
        }

        function goNext() {
            if (step === 1) {
                // entering confirm — nothing else
            }
            if (step < stepCount - 1)
                step++
            // Prefill key fields from the selected wallet when first reaching step 1.
            if (step === 1) {
                if (d.changeKey.trim() === "")
                    d.changeKey = d.selectedAddress.trim()
                if (fundingKeysModel.count === 0 && d.selectedAddress.trim() !== "") {
                    const i = indexOfAddress(d.selectedAddress)
                    addFundingKey(d.selectedAddress.trim(),
                                  i >= 0 ? (root.accountRows[i].label || "") : "")
                }
            }
        }

        function goBack() {
            if (step > 0)
                step--
        }

        function submit() {
            d.resultPending = true
            d.resultSuccess = false
            d.resultText = ""
            step = 3
            root.submitRequested(
                channelIdField.text.trim(),
                noteSelector.selectedIds(),
                metadataField.text.trim(),
                d.changeKey.trim(),
                fundingKeyList(),
                Units.normalizeInput(maxFeeField.text.trim()),
                tipField.text.trim())
        }

        function reset() {
            noteSelector.clearSelection()
            noteSelector.notes = []
            noteSelector.errorText = ""
            selectedAddress = ""
            loadedAddress = ""
            lezChannelCheck.checked = false
            channelIdField.text = ""
            changeKey = ""
            fundingKeysModel.clear()
            maxFeeField.text = ""
            metadataField.text = ""
            tipField.text = ""
            notesTip = ""
            resultText = ""
            resultPending = false
            step = 0
        }

        function summaryLines() {
            var ids = noteSelector.selectedIds()
            return [
                { k: qsTr("Channel ID"), v: channelIdField.text.trim() },
                { k: qsTr("Notes to consume (%1)").arg(ids.length), v: ids.join("\n") },
                { k: qsTr("Total amount"), v: Units.format(noteSelector.selectedTotal) },
                { k: qsTr("Change public key"), v: d.changeKey.trim() },
                { k: qsTr("Funding public keys"), v: fundingKeyList().join("\n") },
                { k: qsTr("Max tx fee"), v: maxFeeField.text.trim().length > 0
                                            ? maxFeeField.text.trim() + " " + Units.SYMBOL : "" },
                { k: qsTr("Metadata (base58)"), v: metadataField.text.trim() || qsTr("(none)") },
                { k: qsTr("Optional tip hex"), v: tipField.text.trim() || qsTr("(current tip)") }
            ]
        }
    }

    component AccountPicker: LogosComboBox {
        id: picker
        Layout.fillWidth: true
        model: root.accountRows
        textRole: "label"
        valueRole: "address"
        implicitHeight: 40
        background: Rectangle {
            radius: Theme.spacing.radiusSmall
            color: Theme.palette.backgroundSecondary
            border.width: 1
            border.color: picker.activeFocus ? Theme.palette.overlayOrange
                                             : Theme.palette.backgroundElevated
        }
        delegate: LogosItemDelegate {
            required property var modelData
            required property int index
            width: picker.width
            implicitHeight: Math.max(
                36, implicitContentHeight + topPadding + bottomPadding)
            highlighted: picker.highlightedIndex === index
            contentItem: AccountSummary {
                keyName: modelData.name || ""
                roleLabel: modelData.roleLabel || ""
                address: modelData.address || ""
                balance: modelData.balance || ""
            }
        }
    }

    component FieldLabel: LogosText {
        Layout.fillWidth: true
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
    }

    NodeOffNotice {
        reason: root.nodeOffReason
        reasonSeverity: root.nodeOffSeverity
    }

    // ---- Header / step indicator ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        Item { Layout.fillWidth: true }
        LogosText {
            text: qsTr("Step %1 of %2").arg(d.step + 1).arg(d.stepCount)
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosInfoButton {
            title: qsTr("Channel Deposit")
            Layout.alignment: Qt.AlignVCenter
            text: qsTr("Deposit wallet notes (UTXOs) into a channel. Pick an address to load its notes, select the notes to consume, fill in the channel id, change/funding keys and max fee, then confirm to submit.")
        }
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: d.step

        // ---- Step 0: Select notes ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.fillWidth: true
                text: qsTr("Select the notes (UTXOs) to deposit into the channel. Their full value is consumed.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            FieldLabel { text: qsTr("Deposit from") }

            AccountPicker {
                placeholderText: qsTr("Choose an account")
                currentIndex: d.indexOfAddress(d.selectedAddress)
                onActivated: function(index) {
                    d.selectedAddress = String(currentValue || "")
                    d.loadNotesFor(d.selectedAddress)
                }
            }

            NoteSelector {
                id: noteSelector
                Layout.fillWidth: true
                addressChosen: d.selectedAddress.length > 0
            }

            Item { Layout.fillHeight: true }
        }

        // ---- Step 1: Fields ----
        LogosScrollView {
            id: fieldsScroll
            ColumnLayout {
                width: fieldsScroll.availableWidth
                spacing: Theme.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium

                    LogosText {
                        text: qsTr("Channel ID hex")
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Item { Layout.fillWidth: true }
                    LogosCheckbox {
                        id: lezChannelCheck
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.lezChannelId.length > 0
                        text: qsTr("LEZ testnet")
                        font.pixelSize: Theme.typography.secondaryText
                        // Clears on the way out: the operator unticked to supply
                        // their own channel, and leaving the preset behind would
                        // show a value the tick says is not in use.
                        onToggled: channelIdField.text = checked ? root.lezChannelId : ""
                    }
                }
                LogosTextField {
                    id: channelIdField
                    Layout.fillWidth: true
                    placeholderText: qsTr("64 hex characters")
                    readOnly: lezChannelCheck.checked
                    validator: RegularExpressionValidator {
                        regularExpression: d.addressHexRegExp
                    }
                }
                LogosText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: channelIdField.text.trim().length > 0
                             && !channelIdField.textInput.acceptableInput
                    text: qsTr("A channel ID is 64 hex characters (32 bytes).")
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }

                FieldLabel { text: qsTr("Change goes to") }
                AccountPicker {
                    placeholderText: qsTr("Choose an account")
                    currentIndex: d.indexOfAddress(d.changeKey)
                    onActivated: function(index) {
                        d.changeKey = String(currentValue || "")
                    }
                }

                FieldLabel { text: qsTr("Accounts funding the gas fee") }

                LogosText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: qsTr("Add one or more accounts. The node draws the transaction "
                               + "fee from them.")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosComboBox {
                        id: fundingPicker
                        Layout.fillWidth: true
                        placeholderText: qsTr("Account…")
                        model: root.accountRows
                        textRole: "label"
                        valueRole: "address"
                        currentIndex: -1
                    }

                    LogosButton {
                        text: qsTr("Add")
                        enabled: fundingPicker.currentIndex >= 0
                                 && !d.fundingHas(fundingPicker.currentValue)
                        onClicked: {
                            d.addFundingKey(String(fundingPicker.currentValue || ""),
                                            fundingPicker.currentText)
                            fundingPicker.currentIndex = -1
                        }
                    }
                }

                LogosFrame {
                    Layout.fillWidth: true
                    padding: Theme.spacing.medium
                    backgroundColor: Theme.palette.surfaceRecessed
                    borderColor: "transparent"
                    radius: Theme.spacing.radiusMedium

                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small

                        LogosText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: fundingKeysModel.count === 0
                            text: qsTr("No accounts added yet.")
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textTertiary
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: fundingKeysModel

                            RowLayout {
                                id: fundingRow
                                required property int index
                                required property string publicKey
                                required property string label

                                Layout.fillWidth: true
                                spacing: Theme.spacing.small

                                LogosText {
                                    text: fundingRow.label
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                                LogosText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: fundingRow.publicKey
                                    font.pixelSize: Theme.typography.secondaryText
                                    color: Theme.palette.textSecondary
                                    elide: Text.ElideMiddle
                                }
                                LogosIconButton {
                                    id: removeFundingButton
                                    flat: true
                                    size: 28
                                    iconSize: 16
                                    iconSource: LogosIcons.trash
                                    iconColor: removeFundingButton.hovered
                                               ? Theme.palette.error
                                               : Theme.palette.textTertiary
                                    onClicked: fundingKeysModel.remove(fundingRow.index)

                                    LogosToolTip {
                                        text: qsTr("Remove this account")
                                        placement: LogosToolTip.Placement.Top
                                        visible: removeFundingButton.hovered
                                    }
                                }
                            }
                        }
                    }
                }

                LogosText {
                    text: qsTr("Max tx fee")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTextField {
                    id: maxFeeField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Maximum transaction fee (LGO)")
                    validator: RegularExpressionValidator {
                        regularExpression: Units.inputRegExp(Qt.locale())
                    }
                }

                LogosText {
                    text: qsTr("Metadata (base58, optional)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTextField {
                    id: metadataField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Base58-encoded metadata bytes")
                }
                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("Input must be base58-encoded; it is decoded to bytes before submission.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: metadataField.text.trim() !== "" && !d.metadataIsValid()
                    text: qsTr("Invalid base58 input")
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }

                LogosText {
                    text: qsTr("Optional tip hex (leave empty for current tip)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosTextField {
                        id: tipField
                        Layout.fillWidth: true
                        placeholderText: qsTr("64 hex characters")
                        validator: RegularExpressionValidator {
                            regularExpression: d.addressHexRegExp
                        }
                    }
                    LogosButton {
                        text: qsTr("Use query tip")
                        enabled: d.notesTip !== ""
                        onClicked: tipField.text = d.notesTip
                    }
                }
            }
        }

        // ---- Step 2: Confirm ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.fillWidth: true
                text: qsTr("Review the deposit. This is the exact payload that will be submitted.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            LogosFrame {
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: Theme.spacing.large
                backgroundColor: Theme.palette.surfaceRecessed
                borderColor: "transparent"
                radius: Theme.spacing.radiusLarge

                contentItem: LogosScrollView {
                    id: confirmScroll
                    ColumnLayout {
                        width: confirmScroll.availableWidth
                        spacing: Theme.spacing.medium
                        Repeater {
                            // Re-evaluated when the confirm step is shown so it
                            // reflects the latest field values.
                            model: d.step === 2 ? d.summaryLines() : []
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.tiny
                                LogosText {
                                    text: modelData.k
                                    font.pixelSize: Theme.typography.secondaryText
                                    color: Theme.palette.textSecondary
                                }
                                LogosText {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.pixelSize: Theme.typography.secondaryText
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Step 3: Result ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.alignment: Qt.AlignHCenter
                visible: d.resultPending
                text: qsTr("Submitting deposit…")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            LogosSpinner {
                Layout.alignment: Qt.AlignHCenter
                visible: d.resultPending
                running: d.resultPending
            }

            // Same severity surface the transfer result uses, so a deposit
            // reports itself the same way a transfer does.
            LogosNotice {
                Layout.fillWidth: true
                visible: !d.resultPending

                severity: d.resultSuccess ? LogosNotice.Success : LogosNotice.Error
                title: d.resultSuccess ? qsTr("Deposit submitted")
                                       : qsTr("Deposit failed")
                message: d.resultText
                shown: !d.resultPending && d.resultText !== ""
                closable: false

                actions: [
                    LogosCopyButton {
                        visible: d.resultSuccess && d.resultText !== ""
                        value: d.resultText
                    }
                ]
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ---- Footer navigation ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosButton {
            text: qsTr("Back")
            visible: d.step > 0 && d.step < 3
            onClicked: d.goBack()
        }
        Item { Layout.fillWidth: true }

        // Steps 0 & 1: Next
        LogosButton {
            text: qsTr("Next")
            visible: d.step < 2
            enabled: d.canAdvance()
            onClicked: d.goNext()
        }
        // Step 2: Confirm & submit
        LogosButton {
            text: qsTr("Confirm & deposit")
            visible: d.step === 2
            enabled: root.nodeRunning
            onClicked: d.submit()
        }
        // Step 3: New deposit (after completion)
        LogosButton {
            text: qsTr("New deposit")
            visible: d.step === 3 && !d.resultPending
            onClicked: d.reset()
        }
    }
}
