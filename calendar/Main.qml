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

    // Quick-access agenda: events for today + tomorrow (loaded independently of
    // the grid window so it stays correct when navigating months in compact view).
    property var agenda: []

    // CalendarIds hidden from display (a UI-only toggle, stored in plugin settings;
    // distinct from whether a calendar is synced, which lives in calsync config).
    property var hiddenCalendars: []

    function settings() { return root.pluginApi?.pluginSettings ?? null }
    function bin() { return root.settings()?.binPath || "calsync" }
    function defaultView() { return root.settings()?.defaultView || "month" }
    function weekStartsOn() { return root.settings()?.weekStartsOn ?? 1 }
    function dayStartHour() { return root.settings()?.dayStartHour ?? 7 }
    function dayEndHour() { return root.settings()?.dayEndHour ?? 22 }

    Component.onCompleted: {
        root.viewMode = root.settings()?.defaultView || "month"
        root._loadCalendars()
    }

    // ── Calendar metadata (colors / visibility) ──────────────────────────────
    // Calendar id/source/color/summary come from calsync's config (the source of
    // truth for what is synced); the per-calendar display-hide toggle lives in
    // plugin settings. Loading config is async, so events are (re)loaded once it
    // returns so colors/visibility are applied on first paint.
    Process {
        id: configProc
        stdout: StdioCollector { onStreamFinished: root._onConfigLoaded(this.text || "") }
        onExited: code => { if (code !== 0) Logger.w("Calendar", "config get exited " + code) }
    }

    function _loadCalendars() {
        root.hiddenCalendars = (root.settings()?.hiddenCalendars ?? []).slice()
        configProc.running = false
        configProc.command = [root.bin(), "config", "get"]
        configProc.running = true
    }

    function _onConfigLoaded(text) {
        var parsed
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        var cals = (parsed && parsed.calendars) ? parsed.calendars : []
        root.calendars = cals.map(function (c) {
            return {
                "id": c.id ?? "",
                "account": c.account ?? "",
                "source": c.source ?? "",
                "color": c.color ?? "",
                "summary": c.summary ?? "",
                "visible": root.hiddenCalendars.indexOf(c.id ?? "") < 0
            }
        })
        root.reloadWindow()
        root.reloadAgenda()
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

    // Per-calendar color (keyed by calendarId, the Google-like model). Falls back
    // to the source color, then the theme primary.
    function colorForCalendar(calId) {
        for (var i = 0; i < root.calendars.length; i++)
            if (root.calendars[i].id === calId && root.calendars[i].color)
                return root.calendars[i].color
        return Color.mPrimary
    }

    // Per-calendar visibility (keyed by calendarId); a calendar is hidden only if
    // the user toggled it off in settings. Unknown calendars are visible.
    function calendarVisible(calId) {
        return root.hiddenCalendars.indexOf(calId) < 0
    }

    // Calendars usable as event-creation targets (synced + writable). Read-only
    // sources like holidays are excluded.
    function writableCalendars() {
        var out = []
        for (var i = 0; i < root.calendars.length; i++) {
            var c = root.calendars[i]
            if (c.source === "holidays") continue
            if (!c.id) continue
            out.push(c)
        }
        return out
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

    // ── Quick-access agenda (today + tomorrow) ───────────────────────────────
    Process {
        id: agendaProc
        stdout: StdioCollector {
            onStreamFinished: root._onAgendaLoaded(this.text || "")
        }
    }

    function reloadAgenda() {
        var from = root.startOfDay(new Date())
        var to = root.addDays(from, 2) // today + tomorrow
        agendaProc.running = false
        agendaProc.command = [root.bin(), "events", "list",
                              "--from", from.toISOString(),
                              "--to", to.toISOString()]
        agendaProc.running = true
    }

    function _onAgendaLoaded(text) {
        var parsed
        try { parsed = JSON.parse(text) } catch (e) { return }
        if (parsed && parsed.ok === false) return
        var list = (parsed && parsed.events) ? parsed.events : []
        root.agenda = root._mapEvents(list)
    }

    // Still-relevant events for quick access: today's ongoing/upcoming ones, or
    // tomorrow's if today is over. Returns { tomorrow: bool, events: [...] }.
    function upcomingAgenda() {
        var now = new Date()
        var todayEnd = root.addDays(root.startOfDay(now), 1)
        var src = root.agenda
        var todays = []
        for (var i = 0; i < src.length; i++)
            if (src[i].start < todayEnd && src[i].end > now) todays.push(src[i])
        if (todays.length > 0) {
            todays.sort(function (a, b) { return a.start - b.start })
            return { "tomorrow": false, "events": todays }
        }
        var tomEnd = root.addDays(todayEnd, 1)
        var toms = []
        for (var j = 0; j < src.length; j++)
            if (src[j].start < tomEnd && src[j].end > todayEnd) toms.push(src[j])
        toms.sort(function (a, b) { return a.start - b.start })
        return { "tomorrow": true, "events": toms }
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
        root.events = root._mapEvents(list)
        root._recomputeBadge()
    }

    // Map raw calsync event JSON to the UI event model (filtering hidden calendars).
    function _mapEvents(list) {
        var out = []
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (!root.calendarVisible(e.calendarId)) continue
            out.push({
                "id": e.id,
                "calendarId": e.calendarId,
                "source": e.source || "",
                "color": root.colorForCalendar(e.calendarId),
                "summary": e.summary || "(sans titre)",
                "location": e.location || "",
                "description": e.description || "",
                "meetLink": e.meetLink || "",
                "allDay": e.allDay === true,
                "recurring": e.recurring === true,
                "recurringEventId": e.recurringEventId || "",
                "instanceStart": e.instanceStart || "",
                "attendees": e.attendees || [],
                "selfResponse": e.selfResponse || "",
                "start": e.allDay ? root._parseDate(e.start) : new Date(e.start),
                "end": e.allDay ? root._parseDate(e.end) : new Date(e.end)
            })
        }
        return out
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

    // Create an event. fields: { summary, start, end, allDay, location, desc,
    //   calendarId (preferred) | source, recurrence (RRULE body), attendees
    //   (comma-separated emails), notify ("all"|"none"|"external") }.
    // start/end are ISO strings (RFC3339) or YYYY-MM-DD when allDay.
    function addEvent(fields) {
        var cmd = [root.bin(), "event", "add", "--summary", fields.summary, "--start", fields.start]
        if (fields.calendarId) cmd.push("--calendar-id", fields.calendarId)
        else if (fields.source) cmd.push("--calendar", fields.source)
        if (fields.end) cmd.push("--end", fields.end)
        if (fields.allDay) cmd.push("--all-day")
        if (fields.location) cmd.push("--location", fields.location)
        if (fields.desc) cmd.push("--desc", fields.desc)
        if (fields.recurrence) cmd.push("--recurrence", fields.recurrence)
        if (fields.attendees !== undefined && fields.attendees !== "") cmd.push("--attendees", fields.attendees)
        if (fields.notify) cmd.push("--notify", fields.notify)
        root._runMutate(cmd)
    }

    // fields may carry scope ("this"|"following"|"all") and instance (the target
    // occurrence's original start) for recurring-event edits, plus attendees /
    // recurrence / notify.
    function editEvent(id, fields) {
        var cmd = [root.bin(), "event", "edit", id]
        if (fields.summary !== undefined) cmd.push("--summary", fields.summary)
        if (fields.start !== undefined) cmd.push("--start", fields.start)
        if (fields.end !== undefined) cmd.push("--end", fields.end)
        if (fields.allDay) cmd.push("--all-day")
        if (fields.location !== undefined) cmd.push("--location", fields.location)
        if (fields.desc !== undefined) cmd.push("--desc", fields.desc)
        if (fields.recurrence !== undefined) cmd.push("--recurrence", fields.recurrence)
        if (fields.attendees !== undefined) cmd.push("--attendees", fields.attendees)
        if (fields.notify) cmd.push("--notify", fields.notify)
        if (fields.scope) cmd.push("--scope", fields.scope)
        if (fields.instance) cmd.push("--instance", fields.instance)
        root._runMutate(cmd)
    }

    // Set the authenticated user's RSVP on an event. scope/instance apply to a
    // single occurrence of a recurring event (scope "this" + instance origStart).
    function respondEvent(id, response, scope, instance) {
        var cmd = [root.bin(), "event", "respond", id, "--response", response]
        if (scope) cmd.push("--scope", scope)
        if (instance) cmd.push("--instance", instance)
        root._runMutate(cmd)
    }

    // scope/instance apply to recurring events (omit for single events).
    function deleteEvent(id, scope, instance) {
        var cmd = [root.bin(), "event", "rm", id]
        if (scope) cmd.push("--scope", scope)
        if (instance) cmd.push("--instance", instance)
        root._runMutate(cmd)
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
        onTriggered: { root.reloadWindow(); root.reloadAgenda() }
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
            root._loadCalendars() // reloads window + agenda once config returns
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
