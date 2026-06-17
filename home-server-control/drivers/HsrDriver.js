.pragma library
.import "Shared.js" as Shared

// Driver Home-Server-Runner : pilote `manager.py` (backend privé, git-aware).
// Toutes les commandes renvoient du JSON (--json), parsé en passthrough.

function _mgr(h, args) {
    var q = args.map(Shared.shq).join(" ")
    // `cd` dans le repo : manager.py lit config.yaml / projects en chemins relatifs.
    // (~ développé par le shell distant car laissé non quoté.)
    return "cd " + (h.hsrPath || "~/Home-Server-Runner") + " && python3 manager.py " + q + " --json"
}

// ── Builders de commandes (renvoient un argv pour Process.command) ───────────
function listCommand(h, sshBase, fetch) {
    return Shared.wrap(h, sshBase, _mgr(h, fetch ? ["status"] : ["status", "--no-fetch"]))
}

function hostInfoCommand(h, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, ["host-info"]))
}

// Logs / shell : manager.py n'est pas impliqué, on parle à docker directement.
function logsCommand(h, container, tail, sshBase) {
    return Shared.wrap(h, sshBase, "docker logs -f --tail " + tail + " " + Shared.shq(container))
}

function logsTerminalArgv(h, container, tail) {
    return Shared.wrapInteractive(h, "docker logs -f --tail " + tail + " " + Shared.shq(container))
}

function shellCommand(h, container) {
    return Shared.wrapInteractive(h, "docker exec -it " + Shared.shq(container) + " sh -lc 'bash || sh'")
}

function serviceActionCommand(h, pid, svc, container, action, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, ["service", pid, svc, action]))
}

function projectActionCommand(h, pid, action, containers, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, ["project", pid, action]))
}

// Features git-aware exclusives HSR.
function checkUpdatesCommand(h, pid, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, ["update", pid, "--check-only"]))
}
function updateCommand(h, pid, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, ["update", pid]))
}
function deployCommand(h, pid, full, sshBase) {
    return Shared.wrap(h, sshBase, _mgr(h, full ? ["deploy", pid, "--full"] : ["deploy", pid]))
}

// ── Parsers : manager.py renvoie déjà le schéma normalisé ───────────────────
function parseList(text) {
    var a = Shared.safeJson(text, null)
    if (a === null) return { __error__: "parse" }
    return Array.isArray(a) ? a : { __error__: "shape" }
}
function parseHostInfo(text) { return Shared.safeJson(text, {}) }

// ── Capacités : HSR débloque tout ───────────────────────────────────────────
var capabilities = {
    update: true, deploy: true, checkUpdates: true, gitBehind: true,
    logs: true, shell: true, start: true, stop: true, restart: true,
    restartAll: true, hostInfo: true, mutate: true
}
