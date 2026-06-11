import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets
import "Dwindle.js" as Dwindle

// Éditeur visuel de layout : cadres = écrans (à leur position réelle), onglets = workspaces,
// box = fenêtres (déplaçables / redimensionnables au glisser-déposer). Voir Dwindle.js pour le pavage.
Item {
    id: editor

    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance

    property string layoutName: ""
    property var windows: []          // copie de travail (chaque fenêtre a un _id stable)
    property var monitors: []         // géométrie écrans live
    property var workspaceRules: ({}) // bind ws→écran (depuis Main : "<wsId>" -> "<monitor>")
    property var extraWss: ({})       // écran -> ws ajoutés manuellement (vides, état éditeur)
    property var autoWss: ({})        // écran -> ws par défaut auto-injecté (écran live mais vide)

    // --- drawer d'applications (ajout/retrait de fenêtres au layout) ---
    property bool drawerOpen: true
    property string appQuery: ""
    property var allApps: []          // [DesktopEntry] visibles, triées par nom
    property var filteredApps: {
        var q = ("" + appQuery).trim().toLowerCase()
        if (!q) return allApps
        var out = []
        for (var i = 0; i < allApps.length; i++) {
            var a = allApps[i]
            var hay = ((a.name || "") + " " + (a.genericName || "") + " " + (a.comment || "")
                       + " " + ((a.command && a.command[0]) || "")).toLowerCase()
            if (hay.indexOf(q) >= 0) out.push(a)
        }
        return out
    }
    function loadApps() {
        var all = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications)
                  ? (DesktopEntries.applications.values || []) : []
        var list = []
        for (var i = 0; i < all.length; i++) {
            var a = all[i]
            if (!a || a.noDisplay) continue
            list.push(a)
        }
        list.sort(function (x, y) { return ("" + (x.name || "")).localeCompare("" + (y.name || "")) })
        allApps = list
    }
    Component.onCompleted: loadApps()
    Connections {
        target: (typeof DesktopEntries !== "undefined") ? DesktopEntries.applications : null
        function onValuesChanged() { editor.loadApps() }
    }

    signal saved()
    signal cancelled()

    // --- état interne ---
    property var trees: ({})          // clé "<monitor>|<ws>" -> arbre dwindle
    property var selectedWs: ({})     // monitor -> ws affiché
    property var placements: ({})     // _id -> {area,x,y,w,h,floating}
    property var framesModel: []      // cadres rendus (coords root)
    property var dividersList: []     // poignées de split (coords root)
    property var trayList: []         // _id des fenêtres scratchpad
    readonly property real gapReal: 10
    // bascule de ws = carrousel : un ws non sélectionné est décalé de slideFactor×largeur-cadre
    // (le Behavior on x des box produit le glissement, l'opacity masque le débordement hors-cadre).
    readonly property real slideFactor: 0.5

    // transform monde réel (px compositeur) -> coords overlay (= coords root editor)
    property real sc: 1
    property real offX: 0
    property real offY: 0
    property real bx0: 0
    property real by0: 0
    property real caOX: 0   // origine de canvasArea dans le repère de l'éditeur
    property real caOY: 0

    // drag en cours
    property int draggingId: -1
    property real grabDX: 0
    property real grabDY: 0
    property real dragX: 0
    property real dragY: 0
    property real dragW: 0
    property real dragH: 0
    // position courante du pointeur en coords overlay (pour le spring-load des onglets/« + »)
    property real ptrX: -1
    property real ptrY: -1
    // cible spring-load en attente (survol pendant le drag) : { kind: "ws"|"add", monitor, ws }
    property var springPending: null
    property bool draggingNew: false  // le drag en cours crée une fenêtre (issue du drawer)
    property int idSeq: 0             // prochain _id libre pour une fenêtre ajoutée

    // ====================== chargement ======================
    // `monitors` est bindé depuis l'extérieur (géométrie live, peut arriver après) -> on n'y touche pas.
    // treesV2/regionV2 (format v2, feuilles = _lid) : arbre AUTORITAIRE -> on s'en sert tel quel
    // au lieu de ré-inférer via fromCenters. Absents (layout v1) -> inférence comme avant.
    function load(name, wins, treesV2, regionV2) {
        layoutName = name
        extraWss = ({})
        var copy = JSON.parse(JSON.stringify(wins || []))
        var lidToId = {}
        for (var i = 0; i < copy.length; i++) {
            copy[i]._id = i
            if (copy[i]._lid !== undefined) lidToId[copy[i]._lid] = i
        }
        idSeq = copy.length   // _id existants = 0..length-1 -> les suivants sont libres
        selectedWs = ({})
        // Région tuilable par groupe (monitor|ws) = bbox des fenêtres tuilées d'origine.
        // Exclut naturellement la barre/gaps_out -> les ratios et tailles restent fidèles.
        var reg = {}
        for (var r = 0; r < copy.length; r++) {
            var cw = copy[r]
            if (cw.special || cw.floating || !cw.monitor || !cw.at || !cw.size)
                continue
            var k = cw.monitor + "|" + cw.workspace
            var x0 = cw.at[0], y0 = cw.at[1], x1 = x0 + cw.size[0], y1 = y0 + cw.size[1]
            if (!reg[k]) reg[k] = { x0: x0, y0: y0, x1: x1, y1: y1 }
            else {
                reg[k].x0 = Math.min(reg[k].x0, x0); reg[k].y0 = Math.min(reg[k].y0, y0)
                reg[k].x1 = Math.max(reg[k].x1, x1); reg[k].y1 = Math.max(reg[k].y1, y1)
            }
        }
        var rg = {}
        for (var rk in reg)
            rg[rk] = { x: reg[rk].x0, y: reg[rk].y0, w: reg[rk].x1 - reg[rk].x0, h: reg[rk].y1 - reg[rk].y0 }
        // région persistée (v2) prioritaire sur la bbox recalculée
        if (regionV2)
            for (var rk2 in regionV2) rg[rk2] = regionV2[rk2]
        regions = rg
        // arbre v2 autoritaire : conversion feuilles _lid -> _id internes
        var seeded = {}
        if (treesV2)
            for (var key in treesV2) {
                var conv = convertTreeToIds(treesV2[key], lidToId)
                if (conv) seeded[key] = conv
            }
        trees = seeded
        windows = copy
        Qt.callLater(recompute)
    }

    // Arbre v2 (feuilles = _lid string) -> arbre interne (feuilles = _id numérique).
    // Une feuille dont le _lid n'a pas de fenêtre correspondante est élaguée (repli sur le frère).
    function convertTreeToIds(t, lidToId) {
        if (!t) return null
        if (t.leaf !== undefined) {
            var id = lidToId[t.leaf]
            return (id !== undefined) ? { leaf: id } : null
        }
        var a = convertTreeToIds(t.a, lidToId)
        var b = convertTreeToIds(t.b, lidToId)
        if (!a && !b) return null
        if (!a) return b
        if (!b) return a
        return { split: t.split, ratio: t.ratio, a: a, b: b }
    }

    // Arbre interne (feuilles = _id) -> arbre v2 (feuilles = _lid) pour la sauvegarde.
    function convertTreeToLids(t, idToLid) {
        if (!t) return null
        if (t.leaf !== undefined) {
            var lid = idToLid[t.leaf]
            return (lid !== undefined) ? { leaf: lid } : null
        }
        var a = convertTreeToLids(t.a, idToLid)
        var b = convertTreeToLids(t.b, idToLid)
        if (!a && !b) return null
        if (!a) return b
        if (!b) return a
        return { split: t.split, ratio: t.ratio, a: a, b: b }
    }

    // Construit le payload v2 {version, windows, trees, region} envoyé au CLI à la sauvegarde.
    // Réassigne un _lid stable (classe#k par ordre du tableau) à chaque fenêtre tuilée et mappe
    // les feuilles internes (_id) vers ces _lid -> arbre autoritaire rejoué fidèlement par load.
    function buildV2Payload() {
        var counter = {}, idToLid = {}
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (w.special || w.floating || !w.monitor || !w.at || !w.size) {
                delete w._lid
                continue
            }
            var cls = ("" + (w["class"] || "")).toLowerCase()
            var k = counter[cls] || 0
            counter[cls] = k + 1
            w._lid = cls + "#" + k
            idToLid[w._id] = w._lid
        }
        var outTrees = {}, outRegions = {}
        for (var key in trees) {
            var conv = convertTreeToLids(trees[key], idToLid)
            if (conv) {
                outTrees[key] = conv
                if (regions[key]) outRegions[key] = regions[key]
            }
        }
        var outWins = JSON.parse(JSON.stringify(windows))
        for (var j = 0; j < outWins.length; j++) delete outWins[j]._id
        return { version: 2, windows: outWins, trees: outTrees, region: outRegions }
    }

    onMonitorsChanged: Qt.callLater(recompute)

    // Région tuilable d'un groupe (bbox d'origine), repli sur le rect de l'écran.
    property var regions: ({})
    function regionFor(key, fallback) { return regions[key] || fallback }

    // ====================== géométrie écrans ======================
    function monitorRealByName(name) {
        for (var i = 0; i < monitors.length; i++) {
            var m = monitors[i]
            if (m.name === name)
                return { x: m.x, y: m.y, w: m.width, h: m.height, online: true }
        }
        // hors-ligne : bounding-box des fenêtres de cet écran
        var minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9, found = false
        for (var j = 0; j < windows.length; j++) {
            var w = windows[j]
            if (w.monitor !== name || !w.at || !w.size)
                continue
            found = true
            minx = Math.min(minx, w.at[0]); miny = Math.min(miny, w.at[1])
            maxx = Math.max(maxx, w.at[0] + w.size[0]); maxy = Math.max(maxy, w.at[1] + w.size[1])
        }
        if (!found)
            return { x: 0, y: 0, w: 1920, h: 1080, online: false }
        return { x: minx, y: miny, w: maxx - minx, h: maxy - miny, online: false }
    }

    function displayMonitors() {
        var seen = {}, list = []
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (!w.special && w.monitor && !seen[w.monitor]) {
                seen[w.monitor] = true
                list.push({ name: w.monitor, real: monitorRealByName(w.monitor) })
            }
        }
        // + tous les écrans live, même vides (pour pouvoir y déposer des fenêtres)
        for (var k = 0; k < monitors.length; k++) {
            var name = monitors[k].name
            if (name && !seen[name]) {
                seen[name] = true
                list.push({ name: name, real: monitorRealByName(name) })
            }
        }
        list.sort(function (a, b) { return (a.real.x - b.real.x) || (a.real.y - b.real.y) })
        return list
    }

    function workspacesFor(name) {
        var seen = {}, list = []
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (!w.special && w.monitor === name && !(w.workspace in seen)) {
                seen[w.workspace] = true
                list.push(w.workspace)
            }
        }
        // + ws ajoutés manuellement (vides), même s'ils n'ont encore aucune fenêtre
        var ex = extraWss[name]
        if (ex)
            for (var e = 0; e < ex.length; e++)
                if (!(ex[e] in seen)) { seen[ex[e]] = true; list.push(ex[e]) }
        // + ws par défaut auto-injecté pour un écran live mais vide
        var au = autoWss[name]
        if (au !== undefined && !(au in seen)) { seen[au] = true; list.push(au) }
        list.sort(function (a, b) { return a - b })
        return list
    }

    // Tous les ws utilisés, tous écrans confondus (fenêtres + ws ajoutés).
    function allUsedWorkspaces() {
        var seen = {}
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (!w.special && w.monitor) seen[w.workspace] = true
        }
        for (var m in extraWss) {
            var ex = extraWss[m]
            for (var e = 0; e < ex.length; e++) seen[ex[e]] = true
        }
        return seen
    }

    // Choisit un ws pour `name` parmi les numéros non présents dans `used` :
    // 1) le plus petit ws bindé à cet écran (config Hyprland), 2) sinon le plus petit
    // entier libre non bindé à un autre écran. Respecte ordre numérique + binds.
    function pickWsFor(name, used) {
        var best = -1
        for (var key in workspaceRules) {
            if (workspaceRules[key] !== name) continue
            var n = parseInt(key)
            if (isNaN(n) || n <= 0 || used[n]) continue
            if (best < 0 || n < best) best = n
        }
        if (best > 0) return best
        for (var m = 1; m < 1000; m++) {
            if (used[m]) continue
            var bound = workspaceRules[("" + m)]
            if (bound && bound !== name) continue
            return m
        }
        return 1
    }

    function nextWorkspaceFor(name) { return pickWsFor(name, allUsedWorkspaces()) }

    // Un écran a-t-il déjà un ws propre (fenêtre non-spéciale dessus, ou ws ajouté via « + ») ?
    function hasOwnWs(name) {
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (!w.special && w.monitor === name) return true
        }
        var ex = extraWss[name]
        return !!(ex && ex.length)
    }

    // ws par défaut à afficher sur chaque écran live mais vide. Calcul déterministe
    // (écrans gauche→droite, numéros réservés au fil de l'eau) -> pas de collision.
    function computeAutoWss() {
        var a = {}
        if (!monitors || monitors.length === 0) return a
        var used = allUsedWorkspaces()
        var disp = displayMonitors()
        for (var i = 0; i < disp.length; i++) {
            var name = disp[i].name
            if (hasOwnWs(name)) continue
            var n = pickWsFor(name, used)
            a[name] = n
            used[n] = true   // réservé -> l'écran suivant prendra un autre numéro
        }
        return a
    }

    function addWorkspace(name) {
        var n = nextWorkspaceFor(name)
        var s = {}
        for (var k in extraWss) s[k] = extraWss[k].slice()
        if (!s[name]) s[name] = []
        if (s[name].indexOf(n) < 0) s[name].push(n)
        extraWss = s
        setWs(name, n)   // bascule dans le nouveau ws (recompute inclus)
    }

    // ====================== transform ======================
    function computeTransform() {
        var disp = displayMonitors()
        if (disp.length === 0 || canvasArea.width <= 0 || canvasArea.height <= 0) {
            sc = 1; offX = 0; offY = 0; bx0 = 0; by0 = 0
            return
        }
        var minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9
        for (var i = 0; i < disp.length; i++) {
            var r = disp[i].real
            minx = Math.min(minx, r.x); miny = Math.min(miny, r.y)
            maxx = Math.max(maxx, r.x + r.w); maxy = Math.max(maxy, r.y + r.h)
        }
        bx0 = minx; by0 = miny
        var bw = maxx - minx, bh = maxy - miny
        var pad = Style.marginM
        var availW = canvasArea.width - 2 * pad
        var availH = canvasArea.height - 2 * pad
        var s = Math.min(availW / bw, availH / bh)
        sc = s
        offX = pad + (availW - bw * s) / 2
        offY = pad + (availH - bh * s) / 2
        // origine de canvasArea dans le repère de l'éditeur (overlay) — gère les marges du ColumnLayout
        var o = canvasArea.mapToItem(editor, 0, 0)
        caOX = o.x; caOY = o.y
    }

    // rect monde réel -> coords overlay (les box vivent dans un overlay couvrant tout l'éditeur)
    function canvasRect(g) {
        return {
            x: (g.x - bx0) * sc + offX + caOX,
            y: (g.y - by0) * sc + offY + caOY,
            w: g.w * sc, h: g.h * sc
        }
    }
    function globalPoint(rx, ry) {
        return { x: (rx - caOX - offX) / sc + bx0, y: (ry - caOY - offY) / sc + by0 }
    }

    // ====================== recompute ======================
    // boxesOnly = true : on ne réassigne ni framesModel ni dividersList (utilisé pendant le drag
    // d'un divider, pour ne pas détruire le delegate MouseArea en cours de manipulation).
    function recompute(boxesOnly) {
        // ws par défaut des écrans live vides (recalculé ici car dépend de monitors/rules/windows,
        // tous chargés de façon asynchrone). Gate JSON -> pas de réassignation inutile/boucle.
        var auto = computeAutoWss()
        if (JSON.stringify(auto) !== JSON.stringify(autoWss)) autoWss = auto

        var disp = displayMonitors()
        // ws sélectionné par défaut = 1er ws de l'écran ; on corrige aussi une sélection devenue
        // invalide (ws disparu ou réassigné) pour ne pas laisser un cadre vide.
        var selFix = null
        for (var dm = 0; dm < disp.length; dm++) {
            var nm = disp[dm].name
            var wss0 = workspacesFor(nm)
            var cur = selectedWs[nm]
            if ((cur === undefined || wss0.indexOf(cur) < 0) && wss0.length > 0) {
                if (!selFix) { selFix = {}; for (var sk in selectedWs) selFix[sk] = selectedWs[sk] }
                selFix[nm] = wss0[0]
            }
        }
        if (selFix) selectedWs = selFix

        computeTransform()
        var p = {}, divs = [], tray = [], fm = []
        var newTrees = {}
        for (var k0 in trees) newTrees[k0] = trees[k0]

        for (var mi = 0; mi < disp.length; mi++) {
            var M = disp[mi]
            var sel = selectedWs[M.name]
            var fr = canvasRect(M.real)
            var wss = workspacesFor(M.name)
            var selIndex = wss.indexOf(sel)
            fm.push({ name: M.name, x: fr.x, y: fr.y, w: fr.w, h: fr.h,
                      online: M.real.online, wss: wss, sel: sel })
            if (sel === undefined)
                continue
            // chaque ws de l'écran est positionné, décalé horizontalement selon sa distance
            // au ws sélectionné -> carrousel. Seul le ws sélectionné est "onScreen" (opaque).
            for (var ki = 0; ki < wss.length; ki++) {
                var ws = wss[ki]
                var onScreen = (ki === selIndex)
                var dx = (ki - selIndex) * fr.w * editor.slideFactor
                var key = M.name + "|" + ws
                var ids = [], idItems = [], floats = []
                for (var wi = 0; wi < windows.length; wi++) {
                    var w = windows[wi]
                    if (w._id === draggingId || w.special) continue
                    if (w.monitor !== M.name || w.workspace !== ws) continue
                    if (w.floating) {
                        floats.push(w)
                    } else {
                        ids.push(w._id)
                        var at = w.at || [M.real.x, M.real.y], sz = w.size || [400, 300]
                        idItems.push({ id: w._id, x: at[0], y: at[1], w: sz[0], h: sz[1] })
                    }
                }
                var region = regionFor(key, M.real)
                // 1re construction d'un groupe : ratios inférés de la géométrie réelle (fidélité).
                if (!newTrees[key])
                    newTrees[key] = idItems.length ? Dwindle.fromCenters(idItems, region) : null
                var tree = Dwindle.reconcile(newTrees[key], region, ids)
                newTrees[key] = tree
                if (tree) {
                    var ts = Dwindle.tiles(tree, region, gapReal)
                    for (var ti = 0; ti < ts.length; ti++) {
                        var cr = canvasRect(ts[ti])
                        p[ts[ti].id] = { area: "canvas", x: cr.x + dx, y: cr.y, w: cr.w, h: cr.h,
                                         floating: false, onScreen: onScreen }
                    }
                    // dividers : seulement pour le ws affiché (on ne redimensionne pas un ws caché)
                    if (onScreen) {
                        var dv = Dwindle.dividers(tree, region, 8 / sc)
                        for (var di = 0; di < dv.length; di++) {
                            var dcr = canvasRect(dv[di])
                            divs.push({ key: key, region: region, path: dv[di].path, split: dv[di].split,
                                        x: dcr.x, y: dcr.y, w: dcr.w, h: dcr.h })
                        }
                    }
                }
                for (var fi = 0; fi < floats.length; fi++) {
                    var fw = floats[fi]
                    var frr = canvasRect({ x: fw.at[0], y: fw.at[1], w: fw.size[0], h: fw.size[1] })
                    p[fw._id] = { area: "canvas", x: frr.x + dx, y: frr.y, w: frr.w, h: frr.h,
                                  floating: true, onScreen: onScreen }
                }
            }
        }
        if (!boxesOnly) framesModel = fm

        // scratchpad -> tray (disposé en ligne dans la bande du bas)
        for (var si = 0; si < windows.length; si++)
            if (windows[si].special && windows[si]._id !== draggingId)
                tray.push(windows[si]._id)
        var to = trayBox.mapToItem(editor, 0, 0)
        var chipW = 120 * Style.uiScaleRatio, chipH = trayBox.height - 2 * Style.marginS
        for (var c = 0; c < tray.length; c++) {
            p[tray[c]] = { area: "tray", floating: false,
                           x: to.x + Style.marginS + c * (chipW + Style.marginS),
                           y: to.y + Style.marginS, w: chipW, h: chipH }
        }
        trayList = tray

        for (var hi = 0; hi < windows.length; hi++) {
            var hid = windows[hi]._id
            if (hid !== draggingId && !p[hid])
                p[hid] = { area: "hidden" }
        }

        trees = newTrees
        placements = p
        if (!boxesOnly) dividersList = divs
    }

    // ====================== drag ======================
    function startDrag(id, pressRX, pressRY) {
        var pl = placements[id]
        if (!pl) return
        draggingId = id
        dragW = pl.w || 200
        dragH = pl.h || 150
        grabDX = (pl.area === "hidden") ? dragW / 2 : (pressRX - pl.x)
        grabDY = (pl.area === "hidden") ? dragH / 2 : (pressRY - pl.y)
        dragX = pressRX - grabDX
        dragY = pressRY - grabDY
        recompute()   // retire la fenêtre saisie -> les autres se réorganisent
    }
    function updateDrag(rx, ry) {
        dragX = rx - grabDX
        dragY = ry - grabDY
        ptrX = rx; ptrY = ry   // alimente les onglets/« + » pour le spring-load
    }

    // Démarre un drag depuis le drawer : crée une fenêtre neuve et réutilise le flux de drag.
    // L'écran/ws cible est fixé au lâcher (endDrag) ; lâchée hors d'un cadre -> annulée.
    function startNewWindowDrag(app, pressRX, pressRY) {
        if (!app) return
        var cls = app.startupClass && app.startupClass.length ? app.startupClass
                  : (app.id ? ("" + app.id).replace(/\.desktop$/, "") : (app.name || "app"))
        var cmd = null
        if (app.command && app.command.length) {
            cmd = []
            for (var ci = 0; ci < app.command.length; ci++) cmd.push("" + app.command[ci])
        }
        var win = {
            _id: idSeq++,
            "class": cls,
            title: app.name || cls,
            cmd: cmd,
            workspace: 0, workspace_name: "", monitor: "",
            special: false, floating: false,
            at: null, size: [800, 600]
        }
        windows = windows.concat([win])
        draggingId = win._id
        draggingNew = true
        dragW = 220; dragH = 150
        grabDX = dragW / 2; grabDY = dragH / 2
        dragX = pressRX - grabDX
        dragY = pressRY - grabDY
        recompute()
    }

    // Retire une fenêtre du layout (drag vers le drawer, ou annulation d'un ajout).
    function removeWindow(id) {
        var w = windowById(id)
        if (w && !w.special && !w.floating && w.monitor) {
            var key = w.monitor + "|" + w.workspace
            if (trees[key]) trees[key] = Dwindle.remove(trees[key], id)
        }
        windows = windows.filter(function (x) { return x._id !== id })
        recompute()
    }

    // Spring-load : un onglet (ou le « + ») devient survolé pendant un drag -> arme un délai
    // avant de basculer/créer, pour ne pas réagir au simple passage du pointeur.
    function requestSpring(monitor, ws) {
        if (springPending && springPending.kind === "ws"
                && springPending.monitor === monitor && springPending.ws === ws)
            return
        springPending = { kind: "ws", monitor: monitor, ws: ws }
        springTimer.restart()
    }
    // Un ws est-il vide (aucune fenêtre non-spéciale dessus) ? -> ws échafaudage tout juste créé.
    function wsIsEmpty(monitor, ws) {
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i]
            if (!w.special && w.monitor === monitor && w.workspace === ws) return false
        }
        return true
    }
    function requestSpringAdd(monitor) {
        // déjà sur un ws vide fraîchement créé -> ne pas en empiler un autre
        if (wsIsEmpty(monitor, selectedWs[monitor])) return
        if (springPending && springPending.kind === "add" && springPending.monitor === monitor)
            return
        springPending = { kind: "add", monitor: monitor }
        springTimer.restart()
    }
    function cancelSpring() {
        springPending = null
        springTimer.stop()
    }
    // Annule seulement si la cible en attente est bien celle-ci (évite qu'un onglet quitté
    // n'annule la cible d'un autre onglet survolé dans le même mouvement).
    function cancelSpringIf(kind, monitor, ws) {
        var s = springPending
        if (!s || s.kind !== kind || s.monitor !== monitor) return
        if (kind === "ws" && s.ws !== ws) return
        cancelSpring()
    }
    // Le pointeur (coords overlay) est-il dans cet item ? Lit ptrX/ptrY -> binding réactif.
    function ptrInItem(item) {
        if (ptrX < 0 || draggingId < 0) return false
        var p = item.mapToItem(overlay, 0, 0)
        return ptrX >= p.x && ptrX < p.x + item.width && ptrY >= p.y && ptrY < p.y + item.height
    }
    function fireSpring() {
        var s = springPending
        springPending = null
        if (!s || draggingId < 0) return
        if (s.kind === "ws") {
            if (selectedWs[s.monitor] !== s.ws) setWs(s.monitor, s.ws)
        } else if (s.kind === "add") {
            addWorkspace(s.monitor)
        }
    }
    Timer { id: springTimer; interval: 250; onTriggered: editor.fireSpring() }
    function monitorFrameAt(rx, ry) {
        for (var i = 0; i < framesModel.length; i++) {
            var f = framesModel[i]
            if (rx >= f.x && rx < f.x + f.w && ry >= f.y && ry < f.y + f.h)
                return f
        }
        return null
    }
    function endDrag(rx, ry) {
        cancelSpring()
        ptrX = -1; ptrY = -1
        var id = draggingId
        var wasNew = draggingNew
        draggingNew = false
        var w = windowById(id)
        if (!w) { draggingId = -1; recompute(); return }
        var to = trayBox.mapToItem(editor, 0, 0)
        var overTray = (rx >= to.x && rx < to.x + trayBox.width &&
                        ry >= to.y && ry < to.y + trayBox.height)
        var dr = appDrawer.mapToItem(editor, 0, 0)
        var overDrawer = (drawerOpen && rx >= dr.x && rx < dr.x + appDrawer.width &&
                          ry >= dr.y && ry < dr.y + appDrawer.height)
        var f = monitorFrameAt(rx, ry)
        if (overDrawer) {
            // lâché sur le drawer -> retrait du layout (annulation si la fenêtre était neuve)
            draggingId = -1
            removeWindow(id)
            return
        } else if (overTray) {
            w.special = true
            w.workspace = -99
            w.workspace_name = "special:special"
        } else if (f && f.sel !== undefined) {
            w.special = false
            w.monitor = f.name
            w.workspace = f.sel
            w.workspace_name = "" + f.sel
            var M = monitorRealByName(f.name)
            if (w.floating) {
                var gp = globalPoint(rx - grabDX, ry - grabDY)
                w.at = [Math.round(gp.x), Math.round(gp.y)]
            } else {
                var key = f.name + "|" + f.sel
                var lp = globalPoint(rx, ry)
                trees[key] = Dwindle.insertAt(trees[key] || null, regionFor(key, M), id, lp.x, lp.y)
            }
        } else if (wasNew) {
            // nouvelle appli lâchée dans le vide -> jamais atterrie, on l'annule
            draggingId = -1
            removeWindow(id)
            return
        }
        // sinon (fenêtre existante lâchée dans le vide) : on annule, recompute restaure la position
        draggingId = -1
        recompute()
    }

    // Écrit la géométrie tuilée (issue de l'arbre) dans les fenêtres -> ce que montre l'éditeur
    // est exactement ce qui est sauvegardé (et rejoué par load via resizewindowpixel).
    function commitTiledGeometry() {
        for (var key in trees) {
            var t = trees[key]
            if (!t) continue
            var sep = key.lastIndexOf("|")
            var name = key.slice(0, sep)
            var ws = parseInt(key.slice(sep + 1))
            var M = monitorRealByName(name)
            var ts = Dwindle.tiles(t, regionFor(key, M), gapReal)
            for (var i = 0; i < ts.length; i++) {
                var w = windowById(ts[i].id)
                if (!w || w.floating || w.special) continue
                if (w.monitor !== name || w.workspace !== ws) continue
                w.at = [Math.round(ts[i].x), Math.round(ts[i].y)]
                w.size = [Math.round(ts[i].w), Math.round(ts[i].h)]
            }
        }
    }

    function windowById(id) {
        for (var i = 0; i < windows.length; i++)
            if (windows[i]._id === id) return windows[i]
        return null
    }

    function setWs(monitorName, ws) {
        var s = {}
        for (var k in selectedWs) s[k] = selectedWs[k]
        s[monitorName] = ws
        selectedWs = s
        recompute()
    }

    function toggleFloat(id) {
        var w = windowById(id)
        if (!w) return
        var pl = placements[id]
        if (!w.floating) {
            // pavé -> flottant : on fige la géométrie rendue courante
            if (pl && pl.area === "canvas") {
                var g = globalPoint(pl.x, pl.y)
                w.at = [Math.round(g.x), Math.round(g.y)]
                w.size = [Math.round(pl.w / sc), Math.round(pl.h / sc)]
            }
            w.floating = true
        } else {
            w.floating = false   // -> pavé : reconcile l'ajoutera à l'arbre du groupe
        }
        recompute()
    }

    function dragDivider(key, region, path, split, gx, gy) {
        if (!trees[key]) return
        var nr = Dwindle.nodeRect(trees[key], region, path)
        var ratio = (split === 'v') ? (gx - nr.x) / nr.w : (gy - nr.y) / nr.h
        trees[key] = Dwindle.setRatio(trees[key], path, ratio)
        recompute(true)   // boxesOnly : garde vivant le delegate du divider en cours de drag
    }

    function resizeFloat(id, dxReal, dyReal, edge) {
        var w = windowById(id)
        if (!w || !w.floating) return
        var x = w.at[0], y = w.at[1], ww = w.size[0], hh = w.size[1]
        if (edge.indexOf("l") >= 0) { x += dxReal; ww -= dxReal }
        if (edge.indexOf("r") >= 0) { ww += dxReal }
        if (edge.indexOf("t") >= 0) { y += dyReal; hh -= dyReal }
        if (edge.indexOf("b") >= 0) { hh += dyReal }
        w.at = [Math.round(x), Math.round(y)]
        w.size = [Math.max(80, Math.round(ww)), Math.max(60, Math.round(hh))]
        recompute()
    }

    // ====================== icônes ======================
    function appIcon(cls) {
        if (!cls) return ""
        var e = DesktopEntries.heuristicLookup(cls)
        var name = (e && e.icon) ? e.icon : ("" + cls).toLowerCase()
        return Quickshell.iconPath(name, true)
    }
    function appName(cls) {
        if (!cls) return "?"
        var e = DesktopEntries.heuristicLookup(cls)
        return (e && e.name) ? e.name : ("" + cls)
    }

    // ====================== menu contextuel : commande de lancement par fenêtre ======================
    // Épingle une commande explicite (`cmd_user`) sur une fenêtre : profil Chrome/Firefox, dossier
    // VSCode, répertoire de terminal, ou commande brute. Le CLI la priorise sur tout (resolve_cmd).
    property int menuWinId: -1
    property real menuX: 0
    property real menuY: 0
    property var menuOpts: null          // descripteur app-options ({kind,label,items,base,flag})
    property bool menuOptsLoading: false
    property bool menuAdvanced: false     // section commande brute dépliée
    // cmd_user est muté en place (propriété JS non observable par QML) : on reflète la commande
    // épinglée courante dans cette propriété string réactive, qui pilote la sélection et le bouton
    // reset. Mise à jour à l'ouverture du menu et après chaque mutation.
    property string menuSelCmd: ""

    function openWindowMenu(id, ox, oy) {
        menuWinId = id; menuX = ox; menuY = oy
        menuOpts = null; menuOptsLoading = true; menuAdvanced = false
        _refreshMenuSel()
        var w = windowById(id)
        if (w && mainInstance) mainInstance.requestAppOptions(w["class"])
    }
    function closeWindowMenu() { menuWinId = -1; menuOpts = null; menuOptsLoading = false }

    // Normalise une commande en tableau JS d'args, ou null. Gère à la fois les vrais tableaux JS
    // (cmd_user rechargé via JSON.parse) ET les QVariantList (cmd des items reçus par signal QML) :
    // Array.isArray renvoie faux pour ces derniers, d'où la comparaison qui échouait après reopen.
    function _asList(c) {
        if (Array.isArray(c)) return c
        if (c && typeof c === "object" && c.length !== undefined) {
            var a = []
            for (var i = 0; i < c.length; i++) a.push("" + c[i])
            return a
        }
        return null
    }
    function joinCmd(c) {
        var l = _asList(c)
        if (l) return l.join(" ")
        return (c === undefined || c === null) ? "" : ("" + c)
    }
    // Reflète la commande épinglée de la fenêtre du menu dans menuSelCmd (réactif).
    function _refreshMenuSel() {
        var w = windowById(menuWinId)
        menuSelCmd = w ? joinCmd(w.cmd_user) : ""
    }
    // Réassigne `windows` pour réévaluer les bindings (delegates + pastille) après mutation en place.
    function _touchWindows() { windows = windows.slice(); _refreshMenuSel() }

    function setWindowCmd(id, cmd) {
        var w = windowById(id); if (!w) return
        if (cmd && cmd.length) w.cmd_user = cmd; else delete w.cmd_user
        _touchWindows()
    }
    function setWindowRaw(id, text) {
        var w = windowById(id); if (!w) return
        var t = ("" + text).trim()
        if (t.length) w.cmd_user = t; else delete w.cmd_user
        _touchWindows()
    }
    function clearWindowCmd(id) {
        var w = windowById(id); if (!w) return
        delete w.cmd_user
        _touchWindows()
    }
    function cmdUserString(id) {
        var w = windowById(id)
        return w ? joinCmd(w.cmd_user) : ""
    }
    function hasCmdUser(w) { return w ? joinCmd(w.cmd_user).length > 0 : false }
    function dirArg(id) {                 // chemin courant (dernier arg) pour le champ "Répertoire"
        var w = windowById(id); if (!w) return ""
        var l = _asList(w.cmd_user)
        return (l && l.length) ? l[l.length - 1] : ""
    }
    function applyDir(id, path) {
        var p = ("" + path).trim()
        if (!menuOpts || menuOpts.kind !== "directory") return
        if (!p.length) { clearWindowCmd(id); return }
        setWindowCmd(id, (_asList(menuOpts.base) || []).concat([menuOpts.flag, p]))
    }

    // Descripteur app-options reçu de façon asynchrone (Main : requestAppOptions → signal).
    Connections {
        target: editor.mainInstance
        ignoreUnknownSignals: true
        function onAppOptionsReady(cls, data) {
            if (editor.menuWinId < 0) return
            var w = editor.windowById(editor.menuWinId)
            if (!w || ("" + (w["class"] || "")).toLowerCase() !== ("" + cls).toLowerCase()) return
            editor.menuOpts = data
            editor.menuOptsLoading = false
            editor._refreshMenuSel()
        }
    }

    onWidthChanged: Qt.callLater(recompute)
    onHeightChanged: Qt.callLater(recompute)
    // workspaceRules arrive de façon asynchrone (Process) -> rejouer le calcul (ws par défaut
    // bindé sur les écrans vides). monitors a déjà son handler onMonitorsChanged plus haut.
    onWorkspaceRulesChanged: Qt.callLater(recompute)

    // ====================== UI ======================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginS

        // --- barre d'outils ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NIconButton {
                icon: "arrow-left"
                tooltipText: "Annuler"
                onClicked: editor.cancelled()
            }
            NIconButton {
                icon: editor.drawerOpen ? "layout-sidebar-left-collapse" : "layout-sidebar-left-expand"
                tooltipText: editor.drawerOpen ? "Masquer les applications" : "Afficher les applications"
                onClicked: editor.drawerOpen = !editor.drawerOpen
            }
            NText {
                Layout.fillWidth: true
                text: "Éditer : " + editor.layoutName
                pointSize: Style.fontSizeL
                elide: Text.ElideRight
            }
            NButton {
                text: "Sauver"
                icon: "device-floppy"
                onClicked: {
                    editor.commitTiledGeometry()   // fige les proportions tuilées (at/size) pour fidélité
                    editor.mainInstance.saveEditedLayout(editor.layoutName, editor.buildV2Payload())
                    editor.saved()
                }
            }
        }

        // --- corps : drawer d'applications (gauche, repliable) + canevas/scratchpad ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.marginS

            // drawer d'applications : glisser une appli vers un cadre l'ajoute au layout ;
            // glisser une fenêtre ici la retire (cf. endDrag).
            NBox {
                id: appDrawer
                visible: editor.drawerOpen
                Layout.preferredWidth: 230 * Style.uiScaleRatio
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    spacing: Style.marginS
                    NTextInput {
                        Layout.fillWidth: true
                        placeholderText: "Rechercher une appli…"
                        inputIconName: "search"
                        onTextChanged: editor.appQuery = text
                    }
                    NListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: editor.filteredApps
                        spacing: Style.marginXXS
                        delegate: Rectangle {
                            id: appRow
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: 40 * Style.uiScaleRatio
                            radius: Style.radiusXS
                            color: appRowMa.containsMouse ? Color.mHover : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Style.marginXS
                                anchors.rightMargin: Style.marginXS
                                spacing: Style.marginS
                                IconImage {
                                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                    source: Quickshell.iconPath(appRow.modelData.icon, true)
                                    asynchronous: true; smooth: true
                                }
                                NText {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name || ""
                                    pointSize: Style.fontSizeS
                                    elide: Text.ElideRight
                                }
                            }
                            // drag -> crée une fenêtre et réutilise le flux de drag de l'éditeur
                            MouseArea {
                                id: appRowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true   // empêche le ListView de voler le drag
                                cursorShape: Qt.OpenHandCursor
                                property bool armed: false
                                property real px: 0
                                property real py: 0
                                onPressed: function (mouse) {
                                    var rp = mapToItem(overlay, mouse.x, mouse.y)
                                    px = rp.x; py = rp.y; armed = true
                                }
                                onPositionChanged: function (mouse) {
                                    if (!armed) return
                                    var rp = mapToItem(overlay, mouse.x, mouse.y)
                                    if (editor.draggingId < 0) {
                                        if (Math.abs(rp.x - px) + Math.abs(rp.y - py) > 6)
                                            editor.startNewWindowDrag(appRow.modelData, px, py)
                                    } else {
                                        editor.updateDrag(rp.x, rp.y)
                                    }
                                }
                                onReleased: function (mouse) {
                                    if (editor.draggingId >= 0) {
                                        var rp = mapToItem(overlay, mouse.x, mouse.y)
                                        editor.endDrag(rp.x, rp.y)
                                    }
                                    armed = false
                                }
                            }
                        }
                    }
                }
            }

            // canevas + scratchpad
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.marginS

                // --- canevas des écrans (cellule de mise en page ; le dessin se fait dans overlay) ---
                Item {
                    id: canvasArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    onWidthChanged: Qt.callLater(editor.recompute)
                    onHeightChanged: Qt.callLater(editor.recompute)
                }

                // --- bande scratchpad ---
                NBox {
                    id: trayBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64 * Style.uiScaleRatio
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginS
                        NIcon { icon: "layers-subtract"; color: Color.mOnSurfaceVariant }
                        NText {
                            text: editor.trayList.length > 0 ? "Scratchpad" : "Scratchpad (déposez une fenêtre ici)"
                            color: Color.mOnSurfaceVariant
                            pointSize: Style.fontSizeS
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    // ====================== overlay : box, dividers, en-têtes ======================
    // Couche unique couvrant tout l'éditeur (les box circulent entre cadres et tray sans reparentage).
    Item {
        id: overlay
        anchors.fill: parent

        // fond des cadres (écrans), sous tout le reste
        Repeater {
            model: editor.framesModel
            delegate: Rectangle {
                required property var modelData
                x: modelData.x; y: modelData.y
                width: modelData.w; height: modelData.h
                radius: Style.radiusS
                color: Color.mSurfaceVariant
                border.color: Color.mOutline
                border.width: Math.max(1, Style.borderS)
                Behavior on x { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
            }
        }

        // poignées de split (z élevé : au-dessus des box, sinon impossible à saisir)
        Repeater {
            model: editor.dividersList
            delegate: Item {
                id: dvItem
                required property var modelData
                property bool dragging: false
                property real lx: modelData.x
                property real ly: modelData.y
                z: 30
                x: dragging ? lx : modelData.x
                y: dragging ? ly : modelData.y
                width: Math.max(6, modelData.w); height: Math.max(6, modelData.h)
                Behavior on x { enabled: !dvItem.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !dvItem.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Color.mPrimary
                    opacity: (divMa.containsMouse || divHover.hovered || dvItem.dragging) ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Style.animationFast } }
                }
                HoverHandler { id: divHover }
                MouseArea {
                    id: divMa
                    anchors.fill: parent
                    anchors.margins: -6   // zone de préhension généreuse
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: modelData.split === 'v' ? Qt.SplitHCursor : Qt.SplitVCursor
                    onPressed: dvItem.dragging = true
                    onPositionChanged: function (mouse) {
                        if (!pressed) return
                        var rp = mapToItem(overlay, mouse.x, mouse.y)
                        if (modelData.split === 'v') dvItem.lx = rp.x - dvItem.width / 2
                        else dvItem.ly = rp.y - dvItem.height / 2
                        var gp = editor.globalPoint(rp.x, rp.y)
                        editor.dragDivider(modelData.key, modelData.region, modelData.path, modelData.split, gp.x, gp.y)
                    }
                    onReleased: { dvItem.dragging = false; editor.recompute() }
                }
            }
        }

        // box de fenêtres
        Repeater {
            model: editor.windows
            delegate: Item {
                id: box
                required property var modelData
                property var pl: editor.placements[modelData._id] || ({ area: "hidden" })
                property bool dragging: editor.draggingId === modelData._id
                property bool isFloating: pl.floating === true
                // ws affiché (ou tray / fenêtre draguée) -> opaque & interactif ; les ws cachés
                // restent rendus (opacity 0) pour pouvoir glisser lors de la bascule (carrousel).
                property bool interactive: dragging || pl.onScreen === true || pl.area === "tray"

                visible: dragging || pl.area === "canvas" || pl.area === "tray"
                z: dragging ? 1000 : (isFloating ? 10 : 2)
                opacity: interactive ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Style.animationFast } }

                // Hover passif (non volé par les enfants) -> évite le clignotement du bouton flottant.
                HoverHandler { id: boxHover; enabled: box.interactive }

                x: dragging ? editor.dragX : (pl.x || 0)
                y: dragging ? editor.dragY : (pl.y || 0)
                width: dragging ? editor.dragW : (pl.w || 0)
                height: dragging ? editor.dragH : (pl.h || 0)

                Behavior on x { enabled: !box.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !box.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !box.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !box.dragging; NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    z: 1   // au-dessus de boxMa : ses enfants (toggle) restent cliquables
                    radius: Style.radiusXS
                    color: box.dragging ? Color.mPrimary : Color.mSurface
                    opacity: box.dragging ? 0.85 : 1.0
                    border.width: Math.max(1, Style.borderS)
                    border.color: box.isFloating ? Color.mTertiary : Color.mOutline

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Style.marginXXS
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 28; Layout.preferredHeight: 28
                            IconImage {
                                id: img
                                anchors.fill: parent
                                source: editor.appIcon(box.modelData["class"])
                                visible: source != ""
                                asynchronous: true; smooth: true
                            }
                            NIcon {
                                anchors.centerIn: parent
                                visible: img.source == ""
                                icon: "app-window"
                                color: Color.mOnSurfaceVariant
                            }
                        }
                        NText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: box.width - Style.marginS
                            visible: box.height > 56 && box.width > 60
                            text: editor.appName(box.modelData["class"])
                            pointSize: Style.fontSizeXS
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // bascule pavé <-> flottant (seul contrôle non-drag)
                    NIconButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Style.marginXXS
                        visible: boxHover.hovered && !box.dragging && box.width > 50
                        icon: box.isFloating ? "layout-grid" : "picture-in-picture-top"
                        tooltipText: box.isFloating ? "Repaver" : "Rendre flottant"
                        onClicked: editor.toggleFloat(box.modelData._id)
                    }

                    // pastille : commande de lancement personnalisée (profil/dossier/cwd) épinglée
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: Style.marginXXS
                        visible: editor.hasCmdUser(box.modelData) && box.width > 40
                        width: 8; height: 8; radius: 4
                        color: Color.mPrimary
                    }
                }

                // déplacement
                MouseArea {
                    id: boxMa
                    anchors.fill: parent
                    enabled: box.interactive
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property bool armed: false
                    property real px: 0
                    property real py: 0
                    onPressed: function (mouse) {
                        var rp = mapToItem(overlay, mouse.x, mouse.y)
                        if (mouse.button === Qt.RightButton) {   // menu : profil/dossier/cwd/commande
                            editor.openWindowMenu(box.modelData._id, rp.x, rp.y)
                            return
                        }
                        px = rp.x; py = rp.y; armed = true
                    }
                    onPositionChanged: function (mouse) {
                        if (!armed) return
                        var rp = mapToItem(overlay, mouse.x, mouse.y)
                        if (!box.dragging) {
                            if (Math.abs(rp.x - px) + Math.abs(rp.y - py) > 6)
                                editor.startDrag(box.modelData._id, px, py)
                        } else {
                            editor.updateDrag(rp.x, rp.y)
                        }
                    }
                    onReleased: function (mouse) {
                        if (box.dragging) {
                            var rp = mapToItem(overlay, mouse.x, mouse.y)
                            editor.endDrag(rp.x, rp.y)
                        }
                        armed = false
                    }
                }

                // poignées de resize (flottant uniquement)
                Repeater {
                    model: box.isFloating && !box.dragging && boxHover.hovered ? 4 : 0
                    delegate: Rectangle {
                        required property int index
                        z: 2
                        readonly property var edges: ["tl", "tr", "bl", "br"]
                        readonly property string edge: edges[index]
                        width: 12; height: 12; radius: 6
                        color: Color.mTertiary
                        x: (edge.indexOf("l") >= 0 ? -2 : box.width - 10)
                        y: (edge.indexOf("t") >= 0 ? -2 : box.height - 10)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: (edge === "tl" || edge === "br") ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                            property real lastX: 0
                            property real lastY: 0
                            onPressed: function (mouse) {
                                var rp = mapToItem(overlay, mouse.x, mouse.y)
                                lastX = rp.x; lastY = rp.y
                            }
                            onPositionChanged: function (mouse) {
                                if (!pressed) return
                                var rp = mapToItem(overlay, mouse.x, mouse.y)
                                editor.resizeFloat(box.modelData._id, (rp.x - lastX) / editor.sc, (rp.y - lastY) / editor.sc, edge)
                                lastX = rp.x; lastY = rp.y
                            }
                        }
                    }
                }
            }
        }

        // en-têtes de cadre (au-dessus des box : nom écran + onglets ws, cliquables)
        Repeater {
            model: editor.framesModel
            delegate: Row {
                id: frameHeader
                required property var modelData
                readonly property string frameName: modelData.name
                x: modelData.x + Style.marginXS
                y: modelData.y + Style.marginXS
                spacing: Style.marginXXS
                // au-dessus des poignées de split (z:30) : onglets ws / bouton « + » prioritaires
                // sur un divider qui passerait juste en dessous (sinon le drag de split vole le clic)
                z: 40
                Behavior on x { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

                Rectangle {
                    height: 22 * Style.uiScaleRatio
                    width: nameText.implicitWidth + Style.marginS * 2
                    radius: Style.radiusXS
                    color: Color.mSurface
                    NText {
                        id: nameText
                        anchors.centerIn: parent
                        text: frameHeader.frameName + (frameHeader.modelData.online ? "" : " (hors-ligne)")
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                    }
                }
                Repeater {
                    model: frameHeader.modelData.wss
                    delegate: Rectangle {
                        id: wsTab
                        required property var modelData
                        property bool active: editor.selectedWs[frameHeader.frameName] === modelData
                        // survolé pendant un drag -> spring-load (bascule après délai)
                        property bool dragHot: editor.ptrInItem(wsTab)
                        onDragHotChanged: dragHot ? editor.requestSpring(frameHeader.frameName, wsTab.modelData)
                                                  : editor.cancelSpringIf("ws", frameHeader.frameName, wsTab.modelData)
                        height: 22 * Style.uiScaleRatio
                        width: wsText.implicitWidth + Style.marginS * 2
                        radius: Style.radiusXS
                        color: active ? Color.mPrimary : (dragHot ? Color.mSecondary : Color.mSurface)
                        border.width: dragHot ? Math.max(1, Style.borderS) : 0
                        border.color: Color.mPrimary
                        NText {
                            id: wsText
                            anchors.centerIn: parent
                            text: "ws " + wsTab.modelData
                            pointSize: Style.fontSizeXS
                            color: wsTab.active ? Color.mOnPrimary : Color.mOnSurfaceVariant
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.setWs(frameHeader.frameName, wsTab.modelData)
                        }
                    }
                }
                // bouton « + » : ajoute un ws (prochain numéro libre, binds respectés) ; au survol
                // pendant un drag, crée-le et bascule dedans (spring-load).
                Rectangle {
                    id: addTab
                    property bool dragHot: editor.ptrInItem(addTab)
                    onDragHotChanged: dragHot ? editor.requestSpringAdd(frameHeader.frameName)
                                              : editor.cancelSpringIf("add", frameHeader.frameName, undefined)
                    height: 22 * Style.uiScaleRatio
                    width: height
                    radius: Style.radiusXS
                    color: dragHot ? Color.mSecondary : Color.mSurface
                    border.width: dragHot ? Math.max(1, Style.borderS) : 0
                    border.color: Color.mPrimary
                    NIcon {
                        anchors.centerIn: parent
                        icon: "plus"
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editor.addWorkspace(frameHeader.frameName)
                    }
                }
            }
        }

        // ====================== menu contextuel d'une fenêtre (clic droit) ======================
        // Capte les clics hors menu pour le fermer.
        MouseArea {
            anchors.fill: parent
            z: 1999
            visible: editor.menuWinId >= 0
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: editor.closeWindowMenu()
        }

        Rectangle {
            id: winMenu
            visible: editor.menuWinId >= 0
            z: 2000
            width: 260 * Style.uiScaleRatio
            implicitHeight: menuCol.implicitHeight + Style.marginS * 2
            height: implicitHeight
            x: Math.max(0, Math.min(editor.menuX, overlay.width - width))
            y: Math.max(0, Math.min(editor.menuY, overlay.height - height))
            radius: Style.radiusS
            color: Color.mSurface
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderS)
            property var win: editor.windowById(editor.menuWinId)

            ColumnLayout {
                id: menuCol
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginXS

                // en-tête : icône + nom de l'app
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS
                    Item {
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        IconImage {
                            id: menuIcon
                            anchors.fill: parent
                            source: winMenu.win ? editor.appIcon(winMenu.win["class"]) : ""
                            visible: source != ""
                            asynchronous: true; smooth: true
                        }
                        NIcon {
                            anchors.centerIn: parent
                            visible: menuIcon.source == ""
                            icon: "app-window"
                            color: Color.mOnSurfaceVariant
                        }
                    }
                    NText {
                        Layout.fillWidth: true
                        text: winMenu.win ? editor.appName(winMenu.win["class"]) : ""
                        pointSize: Style.fontSizeS
                        elide: Text.ElideRight
                    }
                }

                NDivider { Layout.fillWidth: true }

                NText {
                    Layout.fillWidth: true
                    visible: editor.menuOptsLoading
                    text: "Chargement…"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                // section profils / dossiers (liste de choix prêts à l'emploi)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXXS
                    visible: !editor.menuOptsLoading && editor.menuOpts
                             && (editor.menuOpts.kind === "profiles" || editor.menuOpts.kind === "folders")
                    NText {
                        Layout.fillWidth: true
                        text: editor.menuOpts ? (editor.menuOpts.label || "") : ""
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                    // liste scrollable à hauteur fixe (~3 éléments) -> la popup reste compacte
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(optCol.implicitHeight,
                                                          3 * (26 * Style.uiScaleRatio) + 2 * Style.marginXXS)
                        contentHeight: optCol.implicitHeight
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        Column {
                            id: optCol
                            width: parent.width
                            spacing: Style.marginXXS

                            // « par défaut » : aucune commande épinglée -> lancement générique de l'app
                            Rectangle {
                                id: defRow
                                width: parent.width
                                height: 26 * Style.uiScaleRatio
                                radius: Style.radiusXS
                                property bool sel: editor.menuSelCmd.length === 0
                                color: defMa.containsMouse ? Color.mHover : (sel ? Color.mSecondary : "transparent")
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.marginXS
                                    anchors.rightMargin: Style.marginXS
                                    spacing: Style.marginXXS
                                    NText {
                                        Layout.fillWidth: true
                                        text: "Par défaut (aucun)"
                                        pointSize: Style.fontSizeXS
                                        elide: Text.ElideRight
                                        color: defRow.sel ? Color.mOnSecondary : Color.mOnSurfaceVariant
                                    }
                                    NIcon {
                                        visible: defRow.sel
                                        icon: "check"
                                        pointSize: Style.fontSizeXS
                                        color: Color.mOnSecondary
                                    }
                                }
                                MouseArea {
                                    id: defMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: editor.clearWindowCmd(editor.menuWinId)
                                }
                            }
                            Repeater {
                                model: (editor.menuOpts && editor.menuOpts.items) ? editor.menuOpts.items : []
                                delegate: Rectangle {
                                    id: optRow
                                    required property var modelData
                                    width: optCol.width
                                    height: 26 * Style.uiScaleRatio
                                    radius: Style.radiusXS
                                    property bool sel: editor.menuSelCmd.length > 0 && editor.menuSelCmd === editor.joinCmd(modelData.cmd)
                                    color: rowMa.containsMouse ? Color.mHover
                                                               : (sel ? Color.mSecondary : "transparent")
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Style.marginXS
                                        anchors.rightMargin: Style.marginXS
                                        spacing: Style.marginXXS
                                        NText {
                                            Layout.fillWidth: true
                                            text: optRow.modelData.label || ""
                                            pointSize: Style.fontSizeXS
                                            elide: Text.ElideMiddle
                                            color: optRow.sel ? Color.mOnSecondary : Color.mOnSurface
                                        }
                                        NIcon {
                                            visible: optRow.sel
                                            icon: "check"
                                            pointSize: Style.fontSizeXS
                                            color: Color.mOnSecondary
                                        }
                                    }
                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // clic sur l'option sélectionnée -> désépingle (lancement par défaut)
                                        onClicked: optRow.sel ? editor.clearWindowCmd(editor.menuWinId)
                                                              : editor.setWindowCmd(editor.menuWinId, optRow.modelData.cmd)
                                    }
                                }
                            }
                            NText {
                                width: parent.width
                                visible: editor.menuOpts && (!editor.menuOpts.items || editor.menuOpts.items.length === 0)
                                text: "Aucune option détectée."
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurfaceVariant
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // section répertoire de travail (terminaux)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXXS
                    visible: !editor.menuOptsLoading && editor.menuOpts && editor.menuOpts.kind === "directory"
                    NText {
                        Layout.fillWidth: true
                        text: editor.menuOpts ? (editor.menuOpts.label || "") : ""
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                    NTextInput {
                        Layout.fillWidth: true
                        placeholderText: "/chemin/du/dossier"
                        text: editor.dirArg(editor.menuWinId)
                        onEditingFinished: editor.applyDir(editor.menuWinId, text)
                    }
                }

                NDivider { Layout.fillWidth: true }

                // commande brute (avancé) — couvre les apps non gérées et le réglage fin
                NToggle {
                    Layout.fillWidth: true
                    label: "Commande personnalisée"
                    checked: editor.menuAdvanced
                    onToggled: (v) => editor.menuAdvanced = v
                }
                NTextInput {
                    Layout.fillWidth: true
                    visible: editor.menuAdvanced
                    placeholderText: "ex. google-chrome-stable --profile-directory=…"
                    text: editor.cmdUserString(editor.menuWinId)
                    onEditingFinished: editor.setWindowRaw(editor.menuWinId, text)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS
                    NButton {
                        text: "Réinitialiser"
                        outlined: true
                        fontSize: Style.fontSizeS
                        enabled: editor.menuSelCmd.length > 0
                        onClicked: editor.clearWindowCmd(editor.menuWinId)
                    }
                    Item { Layout.fillWidth: true }
                    NButton {
                        text: "Fermer"
                        fontSize: Style.fontSizeS
                        onClicked: editor.closeWindowMenu()
                    }
                }
            }
        }
    }
}
