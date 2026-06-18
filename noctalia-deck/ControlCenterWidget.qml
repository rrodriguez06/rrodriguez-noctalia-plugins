import QtQuick
import Quickshell
import qs.Widgets

// Bouton du centre de contrôle Noctalia : ouvre/ferme le terminal flottant (panel natif).
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "terminal"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Noctalia Deck"

    onClicked: if (pluginApi) pluginApi.togglePanel(screen, (pluginApi.mainInstance && pluginApi.mainInstance.cfgPosition === "centered") ? null : this)
}
