import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Couche logique + PROPRIÉTAIRE PERSISTANT de la tuile terminal.
//
// La tuile (QMLTermWidget) est créée ici avec Main comme parent QObject → elle vit aussi longtemps
// que le plugin. Le Panel natif Noctalia ne fait que la re-parenter visuellement (voir Panel.qml).
//
// Thème "noctalia" :
//   • Avec le fork qmltermwidget-noctalia (slot applyColorSchemeFile) → theming LIVE : on génère un
//     .colorscheme dans ~/.cache depuis les tokens Color.* et on l'applique à chaque changement de
//     palette (wallpaper). Aucun cache, aucun COLORSCHEMES_DIR, aucun sudo.
//   • Sans le fork (qmltermwidget stock) → repli sur un schéma built-in clair/sombre (pas de live ;
//     installer le fork pour le live, cf. README + dossier qmltermwidget-noctalia/).
Item {
    id: root
    property var pluginApi: null

    readonly property string schemesDir: (Quickshell.env("HOME") || "/tmp") + "/.cache/noctalia-deck"
    readonly property string livePath: root.schemesDir + "/live.colorscheme"

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

    // ── Schéma de base (propriété colorScheme du widget) ─────────────────────
    // En mode live, ce built-in n'est qu'une base aussitôt surchargée par applyColorSchemeFile.
    // En repli (stock), c'est le schéma réellement affiché.
    function _isDarkTheme() {
        var c = Color.mSurface
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }
    readonly property string effectiveScheme: {
        if (root.cfgThemeMode === "scheme")
            return root.cfgScheme
        return root._isDarkTheme() ? "Falcon" : "SolarizedLight"
    }

    // ── Génération du .colorscheme depuis la palette Noctalia ────────────────
    function _rgb(c) { return Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) }
    function _blk(section, c) { return "[" + section + "]\nColor=" + root._rgb(c) + "\n\n" }
    function _schemeContent() {
        var s = ""
        s += root._blk("Background", Color.mSurface)
        s += root._blk("BackgroundIntense", Color.mSurfaceVariant)
        s += root._blk("Foreground", Color.mOnSurface)
        s += root._blk("ForegroundIntense", Color.mOnSurface)
        s += root._blk("Color0", Color.mSurfaceVariant)
        s += root._blk("Color1", Color.mError)
        s += root._blk("Color2", Color.mTertiary)
        s += root._blk("Color3", Color.mSecondary)
        s += root._blk("Color4", Color.mPrimary)
        s += root._blk("Color5", Color.mSecondary)
        s += root._blk("Color6", Color.mTertiary)
        s += root._blk("Color7", Color.mOnSurface)
        s += root._blk("Color0Intense", Color.mOnSurfaceVariant)
        s += root._blk("Color1Intense", Color.mError)
        s += root._blk("Color2Intense", Color.mTertiary)
        s += root._blk("Color3Intense", Color.mSecondary)
        s += root._blk("Color4Intense", Color.mPrimary)
        s += root._blk("Color5Intense", Color.mSecondary)
        s += root._blk("Color6Intense", Color.mTertiary)
        s += root._blk("Color7Intense", Color.mOnSurface)
        s += "[General]\nDescription=NoctaliaDeck\nOpacity=1\n"
        return s
    }

    // ── Theming live (fork uniquement) ───────────────────────────────────────
    readonly property bool liveCapable: root.tileItem ? root.tileItem.liveCapable : false

    Process {
        id: liveWriter
        onExited: code => { if (code === 0 && root.tileItem) root.tileItem.applySchemeFile(root.livePath) }
    }
    function _writeLive() {
        if (root.cfgThemeMode !== "noctalia" || !root.liveCapable)
            return
        liveWriter.command = ["sh", "-c",
            'd="$(dirname "$1")"; mkdir -p "$d"; printf "%s" "$2" > "$1"',
            "sh", root.livePath, root._schemeContent()]
        liveWriter.running = true
    }

    // Régénère + applique (debounced) au changement de palette (wallpaper) ou de mode.
    property color paletteKey: Color.mPrimary
    onPaletteKeyChanged: if (root.liveCapable && root.cfgThemeMode === "noctalia") regenDebounce.restart()
    onCfgThemeModeChanged: if (root.liveCapable && cfgThemeMode === "noctalia") regenDebounce.restart()
    Timer { id: regenDebounce; interval: 150; onTriggered: root._writeLive() }

    // ── La tuile persistante ─────────────────────────────────────────────────
    property var tileItem: null
    property bool depAvailable: true

    function reclaimTile() { if (root.tileItem) root.tileItem.parent = root }
    function newSession() { if (root.tileItem) root.tileItem.restart() }

    function _createTile() {
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
            // Si le fork est présent → applique tout de suite les couleurs live du wallpaper.
            root._writeLive()
        }
        if (comp.status === Component.Ready)
            finish()
        else
            comp.statusChanged.connect(finish)
    }

    Component.onCompleted: root._createTile()

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
