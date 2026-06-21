import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Logic layer for the Calendar plugin. It owns no UI: it shells out to the
// `calsync` CLI (Process + JSON), streams live changes via `calsync watch`
// (SplitParser), and exposes state to Panel.qml / BarWidget.qml.
//
// The backend (calsync) holds all sync logic + the JSON cache; this is a thin
// client, mirroring the home-server-control ↔ Home-Server-Runner split.
Item {
    id: root
    property var pluginApi: null

    // ── Exposed state ────────────────────────────────────────────────────────
    property var events: []          // occurrences for the visible window (array of objects)
    property var calendars: []       // [{id, source, color, summary, visible}] from settings + live
    property var selectedDate: new Date()
    property string viewMode: "month" // month | week | day
    property bool isLoading: false
    property bool panelOpen: false
    property string lastError: ""
    property bool authError: false   // calsync reported auth_required

    // Bar badge: count + next upcoming event today.
    property int todayCount: 0
    property string nextLabel: ""

    function settings() { return root.pluginApi?.pluginSettings ?? null }
    function bin() { return root.settings()?.binPath || "calsync" }
    function weekStartsOn() { return root.settings()?.weekStartsOn ?? 1 }
    function dayStartHour() { return root.settings()?.dayStartHour ?? 7 }
    function dayEndHour() { return root.settings()?.dayEndHour ?? 22 }

    Component.onCompleted: {
        root.viewMode = root.settings()?.defaultView || "month"
        root._loadCalendarsFromSettings()
        root.reloadWindow()
    }

    // ── Calendar metadata (colors / visibility) ──────────────────────────────
    function _loadCalendarsFromSettings() {
        root.calendars = (root.settings()?.calendars ?? []).map(function (c) {
            return {
                "id": c.id ?? "",
                "source": c.source ?? "",
                "color": c.color ?? "",
                "summary": c.summary ?? "",
                "visible": c.visible !== false
            }
        })
    }

    function colorForSource(src) {
        for (var i = 0; i < root.calendars.length; i++)
            if (root.calendars[i].source === src && root.calendars[i].color)
                return root.calendars[i].color
        return Color.mPrimary
    }

    function sourceVisible(src) {
        for (var i = 0; i < root.calendars.length; i++)
            if (root.calendars[i].source === src)
                return root.calendars[i].visible
        return true
    }

    // ── Date helpers ─────────────────────────────────────────────────────────
    function startOfDay(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }
    function addDays(d, n) { var x = new Date(d); x.setDate(x.getDate() + n); return x }
    function startOfWeek(d) {
        var x = root.startOfDay(d)
        var diff = (x.getDay() - root.weekStartsOn() + 7) % 7
        return root.addDays(x, -diff)
    }
    function startOfMonth(d) { var x = new Date(d.getFullYear(), d.getMonth(), 1); return x }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    // Visible [from, to) window for the active view (month grid is padded a week
    // each side to cover spillover days).
    function windowRange() {
        var d = root.selectedDate
        if (root.viewMode === "day") {
            var f = root.startOfDay(d)
            return { "from": f, "to": root.addDays(f, 1) }
        }
        if (root.viewMode === "week") {
            var fw = root.startOfWeek(d)
            return { "from": fw, "to": root.addDays(fw, 7) }
        }
        // month
        var fm = root.startOfWeek(root.startOfMonth(d))
        return { "from": root.addDays(fm, -7), "to": root.addDays(fm, 49) }
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    function goToday() { root.selectedDate = new Date(); root.reloadWindow() }
    function goPrev() { root._step(-1) }
    function goNext() { root._step(1) }
    function _step(dir) {
        var d = new Date(root.selectedDate)
        if (root.viewMode === "day") d = root.addDays(d, dir)
        else if (root.viewMode === "week") d = root.addDays(d, 7 * dir)
        else d = new Date(d.getFullYear(), d.getMonth() + dir, 1)
        root.selectedDate = d
        root.reloadWindow()
    }
    function setView(v) {
        if (v === root.viewMode) return
        root.viewMode = v
        root.reloadWindow()
    }

    // ── Reading events ───────────────────────────────────────────────────────
    Process {
        id: eventsProc
        stdout: StdioCollector {
            onStreamFinished: root._onEventsLoaded(this.text || "")
        }
        onExited: code => {
            root.isLoading = false
            if (code !== 0)
                Logger.w("Calendar", "events list exited " + code)
        }
    }

    function reloadWindow() {
        var w = root.windowRange()
        root.isLoading = true
        eventsProc.running = false
        eventsProc.command = [root.bin(), "events", "list",
                              "--from", w.from.toISOString(),
                              "--to", w.to.toISOString()]
        eventsProc.running = true
    }

    function _onEventsLoaded(text) {
        root.isLoading = false
        var parsed
        try { parsed = JSON.parse(text) } catch (e) {
            Logger.w("Calendar", "events parse error: " + e)
            return
        }
        if (parsed && parsed.ok === false) {
            root.lastError = parsed.error ? parsed.error.message : "error"
            root.authError = parsed.error && parsed.error.code === "auth_required"
            return
        }
        root.authError = false
        root.lastError = ""
        var list = (parsed && parsed.events) ? parsed.events : []
        var out = []
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (!root.sourceVisible(e.source)) continue
            out.push({
                "id": e.id,
                "calendarId": e.calendarId,
                "source": e.source || "",
                "color": root.colorForSource(e.source),
                "summary": e.summary || "(sans titre)",
                "location": e.location || "",
                "description": e.description || "",
                "allDay": e.allDay === true,
                "recurring": e.recurring === true,
                "start": e.allDay ? root._parseDate(e.start) : new Date(e.start),
                "end": e.allDay ? root._parseDate(e.end) : new Date(e.end)
            })
        }
        root.events = out
        root._recomputeBadge()
    }

    function _parseDate(s) {
        // all-day "YYYY-MM-DD" → local date
        var p = String(s).split("-")
        if (p.length === 3) return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]))
        return new Date(s)
    }

    // Events intersecting a given day (for grids / agenda).
    function eventsOnDay(day) {
        var dayStart = root.startOfDay(day)
        var dayEnd = root.addDays(dayStart, 1)
        var out = []
        for (var i = 0; i < root.events.length; i++) {
            var e = root.events[i]
            if (e.start < dayEnd && e.end > dayStart) out.push(e)
        }
        out.sort(function (a, b) { return a.start - b.start })
        return out
    }

    function _recomputeBadge() {
        var today = new Date()
        var list = root.eventsOnDay(today)
        root.todayCount = list.length
        var now = new Date()
        root.nextLabel = ""
        for (var i = 0; i < list.length; i++) {
            if (!list[i].allDay && list[i].start >= now) {
                root.nextLabel = Qt.formatDateTime(list[i].start, "hh:mm") + " " + list[i].summary
                break
            }
        }
        if (!root.nextLabel && list.length > 0)
            root.nextLabel = list[0].summary
    }

    // ── Mutations (create / edit / delete) ───────────────────────────────────
    Process {
        id: mutateProc
        stdout: StdioCollector {
            onStreamFinished: root._onMutateDone(this.text || "")
        }
        onExited: code => { if (code !== 0) Logger.w("Calendar", "mutate exited " + code) }
    }

    function _onMutateDone(text) {
        var parsed
        try { parsed = JSON.parse(text) } catch (e) { return }
        if (parsed && parsed.ok === false)
            root.lastError = parsed.error ? parsed.error.message : "error"
        root.reloadWindow()
    }

    // start/end are ISO strings (RFC3339) or YYYY-MM-DD when allDay.
    function addEvent(source, summary, start, end, allDay, location, desc) {
        var cmd = [root.bin(), "event", "add", "--summary", summary, "--start", start,
                   "--calendar", source]
        if (end) cmd.push("--end", end)
        if (allDay) cmd.push("--all-day")
        if (location) cmd.push("--location", location)
        if (desc) cmd.push("--desc", desc)
        root._runMutate(cmd)
    }

    function editEvent(id, fields) {
        var cmd = [root.bin(), "event", "edit", id]
        if (fields.summary !== undefined) cmd.push("--summary", fields.summary)
        if (fields.start !== undefined) cmd.push("--start", fields.start)
        if (fields.end !== undefined) cmd.push("--end", fields.end)
        if (fields.allDay) cmd.push("--all-day")
        if (fields.location !== undefined) cmd.push("--location", fields.location)
        if (fields.desc !== undefined) cmd.push("--desc", fields.desc)
        root._runMutate(cmd)
    }

    function deleteEvent(id) {
        root._runMutate([root.bin(), "event", "rm", id])
    }

    function _runMutate(cmd) {
        mutateProc.running = false
        mutateProc.command = cmd
        mutateProc.running = true
    }

    // Force a sync then reload (manual refresh button).
    Process {
        id: syncProc
        stdout: StdioCollector { onStreamFinished: root.reloadWindow() }
        onExited: code => { if (code !== 0) Logger.w("Calendar", "sync exited " + code) }
    }
    function syncNow() {
        syncProc.running = false
        syncProc.command = [root.bin(), "sync"]
        syncProc.running = true
    }

    // ── Live updates via `calsync watch` ─────────────────────────────────────
    property bool _watchRunning: false
    Process {
        id: watchProc
        stdout: SplitParser { onRead: line => root._onWatchLine(line) }
        onExited: code => {
            root._watchRunning = false
            // Daemon not running → optionally start it, then retry once.
            if (root.panelOpen && (root.settings()?.ensureDaemon ?? true))
                root._ensureDaemon()
        }
    }

    Timer {
        id: reloadDebounce
        interval: 400
        repeat: false
        onTriggered: root.reloadWindow()
    }

    function _onWatchLine(line) {
        var ev
        try { ev = JSON.parse(line) } catch (e) { return }
        if (!ev || ev.type === "sync") return // heartbeat
        reloadDebounce.restart()
    }

    function startWatch() {
        if (root._watchRunning) return
        root._watchRunning = true
        watchProc.running = false
        watchProc.command = [root.bin(), "watch"]
        watchProc.running = true
    }

    function stopWatch() {
        root._watchRunning = false
        watchProc.running = false
    }

    property bool _daemonTried: false
    function _ensureDaemon() {
        if (root._daemonTried) return // only attempt once per session
        root._daemonTried = true
        Quickshell.execDetached(["systemctl", "--user", "enable", "--now", "calsync"])
        ensureRetry.restart()
    }
    Timer {
        id: ensureRetry
        interval: 1500
        repeat: false
        onTriggered: if (root.panelOpen) root.startWatch()
    }

    // ── Panel lifecycle ──────────────────────────────────────────────────────
    function setPanelOpen(open) {
        root.panelOpen = open
        if (open) {
            root._loadCalendarsFromSettings()
            root.reloadWindow()
            if (root.settings()?.syncOnOpen ?? true) root.syncNow()
            root.startWatch()
        } else {
            root.stopWatch()
        }
    }

    // ── CLI IPC (optional remote triggering) ─────────────────────────────────
    IpcHandler {
        target: "calendar"
        function refresh(): string { root.syncNow(); return "ok" }
        function today(): string { root.goToday(); return "ok" }
    }
}
