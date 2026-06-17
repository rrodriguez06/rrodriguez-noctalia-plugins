.pragma library
.import "Shared.js" as Shared

// Driver Docker brut : reconstruit le schéma normalisé à partir de `docker inspect`,
// sans dépendre de Home-Server-Runner. Regroupe les conteneurs par projet docker compose
// (label com.docker.compose.project) avec un bucket synthétique "standalone".
// Aucune feature git-aware (update/deploy/behind) : voir `capabilities`.

// ── Liste : un aller-retour, NDJSON via inspect ─────────────────────────────
// `{{json .}}` (template par-valeur) est universel (≥ Docker 17). On évite
// `docker ps --format json` dont les Labels sont aplatis (virgules des règles Traefik
// illisibles). Sentinelle JSON si docker absent / daemon down → reachable=false côté Main.
function _listRemoteStr() {
    return [
        'command -v docker >/dev/null 2>&1 || { echo \'{"__hsc_error__":"no-docker"}\'; exit 0; }',
        'docker info >/dev/null 2>&1 || { echo \'{"__hsc_error__":"daemon-down"}\'; exit 0; }',
        'ids=$(docker ps -aq 2>/dev/null); [ -n "$ids" ] && docker inspect --format "{{json .}}" $ids || true'
    ].join("\n")
}

function listCommand(h, sshBase, fetch) {
    return Shared.wrap(h, sshBase, _listRemoteStr())
}

function hostInfoCommand(h, sshBase) {
    return Shared.wrap(h, sshBase, Shared.hostInfoRemoteStr())
}

// Logs / shell : identiques au mode HSR (on parle à docker directement).
function logsCommand(h, container, tail, sshBase) {
    return Shared.wrap(h, sshBase, "docker logs -f --tail " + tail + " " + Shared.shq(container))
}
function logsTerminalArgv(h, container, tail) {
    return Shared.wrapInteractive(h, "docker logs -f --tail " + tail + " " + Shared.shq(container))
}
function shellCommand(h, container) {
    return Shared.wrapInteractive(h, "docker exec -it " + Shared.shq(container) + " sh -lc 'bash || sh'")
}

// Action sur un service = action sur SON conteneur (les standalone n'ont pas de service).
function serviceActionCommand(h, pid, svc, container, action, sshBase) {
    return Shared.wrap(h, sshBase, "docker " + action + " " + Shared.shq(container))
}

// Restart de tout un projet : compose v2 par label de projet, fallback restart par nom
// (couvre compose v1, docker compose absent, et le bucket "standalone").
function projectActionCommand(h, pid, action, containers, sshBase) {
    var names = (containers || []).map(Shared.shq).join(" ")
    var rs
    if (pid === "standalone" || !names) {
        rs = names ? ("docker " + action + " " + names) : "true"
    } else {
        rs = "docker compose -p " + Shared.shq(pid) + " " + action + " 2>/dev/null"
           + " || docker " + action + " " + names
    }
    return Shared.wrap(h, sshBase, rs)
}

// ── Parsers ──────────────────────────────────────────────────────────────────
function _status(c) {
    return String((c.State && c.State.Status) || "missing").toLowerCase()  // running|exited|created|...
}
function _health(c) {
    var s = c.State && c.State.Health && c.State.Health.Status
    if (!s) return "none"                                                   // pas de healthcheck
    return String(s).toLowerCase()                                          // healthy|unhealthy|starting
}
function _ports(c) {
    var out = [], seen = {}
    var ps = (c.NetworkSettings && c.NetworkSettings.Ports) || {}
    for (var key in ps) {                          // key ex. "80/tcp"
        var binds = ps[key]
        if (!binds || !binds.length) continue      // ports exposés non publiés : ignorés (comme manager.py)
        var cport = key.split("/")[0]
        for (var i = 0; i < binds.length; i++) {
            var hp = binds[i].HostPort
            if (!hp) continue
            var label = hp + "->" + cport
            if (!seen[label]) { seen[label] = true; out.push(label) }  // dédupe IPv4/IPv6
        }
    }
    return out
}

function parseList(text) {
    text = (text || "").trim()
    if (!text) return []
    if (text.indexOf("__hsc_error__") !== -1) {
        var e = Shared.safeJson(text.split(/\r?\n/)[0], null)
        if (e && e.__hsc_error__) return { __error__: e.__hsc_error__ }
    }
    var byProject = {}
    var lines = text.split(/\r?\n/)
    for (var li = 0; li < lines.length; li++) {
        var line = lines[li].trim()
        if (!line) continue
        var c = Shared.safeJson(line, null)
        if (!c) continue
        var labels = (c.Config && c.Config.Labels) || {}
        var proj = labels["com.docker.compose.project"] || "standalone"
        var cname = c.Name ? c.Name.replace(/^\//, "") : ""
        var svc = labels["com.docker.compose.service"] || cname || "?"
        if (!byProject[proj])
            byProject[proj] = {
                id: proj,
                mode: (proj === "standalone" ? "standalone" : "compose"),
                services: [], repos: []
            }
        byProject[proj].services.push({
            name: svc,
            containerName: cname,
            status: _status(c),
            health: _health(c),
            build: "",            // pas de contexte de build connu en mode docker
            repoBehind: 0,         // pas de git
            ports: _ports(c),
            urls: Shared.traefikUrls(labels)
        })
    }
    // Ordre stable : standalone en dernier, projets alpha, services alpha.
    var keys = Object.keys(byProject).sort(function (a, b) {
        if (a === "standalone") return 1
        if (b === "standalone") return -1
        return a < b ? -1 : (a > b ? 1 : 0)
    })
    var out = []
    for (var ki = 0; ki < keys.length; ki++) {
        var p = byProject[keys[ki]]
        p.services.sort(function (x, y) { return x.name < y.name ? -1 : (x.name > y.name ? 1 : 0) })
        out.push(p)
    }
    return out
}

function parseHostInfo(text) { return Shared.safeJson(text, {}) }

// ── Capacités : pas de git-aware (update/deploy/checkUpdates/gitBehind = false) ──
var capabilities = {
    update: false, deploy: false, checkUpdates: false, gitBehind: false,
    logs: true, shell: true, start: true, stop: true, restart: true,
    restartAll: true, hostInfo: true, mutate: true
}
