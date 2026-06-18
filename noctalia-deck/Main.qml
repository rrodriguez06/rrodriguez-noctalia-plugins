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
// Thème : en mode "noctalia", on GÉNÈRE un .colorscheme depuis les tokens Color.* (bg/fg/accents
// extraits du wallpaper) et on le régénère à chaque changement de palette. qmltermwidget ne charge
// les schémas que depuis $COLORSCHEMES_DIR, et son ColorSchemeManager IGNORE définitivement ce
// dossier s'il n'existe pas à l'init → on s'assure qu'il existe + est peuplé AVANT de créer la tuile
// (et idéalement avant qs : voir env-hyprland.d/noctalia-deck.sh).
Item {
    id: root
    property var pluginApi: null

    readonly property string schemesDir: (Quickshell.env("HOME") || "~") + "/.local/share/noctalia-deck/colorschemes"
    readonly property string builtinSchemesDir: "/usr/lib/qt6/qml/QMLTermWidget/color-schemes"

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

    // ── Schéma effectif ──────────────────────────────────────────────────────
    property string genName: ""
    property int genCounter: 0
    function _isDarkTheme() {
        var c = Color.mSurface
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }
    readonly property string effectiveScheme: {
        if (root.cfgThemeMode === "scheme")
            return root.cfgScheme
        if (root.genName !== "")
            return root.genName
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
        s += "[General]\nDescription=Noctalia Deck\nOpacity=1\n"
        return s
    }

    // Écrit le schéma généré sous un nom incrémenté (contourne le cache de qmltermwidget), puis
    // bascule dessus une fois le fichier écrit.
    Process {
        id: schemeWriter
        property string pendingName: ""
        onExited: code => { if (code === 0) root.genName = schemeWriter.pendingName }
    }
    function regenerateScheme() {
        if (root.cfgThemeMode !== "noctalia" || !root.schemesDir)
            return
        root.genCounter += 1
        var name = "NoctaliaDeck" + root.genCounter
        schemeWriter.pendingName = name
        schemeWriter.command = ["sh", "-c",
            'd="$1"; mkdir -p "$d"; rm -f "$d"/NoctaliaDeck*.colorscheme; printf "%s" "$3" > "$d/$2.colorscheme"',
            "sh", root.schemesDir, name, root._schemeContent()]
        schemeWriter.running = true
    }

    // Régénère (debounced) au changement de palette (wallpaper) ou en repassant en mode noctalia.
    property color paletteKey: Color.mPrimary
    onPaletteKeyChanged: regenDebounce.restart()
    onCfgThemeModeChanged: if (cfgThemeMode === "noctalia") regenDebounce.restart()
    Timer { id: regenDebounce; interval: 150; onTriggered: root.regenerateScheme() }

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
        }
        if (comp.status === Component.Ready)
            finish()
        else
            comp.statusChanged.connect(finish)
    }

    // Prépare le dossier (mkdir + copie des built-ins + schéma initial) PUIS crée la tuile.
    // Séquencer garantit que le dossier existe avant l'init du ColorSchemeManager (1ère tuile).
    Process {
        id: prepProcess
        onExited: code => {
            root.genName = "NoctaliaDeck1"
            root._createTile()
        }
    }
    Component.onCompleted: {
        root.genCounter = 1
        prepProcess.command = ["sh", "-c",
            'd="$1"; mkdir -p "$d"; cp -f "$3"/*.colorscheme "$d"/ 2>/dev/null; rm -f "$d"/NoctaliaDeck*.colorscheme; printf "%s" "$2" > "$d/NoctaliaDeck1.colorscheme"',
            "sh", root.schemesDir, root._schemeContent(), root.builtinSchemesDir]
        prepProcess.running = true
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
