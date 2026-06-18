import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Pastille de barre : ouvre/ferme le terminal flottant (panel natif, attaché à la barre).
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property bool depAvailable: main ? main.depAvailable : true

    implicitWidth: pill.width
    implicitHeight: pill.height

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true
        icon: "terminal"
        tooltipText: root.depAvailable ? (pluginApi ? pluginApi.tr("bar.toggle") : "Terminal")
                                       : (pluginApi ? pluginApi.tr("error.missingDep") : "qmltermwidget manquant")
        // En mode « centré », on n'attache pas au bouton (sinon SmartPanel ignore le centrage).
        onClicked: if (root.pluginApi) root.pluginApi.togglePanel(root.screen, (root.main && root.main.cfgPosition === "centered") ? null : pill)
        onRightClicked: PanelService.showContextMenu(contextMenu, root, root.screen)
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": pluginApi ? pluginApi.tr("context.newSession") : "New session", "action": "newSession", "icon": "refresh" },
            { "label": pluginApi ? pluginApi.tr("context.settings") : "Settings", "action": "settings", "icon": "settings" }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)
            if (!root.pluginApi) return
            if (action === "settings")
                BarService.openPluginSettings(root.screen, root.pluginApi.manifest)
            else if (action === "newSession" && root.main)
                root.main.newSession()
        }
    }
}
