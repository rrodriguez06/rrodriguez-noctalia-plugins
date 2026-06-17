import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "drivers/Shared.js" as Shared
import "drivers/HsrDriver.js" as Hsr
import "drivers/DockerDriver.js" as Docker
import "drivers/Registry.js" as Registry

// Couche logique non-visuelle. Pilote un home server via un « driver » résolu par hôte :
//   • docker  : inspection/contrôle des conteneurs avec le seul CLI `docker` (défaut public),
//   • hsr     : Home-Server-Runner (manager.py) — features git-aware (update/deploy),
//   • auto    : sonde la présence de manager.py et choisit docker ou hsr.
// Cible locale (alias SSH vide) OU distante (~/.ssh/config). Aucun secret stocké.
Item {
    id: root
    property var pluginApi: null

    // ── État exposé au Panel / BarWidget ────────────────────────────────────
    property var statusData: []           // tableau normalisé renvoyé par le driver (hôte actif)
    property var hostInfo: ({})           // objet host-info (hôte actif)
    property var planByPid: ({})          // pid -> plan d'`update --check-only` (HSR)
    property bool reachable: true         // dernier poll de l'hôte actif a-t-il réussi ?
    property var expandedByPid: ({})      // pid -> bool : état déplié mémorisé (replié par défaut)
    property var svcModels: ({})          // pid -> ListModel des services (MAJ en place, anti-blink)

    // Mode résolu par hôte (clé = alias SSH ou "__local__") : évite de re-sonder à chaque poll.
    property var resolvedMode: ({})

    // Résumé pour la pastille de barre.
    property int barDown: 0
    property int barUnhealthy: 0
    property int barTotal: 0
    property int barBehind: 0

    // Modèle résumé par projet pour la NListView du Panel.
    property ListModel projectsModel: ListModel {}

    // Logs en direct (overlay du Panel).
    property ListModel logModel: ListModel {}
    property string logTitle: ""
    property string logContainer: ""      // conteneur en cours de stream (pour « ouvrir en grand »)

    property bool panelOpen: false
    property var _prevStates: ({})        // watchdog : dernier état connu par "pid/svc"
    property string _planPending: ""

    // Options SSH : multiplexing pour que les polls réutilisent une connexion persistante.
    readonly property var sshBase: [
        "-o", "ConnectTimeout=6",
        "-o", "BatchMode=yes",
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=/tmp/hsrc-%r@%h:%p",
        "-o", "ControlPersist=60s"
    ]

    // ── Réglages / hôtes ─────────────────────────────────────────────────────
    function settings() { return root.pluginApi?.pluginSettings ?? null }

    function hostAt(i) {
        var hs = root.settings()?.hosts ?? []
        return (i >= 0 && i < hs.length) ? hs[i] : null
    }

    function activeHost() {
        var hs = root.settings()?.hosts ?? []
        var i = root.settings()?.activeHostIndex ?? 0
        if (i < 0 || i >= hs.length) i = 0
        return hs.length ? hs[i] : null
    }

    function isReadOnly() { return root.activeHost()?.readOnly ?? false }

    // ── Résolution du driver ─────────────────────────────────────────────────
    function hostKey(h) {
        return (h && h.sshAlias && String(h.sshAlias).trim()) ? String(h.sshAlias).trim() : "__local__"
    }

    // Mode effectif : explicite (hsr/docker) ou résolu par la sonde (auto -> docker par défaut).
    function effectiveMode(h) {
        if (!h) return "docker"
        var requested = h.mode || "auto"
        if (requested === "hsr" || requested === "docker") return requested
        return root.resolvedMode[root.hostKey(h)] || "docker"
    }

    function driverFor(h) { return (root.effectiveMode(h) === "hsr") ? Hsr : Docker }

    function capabilities() { return Registry.capabilitiesFor(root.effectiveMode(root.activeHost())) }

    // Sonde auto : résout le mode de l'hôte puis re-poll. Renvoie false tant que la sonde tourne
    // (les appelants — pollStatus/pollHostInfo — diffèrent ; onExited relance le poll).
    function ensureResolved(h) {
        if (!h) return false
        if ((h.mode || "auto") !== "auto") return true
        var k = root.hostKey(h)
        if (root.resolvedMode[k]) return true
        if (probeProc.running && probeProc.forKey === k) return false
        probeProc.running = false
        probeProc.forKey = k
        probeProc.command = Registry.probeCommand(h, root.sshBase)
        probeProc.running = true
        return false
    }

    Process {
        id: probeProc
        property string forKey: ""
        stdout: StdioCollector { id: probeOut }
        onExited: code => {
            var sig = (probeOut.text || "").trim()
            var mode = (code === 0 && sig.indexOf("HSR") !== -1) ? "hsr" : "docker"
            var m = root.resolvedMode
            m[probeProc.forKey] = mode
            root.resolvedMode = Object.assign({}, m)   // force le binding (capabilities, caps du Panel)
            root.pollStatus(true)
            root.pollHostInfo()
        }
    }

    // ── Lookups schéma normalisé ─────────────────────────────────────────────
    function servicesOf(pid) {
        for (var i = 0; i < root.statusData.length; i++)
            if (root.statusData[i].id === pid)
                return root.statusData[i].services || []
        return []
    }

    function reposOf(pid) {
        for (var i = 0; i < root.statusData.length; i++)
            if (root.statusData[i].id === pid)
                return root.statusData[i].repos || []
        return []
    }

    function _containerFor(pid, svc) {
        var s = root.servicesOf(pid)
        for (var i = 0; i < s.length; i++)
            if (s[i].name === svc) return s[i].containerName || ""
        return ""
    }

    function _containersOf(pid) {
        return root.servicesOf(pid)
            .map(function (s) { return s.containerName })
            .filter(function (c) { return c && c.length })
    }

    // ── Lecture : status ──────────────────────────────────────────────────────
    Process {
        id: statusProc
        property var _driver: null
        stdout: StdioCollector {
            onStreamFinished: {
                var drv = statusProc._driver || root.driverFor(root.activeHost())
                var arr = drv.parseList(this.text || "")
                if (arr && arr.__error__) {
                    root.reachable = false
                    Logger.w("HSC", "list error: " + arr.__error__)
                    return
                }
                if (!Array.isArray(arr)) { root.reachable = false; return }
                root.applyStatus(arr)
                root.runWatchdog()
            }
        }
        onExited: code => { if (code !== 0) { root.reachable = false } }
    }

    function pollStatus(fetch) {
        var h = root.activeHost()
        if (!h) { root.reachable = false; return }
        if (!root.ensureResolved(h)) return
        var drv = root.driverFor(h)
        statusProc._driver = drv
        statusProc.running = false
        statusProc.command = drv.listCommand(h, root.sshBase, fetch)
        statusProc.running = true
    }

    function applyStatus(arr) {
        root.statusData = arr
        var down = 0, unhealthy = 0, total = 0, behind = 0
        for (var i = 0; i < arr.length; i++) {
            var p = arr[i]
            var svcs = p.services || []
            var pdown = 0, punhealthy = 0
            for (var j = 0; j < svcs.length; j++) {
                total++
                if (svcs[j].status !== "running") { down++; pdown++ }
                if (svcs[j].health === "unhealthy") { unhealthy++; punhealthy++ }
            }
            var pbehind = 0
            var repos = p.repos || []
            for (var k = 0; k < repos.length; k++) pbehind += (repos[k].behind || 0)
            behind += pbehind
            var row = {
                "pid": p.id, "mode": p.mode || "",
                "serviceCount": svcs.length, "downCount": pdown,
                "unhealthyCount": punhealthy, "behind": pbehind
            }
            // MAJ EN PLACE (pas de clear) : les délégués persistent -> aucun blink,
            // l'état déplié (mémorisé par pid) et l'état « confirmation » des lignes sont conservés.
            if (i < root.projectsModel.count) root.projectsModel.set(i, row)
            else root.projectsModel.append(row)
            root._syncServiceModel(p.id, svcs)
        }
        while (root.projectsModel.count > arr.length)
            root.projectsModel.remove(root.projectsModel.count - 1)

        root.barDown = down; root.barUnhealthy = unhealthy
        root.barTotal = total; root.barBehind = behind
        root.reachable = true
    }

    // ListModel de services par projet, mis à jour EN PLACE (set/append/remove) : les lignes
    // ne sont jamais recréées au poll -> pas de blink, pas de perte d'état de confirmation.
    function svcModelFor(pid) {
        if (!root.svcModels[pid])
            root.svcModels[pid] = Qt.createQmlObject('import QtQuick; ListModel {}', root)
        return root.svcModels[pid]
    }

    function _syncServiceModel(pid, svcs) {
        var m = root.svcModelFor(pid)
        for (var i = 0; i < svcs.length; i++) {
            var s = svcs[i]
            var urls = s.urls || []
            var row = {
                "name": s.name || "",
                "containerName": s.containerName || "",
                "status": s.status || "",
                "health": s.health || "none",
                "build": s.build || "",
                "repoBehind": s.repoBehind || 0,
                "ports": (s.ports || []).join(", "),
                "url0": urls.length ? urls[0] : "",
                "hasUrl": urls.length > 0
            }
            if (i < m.count) m.set(i, row)
            else m.append(row)
        }
        while (m.count > svcs.length) m.remove(m.count - 1)
    }

    // État déplié/replié mémorisé par projet (survit aux polls et à la réouverture du panneau).
    function isExpanded(pid) { return root.expandedByPid[pid] === true }
    function toggleExpanded(pid) {
        var m = root.expandedByPid
        m[pid] = !(m[pid] === true)
        root.expandedByPid = Object.assign({}, m)
    }

    // ── Watchdog : notifie quand un service tombe ────────────────────────────
    function runWatchdog() {
        var cur = {}
        for (var i = 0; i < root.statusData.length; i++) {
            var p = root.statusData[i]
            var svcs = p.services || []
            for (var j = 0; j < svcs.length; j++) {
                var s = svcs[j]
                cur[p.id + "/" + s.name] = { "status": s.status, "health": s.health, "container": s.containerName }
            }
        }
        var hadBaseline = Object.keys(root._prevStates).length > 0
        var notify = root.settings()?.notifyOnStateChange ?? true
        if (hadBaseline && notify) {
            for (var key in cur) {
                var c = cur[key]
                var bad = c.status === "exited" || c.status === "dead" || c.health === "unhealthy"
                var pv = root._prevStates[key]
                var wasBad = pv ? (pv.status === "exited" || pv.status === "dead" || pv.health === "unhealthy") : false
                if (bad && !wasBad)
                    root.notifyDown(key, c)
            }
        }
        root._prevStates = cur
    }

    function notifyDown(key, c) {
        var label = (c.health === "unhealthy") ? "unhealthy" : c.status
        ToastService.showError("⚠ " + key + " : " + label)
        Quickshell.execDetached(["notify-send", "-u", "critical", "Home Server", key + " — " + label])
    }

    // ── host-info ───────────────────────────────────────────────────────────
    Process {
        id: hostInfoProc
        property var _driver: null
        stdout: StdioCollector {
            onStreamFinished: {
                var drv = hostInfoProc._driver || root.driverFor(root.activeHost())
                root.hostInfo = drv.parseHostInfo(this.text || "{}")
            }
        }
    }

    function pollHostInfo() {
        var h = root.activeHost()
        if (!h) return
        if (!root.ensureResolved(h)) return
        var drv = root.driverFor(h)
        hostInfoProc._driver = drv
        hostInfoProc.running = false
        hostInfoProc.command = drv.hostInfoCommand(h, root.sshBase)
        hostInfoProc.running = true
    }

    // ── update --check-only (plan de MAJ, HSR uniquement) ─────────────────────
    Process {
        id: planProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { var plan = JSON.parse(this.text || "{}") }
                catch (e) { Logger.w("HSC", "plan parse error: " + e); return }
                var m = root.planByPid
                m[root._planPending] = plan
                root.planByPid = m
                root.planByPid = Object.assign({}, m)   // force le binding
                if (plan.noop)
                    ToastService.showNotice("Aucune mise à jour pour " + root._planPending)
                else if (plan.fullUp)
                    ToastService.showNotice(root._planPending + " : déploiement complet requis")
                else
                    ToastService.showNotice("MAJ dispo " + root._planPending + " : " + (plan.rebuild || []).join(", "))
            }
        }
    }

    function checkUpdates(pid) {
        var h = root.activeHost()
        if (!h || !root.capabilities().checkUpdates) return
        var drv = root.driverFor(h)
        root._planPending = pid
        planProc.running = false
        planProc.command = drv.checkUpdatesCommand(h, pid, root.sshBase)
        planProc.running = true
    }

    // ── Actions mutantes (capture + toast), comme hypr-layout ───────────────
    Component {
        id: actionComp
        Process {
            property string fallbackMsg: ""
            stdout: StdioCollector { id: aOut }
            stderr: StdioCollector { id: aErr }
            onExited: code => {
                if (code === 0)
                    ToastService.showNotice(fallbackMsg || (aOut.text || "").trim())
                else
                    ToastService.showError((aErr.text || aOut.text || "").trim() || ("erreur (code " + code + ")"))
                root.refreshSoon()
                destroy()
            }
        }
    }

    function dispatch(command, busyMsg, fallbackMsg) {
        var showToasts = root.settings()?.showToasts ?? true
        if (showToasts && busyMsg) ToastService.showNotice(busyMsg)
        var p = actionComp.createObject(root, { command: command, fallbackMsg: fallbackMsg || "" })
        if (p) p.running = true
        else Quickshell.execDetached(command)
    }

    Timer { id: refreshTimer; interval: 1500; onTriggered: root.pollStatus(false) }
    function refreshSoon() { refreshTimer.restart() }

    function serviceAction(pid, svc, action) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        var h = root.activeHost(); if (!h) return
        var drv = root.driverFor(h)
        var container = root._containerFor(pid, svc)
        root.dispatch(drv.serviceActionCommand(h, pid, svc, container, action, root.sshBase),
                      action + " " + svc + "…", "✓ " + action + " " + svc)
    }

    function updateProject(pid) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        if (!root.capabilities().update) return
        var h = root.activeHost(); if (!h) return
        var drv = root.driverFor(h)
        root.dispatch(drv.updateCommand(h, pid, root.sshBase),
                      "Mise à jour de « " + pid + " »…", "✓ " + pid + " à jour")
    }

    function deployProject(pid, full) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        if (!root.capabilities().deploy) return
        var h = root.activeHost(); if (!h) return
        var drv = root.driverFor(h)
        root.dispatch(drv.deployCommand(h, pid, full, root.sshBase),
                      "Déploiement de « " + pid + " »…", "✓ " + pid + " déployé")
    }

    // Relance TOUS les conteneurs d'un projet (sans rebuild).
    function projectAction(pid, action) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        var h = root.activeHost(); if (!h) return
        var drv = root.driverFor(h)
        var containers = root._containersOf(pid)
        root.dispatch(drv.projectActionCommand(h, pid, action, containers, root.sshBase),
                      action + " « " + pid + " »…", "✓ " + pid + " : " + action)
    }

    // ── Logs en direct ───────────────────────────────────────────────────────
    Process {
        id: logProc
        stdout: SplitParser { onRead: line => root.appendLog(line) }
        stderr: SplitParser { onRead: line => root.appendLog(line) }
    }

    function streamLogs(svc, container) {
        var h = root.activeHost()
        if (!h || !container) return
        var drv = root.driverFor(h)
        var tail = root.settings()?.logTailLines ?? 200
        logProc.running = false
        root.logModel.clear()
        root.logTitle = svc
        root.logContainer = container
        logProc.command = drv.logsCommand(h, container, tail, root.sshBase)
        logProc.running = true
    }

    function stopLogs() { logProc.running = false }

    // Ouvre les logs « en grand » dans un vrai terminal (suit en direct, scrollback complet).
    function openLogsInTerminal() {
        var h = root.activeHost()
        if (!h || !root.logContainer) return
        var drv = root.driverFor(h)
        var tail = root.settings()?.logTailLines ?? 200
        Quickshell.execDetached(root._terminalArgs().concat(drv.logsTerminalArgv(h, root.logContainer, tail)))
    }

    function appendLog(line) {
        root.logModel.append({ "line": line })
        while (root.logModel.count > 2000) root.logModel.remove(0)
    }

    // ── Shell interactif (terminal) ──────────────────────────────────────────
    function _terminalArgs() {
        var t = (root.settings()?.terminalCommand ?? "kitty -e").trim()
        return t.length ? t.split(/\s+/) : ["kitty", "-e"]
    }

    function openShell(container) {
        var h = root.activeHost()
        if (!h || !container) return
        var drv = root.driverFor(h)
        Quickshell.execDetached(root._terminalArgs().concat(drv.shellCommand(h, container)))
    }

    // « Ouvrir un shell sur l'hôte » : terminal local simple, ou ssh -t en distant.
    function openHostSsh() {
        var h = root.activeHost(); if (!h) return
        if (Shared.isLocal(h))
            Quickshell.execDetached(root._terminalArgs())
        else
            Quickshell.execDetached(root._terminalArgs().concat(["ssh", "-t", h.sshAlias]))
    }

    function openUrl(url) {
        if (url) Quickshell.execDetached(["xdg-open", url])
    }

    // ── Test de connexion (Settings) ─────────────────────────────────────────
    Process {
        id: testProc
        property var _driver: null
        stdout: StdioCollector { id: tOut }
        stderr: StdioCollector { id: tErr }
        onExited: code => {
            if (code === 0) {
                var drv = testProc._driver || root.driverFor(root.activeHost())
                var info = drv.parseHostInfo(tOut.text || "{}")
                ToastService.showNotice("✓ Connecté : " + (info.hostname || "ok"))
            } else {
                ToastService.showError("Échec connexion : " + ((tErr.text || "").trim() || ("code " + code)))
            }
        }
    }

    function testConnection(index) {
        var h = (index === undefined) ? root.activeHost() : root.hostAt(index)
        if (!h) { ToastService.showError("Aucun hôte configuré"); return }
        ToastService.showNotice("Test de " + (h.name || h.sshAlias || "local") + "…")
        // host-info fonctionne dans les deux drivers ; en auto pré-sonde, le défaut docker convient.
        var drv = root.driverFor(h)
        testProc._driver = drv
        testProc.running = false
        testProc.command = drv.hostInfoCommand(h, root.sshBase)
        testProc.running = true
    }

    // ── Sélection d'hôte ─────────────────────────────────────────────────────
    function selectHost(index) {
        if (!root.settings()) return
        var hs = root.settings().hosts || []
        if (index < 0 || index >= hs.length) return
        root.settings().activeHostIndex = index
        root.pluginApi.saveSettings()
        root._prevStates = ({})   // reset du watchdog au changement d'hôte
        root.statusData = []
        root.projectsModel.clear()
        root.svcModels = ({})         // les anciens ListModel deviennent collectables
        root.expandedByPid = ({})     // repli par défaut sur le nouvel hôte
        root.hostInfo = ({})
        root.pollStatus(true)         // ensureResolved() sonde le nouvel hôte si besoin
        root.pollHostInfo()
    }

    // ── Cycle de vie panel + polling ─────────────────────────────────────────
    function setPanelOpen(open) {
        root.panelOpen = open
        if (open) { root.pollStatus(true); root.pollHostInfo() }
    }

    Timer {
        id: pollTimer
        repeat: true
        running: true
        interval: root.panelOpen ? (root.settings()?.pollIntervalOpenMs ?? 8000)
                                 : (root.settings()?.pollIntervalIdleMs ?? 45000)
        onTriggered: root.pollStatus(false)
    }

    // Quand le panel est ouvert : rafraîchit la dérive git périodiquement (avec fetch, HSR).
    Timer {
        id: driftTimer
        repeat: true
        running: root.panelOpen && (root.settings()?.driftFetchOnOpen ?? true)
        interval: 60000
        onTriggered: root.pollStatus(true)
    }

    Component.onCompleted: root.pollStatus(false)

    // ── IPC : qs -c noctalia-shell ipc call plugin:home-server-control <fn> ──
    IpcHandler {
        target: "plugin:home-server-control"
        function togglePanel() {
            if (root.pluginApi)
                root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
        }
        function refresh() { root.pollStatus(true) }
        function selectHost(i: int) { root.selectHost(i) }
        function restart(pid: string, svc: string) { root.serviceAction(pid, svc, "restart") }
        function stop(pid: string, svc: string) { root.serviceAction(pid, svc, "stop") }
        function start(pid: string, svc: string) { root.serviceAction(pid, svc, "start") }
        function update(pid: string) { root.updateProject(pid) }
    }
}
