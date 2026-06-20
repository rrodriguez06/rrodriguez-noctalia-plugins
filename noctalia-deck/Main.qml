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
    readonly property int cfgScratchpadFontSize: (s && s.scratchpadFontSize) ? s.scratchpadFontSize : 13
    readonly property string cfgShell: (s && s.shellProgram) ? s.shellProgram : ""
    readonly property string cfgProcMonCommand: (s && s.procMonCommand && s.procMonCommand.length > 0) ? s.procMonCommand : "btop"
    readonly property bool cfgShowToasts: (s && s.showToasts !== undefined) ? s.showToasts : true
    readonly property bool cfgLogsAutoClose: (s && s.logsAutoClose !== undefined) ? s.logsAutoClose : true

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
    readonly property var _baseTabs: [
        { "id": "shell",      "type": "terminal",   "icon": "terminal",   "shellProgram": root.cfgShell, "shellArgs": [],                                       "autoRelaunch": false },
        { "id": "procmon",    "type": "terminal",   "icon": "activity",   "shellProgram": root._shell,   "shellArgs": ["-c", "exec " + root.cfgProcMonCommand], "autoRelaunch": true  },
        { "id": "scratchpad", "type": "scratchpad", "icon": "calculator", "shellProgram": "",            "shellArgs": [],                                       "autoRelaunch": false }
    ]
    // Modèle d'onglets EFFECTIF (mutable) : les onglets de base + un éventuel onglet « logs » dynamique
    // (cf. openLogs, appelé par d'autres plugins). Initialisé depuis _baseTabs dans Component.onCompleted,
    // AVANT _createTiles (qui l'itère). Reste index-aligné avec `tiles`.
    property var tabsModel: []
    property int _logsTabIndex: -1   // index de l'onglet logs courant ; -1 si aucun

    // ── Les tuiles persistantes ──────────────────────────────────────────────
    property var tiles: []
    property int currentTab: 0
    property bool depAvailable: true
    // Registre de composants de tuile par type ("terminal" → TerminalTile, "scratchpad" → ScratchpadTile),
    // mémoïsé. Remplace l'ancien _tileComp unique (qui hardcodait TerminalTile pour TOUS les onglets).
    property var _comps: ({})
    property var _placeholderComp: null   // composant de repli (module de tuile absent)

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

    function reclaimTiles() {
        for (var i = 0; i < root.tiles.length; i++)
            root.tiles[i].parent = tileHolder
    }

    // Crée (SANS démarrer) une tuile depuis une entrée de tabsModel, parentée au holder. Le démarrage
    // se fait au 1er attachement au panel (Panel._attachTiles) → directement à la taille du panel, sans
    // resize depuis le holder (pas d'artefact de scroll).
    // Charge (et mémoïse) le composant de tuile pour un type donné.
    function _ensureComp(type) {
        if (root._comps[type] !== undefined)
            return root._comps[type]
        var file = (type === "scratchpad") ? "ScratchpadTile.qml" : "TerminalTile.qml"
        var c = Qt.createComponent(file)
        var m = root._comps
        m[type] = c
        root._comps = m
        return c
    }

    // Dispatcher : choisit le composant selon spec.type et délègue à la fabrique adéquate.
    function _makeTile(spec) {
        var comp = root._ensureComp(spec.type)
        if (!comp || comp.status !== Component.Ready)
            return null
        if (spec.type === "scratchpad")
            return root._makeScratchTile(comp, spec)
        return root._makeTerminalTile(comp, spec)
    }

    function _makeTerminalTile(comp, spec) {
        var isLogs = (spec.id === "logs")
        var t = comp.createObject(tileHolder, {
            "shellProgram": spec.shellProgram,
            "shellArgs": spec.shellArgs,
            "autoRelaunch": spec.autoRelaunch
        })
        if (!t)
            return null
        t.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
        t.fontSize = Qt.binding(function () { return root.cfgFontSize })
        t.colorScheme = Qt.binding(function () { return root.effectiveScheme })
        t.scrollBottomTooltip = Qt.binding(function () { return root.pluginApi ? root.pluginApi.tr("term.scrollBottom") : "" })
        // Taille explicite et STABLE (cf. deckContentW/H) → la tuile ne suit PAS l'animation du panel,
        // donc le terminal ne se redimensionne pas (pas de reflow / prompt qui remonte à la ré-ouverture).
        t.width = Qt.binding(function () { return root.deckContentW })
        t.height = Qt.binding(function () { return root.deckContentH })
        // Onglet service (autoRelaunch) terminé après avoir vécu assez longtemps (garde anti-spin) →
        // RECRÉE cette tuile (session fraîche). On se branche sur `finished` (signal stable) plutôt que
        // sur un signal dédié, pour rester robuste à un rechargement QML partiel (cf. cache plugin).
        // Onglet logs : si cfgLogsAutoClose, on FERME l'onglet quand le flux se termine — mais seulement
        // s'il a vécu > _minLifeMs (un échec immédiat, ex. ssh KO, reste affiché pour lire l'erreur) ET
        // si c'est toujours la tuile logs courante (une tuile remplacée/détruite a indexOf = -1 → ignorée).
        t.finished.connect(function () {
            var i = root.tiles.indexOf(t)
            var livedEnough = (Date.now() - t._startedAt) > t._minLifeMs
            if (t.autoRelaunch && livedEnough)
                root._recreateTileAt(i)
            else if (isLogs && root.cfgLogsAutoClose && livedEnough && i >= 0 && i === root._logsTabIndex)
                root.closeLogs()
        })
        return t
    }

    function _makeScratchTile(comp, spec) {
        var t = comp.createObject(tileHolder, { "pluginApi": root.pluginApi })
        if (!t)
            return null
        t.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
        t.fontSize = Qt.binding(function () { return root.cfgScratchpadFontSize })
        t.width = Qt.binding(function () { return root.deckContentW })
        t.height = Qt.binding(function () { return root.deckContentH })
        // Theming via les tokens Color.* (à l'intérieur de la tuile) ; pas de colorScheme / finished / autoRelaunch.
        return t
    }

    // Tuile de repli si le composant d'un type non-terminal n'a pas pu se charger (module C++ absent).
    function _makePlaceholderTile(spec) {
        if (!root._placeholderComp)
            root._placeholderComp = Qt.createComponent("PlaceholderTile.qml")
        if (!root._placeholderComp || root._placeholderComp.status !== Component.Ready)
            return null
        var t = root._placeholderComp.createObject(tileHolder, { "pluginApi": root.pluginApi })
        if (!t)
            return null
        t.width = Qt.binding(function () { return root.deckContentW })
        t.height = Qt.binding(function () { return root.deckContentH })
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

    // ── Onglet « logs » dynamique ─────────────────────────────────────────────
    // Ouvre (ou réutilise) un onglet terminal éphémère exécutant `argv` (programme + args, déjà prêts
    // à exec → AUCUNE re-quote). Pensé pour d'autres plugins (ex. home-server-control) : les logs
    // suivent en direct, isolés du shell de l'utilisateur, accessibles partout sans occuper de
    // workspace. Fermable via la croix de l'onglet (closeLogs). `title` = libellé de l'onglet.
    function openLogs(title, argv) {
        if (!root.depAvailable || !argv || argv.length === 0)
            return
        var spec = {
            "id": "logs", "type": "terminal", "icon": "file-text",
            "shellProgram": String(argv[0]), "shellArgs": argv.slice(1),
            "autoRelaunch": false, "closable": true,
            "title": (title && String(title).length > 0) ? String(title) : "Logs"
        }
        if (root._logsTabIndex >= 0 && root._logsTabIndex < root.tabsModel.length) {
            // Onglet logs déjà ouvert → nouvelle commande = session fraîche (recrée la tuile en place).
            var tm = root.tabsModel.slice(); tm[root._logsTabIndex] = spec; root.tabsModel = tm
            root._recreateTileAt(root._logsTabIndex)
        } else {
            // Crée la tuile (parentée au holder, démarrage différé à l'attache au panel), puis l'ajoute
            // à la fin de tabsModel ET tiles (l'assignation de tiles notifie le Panel → attache + start).
            var t = root._makeTile(spec)
            if (!t)
                return
            var tm2 = root.tabsModel.slice(); tm2.push(spec); root.tabsModel = tm2
            var ta = root.tiles.slice(); ta.push(t); root.tiles = ta
            root._logsTabIndex = root.tabsModel.length - 1
            root._writeLive()       // theming live de la nouvelle tuile (si fork présent)
        }
        root.currentTab = root._logsTabIndex
        if (root.pluginApi)
            root.pluginApi.withCurrentScreen(s => root.pluginApi.openPanel(s))
    }

    // Ferme l'onglet logs : détruit la tuile (tue son process) et retire l'entrée des deux modèles.
    function closeLogs() {
        var idx = root._logsTabIndex
        if (idx < 0 || idx >= root.tiles.length)
            return
        var old = root.tiles[idx]
        var tm = root.tabsModel.slice(); tm.splice(idx, 1)
        var ta = root.tiles.slice(); ta.splice(idx, 1)
        root.tabsModel = tm
        root.tiles = ta            // notifie le Panel (ré-attache la liste réduite)
        root._logsTabIndex = -1
        if (old) { old.visible = false; Qt.callLater(function () { old.destroy() }) }
        if (root.currentTab >= root.tiles.length)
            root.currentTab = root.tiles.length - 1
        if (root.currentTab < 0)
            root.currentTab = 0
    }

    function _createTiles() {
        // Composants nécessaires (un par type distinct présent dans tabsModel).
        var termComp = root._ensureComp("terminal")
        var hasScratch = false
        for (var k = 0; k < root.tabsModel.length; k++)
            if (root.tabsModel[k].type === "scratchpad") { hasScratch = true; break }
        var scratchComp = hasScratch ? root._ensureComp("scratchpad") : null

        function settled(c) { return !c || c.status === Component.Ready || c.status === Component.Error }
        function tryBuild() {
            if (settled(termComp) && settled(scratchComp))
                root._buildAllTiles(termComp)
        }
        if (settled(termComp) && settled(scratchComp)) {
            root._buildAllTiles(termComp)
        } else {
            if (!settled(termComp)) termComp.statusChanged.connect(tryBuild)
            if (scratchComp && !settled(scratchComp)) scratchComp.statusChanged.connect(tryBuild)
        }
    }

    function _buildAllTiles(termComp) {
        // La dépendance TERMINAL reste bloquante pour tout le deck (comportement inchangé).
        if (termComp.status === Component.Error) {
            root.depAvailable = false
            ToastService.showError(root.pluginApi ? root.pluginApi.tr("error.missingDep")
                                                  : "Noctalia Deck : qmltermwidget manquant (pacman -S qmltermwidget)")
            Logger.e("NoctaliaDeck", "TerminalTile load error: " + termComp.errorString())
            return
        }
        var created = []
        for (var i = 0; i < root.tabsModel.length; i++) {
            var spec = root.tabsModel[i]
            var t = root._makeTile(spec)
            if (!t) {
                // Seule la dépendance terminal est bloquante. Un module non-terminal manquant → repli par-tuile.
                if (spec.type !== "scratchpad") {
                    root.depAvailable = false
                    return
                }
                t = root._makePlaceholderTile(spec)
                if (!t)
                    continue   // dernier recours (ne devrait pas arriver) : on saute l'onglet
            }
            created.push(t)
        }
        root.tiles = created   // assignation (pas push) → notifie le Panel
        // Si le fork est présent → applique tout de suite les couleurs live du wallpaper.
        root._writeLive()
    }

    Component.onCompleted: {
        root.tabsModel = root._baseTabs.slice()   // doit précéder _createTiles (qui itère tabsModel)
        root._createTiles()
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
        function closeLogs() { root.closeLogs() }
    }
}
