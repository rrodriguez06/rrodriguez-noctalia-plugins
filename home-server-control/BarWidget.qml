import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Pastille de barre : état agrégé des services de l'hôte actif + compteur dans le tooltip.
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property bool reachable: main ? main.reachable : false
    readonly property int down: main ? main.barDown : 0
    readonly property int unhealthy: main ? main.barUnhealthy : 0
    readonly property int total: main ? main.barTotal : 0
    readonly property int behind: main ? main.barBehind : 0

    implicitWidth: pill.width
    implicitHeight: pill.height

    function stateIcon() {
        if (!reachable) return "server-off"
        if (down > 0 || unhealthy > 0) return "alert-triangle"
        return "server"
    }

    function tip() {
        if (!reachable) return "Home Server — injoignable"
        var ok = total - down
        var t = "Home Server — " + ok + "/" + total + " actifs"
        if (unhealthy > 0) t += "  ·  " + unhealthy + " unhealthy"
        if (behind > 0) t += "  ·  " + behind + " commit(s) en retard"
        return t
    }

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true
        icon: root.stateIcon()
        tooltipText: root.tip()
        onClicked: if (root.pluginApi) root.pluginApi.togglePanel(root.screen, pill)
        onRightClicked: PanelService.showContextMenu(contextMenu, root, root.screen)
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": root.pluginApi ? root.pluginApi.tr("context.refresh") : "Refresh", "action": "refresh", "icon": "refresh" },
            { "label": root.pluginApi ? root.pluginApi.tr("context.settings") : "Settings", "action": "settings", "icon": "settings" }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)
            if (!root.pluginApi) return
            if (action === "settings")
                BarService.openPluginSettings(root.screen, root.pluginApi.manifest)
            else if (action === "refresh" && root.main)
                root.main.pollStatus(true)
        }
    }
}
