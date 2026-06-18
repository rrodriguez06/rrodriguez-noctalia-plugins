import QtQuick
import Quickshell
import qs.Widgets

// Bouton du centre de contrôle Noctalia : bascule le terminal flottant.
NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "terminal"
    tooltipText: pluginApi ? pluginApi.tr("ccw.tooltip") : "Noctalia Deck"

    onClicked: if (pluginApi && pluginApi.mainInstance) pluginApi.mainInstance.toggle()
}
