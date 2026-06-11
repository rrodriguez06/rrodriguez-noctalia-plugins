.pragma library

// Simulation de pavage dwindle (à la Hyprland) pour l'éditeur visuel.
//
// Arbre binaire :
//   feuille : { leaf: <id> }                          // id = identifiant stable d'une fenêtre
//   nœud    : { split: 'v'|'h', ratio: <0..1>, a, b } // 'v' = côte à côte (gauche=a),
//                                                      // 'h' = empilé (haut=a)
//
// Rien n'est muté en place : les opérations renvoient un nouvel arbre (clone), ce qui
// permet de réassigner une propriété QML et de déclencher les bindings/animations.

function _leaf(id) { return { leaf: id } }
function isLeaf(t) { return t && t.leaf !== undefined }

function clone(t) {
    if (!t) return t
    if (isLeaf(t)) return { leaf: t.leaf }
    return { split: t.split, ratio: t.ratio, a: clone(t.a), b: clone(t.b) }
}

// --- géométrie : id -> {x,y,w,h} (sans gap) ---
function _rects(t, r, out) {
    if (!t) return out
    if (isLeaf(t)) { out[t.leaf] = { x: r.x, y: r.y, w: r.w, h: r.h }; return out }
    var ratio = t.ratio
    if (t.split === 'v') {
        var aw = r.w * ratio
        _rects(t.a, { x: r.x, y: r.y, w: aw, h: r.h }, out)
        _rects(t.b, { x: r.x + aw, y: r.y, w: r.w - aw, h: r.h }, out)
    } else {
        var ah = r.h * ratio
        _rects(t.a, { x: r.x, y: r.y, w: r.w, h: ah }, out)
        _rects(t.b, { x: r.x, y: r.y + ah, w: r.w, h: r.h - ah }, out)
    }
    return out
}

// Renvoie un tableau [{id,x,y,w,h}] avec un gap (inset) appliqué à chaque feuille.
function tiles(t, rect, gap) {
    var raw = _rects(t, rect, {})
    var g = gap || 0
    var out = []
    for (var id in raw) {
        var r = raw[id]
        out.push({
            id: parseInt(id),
            x: r.x + g, y: r.y + g,
            w: Math.max(1, r.w - 2 * g),
            h: Math.max(1, r.h - 2 * g)
        })
    }
    return out
}

// --- dividers (poignées de resize) : [{path:[...], split, x,y,w,h}] ---
function _dividers(t, r, path, thickness, out) {
    if (!t || isLeaf(t)) return out
    var th = thickness
    if (t.split === 'v') {
        var aw = r.w * t.ratio
        out.push({ path: path.slice(), split: 'v', ratio: t.ratio,
                   x: r.x + aw - th / 2, y: r.y, w: th, h: r.h })
        _dividers(t.a, { x: r.x, y: r.y, w: aw, h: r.h }, path.concat('a'), thickness, out)
        _dividers(t.b, { x: r.x + aw, y: r.y, w: r.w - aw, h: r.h }, path.concat('b'), thickness, out)
    } else {
        var ah = r.h * t.ratio
        out.push({ path: path.slice(), split: 'h', ratio: t.ratio,
                   x: r.x, y: r.y + ah - th / 2, w: r.w, h: th })
        _dividers(t.a, { x: r.x, y: r.y, w: r.w, h: ah }, path.concat('a'), thickness, out)
        _dividers(t.b, { x: r.x, y: r.y + ah, w: r.w, h: r.h - ah }, path.concat('b'), thickness, out)
    }
    return out
}

function dividers(t, rect, thickness) {
    return _dividers(t, rect, [], thickness || 6, [])
}

// --- construction par insertions séquentielles (spirale dwindle) ---
// L'orientation de chaque split suit la plus grande dimension de la feuille scindée,
// exactement comme Hyprland à l'ouverture des fenêtres une à une.
function build(ids, rect) {
    if (!ids || ids.length === 0) return null
    var tree = _leaf(ids[0])
    var last = ids[0]
    for (var k = 1; k < ids.length; k++) {
        var rs = _rects(tree, rect, {})
        var lr = rs[last] || rect
        var orient = (lr.w >= lr.h) ? 'v' : 'h'
        tree = _splitLeaf(tree, last, orient, ids[k])
        last = ids[k]
    }
    return tree
}

// Reconstruit un arbre depuis la géométrie réelle des fenêtres (at/size), pour que l'éditeur
// reflète les proportions du layout. Récursif : à chaque niveau on coupe selon l'axe où les
// centres sont les plus dispersés (comme dwindle scinde la plus grande dimension), au plus grand
// écart entre centres consécutifs ; le ratio vient de la position réelle de la coupe.
// Robuste aux fenêtres qui se chevauchent (données capturées imparfaites) : on normalise.
function _clampRatio(r) { return Math.max(0.05, Math.min(0.95, r)) }

function fromCenters(items, region) {
    if (!items || items.length === 0) return null
    if (items.length === 1) return _leaf(items[0].id)
    var cx = [], cy = []
    for (var i = 0; i < items.length; i++) {
        cx.push(items[i].x + items[i].w / 2)
        cy.push(items[i].y + items[i].h / 2)
    }
    var minX = Math.min.apply(null, cx), maxX = Math.max.apply(null, cx)
    var minY = Math.min.apply(null, cy), maxY = Math.max.apply(null, cy)
    var vert = (maxX - minX) >= (maxY - minY)   // côte à côte si les centres s'étalent en X

    var sorted = items.slice().sort(function (a, b) {
        return vert ? (a.x + a.w / 2) - (b.x + b.w / 2) : (a.y + a.h / 2) - (b.y + b.h / 2)
    })
    // plus grand écart entre centres consécutifs -> frontière entre les 2 groupes
    var splitIdx = 1, bestGap = -1
    for (var k = 1; k < sorted.length; k++) {
        var c0 = vert ? (sorted[k - 1].x + sorted[k - 1].w / 2) : (sorted[k - 1].y + sorted[k - 1].h / 2)
        var c1 = vert ? (sorted[k].x + sorted[k].w / 2) : (sorted[k].y + sorted[k].h / 2)
        if (c1 - c0 > bestGap) { bestGap = c1 - c0; splitIdx = k }
    }
    var A = sorted.slice(0, splitIdx), B = sorted.slice(splitIdx)
    // coupe = milieu entre le bord intérieur de A et celui de B (= la frontière réelle du split,
    // exacte pour un pavage propre, même asymétrique 70/30 ; ~centre si les fenêtres se chevauchent).
    if (vert) {
        var aMax = -1e9, bMin = 1e9
        for (var ia = 0; ia < A.length; ia++) aMax = Math.max(aMax, A[ia].x + A[ia].w)
        for (var ib = 0; ib < B.length; ib++) bMin = Math.min(bMin, B[ib].x)
        var cut = (aMax + bMin) / 2
        var ratio = _clampRatio((cut - region.x) / region.w)
        return { split: 'v', ratio: ratio,
                 a: fromCenters(A, { x: region.x, y: region.y, w: region.w * ratio, h: region.h }),
                 b: fromCenters(B, { x: region.x + region.w * ratio, y: region.y, w: region.w * (1 - ratio), h: region.h }) }
    } else {
        var aMaxY = -1e9, bMinY = 1e9
        for (var ja = 0; ja < A.length; ja++) aMaxY = Math.max(aMaxY, A[ja].y + A[ja].h)
        for (var jb = 0; jb < B.length; jb++) bMinY = Math.min(bMinY, B[jb].y)
        var cutY = (aMaxY + bMinY) / 2
        var ratioH = _clampRatio((cutY - region.y) / region.h)
        return { split: 'h', ratio: ratioH,
                 a: fromCenters(A, { x: region.x, y: region.y, w: region.w, h: region.h * ratioH }),
                 b: fromCenters(B, { x: region.x, y: region.y + region.h * ratioH, w: region.w, h: region.h * (1 - ratioH) }) }
    }
}

function _splitLeaf(t, targetId, orient, newId) {
    if (!t) return _leaf(newId)
    if (isLeaf(t)) {
        if (t.leaf === targetId)
            return { split: orient, ratio: 0.5, a: _leaf(targetId), b: _leaf(newId) }
        return t
    }
    return { split: t.split, ratio: t.ratio,
             a: _splitLeaf(t.a, targetId, orient, newId),
             b: _splitLeaf(t.b, targetId, orient, newId) }
}

// Ajoute une feuille en scindant la dernière (utilisé quand un id apparaît dans un groupe).
function append(t, rect, id) {
    if (!t) return _leaf(id)
    var ls = leaves(t)
    var last = ls[ls.length - 1]
    var rs = _rects(t, rect, {})
    var lr = rs[last] || rect
    var orient = (lr.w >= lr.h) ? 'v' : 'h'
    return _splitLeaf(t, last, orient, id)
}

// Réconcilie un arbre avec l'ensemble d'ids voulu (retire les absents, ajoute les nouveaux),
// en préservant les ratios des splits existants.
function reconcile(t, rect, ids) {
    var want = {}
    for (var i = 0; i < ids.length; i++) want[ids[i]] = true
    var have = {}
    var cur = leaves(t)
    for (var j = 0; j < cur.length; j++) {
        have[cur[j]] = true
        if (!want[cur[j]]) t = remove(t, cur[j])
    }
    for (var k = 0; k < ids.length; k++)
        if (!have[ids[k]]) t = append(t, rect, ids[k])
    return t
}

// --- ratio d'un nœud (resize de split) ---
function setRatio(t, path, ratio) {
    var c = clone(t)
    var n = c
    for (var i = 0; i < path.length; i++)
        n = (path[i] === 'a') ? n.a : n.b
    n.ratio = Math.max(0.05, Math.min(0.95, ratio))
    return c
}

// Rect du nœud (split) situé à `path` — sert à recalculer un ratio au drag d'un divider.
function nodeRect(t, rect, path) {
    var r = rect
    var n = t
    for (var i = 0; i < path.length; i++) {
        if (n.split === 'v') {
            var aw = r.w * n.ratio
            if (path[i] === 'a') r = { x: r.x, y: r.y, w: aw, h: r.h }
            else r = { x: r.x + aw, y: r.y, w: r.w - aw, h: r.h }
        } else {
            var ah = r.h * n.ratio
            if (path[i] === 'a') r = { x: r.x, y: r.y, w: r.w, h: ah }
            else r = { x: r.x, y: r.y + ah, w: r.w, h: r.h - ah }
        }
        n = (path[i] === 'a') ? n.a : n.b
    }
    return r
}

// --- suppression d'une feuille (le parent est remplacé par le frère) ---
function remove(t, id) {
    if (!t) return null
    if (isLeaf(t)) return (t.leaf === id) ? null : t
    if (isLeaf(t.a) && t.a.leaf === id) return clone(t.b)
    if (isLeaf(t.b) && t.b.leaf === id) return clone(t.a)
    return { split: t.split, ratio: t.ratio, a: remove(t.a, id), b: remove(t.b, id) }
}

// --- insertion près d'un point (drop) : scinde la feuille contenant le point ---
function insertAt(t, rect, newId, px, py) {
    if (!t) return _leaf(newId)
    var rs = _rects(t, rect, {})
    var targetId = null, best = Infinity
    for (var id in rs) {
        var r = rs[id]
        if (px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) { targetId = parseInt(id); break }
        // repli : feuille au centre le plus proche
        var cx = r.x + r.w / 2, cy = r.y + r.h / 2
        var d = (cx - px) * (cx - px) + (cy - py) * (cy - py)
        if (d < best) { best = d; if (targetId === null) targetId = parseInt(id) }
    }
    if (targetId === null) return _leaf(newId)
    var tr = rs[targetId]
    var orient = (tr.w >= tr.h) ? 'v' : 'h'
    // côté de dépose : si on lâche dans la 2e moitié, la nouvelle fenêtre va en 'b' (défaut),
    // sinon en 'a' (on inverse l'ordre des enfants).
    var secondHalf = (orient === 'v') ? (px >= tr.x + tr.w / 2) : (py >= tr.y + tr.h / 2)
    return _insertSplit(t, targetId, orient, newId, secondHalf)
}

function _insertSplit(t, targetId, orient, newId, newInB) {
    if (!t) return _leaf(newId)
    if (isLeaf(t)) {
        if (t.leaf !== targetId) return t
        var old = _leaf(targetId), neo = _leaf(newId)
        return { split: orient, ratio: 0.5, a: newInB ? old : neo, b: newInB ? neo : old }
    }
    return { split: t.split, ratio: t.ratio,
             a: _insertSplit(t.a, targetId, orient, newId, newInB),
             b: _insertSplit(t.b, targetId, orient, newId, newInB) }
}

// --- feuilles dans l'ordre de l'arbre (gauche→droite, haut→bas) ---
function leaves(t, out) {
    out = out || []
    if (!t) return out
    if (isLeaf(t)) { out.push(t.leaf); return out }
    leaves(t.a, out); leaves(t.b, out)
    return out
}
