import QtQuick
import Quickshell
import qs.Widgets

// Control center button: opens/closes the Calendar panel.
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "calendar"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Calendar"

    onClicked: if (pluginApi) pluginApi.togglePanel(screen, this)
}
