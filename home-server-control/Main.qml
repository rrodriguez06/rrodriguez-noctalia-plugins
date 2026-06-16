import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Couche logique non-visuelle : pilote `manager.py` du Home-Server-Runner à distance via SSH.
// Toutes les commandes serveur renvoient du JSON (--json) parsé ici. Aucun secret n'est stocké :
// l'authentification passe par les alias ~/.ssh/config de l'utilisateur.
Item {
    id: root
    property var pluginApi: null

    // ── État exposé au Panel / BarWidget ────────────────────────────────────
    property var statusData: []           // tableau brut renvoyé par `status` (hôte actif)
    property var hostInfo: ({})           // objet `host-info` (hôte actif)
    property var planByPid: ({})          // pid -> plan d'`update --check-only`
    property bool reachable: true         // dernier poll de l'hôte actif a-t-il réussi ?

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

    // ── Helpers SSH / commandes ─────────────────────────────────────────────
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

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

    function remoteMgr(h, args) {
        var q = args.map(root.shq).join(" ")
        return "python3 " + (h.hsrPath || "~/Home-Server-Runner") + "/manager.py " + q + " --json"
    }

    function sshArgv(h, remoteStr) {
        return ["ssh"].concat(root.sshBase).concat([h.sshAlias, remoteStr])
    }

    function mgrArgv(h, args) { return root.sshArgv(h, root.remoteMgr(h, args)) }

    // Services détaillés d'un projet (pour le dépliage du Panel).
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

    // ── Lecture : status ────────────────────────────────────────────────────
    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text || "[]")
                } catch (e) {
                    root.reachable = false
                    Logger.w("HSC", "status parse error: " + e)
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
        var args = fetch ? ["status"] : ["status", "--no-fetch"]
        statusProc.running = false
        statusProc.command = root.mgrArgv(h, args)
        statusProc.running = true
    }

    function applyStatus(arr) {
        root.statusData = arr
        root.projectsModel.clear()
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
            root.projectsModel.append({
                "pid": p.id, "mode": p.mode || "",
                "serviceCount": svcs.length, "downCount": pdown,
                "unhealthyCount": punhealthy, "behind": pbehind
            })
        }
        root.barDown = down; root.barUnhealthy = unhealthy
        root.barTotal = total; root.barBehind = behind
        root.reachable = true
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
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hostInfo = JSON.parse(this.text || "{}") }
                catch (e) { Logger.w("HSC", "host-info parse error: " + e) }
            }
        }
    }

    function pollHostInfo() {
        var h = root.activeHost()
        if (!h) return
        hostInfoProc.running = false
        hostInfoProc.command = root.mgrArgv(h, ["host-info"])
        hostInfoProc.running = true
    }

    // ── update --check-only (plan de MAJ) ────────────────────────────────────
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
        if (!h) return
        root._planPending = pid
        planProc.running = false
        planProc.command = root.mgrArgv(h, ["update", pid, "--check-only"])
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
        root.dispatch(root.mgrArgv(h, ["service", pid, svc, action]),
                      action + " " + svc + "…", "✓ " + action + " " + svc)
    }

    function updateProject(pid) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        var h = root.activeHost(); if (!h) return
        root.dispatch(root.mgrArgv(h, ["update", pid]),
                      "Mise à jour de « " + pid + " »…", "✓ " + pid + " à jour")
    }

    function deployProject(pid, full) {
        if (root.isReadOnly()) { ToastService.showError("Hôte en lecture seule"); return }
        var h = root.activeHost(); if (!h) return
        var args = full ? ["deploy", pid, "--full"] : ["deploy", pid]
        root.dispatch(root.mgrArgv(h, args),
                      "Déploiement de « " + pid + " »…", "✓ " + pid + " déployé")
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
        var tail = root.settings()?.logTailLines ?? 200
        logProc.running = false
        root.logModel.clear()
        root.logTitle = svc
        logProc.command = root.sshArgv(h, "docker logs -f --tail " + tail + " " + root.shq(container))
        logProc.running = true
    }

    function stopLogs() { logProc.running = false }

    function appendLog(line) {
        root.logModel.append({ "line": line })
        while (root.logModel.count > 2000) root.logModel.remove(0)
    }

    // ── SSH interactif (terminal) ────────────────────────────────────────────
    function _terminalArgs() {
        var t = (root.settings()?.terminalCommand ?? "kitty -e").trim()
        return t.length ? t.split(/\s+/) : ["kitty", "-e"]
    }

    function openShell(container) {
        var h = root.activeHost()
        if (!h || !container) return
        Quickshell.execDetached(root._terminalArgs().concat(
            ["ssh", "-t", h.sshAlias, "docker exec -it " + container + " sh -lc 'bash || sh'"]))
    }

    function openHostSsh() {
        var h = root.activeHost(); if (!h) return
        Quickshell.execDetached(root._terminalArgs().concat(["ssh", "-t", h.sshAlias]))
    }

    function openUrl(url) {
        if (url) Quickshell.execDetached(["xdg-open", url])
    }

    // ── Test de connexion (Settings) ─────────────────────────────────────────
    Process {
        id: testProc
        stdout: StdioCollector { id: tOut }
        stderr: StdioCollector { id: tErr }
        onExited: code => {
            if (code === 0) {
                try {
                    var info = JSON.parse(tOut.text || "{}")
                    ToastService.showNotice("✓ Connecté : " + (info.hostname || "ok"))
                } catch (e) { ToastService.showNotice("✓ Connecté") }
            } else {
                ToastService.showError("Échec connexion : " + ((tErr.text || "").trim() || ("code " + code)))
            }
        }
    }

    function testConnection(index) {
        var h = (index === undefined) ? root.activeHost() : root.hostAt(index)
        if (!h) { ToastService.showError("Aucun hôte configuré"); return }
        ToastService.showNotice("Test de " + (h.name || h.sshAlias) + "…")
        testProc.running = false
        testProc.command = root.mgrArgv(h, ["host-info"])
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
        root.hostInfo = ({})
        root.pollStatus(true)
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

    // Quand le panel est ouvert : rafraîchit la dérive git périodiquement (avec fetch).
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
