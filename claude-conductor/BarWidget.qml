import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Pastille de barre : état agrégé des sessions Claude Code + badge « attend » + compteurs en tooltip.
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property int running: main ? main.barRunning : 0
    readonly property int waiting: main ? main.barWaiting : 0
    readonly property int idle: main ? main.barIdle : 0
    readonly property int total: main ? main.barTotal : 0

    implicitWidth: pill.width
    implicitHeight: pill.height

    function stateIcon() {
        if (root.waiting > 0) return "alert-circle"     // il t'attend — l'actionnable
        if (root.running > 0) return "loader-2"          // ça travaille
        return "robot"                                   // prêt / aucune
    }

    function tip() {
        if (root.total === 0) return root.pluginApi?.tr("bar.none") ?? "Claude Conductor — aucune session"
        var parts = [root.total + " " + (root.pluginApi?.tr("bar.sessions") ?? "session(s)")]
        if (root.waiting > 0) parts.push(root.waiting + " " + (root.pluginApi?.tr("bar.waiting") ?? "attend"))
        if (root.running > 0) parts.push(root.running + " " + (root.pluginApi?.tr("bar.running") ?? "travaille(nt)"))
        if (root.idle > 0) parts.push(root.idle + " " + (root.pluginApi?.tr("bar.idle") ?? "prête(s)"))
        return "Claude Conductor — " + parts.join("  ·  ")
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

    // Badge « attend » : petit cercle rouge avec le compteur, par-dessus la pastille.
    Rectangle {
        visible: root.waiting > 0
        anchors.right: pill.right
        anchors.top: pill.top
        anchors.rightMargin: -2
        anchors.topMargin: -2
        width: Math.max(14, badge.implicitWidth + 6)
        height: 14
        radius: 7
        color: Color.mError
        z: 2
        NText {
            id: badge
            anchors.centerIn: parent
            text: String(root.waiting)
            pointSize: Style.fontSizeXS
            color: Color.mOnError
        }
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": root.pluginApi ? root.pluginApi.tr("context.focusNext") : "Focus", "action": "focusNext", "icon": "arrow-big-right" },
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
                root.main.refreshNow()
            else if (action === "focusNext" && root.main)
                root.main.focusNext()
        }
    }
}
