import QtQuick
import Quickshell
import qs.Widgets

// Bouton dans le centre de contrôle Noctalia : ouvre/ferme le panneau Hypr Layout.
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "layout-dashboard"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Hypr Layout"

    onClicked: if (pluginApi) pluginApi.togglePanel(screen, this)
}
