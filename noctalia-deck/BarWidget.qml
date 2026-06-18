import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Pastille de barre : bascule le terminal flottant. L'icône reflète l'état (ouvert / process actif).
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property bool deckVisible: main ? main.deckVisible : false
    readonly property bool depAvailable: main ? main.depAvailable : true

    implicitWidth: pill.width
    implicitHeight: pill.height

    function tip() {
        if (!depAvailable)
            return pluginApi ? pluginApi.tr("error.missingDep") : "qmltermwidget manquant"
        return deckVisible ? (pluginApi ? pluginApi.tr("bar.hide") : "Masquer le terminal")
                           : (pluginApi ? pluginApi.tr("bar.show") : "Afficher le terminal")
    }

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true
        icon: root.deckVisible ? "terminal-2" : "terminal"
        tooltipText: root.tip()
        onClicked: if (root.main) root.main.toggle()
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
