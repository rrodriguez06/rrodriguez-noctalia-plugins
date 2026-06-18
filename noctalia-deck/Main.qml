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
// extraits du wallpaper par Noctalia) et on le régénère à chaque changement de palette. qmltermwidget
// ne sait charger un schéma que depuis $COLORSCHEMES_DIR → voir env-hyprland.d/noctalia-deck.sh.
Item {
    id: root
    property var pluginApi: null

    // Dossier des schémas (DOIT correspondre à COLORSCHEMES_DIR dans l'env uwsm).
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
    // "scheme" : built-in choisi. "noctalia" : schéma généré (nom incrémenté), repli clair/sombre.
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
        // ANSI : on mappe les accents Noctalia (extraits du wallpaper) sur les couleurs visibles.
        s += root._blk("Color0", Color.mSurfaceVariant)   // black
        s += root._blk("Color1", Color.mError)            // red
        s += root._blk("Color2", Color.mTertiary)         // green
        s += root._blk("Color3", Color.mSecondary)        // yellow
        s += root._blk("Color4", Color.mPrimary)          // blue
        s += root._blk("Color5", Color.mSecondary)        // magenta
        s += root._blk("Color6", Color.mTertiary)         // cyan
        s += root._blk("Color7", Color.mOnSurface)        // white
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
        var path = root.schemesDir + "/" + name + ".colorscheme"
        schemeWriter.pendingName = name
        // Nettoie les anciens schémas générés puis écrit le nouveau (contenu passé en argument
        // positionnel $2 → pas d'interprétation shell).
        schemeWriter.command = ["sh", "-c",
            'd="$(dirname "$1")"; mkdir -p "$d"; rm -f "$d"/NoctaliaDeck*.colorscheme; printf "%s" "$2" > "$1"',
            "sh", path, root._schemeContent()]
        schemeWriter.running = true
    }

    // Régénère (debounced) quand la palette change (changement de wallpaper) ou quand on passe en mode noctalia.
    property color paletteKey: Color.mPrimary
    onPaletteKeyChanged: regenDebounce.restart()
    onCfgThemeModeChanged: if (cfgThemeMode === "noctalia") regenDebounce.restart()
    Timer { id: regenDebounce; interval: 150; onTriggered: root.regenerateScheme() }

    // ── La tuile persistante ─────────────────────────────────────────────────
    property var tileItem: null
    property bool depAvailable: true

    function reclaimTile() { if (root.tileItem) root.tileItem.parent = root }
    function newSession() { if (root.tileItem) root.tileItem.restart() }

    Component.onCompleted: {
        // Prépare le dossier des schémas : crée + recopie les built-ins (pour garder le mode "scheme"
        // si COLORSCHEMES_DIR remplace le dossier système).
        Quickshell.execDetached(["sh", "-c",
            'mkdir -p "$1"; cp -f "$2"/*.colorscheme "$1"/ 2>/dev/null || true',
            "sh", root.schemesDir, root.builtinSchemesDir])

        // Tuile (création différée + isolée : import QMLTermWidget manquant ne casse pas tout).
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

        // Génère le schéma initial calé sur la palette courante.
        regenDebounce.restart()
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
