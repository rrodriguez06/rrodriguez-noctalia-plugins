.pragma library
.import "Shared.js" as Shared

// Driver gcloud / Cloud Run : reconstruit le schéma normalisé à partir de
// `gcloud run services list --format=json` (Knative). Regroupe les services par RÉGION.
// Auth = compte gcloud ambiant : SA (*.gserviceaccount.com) → lecture seule, sinon user →
// inscriptible. v1 = lecture seule (status + logs) ; la machinerie de caps dynamiques est en place
// (voir capsFromIdentity) pour allumer des actions plus tard.

function _flags(h) {
    var f = ""
    if (h && h.project) f += " --project " + Shared.shq(h.project)
    if (h && h.region) f += " --region " + Shared.shq(h.region)
    return f
}

// ── Liste : Knative JSON, toutes régions si region vide ─────────────────────
// Sentinelle si gcloud absent. Un échec d'auth/projet → stderr + exit≠0 → Main: reachable=false.
function listCommand(h, sshBase, fetch) {
    var rs = "command -v gcloud >/dev/null 2>&1 || { echo '{\"__hsc_error__\":\"no-gcloud\"}'; exit 0; }\n"
           + "gcloud run services list" + _flags(h) + " --format=json"
    return Shared.wrap(h, sshBase, rs)
}

function parseList(text) {
    text = (text || "").trim()
    if (!text) return []
    if (text.indexOf("__hsc_error__") !== -1) {
        var e = Shared.safeJson(text.split(/\r?\n/)[0], null)
        if (e && e.__hsc_error__) return { __error__: e.__hsc_error__ }
    }
    var arr = Shared.safeJson(text, null)
    if (!Array.isArray(arr)) return { __error__: "parse" }

    var byRegion = {}
    for (var i = 0; i < arr.length; i++) {
        var s = arr[i]
        if (!s || !s.metadata) continue
        var md = s.metadata, st = s.status || {}
        var labels = md.labels || {}
        var region = labels["cloud.googleapis.com/location"] || "unknown"

        // Condition Ready → status/health normalisés.
        var ready = "Unknown"
        var conds = st.conditions || []
        for (var c = 0; c < conds.length; c++)
            if (conds[c].type === "Ready") { ready = conds[c].status; break }
        var status, health
        if (ready === "True") { status = "running"; health = "none" }
        else if (ready === "False") { status = "exited"; health = "unhealthy" }
        else { status = "running"; health = "starting" }   // Unknown = en cours de déploiement

        if (!byRegion[region])
            byRegion[region] = { id: region, mode: "cloudrun", services: [], repos: [] }
        byRegion[region].services.push({
            name: md.name || "?",
            containerName: md.name || "",          // cible pour les logs
            status: status,
            health: health,
            build: st.latestReadyRevisionName || "",
            repoBehind: 0,
            ports: [],
            urls: st.url ? [st.url] : []
        })
    }

    var keys = Object.keys(byRegion).sort(function (a, b) {
        return a < b ? -1 : (a > b ? 1 : 0)
    })
    var out = []
    for (var ki = 0; ki < keys.length; ki++) {
        var p = byRegion[keys[ki]]
        p.services.sort(function (x, y) { return x.name < y.name ? -1 : (x.name > y.name ? 1 : 0) })
        out.push(p)
    }
    return out
}

// ── Identité / caps dynamiques (compte ambiant) ─────────────────────────────
// Sonde rapide (pas d'appel API). Main appelle ceci via ensureCaps (non-bloquant).
function identityProbeCommand(h, sshBase) {
    return Shared.wrap(h, sshBase, "gcloud config get-value account 2>/dev/null")
}

function capsFromIdentity(text, h) {
    var lines = (text || "").split(/\r?\n/).map(function (s) { return s.trim() }).filter(Boolean)
    var acct = lines.length ? lines[lines.length - 1] : ""
    if (acct === "(unset)") acct = ""
    var isSA = /\.gserviceaccount\.com$/.test(acct)
    var writable = !!acct && !isSA && !(h && h.readOnly)
    return {
        caps: {
            update: false, deploy: false, checkUpdates: false, gitBehind: false,
            logs: true, shell: false, start: false, stop: false, restart: false,
            restartAll: false, hostInfo: true,
            mutate: writable   // v1 : aucune action câblée ; les futures s'y branchent
        },
        identity: { account: acct || "?", writable: writable, kind: isSA ? "sa" : "user" }
    }
}

// Titre = projet (pas de jauges RAM/disque en serverless ; le Panel les masque déjà).
function hostInfoCommand(h, sshBase) {
    return Shared.wrap(h, sshBase, "printf '{\"hostname\":\"%s\"}' " + Shared.shq((h && h.project) || "Cloud Run"))
}
function parseHostInfo(text) { return Shared.safeJson(text, {}) }

// ── Logs Cloud Run via Cloud Logging (one-shot, non-streaming) ──────────────
// Rapidité : `--order=desc` (indexé) + `--limit N` récupère les N entrées les PLUS récentes
// (au lieu de `--order=asc --freshness=1d` qui ramène les plus vieilles et reste vide sur un
// service peu actif). On inverse ensuite avec `tac` pour un affichage chronologique.
//
// Complétude : Cloud Run produit 3 formes de logs et l'ancien format n'en montrait qu'une
// (`textPayload`) → message vide pour le reste. On couvre les trois :
//   • textPayload                — logs stdout/stderr de l'app
//   • jsonPayload.message        — logs structurés
//   • httpRequest.*              — logs de requêtes (method / status / url)
function _logsFormat() {
    return "--format='value[separator=\" \"]("
         + "timestamp.date(format=\"%Y-%m-%dT%H:%M:%S\",tz=\"LOCAL\"),"
         + "severity,textPayload,jsonPayload.message,"
         + "httpRequest.requestMethod,httpRequest.status,httpRequest.requestUrl)'"
}
function _logsRemoteStr(h, container, tail) {
    var filter = "resource.type=cloud_run_revision AND resource.labels.service_name=" + container
    return "gcloud logging read " + Shared.shq(filter)
         + (h && h.project ? " --project " + Shared.shq(h.project) : "")
         + " --limit " + tail + " --order=desc " + _logsFormat()
         + " | tac"
}
function logsCommand(h, container, tail, sshBase) {
    return Shared.wrap(h, sshBase, _logsRemoteStr(h, container, tail))
}
function logsTerminalArgv(h, container, tail) {
    return Shared.wrapInteractive(h, _logsRemoteStr(h, container, tail))
}

// Pas de shell dans Cloud Run.
function shellCommand(h, container) { return null }

// v1 : aucune action d'écriture (gardées off par caps). Builders absents volontairement.

// Caps statiques par défaut (avant résolution de la sonde) : lecture seule.
var capabilities = {
    update: false, deploy: false, checkUpdates: false, gitBehind: false,
    logs: true, shell: false, start: false, stop: false, restart: false,
    restartAll: false, hostInfo: true, mutate: false
}
