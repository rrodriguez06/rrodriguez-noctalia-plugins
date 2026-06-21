import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Bar pill: opens the calendar panel; tooltip shows today's date, event count
// and the next upcoming event.
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null

    implicitWidth: pill.width
    implicitHeight: pill.height

    function tip() {
        var t = Qt.formatDateTime(new Date(), "dddd d MMMM")
        if (!main) return t
        if (main.todayCount > 0) t += "  ·  " + main.todayCount + " évén."
        if (main.nextLabel) t += "\n→ " + main.nextLabel
        return t
    }

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true
        icon: "calendar"
        tooltipText: root.tip()
        onClicked: if (root.pluginApi) root.pluginApi.togglePanel(root.screen, pill)
        onRightClicked: PanelService.showContextMenu(contextMenu, root, root.screen)
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": root.pluginApi ? root.pluginApi.tr("context.today") : "Today", "action": "today", "icon": "calendar" },
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
                root.main.syncNow()
            else if (action === "today" && root.main)
                root.main.goToday()
        }
    }
}
