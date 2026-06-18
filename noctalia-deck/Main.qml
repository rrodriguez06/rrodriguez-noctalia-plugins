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
// Thème "noctalia" : on GÉNÈRE un .colorscheme depuis les tokens Color.* (bg/fg/accents du wallpaper)
// et on l'écrit dans le dossier système de qmltermwidget (rendu inscriptible une fois :
//   sudo chown "$USER" /usr/lib/qt6/qml/QMLTermWidget/color-schemes  ).
//
// ⚠️ LIMITE qmltermwidget : TerminalDisplay::setColorScheme n'accepte qu'un schéma présent dans
// availableColorSchemes(), lui-même rempli par loadAllColorSchemes() UNE SEULE FOIS (flag
// _haveLoadedAll) au premier setColorScheme. Donc :
//   • le schéma doit exister AVANT la création de la tuile (sinon fond blanc par défaut) ;
//   • le thème ne peut PAS suivre le wallpaper en live (liste figée) → il reflète la palette au
//     démarrage du shell ; un relog le réactualise.
Item {
    id: root
    property var pluginApi: null

    readonly property string schemesDir: "/usr/lib/qt6/qml/QMLTermWidget/color-schemes"
    readonly property string genName: "NoctaliaDeck"   // nom fixe (présent au scan initial)

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
    property bool genReady: false   // passe à true quand le .colorscheme généré est écrit
    function _isDarkTheme() {
        var c = Color.mSurface
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5
    }
    readonly property string effectiveScheme: {
        if (root.cfgThemeMode === "scheme")
            return root.cfgScheme
        if (root.genReady)
            return root.genName
        return root._isDarkTheme() ? "Falcon" : "SolarizedLight"   // repli si génération impossible
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

    // Écrit le schéma PUIS crée la tuile (l'ordre est critique : le schéma doit exister avant le
    // premier setColorScheme, sinon qmltermwidget fige une liste qui ne le contient pas → fond blanc).
    Process {
        id: schemeWriter
        onExited: code => {
            if (code === 0) {
                root.genReady = true
            } else if (root.cfgShowToasts) {
                ToastService.showError(root.pluginApi ? root.pluginApi.tr("error.schemeDirRO")
                    : "Noctalia Deck : dossier de schémas non inscriptible — sudo chown \"$USER\" /usr/lib/qt6/qml/QMLTermWidget/color-schemes")
            }
            root._createTile()
        }
    }

    // ── La tuile persistante ─────────────────────────────────────────────────
    property var tileItem: null
    property bool depAvailable: true

    function reclaimTile() { if (root.tileItem) root.tileItem.parent = root }
    function newSession() { if (root.tileItem) root.tileItem.restart() }

    function _createTile() {
        if (root.tileItem)
            return
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

    Component.onCompleted: {
        // Écrit le schéma généré (palette courante), puis crée la tuile dans onExited.
        schemeWriter.command = ["sh", "-c",
            'printf "%s" "$2" > "$1/NoctaliaDeck.colorscheme"',
            "sh", root.schemesDir, root._schemeContent()]
        schemeWriter.running = true
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
