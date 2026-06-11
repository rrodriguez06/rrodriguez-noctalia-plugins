import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    implicitWidth: pill.width
    implicitHeight: pill.height

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true
        icon: "layout-dashboard"
        tooltipText: "Hypr Layout"
        onClicked: if (root.pluginApi) root.pluginApi.togglePanel(root.screen, pill)
        onRightClicked: PanelService.showContextMenu(contextMenu, root, root.screen)
    }

    // Menu clic-droit : Paramètres + Fermer toutes les fenêtres.
    NPopupContextMenu {
        id: contextMenu
        model: [
            {
                "label": root.pluginApi ? root.pluginApi.tr("context.settings") : "Settings",
                "action": "settings",
                "icon": "settings"
            },
            {
                "label": root.pluginApi ? root.pluginApi.tr("context.clean") : "Close all windows",
                "action": "clean",
                "icon": "trash"
            }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)
            if (!root.pluginApi)
                return
            if (action === "settings")
                BarService.openPluginSettings(root.screen, root.pluginApi.manifest)
            else if (action === "clean" && root.pluginApi.mainInstance)
                root.pluginApi.mainInstance.cleanAll()
        }
    }
}
