import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "drivers/Shared.js" as Shared
import "drivers/Sessions.js" as Sessions
import "drivers/Transcript.js" as Transcript
import "drivers/Focus.js" as Focus
import "drivers/Hooks.js" as Hooks

// Couche logique non-visuelle de Claude Conductor.
// Observe les sessions Claude Code (100 % local, aucun appel modèle) via deux sources réconciliées :
//   • HOOKS (push, IPC) : transitions d'état + (dés)enregistrement — fiable pour « waiting ».
//   • POLL local léger (cc-collect) : présence/GC + bootstrap des sessions nées avant le plugin.
// Enrichissement (titre, branche, modèle, dernier message) à la demande quand le panneau est ouvert.
Item {
    id: root
    property var pluginApi: null

    // Répertoire du plugin (pour invoquer scripts/*). Résolu depuis l'URL de ce fichier.
    readonly property string pluginDir: {
        var u = Qt.resolvedUrl(".").toString()
        if (u.indexOf("file://") === 0) u = u.substring(7)
        u = decodeURIComponent(u)
        if (u.length > 1 && u.charAt(u.length - 1) === "/") u = u.substring(0, u.length - 1)
        return u
    }

    // ── Registre des sessions ────────────────────────────────────────────────
    // id -> { id, pid, cwd, project, entrypoint, title, branch, model,
    //         state, reason, startedAt, runStartMs, lastActivity, lastStateChange, misses }
    property var sessions: ({})

    // Modèle plat (groupé par projet via section dans le Panel), MAJ en place (anti-blink).
    property ListModel sessionsModel: ListModel {}

    // Agrégats pour la pastille.
    property int barRunning: 0
    property int barWaiting: 0
    property int barIdle: 0
    property int barTotal: 0

    property bool panelOpen: false
    property bool hooksInstalled: false
    property real now: 0                       // horloge pour l'affichage des âges

    // Tail en direct (overlay du Panel) — texte rendu lisible depuis le JSONL.
    property string logText: ""
    property var _logLines: []
    readonly property int logCap: 4000
    property string logTitle: ""
    property string logCwd: ""
    property string logSid: ""

    property string _lastFocusId: ""

    function settings() { return root.pluginApi?.pluginSettings ?? null }
    function nowMs() { return Date.now() }
    function trackedList() { return root.settings()?.trackEntrypoints ?? ["cli", "claude-vscode"] }

    function newRecord(id) {
        var t = root.nowMs()
        return {
            "id": id, "pid": 0, "cwd": "", "project": "?", "entrypoint": "",
            "title": "", "branch": "", "model": "", "state": "idle", "reason": "",
            "startedAt": t, "runStartMs": 0, "lastActivity": t, "lastStateChange": t, "misses": 0
        }
    }

    // ── Machine à états : événement poussé par un hook (via IPC) ───────────────
    function onEvent(state, id, cwd, message, transcript) {
        if (!id) return
        var s = root.sessions[id] || root.newRecord(id)
        if (cwd && cwd.length) { s.cwd = cwd; s.project = Shared.projectName(cwd) }
        s.lastActivity = root.nowMs()

        if (state === "end") {
            delete root.sessions[id]
            root.applySessions()
            return
        }

        var mapped = (state === "running") ? "running"
                   : (state === "waiting") ? "waiting"
                   : "idle"                                   // start | idle | inconnu → prêt
        var prev = s.state
        if (mapped === "running" && prev !== "running") s.runStartMs = root.nowMs()
        s.state = mapped
        s.reason = (state === "waiting") ? (message || "") : ""
        if (mapped !== prev) s.lastStateChange = root.nowMs()
        s.misses = 0
        root.sessions[id] = s
        root.applySessions()

        if (mapped === "waiting" && prev !== "waiting") root.notifyWaiting(s)
        else if (mapped === "idle" && prev === "running") root.maybeNotifyDone(s)

        if (root.panelOpen && (root.settings()?.enrichOnOpen ?? true)) root.enrichSession(id)
    }

    // ── Recompose le modèle + agrégats depuis le registre ─────────────────────
    function _ordered() {
        var tracked = root.trackedList()
        var out = []
        for (var id in root.sessions) {
            var s = root.sessions[id]
            if (!Sessions.isTracked(s.entrypoint, tracked)) continue
            out.push(s)
        }
        out.sort(function (a, b) {
            if (a.project !== b.project) return a.project < b.project ? -1 : 1
            return (a.startedAt || 0) - (b.startedAt || 0)
        })
        return out
    }

    function _row(s) {
        return {
            "sid": s.id, "project": s.project || "?", "cwd": s.cwd || "", "pid": s.pid || 0,
            "entry": Sessions.entrypointKind(s.entrypoint), "title": s.title || "",
            "branch": s.branch || "", "state": s.state || "idle",
            "reason": s.reason || "", "startedAt": s.startedAt || 0, "lastActivity": s.lastActivity || 0
        }
    }

    function applySessions() {
        var desired = root._ordered()
        // MAJ en place si la séquence d'ids est identique (aucun blink), sinon reconstruction.
        var sameSeq = desired.length === root.sessionsModel.count
        if (sameSeq) {
            for (var i = 0; i < desired.length; i++)
                if (root.sessionsModel.get(i).sid !== desired[i].id) { sameSeq = false; break }
        }
        if (sameSeq) {
            for (var j = 0; j < desired.length; j++) root.sessionsModel.set(j, root._row(desired[j]))
        } else {
            root.sessionsModel.clear()
            for (var k = 0; k < desired.length; k++) root.sessionsModel.append(root._row(desired[k]))
        }

        var run = 0, wait = 0, idle = 0
        for (var n = 0; n < desired.length; n++) {
            var st = desired[n].state
            if (st === "running") run++
            else if (st === "waiting") wait++
            else idle++
        }
        root.barRunning = run; root.barWaiting = wait; root.barIdle = idle
        root.barTotal = desired.length
    }

    // ── Sweep présence / bootstrap / GC (cc-collect) ──────────────────────────
    Process {
        id: collectProc
        stdout: StdioCollector {
            onStreamFinished: {
                var list = Sessions.parseCollect(this.text || "[]")
                root.reconcile(list)
            }
        }
    }

    function pollCollect() {
        collectProc.running = false
        collectProc.command = Sessions.collectCommand(root.pluginDir)
        collectProc.running = true
    }

    function reconcile(list) {
        var live = ({})
        for (var i = 0; i < list.length; i++) {
            var rec = list[i]
            if (!rec.sessionId) continue
            live[rec.sessionId] = true
            var s = root.sessions[rec.sessionId] || root.newRecord(rec.sessionId)
            if (rec.pid) s.pid = rec.pid
            if (rec.cwd) { s.cwd = rec.cwd; s.project = Shared.projectName(rec.cwd) }
            if (rec.entrypoint) s.entrypoint = rec.entrypoint
            if (rec.startedAt) s.startedAt = rec.startedAt
            s.misses = 0
            root.sessions[rec.sessionId] = s
        }
        // GC : retire les sessions absentes du dernier sweep (les sorties propres passent par SessionEnd).
        for (var id in root.sessions) {
            if (live[id]) continue
            var ss = root.sessions[id]
            ss.misses = (ss.misses || 0) + 1
            // pid déjà confirmé puis disparu = crash/kill → 2 sweeps de grâce ; hook-only jamais vu = 3.
            var limit = ss.pid ? 2 : 3
            if (ss.misses >= limit) delete root.sessions[id]
            else root.sessions[id] = ss
        }
        root.applySessions()
        if (root.panelOpen && (root.settings()?.enrichOnOpen ?? true)) root.enrichAll()
    }

    // ── Enrichissement (titre/branche/modèle/dernier message) — file séquentielle ─
    property var _enrichQueue: []
    property bool _enriching: false

    function enrichSession(id) {
        if (root._enrichQueue.indexOf(id) === -1) root._enrichQueue.push(id)
        root._enrichPump()
    }
    function enrichAll() { for (var id in root.sessions) root.enrichSession(id) }

    function _enrichPump() {
        if (root._enriching || !root._enrichQueue.length) return
        var id = root._enrichQueue.shift()
        var s = root.sessions[id]
        if (!s || !s.cwd) { root._enrichPump(); return }
        root._enriching = true
        enrichProc._id = id
        enrichProc.running = false
        enrichProc.command = Transcript.enrichCommand(root.pluginDir, s.cwd, id)
        enrichProc.running = true
    }

    Process {
        id: enrichProc
        property string _id: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var info = Transcript.parseEnrich(this.text || "{}")
                var s = root.sessions[enrichProc._id]
                if (s && info) {
                    if (info.title) s.title = info.title
                    if (info.gitBranch) s.branch = info.gitBranch
                    if (info.model) s.model = info.model
                    root.sessions[enrichProc._id] = s
                    root.applySessions()
                }
                root._enriching = false
                root._enrichPump()
            }
        }
        onExited: code => { if (code !== 0) { root._enriching = false; root._enrichPump() } }
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    function notifyWaiting(s) {
        if (!(root.settings()?.notifyOnWaiting ?? true)) return
        ToastService.showNotice("⚠ " + s.project + " " + (root.pluginApi?.tr("notif.waiting") ?? "attend"))
        Quickshell.execDetached(["notify-send", "-u", "normal", "-a", "Claude Conductor",
                                 "⚠ " + s.project, (s.reason || (root.pluginApi?.tr("notif.waiting") ?? "attend ta validation"))])
    }

    function maybeNotifyDone(s) {
        if (!(root.settings()?.notifyOnDone ?? true)) return
        var minS = root.settings()?.doneMinSeconds ?? 20
        var ranS = s.runStartMs ? Math.floor((root.nowMs() - s.runStartMs) / 1000) : 0
        if (ranS < minS) return
        var dur = ranS < 60 ? (ranS + "s") : (Math.floor(ranS / 60) + "m" + (ranS % 60) + "s")
        ToastService.showNotice("✓ " + s.project + " — " + (root.pluginApi?.tr("notif.done") ?? "terminé") + " (" + dur + ")")
        Quickshell.execDetached(["notify-send", "-u", "low", "-a", "Claude Conductor",
                                 "✓ " + s.project, (root.pluginApi?.tr("notif.done") ?? "agent terminé") + " (" + dur + ")"])
    }

    // ── Actions : focus / téléportation / resume ──────────────────────────────
    function focusSession(id) {
        var s = root.sessions[id]; if (!s) return
        root._lastFocusId = id
        Quickshell.execDetached(Focus.focusCommand(root.pluginDir, s))
    }

    // Cycle vers le prochain agent en « waiting » (sinon le « running » le plus récent).
    function focusNext() {
        var waiting = [], running = []
        var ord = root._ordered()
        for (var i = 0; i < ord.length; i++) {
            if (ord[i].state === "waiting") waiting.push(ord[i])
            else if (ord[i].state === "running") running.push(ord[i])
        }
        var pick = null
        if (waiting.length) {
            var idx = -1
            for (var j = 0; j < waiting.length; j++) if (waiting[j].id === root._lastFocusId) { idx = j; break }
            pick = waiting[(idx + 1) % waiting.length]
        } else if (running.length) {
            running.sort(function (a, b) { return (b.lastActivity || 0) - (a.lastActivity || 0) })
            pick = running[0]
        }
        if (pick) root.focusSession(pick.id)
        else ToastService.showNotice(root.pluginApi?.tr("panel.empty") ?? "Aucune session")
    }

    function resumeSession(id) {
        var s = root.sessions[id]; if (!s) return
        Quickshell.execDetached(Focus.resumeCommand(Shared.terminalArgs(root.settings()?.terminalCommand), s))
    }

    function openUrl(url) { if (url) Quickshell.execDetached(["xdg-open", url]) }

    // ── Tail en direct (overlay) ──────────────────────────────────────────────
    Process {
        id: logProc
        stdout: SplitParser { onRead: line => root.appendLog(line) }
        stderr: SplitParser { onRead: line => root.appendLog(line) }
    }

    function streamTail(id) {
        var s = root.sessions[id]; if (!s || !s.cwd) return
        logProc.running = false
        root._logLines = []
        root.logText = ""
        root.logTitle = (s.title && s.title.length) ? s.title : s.project
        root.logCwd = s.cwd
        root.logSid = id
        var tail = root.settings()?.tailLines ?? 200
        logProc.command = Transcript.tailCommand(s.cwd, id, tail)
        logProc.running = true
    }

    function stopTail() { logProc.running = false }

    function appendLog(line) {
        var rendered = Transcript.renderLine(line)
        if (!rendered.length) return
        var arr = root._logLines
        arr.push(rendered)
        if (arr.length > root.logCap) arr.splice(0, arr.length - root.logCap)
        root.logText = arr.join("\n")
    }

    function openTailInTerminal() {
        if (!root.logCwd || !root.logSid) return
        var n = root.settings()?.tailLines ?? 200
        Quickshell.execDetached(Shared.terminalArgs(root.settings()?.terminalCommand)
            .concat(["sh", Shared.scriptPath(root.pluginDir, "cc-tail"), root.logCwd, root.logSid, String(n)]))
    }

    // ── Hooks : install / désinstall / statut ─────────────────────────────────
    Process {
        id: hooksProc
        property string _mode: ""
        stdout: StdioCollector { id: hooksOut }
        stderr: StdioCollector { id: hooksErr }
        onExited: code => {
            if (code === 0) {
                ToastService.showNotice((hooksOut.text || "").trim() || "✓")
                root.hooksInstalled = (hooksProc._mode === "install")
                if (root.settings()) { root.settings().hooksInstalled = root.hooksInstalled; root.pluginApi.saveSettings() }
            } else {
                ToastService.showError((hooksErr.text || hooksOut.text || "").trim() || ("erreur (code " + code + ")"))
            }
        }
    }

    function installHooks() {
        hooksProc._mode = "install"
        hooksProc.running = false
        hooksProc.command = Hooks.installCommand(root.pluginDir)
        hooksProc.running = true
    }
    function uninstallHooks() {
        hooksProc._mode = "uninstall"
        hooksProc.running = false
        hooksProc.command = Hooks.uninstallCommand(root.pluginDir)
        hooksProc.running = true
    }

    Process {
        id: hooksStatusProc
        stdout: StdioCollector {
            onStreamFinished: { root.hooksInstalled = (this.text || "").trim() === "installed" }
        }
    }
    function refreshHooksStatus() {
        hooksStatusProc.running = false
        hooksStatusProc.command = Hooks.statusCommand(root.pluginDir)
        hooksStatusProc.running = true
    }

    function refreshNow() { root.pollCollect(); if (root.panelOpen) root.enrichAll(); root.refreshHooksStatus() }

    // ── Cycle de vie panneau + timers ─────────────────────────────────────────
    function setPanelOpen(open) {
        root.panelOpen = open
        if (open) { root.pollCollect(); root.enrichAll() }
        else root.stopTail()
    }

    Timer {
        id: pollTimer
        repeat: true; running: true
        interval: root.panelOpen ? (root.settings()?.pollLivenessOpenMs ?? 4000)
                                 : (root.settings()?.pollLivenessIdleMs ?? 12000)
        onTriggered: root.pollCollect()
    }

    // Horloge d'affichage des âges (plus vive quand le panneau est ouvert).
    Timer {
        repeat: true; running: true
        interval: root.panelOpen ? 1000 : 5000
        onTriggered: root.now = root.nowMs()
    }

    Component.onCompleted: {
        root.now = root.nowMs()
        root.pollCollect()
        root.refreshHooksStatus()
    }

    // ── IPC : qs -c noctalia-shell ipc call plugin:claude-conductor <fn> ───────
    IpcHandler {
        target: "plugin:claude-conductor"
        function event(state: string, id: string, cwd: string, message: string, transcript: string) {
            root.onEvent(state, id, cwd, message, transcript)
        }
        function focus(id: string) { root.focusSession(id) }
        function focusNext() { root.focusNext() }
        function resume(id: string) { root.resumeSession(id) }
        function refresh() { root.refreshNow() }
        function togglePanel() {
            if (root.pluginApi) root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
        }
    }
}
