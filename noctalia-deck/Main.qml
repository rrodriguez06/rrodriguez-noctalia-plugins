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
    readonly property string cfgProcMonCommand: (s && s.procMonCommand && s.procMonCommand.length > 0) ? s.procMonCommand : "btop"
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
    readonly property bool liveCapable: (root.tiles.length > 0) ? root.tiles[0].liveCapable : false

    Process {
        id: liveWriter
        // Applique le .colorscheme fraîchement écrit à TOUTES les tuiles (shell, procmon, …).
        onExited: code => {
            if (code !== 0)
                return
            for (var i = 0; i < root.tiles.length; i++)
                root.tiles[i].applySchemeFile(root.livePath)
        }
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

    // ── Onglets du deck ──────────────────────────────────────────────────────
    // Modèle déclaratif : chaque entrée = une tuile persistante. Socle pour de futurs services.
    //   • shell   : $SHELL (vide ⇒ défaut QMLTermSession), pas d'auto-relance.
    //   • procmon : moniteur de processus (btop par défaut, configurable). Lancé via le shell pour
    //               résoudre le PATH et permettre une ligne de commande arbitraire ; auto-relance si
    //               on le quitte (ex. « q » dans btop). Couleurs gérées par Noctalia (template btop).
    readonly property string _shell: (Quickshell.env("SHELL") && Quickshell.env("SHELL").length > 0) ? Quickshell.env("SHELL") : "/bin/sh"
    // Shell du deck lancé via `env NOCTALIA_DECK=1 <shell>` : ajoute un marqueur (sans toucher au reste
    // de l'environnement) que le .zshrc lit pour aligner le bandeau/prompt en bas (cf. README).
    readonly property string _shellProg: (root.cfgShell && root.cfgShell.length > 0) ? root.cfgShell : root._shell
    readonly property var tabsModel: [
        { "id": "shell",   "icon": "terminal", "shellProgram": "/usr/bin/env", "shellArgs": ["NOCTALIA_DECK=1", root._shellProg], "autoRelaunch": false },
        { "id": "procmon", "icon": "activity", "shellProgram": root._shell,    "shellArgs": ["-c", "exec " + root.cfgProcMonCommand], "autoRelaunch": true  }
    ]

    // ── Les tuiles persistantes ──────────────────────────────────────────────
    property var tiles: []
    property int currentTab: 0
    property bool depAvailable: true

    // Conteneur « au repos » des tuiles : invisible mais DIMENSIONNÉ (≈ taille du panel), jamais 0×0.
    // Indispensable pour les TUIs (btop) : re-parenter vers un parent 0×0 pousserait un winsize 0 au PTY
    // → btop planterait (« Failed to get size of terminal! »). Le Panel re-parente les tuiles dans sa
    // zone visible à l'ouverture et les rend ici à la fermeture.
    Item {
        id: tileHolder
        visible: false
        width: root.cfgWidth * Style.uiScaleRatio
        height: root.cfgHeight * Style.uiScaleRatio
    }

    function reclaimTiles() { for (var i = 0; i < root.tiles.length; i++) root.tiles[i].parent = tileHolder }
    function newSession() {
        var t = (root.currentTab >= 0 && root.currentTab < root.tiles.length) ? root.tiles[root.currentTab] : null
        if (t) t.restart()
    }

    function _createTiles() {
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
            var created = []
            for (var i = 0; i < root.tabsModel.length; i++) {
                var spec = root.tabsModel[i]
                var t = comp.createObject(tileHolder, {
                    "shellProgram": spec.shellProgram,
                    "shellArgs": spec.shellArgs,
                    "autoRelaunch": spec.autoRelaunch
                })
                if (!t) {
                    root.depAvailable = false
                    return
                }
                t.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
                t.fontSize = Qt.binding(function () { return root.cfgFontSize })
                t.colorScheme = Qt.binding(function () { return root.effectiveScheme })
                t.start()
                created.push(t)
            }
            root.tiles = created   // assignation (pas push) → notifie le Panel
            // Si le fork est présent → applique tout de suite les couleurs live du wallpaper.
            root._writeLive()
        }
        if (comp.status === Component.Ready)
            finish()
        else
            comp.statusChanged.connect(finish)
    }

    Component.onCompleted: root._createTiles()

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
