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
    readonly property var tabsModel: [
        { "id": "shell",   "icon": "terminal", "shellProgram": root.cfgShell, "shellArgs": [],                                       "autoRelaunch": false },
        { "id": "procmon", "icon": "activity", "shellProgram": root._shell,   "shellArgs": ["-c", "exec " + root.cfgProcMonCommand], "autoRelaunch": true  }
    ]

    // ── Les tuiles persistantes ──────────────────────────────────────────────
    property var tiles: []
    property int currentTab: 0
    property bool depAvailable: true
    property var _tileComp: null   // composant TerminalTile chargé (réutilisé pour « Nouvelle session »)

    // Taille STABILISÉE de la zone terminal. Panel.reportContentSize() la met à jour via un debounce :
    // pendant l'animation d'ouverture du panel (termClip 0→plein), la valeur reste FIGÉE → les tuiles,
    // dimensionnées dessus, NE SE REDIMENSIONNENT PAS (termClip les clippe pendant la révélation). Donc
    // aucun reflow du terminal à la ré-ouverture → le prompt reste en bas (scroll uniquement vers le haut).
    property real deckContentW: root.cfgWidth * Style.uiScaleRatio
    property real deckContentH: root.cfgHeight * Style.uiScaleRatio
    property real _pendingCW: 0
    property real _pendingCH: 0
    function reportContentSize(w, h) {
        if (w > 0) root._pendingCW = w
        if (h > 0) root._pendingCH = h
        sizeSettle.restart()
    }
    Timer {
        id: sizeSettle
        interval: 120   // > durée d'animation d'ouverture du panel : ne fige la taille qu'une fois stable
        onTriggered: {
            if (root._pendingCW > 0) root.deckContentW = root._pendingCW
            if (root._pendingCH > 0) root.deckContentH = root._pendingCH
        }
    }

    // Conteneur « au repos » des tuiles : invisible mais DIMENSIONNÉ (jamais 0×0), calé sur la taille du
    // panel. Indispensable aussi pour les TUIs (btop) : re-parenter vers un parent 0×0 pousserait un
    // winsize 0 au PTY → btop planterait (« Failed to get size of terminal! »). Le Panel re-parente les
    // tuiles dans sa zone visible à l'ouverture et les rend ici à la fermeture.
    Item {
        id: tileHolder
        visible: false
        width: root.deckContentW > 0 ? root.deckContentW : root.cfgWidth * Style.uiScaleRatio
        height: root.deckContentH > 0 ? root.deckContentH : root.cfgHeight * Style.uiScaleRatio
    }

    function reclaimTiles() { for (var i = 0; i < root.tiles.length; i++) root.tiles[i].parent = tileHolder }

    // Crée (SANS démarrer) une tuile depuis une entrée de tabsModel, parentée au holder. Le démarrage
    // se fait au 1er attachement au panel (Panel._attachTiles) → directement à la taille du panel, sans
    // resize depuis le holder (pas d'artefact de scroll).
    function _makeTile(spec) {
        if (!root._tileComp || root._tileComp.status !== Component.Ready)
            return null
        var t = root._tileComp.createObject(tileHolder, {
            "shellProgram": spec.shellProgram,
            "shellArgs": spec.shellArgs,
            "autoRelaunch": spec.autoRelaunch
        })
        if (!t)
            return null
        t.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
        t.fontSize = Qt.binding(function () { return root.cfgFontSize })
        t.colorScheme = Qt.binding(function () { return root.effectiveScheme })
        // Taille explicite et STABLE (cf. deckContentW/H) → la tuile ne suit PAS l'animation du panel,
        // donc le terminal ne se redimensionne pas (pas de reflow / prompt qui remonte à la ré-ouverture).
        t.width = Qt.binding(function () { return root.deckContentW })
        t.height = Qt.binding(function () { return root.deckContentH })
        // Onglet service (autoRelaunch) terminé après avoir vécu assez longtemps (garde anti-spin) →
        // RECRÉE cette tuile (session fraîche). On se branche sur `finished` (signal stable) plutôt que
        // sur un signal dédié, pour rester robuste à un rechargement QML partiel (cf. cache plugin).
        t.finished.connect(function () {
            if (t.autoRelaunch && (Date.now() - t._startedAt) > t._minLifeMs)
                root._recreateTileAt(root.tiles.indexOf(t))
        })
        return t
    }

    // Recrée la tuile à l'index donné = VRAIE session fraîche (nouveau shell, dossier par défaut,
    // scrollback vide) ; l'ancienne est détruite (son process est tué). Bien plus fiable qu'un
    // startShellProgram() en place : il ne relance ni un shell vivant, ni une session déjà terminée.
    function _recreateTileAt(idx) {
        if (idx < 0 || idx >= root.tiles.length)
            return
        var old = root.tiles[idx]
        var t = root._makeTile(root.tabsModel[idx])
        if (!t)
            return
        var arr = root.tiles.slice()
        arr[idx] = t
        root.tiles = arr        // → Panel ré-attache et démarre la nouvelle tuile (à la taille du panel)
        if (old) { old.visible = false; Qt.callLater(function () { old.destroy() }) }
        root._writeLive()       // theming live de la nouvelle tuile
    }

    // « Nouvelle session » (widget/IPC) : recrée la tuile de l'onglet courant.
    function newSession() { root._recreateTileAt(root.currentTab) }

    function _createTiles() {
        root._tileComp = Qt.createComponent("TerminalTile.qml")
        function finish() {
            if (root._tileComp.status === Component.Error) {
                root.depAvailable = false
                ToastService.showError(root.pluginApi ? root.pluginApi.tr("error.missingDep")
                                                      : "Noctalia Deck : qmltermwidget manquant (pacman -S qmltermwidget)")
                Logger.e("NoctaliaDeck", "TerminalTile load error: " + root._tileComp.errorString())
                return
            }
            if (root._tileComp.status !== Component.Ready)
                return
            var created = []
            for (var i = 0; i < root.tabsModel.length; i++) {
                var t = root._makeTile(root.tabsModel[i])
                if (!t) {
                    root.depAvailable = false
                    return
                }
                created.push(t)
            }
            root.tiles = created   // assignation (pas push) → notifie le Panel
            // Si le fork est présent → applique tout de suite les couleurs live du wallpaper.
            root._writeLive()
        }
        if (root._tileComp.status === Component.Ready)
            finish()
        else
            root._tileComp.statusChanged.connect(finish)
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
