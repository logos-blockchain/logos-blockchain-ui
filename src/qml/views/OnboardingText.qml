pragma Singleton

import QtQuick

// Values the wizard uses that the design system has no token for.
QtObject {
    // Step heading, e.g. "How do you want to start?", "Network", "Fund your node".
    readonly property int stepHeading: 18
    // Sub-hint under a field, smaller than secondaryText.
    readonly property int fieldHint: 11
}
