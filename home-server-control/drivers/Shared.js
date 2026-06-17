.pragma library

// Helpers partagés par tous les drivers (HSR, Docker, futur gcloud).
// QML-free : aucun accès à Qt / Logger / Style. Les drivers retournent des données
// pures ; toute I/O (Process, toasts, logs) reste dans Main.qml.

// Quote un argument pour un shell POSIX (single-quote safe).
function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

// ── Seam local vs SSH ───────────────────────────────────────────────────────
// Les drivers construisent UNE chaîne shell (`remoteStr`) puis appellent wrap().
// En local (sshAlias vide) : `sh -c '<remoteStr>'`. En SSH : `ssh <opts> <alias> '<remoteStr>'`.
// Comportement identique des deux côtés (le snippet host-info et les pipelines docker
// tournent sous un shell dans les deux cas). `sshBase` est fourni par Main (options
// ControlMaster) pour garder ce module QML-free.
function isLocal(h) { return !h || !h.sshAlias || !String(h.sshAlias).trim() }

function wrap(h, sshBase, remoteStr) {
    if (isLocal(h)) return ["sh", "-c", remoteStr]
    return ["ssh"].concat(sshBase || []).concat([h.sshAlias, remoteStr])
}

// Variante interactive (terminal) : ssh -t pour allouer un TTY, login shell en local.
function wrapInteractive(h, remoteStr) {
    if (isLocal(h)) return ["sh", "-lc", remoteStr]
    return ["ssh", "-t", h.sshAlias, remoteStr]
}

// ── host-info : snippet POSIX sh + /proc (busybox-safe) ─────────────────────
// Produit le sous-ensemble de hostInfo lu par le Panel :
//   { hostname, mem:{usedPct}, disks:[{usedPct}], loadavg:[3], uptimeSeconds }
function hostInfoRemoteStr() {
    return [
        'H=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo "?")',
        'MT=$(awk \'/^MemTotal:/{print $2}\' /proc/meminfo)',
        'MA=$(awk \'/^MemAvailable:/{print $2}\' /proc/meminfo)',
        'MP=$(awk -v t="$MT" -v a="$MA" \'BEGIN{if(t>0)printf "%.1f",(t-a)/t*100; else printf "null"}\')',
        'DP=$(df -P / | awk \'NR==2{gsub("%","",$5); print $5}\')',
        'read U _ < /proc/uptime',
        'read L1 L2 L3 _ < /proc/loadavg',
        'printf \'{"hostname":"%s","mem":{"usedPct":%s},"disks":[{"usedPct":%s}],"loadavg":[%s,%s,%s],"uptimeSeconds":%s}\\n\''
            + ' "$H" "$MP" "${DP:-null}" "$L1" "$L2" "$L3" "${U%%.*}"'
    ].join("; ")
}

// ── Traefik : extrait les URLs des labels d'un conteneur ─────────────────────
// labels : map { "traefik.http.routers.<x>.rule": "Host(`a`) || Host(`b`)", ... }
function traefikUrls(labels) {
    var urls = []
    if (!labels) return urls
    var re = /Host\(`([^`]+)`\)/g
    for (var k in labels) {
        if (k.indexOf("traefik.http.routers.") !== 0) continue
        if (k.lastIndexOf(".rule") !== k.length - 5) continue   // endsWith ".rule"
        var v = String(labels[k]), m
        re.lastIndex = 0
        while ((m = re.exec(v)) !== null) {
            var u = "https://" + m[1]
            if (urls.indexOf(u) === -1) urls.push(u)
        }
    }
    return urls
}

// JSON.parse robuste : renvoie `fallback` en cas d'erreur.
function safeJson(text, fallback) {
    try { return JSON.parse(text || "") } catch (e) { return fallback }
}
