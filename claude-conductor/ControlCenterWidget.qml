import QtQuick
import Quickshell
import qs.Widgets

// Bouton du centre de contrôle Noctalia : ouvre/ferme le panneau Claude Conductor.
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "robot"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Claude Conductor"

    onClicked: if (pluginApi) pluginApi.togglePanel(screen, this)
}
