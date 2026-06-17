.pragma library

// Helpers partagés par les drivers de Claude Conductor.
// QML-free : aucun accès à Qt / Logger / Style. Pures fonctions ; toute I/O reste dans Main.qml.

// Quote un argument pour un shell POSIX (single-quote safe).
function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

// JSON.parse robuste : renvoie `fallback` en cas d'erreur.
function safeJson(text, fallback) {
    try { return JSON.parse(text || "") } catch (e) { return fallback }
}

// Chemin absolu d'un script du plugin. `pluginDir` est résolu dans Main via Qt.resolvedUrl(".").
function scriptPath(pluginDir, name) {
    var d = String(pluginDir || "")
    if (d.length && d.charAt(d.length - 1) === "/") d = d.substring(0, d.length - 1)
    return d + "/scripts/" + name
}

// Nom court de projet = dernier segment du cwd (ce qui s'affiche groupé dans le panneau).
function projectName(cwd) {
    var s = String(cwd || "").replace(/\/+$/, "")
    if (!s.length) return "?"
    var i = s.lastIndexOf("/")
    return i === -1 ? s : s.substring(i + 1)
}

// Découpe la commande de terminal configurée ("kitty -e") en argv.
function terminalArgs(cmd) {
    var t = String(cmd || "kitty -e").trim()
    return t.length ? t.split(/\s+/) : ["kitty", "-e"]
}

// Âge lisible depuis un ISO-8601 ou un epoch-ms, relatif à `nowMs`.
function relAge(when, nowMs) {
    var t = 0
    if (typeof when === "number") t = when
    else if (when) { t = Date.parse(when); if (isNaN(t)) return "" }
    else return ""
    var sec = Math.max(0, Math.floor((nowMs - t) / 1000))
    if (sec < 60) return sec + "s"
    var m = Math.floor(sec / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h" + (m % 60 ? " " + (m % 60) + "m" : "")
    var d = Math.floor(h / 24)
    return d + "j" + (h % 24 ? " " + (h % 24) + "h" : "")
}
