import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Couche logique + PROPRIÉTAIRE PERSISTANT de la tuile terminal.
//
// La tuile (QMLTermWidget) est créée ici avec Main comme parent QObject → elle vit aussi longtemps
// que le plugin. Le Panel natif Noctalia (Panel.qml) ne fait que la re-parenter visuellement le temps
// de l'affichage, puis la rend à Main à la fermeture (reclaimTile). Résultat : la session shell +
// le scrollback survivent aux ouvertures/fermetures, tout en profitant du panel natif (attache-barre,
// coins intelligents, focus clavier, fermeture au clic-dehors, animations).
Item {
    id: root
    property var pluginApi: null

    // ── Réglages (repli sur les défauts du manifeste) ────────────────────────
    readonly property var s: pluginApi?.pluginSettings ?? null
    readonly property int cfgWidth: (s && s.width) ? s.width : 900
    readonly property int cfgHeight: (s && s.height) ? s.height : 480
    readonly property string cfgPosition: (s && s.position) ? s.position : "attached"
    readonly property string cfgThemeMode: (s && s.themeMode) ? s.themeMode : "noctalia"
    readonly property string cfgScheme: (s && s.schemeName) ? s.schemeName : "Solarized"
    readonly property string cfgFontFamily: (s && s.fontFamily && s.fontFamily.length > 0) ? s.fontFamily : "monospace"
    readonly property int cfgFontSize: (s && s.fontSize) ? s.fontSize : 11
    readonly property string cfgShell: (s && s.shellProgram) ? s.shellProgram : ""
    readonly property bool cfgShowToasts: (s && s.showToasts !== undefined) ? s.showToasts : true

    // ── Résolution du thème terminal ─────────────────────────────────────────
    // "scheme" : schéma fixe. "noctalia" : suit le clair/sombre du thème global (luminance mSurface).
    function _isDarkTheme() {
        var c = Color.mSurface
        var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return lum < 0.5
    }
    readonly property string effectiveScheme: {
        if (root.cfgThemeMode === "scheme")
            return root.cfgScheme
        return root._isDarkTheme() ? "Falcon" : "SolarizedLight"
    }

    // ── La tuile persistante ─────────────────────────────────────────────────
    property var tileItem: null
    property bool depAvailable: true

    function reclaimTile() {
        // Rendu à Main (parent persistant) quand le panel se ferme/détruit.
        if (root.tileItem)
            root.tileItem.parent = root
    }
    function newSession() {
        if (root.tileItem)
            root.tileItem.restart()
    }

    // Création différée + isolée (un import QMLTermWidget manquant ne casse pas tout le plugin).
    Component.onCompleted: {
        var comp = Qt.createComponent("TerminalTile.qml")
        function finish() {
            if (comp.status === Component.Error) {
                root.depAvailable = false
                ToastService.showError(root.pluginApi ? root.pluginApi.tr("error.missingDep")
                                                      : "Noctalia Deck : qmltermwidget manquant (pacman -S qmltermwidget)")
                Logger.e("NoctaliaDeck", "TerminalTile load error: " + comp.errorString())
                return
            }
            if (comp.status !== Component.Ready)
                return
            var t = comp.createObject(root, { "shellProgram": root.cfgShell })
            if (!t) {
                root.depAvailable = false
                return
            }
            t.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
            t.fontSize = Qt.binding(function () { return root.cfgFontSize })
            t.colorScheme = Qt.binding(function () { return root.effectiveScheme })
            root.tileItem = t
            t.start()
        }
        if (comp.status === Component.Ready)
            finish()
        else
            comp.statusChanged.connect(finish)
    }

    // ── IPC : qs -c noctalia-shell ipc call plugin:noctalia-deck <fn> ─────────
    IpcHandler {
        target: "plugin:noctalia-deck"
        function toggle() {
            if (root.pluginApi)
                root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
        }
        function show() {
            if (root.pluginApi)
                root.pluginApi.withCurrentScreen(s => root.pluginApi.openPanel(s))
        }
        function hide() {
            if (root.pluginApi)
                root.pluginApi.withCurrentScreen(s => root.pluginApi.closePanel(s))
        }
        function newSession() { root.newSession() }
    }
}
