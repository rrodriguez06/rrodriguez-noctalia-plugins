import QtQuick
import Quickshell
import qs.Widgets

// Bouton du centre de contrôle Noctalia : ouvre/ferme le panneau Home Server Control.
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "server"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Home Server Control"

    onClicked: if (pluginApi) pluginApi.togglePanel(screen, this)
}
