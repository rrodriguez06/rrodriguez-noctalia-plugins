import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Modules.Cards
import qs.Services.Location

// Calendar panel: header (period nav + view switch + actions), month/week/day
// views, and an event editor overlay. All data comes from main (the CLI bridge).
Item {
    id: root
    property var pluginApi: null
    readonly property var main: pluginApi?.mainInstance ?? null

    // Noctalia panel contract.
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    // Compact (Clock-like) view opens by default; the expanded calendar is reached
    // via the expand button. SmartPanel resizes reactively when these change.
    property bool compact: true
    property real contentPreferredWidth: compact ? Math.round(440 * Style.uiScaleRatio) : 920 * Style.uiScaleRatio
    property real contentPreferredHeight: compact ? (compactCol.implicitHeight + Style.marginL * 2) : 680 * Style.uiScaleRatio
    anchors.fill: parent

    // Timeline geometry (week/day hour grids).
    readonly property real hourPx: 44 * Style.uiScaleRatio
    readonly property real gutterW: 46 * Style.uiScaleRatio
    readonly property real topPad: 10 * Style.uiScaleRatio // breathing room above the first hour

    // Editor state.
    property bool editing: false
    property string edId: ""
    property string edSummary: ""
    property bool edAllDay: false
    property string edStartDate: ""
    property string edStartTime: "09:00"
    property string edEndDate: ""
    property string edEndTime: "10:00"
    property string edLocation: ""
    property string edDesc: ""
    property string edSource: ""
    // Recurring-event editing.
    property bool edRecurring: false
    property string edInstanceStart: ""
    property string edScope: "this" // this | following | all

    // Inspection (read-only) state — clicking an event opens this first.
    property bool inspecting: false
    property var insEvent: null

    // Top-level tab (0 = calendar, 1 = board).
    property int activeTab: 0

    // Card editor state.
    property bool cardEditing: false
    property string cdId: ""
    property string cdTitle: ""
    property string cdNotes: ""
    property string cdPriority: "normal"
    property int cdProgress: 0
    property string cdDue: ""
    property string cdColumn: ""

    // Add-column overlay state.
    property bool columnEditing: false
    property string cgName: ""

    onVisibleChanged: {
        if (main) main.setPanelOpen(visible)
        if (visible) {
            // Always open compact; ensure the month window is loaded so the mini
            // calendar has events for its dots.
            root.compact = true
            if (main && main.viewMode !== "month") main.setView("month")
        } else {
            root.editing = false
        }
    }

    function tr(k, fb) { return root.pluginApi ? root.pluginApi.tr(k) : fb }

    function periodLabel() {
        if (!main) return ""
        var d = main.selectedDate
        if (main.viewMode === "day") return Qt.formatDateTime(d, "dddd d MMMM yyyy")
        if (main.viewMode === "week") {
            var s = main.startOfWeek(d)
            var e = main.addDays(s, 6)
            return Qt.formatDateTime(s, "d MMM") + " – " + Qt.formatDateTime(e, "d MMM yyyy")
        }
        return Qt.formatDateTime(d, "MMMM yyyy")
    }

    function weekdayNames() {
        // short weekday labels honoring weekStartsOn
        var base = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var loc = [Qt.locale().standaloneDayName(0, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(1, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(2, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(3, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(4, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(5, Locale.ShortFormat),
                   Qt.locale().standaloneDayName(6, Locale.ShortFormat)]
        var start = main ? main.weekStartsOn() : 1
        var out = []
        for (var i = 0; i < 7; i++) out.push(loc[(start + i) % 7])
        return out
    }

    function sourceModel() {
        var seen = {}
        var out = []
        var cals = main ? main.calendars : []
        for (var i = 0; i < cals.length; i++) {
            var s = cals[i].source
            if (s === "holidays") continue // read-only source: not a creation target
            if (s && !seen[s]) { seen[s] = true; out.push({ "key": s, "name": s }) }
        }
        if (out.length === 0) {
            out.push({ "key": "perso", "name": "perso" })
            out.push({ "key": "work", "name": "work" })
        }
        return out
    }

    // ── Editor helpers ───────────────────────────────────────────────────────
    // frac is a fraction-of-day in hours (e.g. 9.5 = 09:30) → "HH:MM".
    function fracToTime(f) {
        var h = Math.floor(f)
        var m = Math.round((f - h) * 60)
        if (m >= 60) { h += 1; m -= 60 }
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }

    // startFrac/endFrac (optional, in hours) pre-fill the time when creating from
    // an hour-grid slot (click) or a drag selection. endFrac defaults to +1h; a
    // range shorter than 15 min is widened to 15 min.
    function openNew(day, startFrac, endFrac) {
        var d = day ? day : (main ? main.selectedDate : new Date())
        root.edId = ""
        root.edSummary = ""
        root.edAllDay = false
        root.edStartDate = Qt.formatDate(d, "yyyy-MM-dd")
        root.edEndDate = Qt.formatDate(d, "yyyy-MM-dd")
        if (startFrac !== undefined && startFrac !== null) {
            var a = startFrac
            var b = (endFrac !== undefined && endFrac !== null) ? endFrac : startFrac + 1
            if (b - a < 0.25) b = a + 0.25
            root.edStartTime = root.fracToTime(a)
            root.edEndTime = root.fracToTime(b)
        } else {
            root.edStartTime = "09:00"
            root.edEndTime = "10:00"
        }
        root.edLocation = ""
        root.edDesc = ""
        root.edRecurring = false
        root.edInstanceStart = ""
        root.edScope = "this"
        var sm = root.sourceModel()
        root.edSource = sm.length ? sm[0].key : "perso"
        root.editing = true
    }

    function openEdit(ev) {
        root.edId = ev.id
        root.edSummary = ev.summary
        root.edAllDay = ev.allDay
        root.edStartDate = Qt.formatDate(ev.start, "yyyy-MM-dd")
        root.edEndDate = Qt.formatDate(ev.end, "yyyy-MM-dd")
        root.edStartTime = Qt.formatDateTime(ev.start, "hh:mm")
        root.edEndTime = Qt.formatDateTime(ev.end, "hh:mm")
        root.edLocation = ev.location
        root.edDesc = ev.description
        root.edSource = ev.source
        root.edRecurring = ev.recurring === true
        root.edInstanceStart = ev.instanceStart || ""
        root.edScope = "this" // safest default for a recurring occurrence
        root.editing = true
    }

    // Clicking an event opens a read-only inspection first; "Edit" switches to the
    // editor (so a misclick never drops straight into an edit form).
    function openInspect(ev) {
        root.insEvent = ev
        root.inspecting = true
    }
    function editFromInspect() {
        var ev = root.insEvent
        root.inspecting = false
        if (ev) root.openEdit(ev)
    }

    function buildISO(dateStr, timeStr) {
        var dt = new Date(dateStr + "T" + timeStr + ":00")
        return dt.toISOString()
    }

    function saveEditor() {
        if (!main) return
        var start = root.edAllDay ? root.edStartDate : root.buildISO(root.edStartDate, root.edStartTime)
        var end = root.edAllDay ? root.edEndDate : root.buildISO(root.edEndDate, root.edEndTime)
        if (root.edId === "") {
            main.addEvent(root.edSource, root.edSummary, start, end, root.edAllDay, root.edLocation, root.edDesc)
        } else {
            var fields = {
                "summary": root.edSummary, "start": start, "end": end,
                "allDay": root.edAllDay, "location": root.edLocation, "desc": root.edDesc
            }
            if (root.edRecurring) {
                fields.scope = root.edScope
                fields.instance = root.edInstanceStart
            }
            main.editEvent(root.edId, fields)
        }
        root.editing = false
    }

    function scopeModel() {
        return [{ "key": "this", "name": root.tr("editor.scopeThis", "This event") },
                { "key": "following", "name": root.tr("editor.scopeFollowing", "This and following") },
                { "key": "all", "name": root.tr("editor.scopeAll", "All events") }]
    }

    // ── Kanban helpers ───────────────────────────────────────────────────────
    function boardColumns() { return (root.main && root.main.board && root.main.board.columns) ? root.main.board.columns : [] }

    function cardsIn(colId) {
        var cards = (root.main && root.main.board && root.main.board.cards) ? root.main.board.cards : []
        return cards.filter(function (c) { return c.column === colId })
                    .sort(function (a, b) { return (a.order || 0) - (b.order || 0) })
    }

    function priorityModel() {
        return [{ "key": "low", "name": root.tr("priority.low", "Low") },
                { "key": "normal", "name": root.tr("priority.normal", "Normal") },
                { "key": "high", "name": root.tr("priority.high", "High") }]
    }

    function columnModel() {
        return root.boardColumns().map(function (c) { return { "key": c.id, "name": c.name } })
    }

    function priorityColor(p) {
        if (p === "high") return Color.mError
        if (p === "low") return Color.mOnSurfaceVariant
        return Color.mPrimary
    }

    function openNewCard(colId) {
        root.cdId = ""
        root.cdTitle = ""
        root.cdNotes = ""
        root.cdPriority = "normal"
        root.cdProgress = 0
        root.cdDue = ""
        var cols = root.boardColumns()
        root.cdColumn = colId || (cols.length ? cols[0].id : "")
        root.cardEditing = true
    }

    function openCard(card) {
        root.cdId = card.id
        root.cdTitle = card.title
        root.cdNotes = card.notes || ""
        root.cdPriority = card.priority || "normal"
        root.cdProgress = card.progress || 0
        root.cdDue = card.due || ""
        root.cdColumn = card.column
        root.cardEditing = true
    }

    function saveCard() {
        if (!root.main) return
        if (root.cdId === "") {
            root.main.addCard(root.cdTitle, { "column": root.cdColumn, "notes": root.cdNotes,
                "priority": root.cdPriority, "progress": root.cdProgress, "due": root.cdDue })
        } else {
            root.main.updateCard(root.cdId, { "title": root.cdTitle, "notes": root.cdNotes,
                "priority": root.cdPriority, "progress": root.cdProgress, "due": root.cdDue, "column": root.cdColumn })
        }
        root.cardEditing = false
    }

    function deleteCard() {
        if (root.main && root.cdId !== "") root.main.rmCard(root.cdId)
        root.cardEditing = false
    }

    function timeRange(ev) {
        if (ev.allDay) return root.tr("panel.allDay", "All day")
        return Qt.formatDateTime(ev.start, "hh:mm") + "–" + Qt.formatDateTime(ev.end, "hh:mm")
    }

    // ── Hour-grid geometry helpers ───────────────────────────────────────────
    function hourFrac(d) { return d.getHours() + d.getMinutes() / 60 }

    // packEvents lays overlapping timed events into side-by-side lanes. It groups
    // events into clusters of transitively-overlapping items, assigns each the
    // first free lane, and tags it with the cluster's lane count so the delegate
    // can size/position columns. Returns [{ ev, lane, lanes }].
    function packEvents(events) {
        var evs = (events || []).slice().sort(function (a, b) {
            var d = a.start.getTime() - b.start.getTime()
            return d !== 0 ? d : (a.end.getTime() - b.end.getTime())
        })
        var out = []
        var cluster = [] // [{ ev, lane }] of the current overlapping group
        var clusterEnd = 0
        function flush() {
            var lanes = 0
            for (var k = 0; k < cluster.length; k++) lanes = Math.max(lanes, cluster[k].lane + 1)
            for (var m = 0; m < cluster.length; m++)
                out.push({ "ev": cluster[m].ev, "lane": cluster[m].lane, "lanes": lanes })
            cluster = []
            clusterEnd = 0
        }
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i]
            var s = e.start.getTime(), en = e.end.getTime()
            if (cluster.length && s >= clusterEnd) flush()
            var used = {}
            for (var j = 0; j < cluster.length; j++) {
                var c = cluster[j]
                if (c.ev.end.getTime() > s && c.ev.start.getTime() < en) used[c.lane] = true
            }
            var lane = 0
            while (used[lane]) lane++
            cluster.push({ "ev": e, "lane": lane })
            clusterEnd = Math.max(clusterEnd, en)
        }
        if (cluster.length) flush()
        return out
    }

    // scrollToNow positions a timeline Flickable so the current hour sits in the
    // upper third of the viewport (called once when a week/day view is built).
    function scrollToNow(flick, startH) {
        if (!flick) return
        var y = (root.hourFrac(new Date()) - startH) * root.hourPx + root.topPad - flick.height * 0.3
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(y, maxY))
    }

    // Compact segmented switcher (used for Calendar/Board and Month/Week/Day).
    component SegControl: Rectangle {
        id: seg
        property var options: [] // [{ key, label }]
        property string current: ""
        signal picked(string key)
        implicitWidth: segRow.implicitWidth + 6
        implicitHeight: segRow.implicitHeight + 6
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        border.width: Style.borderS
        border.color: Style.boxBorderColor

        RowLayout {
            id: segRow
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: segItem
                    required property var modelData
                    property bool active: seg.current === modelData.key
                    radius: Style.radiusS
                    implicitWidth: segLbl.implicitWidth + Style.marginM
                    implicitHeight: segLbl.implicitHeight + Style.marginXS
                    color: segItem.active ? Color.mPrimary
                                          : (segItemMA.containsMouse ? Color.mHover : "transparent")
                    Behavior on color { ColorAnimation { duration: 100 } }
                    NText {
                        id: segLbl
                        anchors.centerIn: parent
                        text: segItem.modelData.label
                        pointSize: Style.fontSizeS
                        color: segItem.active ? Color.mOnPrimary : Color.mOnSurface
                    }
                    MouseArea {
                        id: segItemMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(segItem.modelData.key)
                    }
                }
            }
        }
    }

    Item {
        id: panelContainer
        anchors.fill: parent
        visible: !root.compact

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS
            opacity: (root.editing || root.cardEditing || root.columnEditing || root.inspecting) ? 0.15 : 1.0

            // ── Tab switcher (Calendar / Board) — compact segmented control ──
            RowLayout {
                Layout.fillWidth: true
                SegControl {
                    options: [{ "key": "calendar", "label": root.tr("tabs.calendar", "Calendar") },
                              { "key": "board", "label": root.tr("tabs.board", "Board") }]
                    current: root.activeTab === 1 ? "board" : "calendar"
                    onPicked: key => root.activeTab = (key === "board" ? 1 : 0)
                }
                Item { Layout.fillWidth: true }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.activeTab

                // ── Calendar tab ──────────────────────────────────────────────
                ColumnLayout {
                    spacing: Style.marginS

                    // Header island (nav + view switch + actions)
                    NBox {
                        forceOpaque: true
                        Layout.fillWidth: true
                        implicitHeight: headerRow.implicitHeight + Style.marginS * 2
                        RowLayout {
                            id: headerRow
                            anchors.fill: parent
                            anchors.leftMargin: Style.marginM
                            anchors.rightMargin: Style.marginM
                            anchors.topMargin: Style.marginXS
                            anchors.bottomMargin: Style.marginXS
                            spacing: Style.marginXS

                            NIconButton { icon: "minimize"; tooltipText: root.tr("compact.back", "Compact view"); onClicked: { root.compact = true; if (root.main) root.main.setView("month") } }
                            NIconButton { icon: "chevron-left"; tooltipText: root.tr("panel.prev", "Previous"); onClicked: if (root.main) root.main.goPrev() }
                            NIconButton { icon: "chevron-right"; tooltipText: root.tr("panel.next", "Next"); onClicked: if (root.main) root.main.goNext() }
                            NButton { text: root.tr("panel.today", "Today"); onClicked: if (root.main) root.main.goToday() }
                            NText {
                                Layout.leftMargin: Style.marginXS
                                Layout.fillWidth: true
                                text: root.periodLabel()
                                pointSize: Style.fontSizeL
                                color: Color.mOnSurface
                                elide: Text.ElideRight
                            }
                            SegControl {
                                options: [{ "key": "month", "label": root.tr("panel.month", "Month") },
                                          { "key": "week", "label": root.tr("panel.week", "Week") },
                                          { "key": "day", "label": root.tr("panel.day", "Day") }]
                                current: root.main ? root.main.viewMode : "month"
                                onPicked: key => { if (root.main) root.main.setView(key) }
                            }
                            NIconButton { Layout.leftMargin: Style.marginXS; icon: "refresh"; tooltipText: root.tr("panel.refresh", "Refresh"); onClicked: if (root.main) root.main.syncNow() }
                            NIconButton { icon: "plus"; tooltipText: root.tr("panel.add", "New event"); onClicked: root.openNew(null) }
                        }
                    }

                    // Auth hint when calsync is not authenticated.
                    NText {
                        Layout.fillWidth: true
                        visible: root.main && root.main.authError
                        text: root.tr("panel.authHint", "Not signed in — run `calsync auth` in a terminal.")
                        color: Color.mError
                        pointSize: Style.fontSizeS
                    }

                    // Calendar body island
                    NBox {
                        forceOpaque: true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Loader {
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            sourceComponent: !root.main ? null
                                             : (root.main.viewMode === "week" ? weekComp
                                                : (root.main.viewMode === "day" ? dayComp : monthComp))
                        }
                    }
                }

                // ── Board tab ─────────────────────────────────────────────────
                Loader {
                    sourceComponent: boardComp
                }
            }
        }

        // ── Editor overlays ───────────────────────────────────────────────────
        Loader {
            anchors.fill: parent
            active: root.inspecting
            sourceComponent: inspectComp
        }
        Loader {
            anchors.fill: parent
            active: root.editing
            sourceComponent: editorComp
        }
        Loader {
            anchors.fill: parent
            active: root.cardEditing
            sourceComponent: cardEditorComp
        }
    }

    // ====================================================================== //
    //  Compact (Clock-like) view: colored header + mini month + weather
    // ====================================================================== //
    Item {
        id: compactContainer
        anchors.fill: parent
        visible: root.compact

        ColumnLayout {
            id: compactCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.marginL
            spacing: Style.marginM

            // Reused Noctalia card: colored date/month/year + clock.
            CalendarHeaderCard {
                Layout.fillWidth: true
            }

            // Custom mini month grid (dots = calsync events).
            NBox {
                forceOpaque: true
                Layout.fillWidth: true
                implicitHeight: miniCol.implicitHeight + Style.marginM * 2

                ColumnLayout {
                    id: miniCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginXS

                    // Nav row: month/year label + prev/today/next + expand.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginXS

                        NText {
                            text: root.main ? Qt.formatDateTime(root.main.selectedDate, "MMMM yyyy").toUpperCase() : ""
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                        }
                        NDivider { Layout.fillWidth: true }
                        NIconButton { icon: "chevron-left"; tooltipText: root.tr("panel.prev", "Previous"); onClicked: if (root.main) root.main.goPrev() }
                        NIconButton { icon: "calendar"; tooltipText: root.tr("panel.today", "Today"); onClicked: if (root.main) root.main.goToday() }
                        NIconButton { icon: "chevron-right"; tooltipText: root.tr("panel.next", "Next"); onClicked: if (root.main) root.main.goNext() }
                        NIconButton { icon: "expand"; tooltipText: root.tr("compact.openFull", "Open full calendar"); onClicked: root.compact = false }
                    }

                    // Weekday header (2-letter uppercase, bold, accent — like the Clock).
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: root.weekdayNames()
                            delegate: NText {
                                required property var modelData
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: String(modelData).substring(0, 2).toUpperCase()
                                pointSize: Style.fontSizeS
                                font.weight: Style.fontWeightBold
                                color: Color.mPrimary
                            }
                        }
                    }

                    // 7-col, 6-week grid.
                    GridLayout {
                        id: miniGrid
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: Style.marginXXS
                        columnSpacing: Style.marginXXS

                        property var gridStart: root.main ? root.main.startOfWeek(root.main.startOfMonth(root.main.selectedDate)) : new Date()

                        Repeater {
                            model: 42
                            delegate: Item {
                                id: miniCell
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: Style.baseWidgetSize * 0.9

                                property var day: root.main ? root.main.addDays(miniGrid.gridStart, index) : new Date()
                                property bool inMonth: root.main && day.getMonth() === root.main.selectedDate.getMonth()
                                property bool isToday: root.main && root.main.sameDay(day, new Date())
                                property var dayEvents: root.main ? root.main.eventsOnDay(day) : []

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: Style.baseWidgetSize * 0.9
                                    height: Style.baseWidgetSize * 0.9
                                    radius: Style.radiusM
                                    color: miniCell.isToday ? Color.mSecondary
                                                            : (cellMA.containsMouse ? Color.mHover : "transparent")
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    NText {
                                        anchors.centerIn: parent
                                        text: miniCell.day.getDate()
                                        pointSize: Style.fontSizeM
                                        font.weight: miniCell.isToday ? Style.fontWeightBold : Style.fontWeightMedium
                                        color: miniCell.isToday ? Color.mOnSecondary
                                                               : (miniCell.inMonth ? Color.mOnSurface : Color.mOnSurfaceVariant)
                                        opacity: miniCell.inMonth ? 1.0 : 0.4
                                    }

                                    // Event dots (calsync per-source colors).
                                    Row {
                                        visible: miniCell.dayEvents.length > 0
                                        spacing: 2
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Style.marginXXS
                                        Repeater {
                                            model: Math.min(miniCell.dayEvents.length, 3)
                                            delegate: Rectangle {
                                                required property int index
                                                width: 4
                                                height: 4
                                                radius: Style.radiusXXS
                                                color: miniCell.isToday ? Color.mOnSecondary : miniCell.dayEvents[index].color
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: cellMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.main) {
                                                root.main.selectedDate = miniCell.day
                                                root.main.setView("day")
                                                root.compact = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Reused Noctalia card: current weather + 5-day forecast.
            WeatherCard {
                Layout.fillWidth: true
                forecastDays: 5
                showLocation: false
            }
        }
    }

    // ====================================================================== //
    //  Reusable timeline pieces (hour gutter + a day's hour column)
    // ====================================================================== //
    component HourGutter: Item {
        id: gut
        property int startH: 7
        property int endH: 22
        implicitWidth: root.gutterW
        implicitHeight: (endH - startH) * root.hourPx + root.topPad * 2
        Repeater {
            model: (gut.endH - gut.startH + 1)
            delegate: NText {
                required property int index
                width: gut.width - 4
                y: index * root.hourPx + root.topPad - (height / 2)
                horizontalAlignment: Text.AlignRight
                text: (gut.startH + index < 10 ? "0" : "") + (gut.startH + index) + ":00"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
            }
        }
    }

    component HourColumn: Item {
        id: col
        property var day
        property var events: []
        property int startH: 7
        property int endH: 22
        property bool showNow: false
        property bool showLeftDivider: false
        // Overlapping events packed into side-by-side lanes.
        property var packed: root.packEvents(col.events)
        // Live fraction-of-day for the "now" line; ticked every minute.
        property real nowFrac: root.hourFrac(new Date())
        // Hour row currently hovered (empty space) for click-to-create feedback.
        property int hoverHour: -1
        // Drag-to-create selection (fraction-of-day in hours, -1 = none).
        property real selStartFrac: -1
        property real selEndFrac: -1
        implicitHeight: (endH - startH) * root.hourPx + root.topPad * 2

        Timer {
            interval: 60000
            repeat: true
            running: col.showNow
            onTriggered: col.nowFrac = root.hourFrac(new Date())
        }

        // subtle today-column tint (week view) to anchor the eye on today
        Rectangle {
            visible: col.showNow
            anchors.fill: parent
            color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.06)
        }

        // left divider (week view: separate day columns)
        Rectangle {
            visible: col.showLeftDivider
            x: 0
            width: 1
            height: col.height
            color: Color.mOutline
        }

        // hour grid lines
        Repeater {
            model: (col.endH - col.startH + 1)
            delegate: Rectangle {
                required property int index
                y: index * root.hourPx + root.topPad
                width: col.width
                height: 1
                color: Color.mOutline
            }
        }

        // hovered-hour highlight (only when idle, i.e. not mid-selection)
        Rectangle {
            visible: col.hoverHour >= col.startH && col.hoverHour < col.endH && col.selStartFrac < 0
            x: 1
            width: col.width - 2
            y: (col.hoverHour - col.startH) * root.hourPx + root.topPad
            height: root.hourPx
            radius: Style.radiusXS
            color: Qt.rgba(Color.mHover.r, Color.mHover.g, Color.mHover.b, 0.5)
        }

        // drag-to-create selection preview (snapped to the half hour)
        Rectangle {
            visible: col.selStartFrac >= 0 && col.selEndFrac >= 0
            x: 1
            width: col.width - 2
            y: (Math.min(col.selStartFrac, col.selEndFrac) - col.startH) * root.hourPx + root.topPad
            height: Math.max(Math.abs(col.selEndFrac - col.selStartFrac) * root.hourPx, 2)
            radius: Style.radiusXS
            color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.30)
            border.width: 1
            border.color: Color.mPrimary
            NText {
                anchors.centerIn: parent
                visible: parent.height > 18
                text: root.fracToTime(Math.min(col.selStartFrac, col.selEndFrac)) + " – " + root.fracToTime(Math.max(col.selStartFrac, col.selEndFrac))
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
            }
        }

        // empty-slot interaction: hover highlight + drag-to-create (15-min snap).
        // preventStealing keeps the drag here (no Flickable scroll); wheel still scrolls.
        MouseArea {
            id: slotMA
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            function fracAt(my) {
                var snapped = Math.round(((my - root.topPad) / root.hourPx + col.startH) * 4) / 4 // 15-min snap
                return Math.max(col.startH, Math.min(snapped, col.endH))
            }
            onPressed: mouse => {
                col.selStartFrac = slotMA.fracAt(mouse.y)
                col.selEndFrac = col.selStartFrac
                col.hoverHour = -1
            }
            onPositionChanged: mouse => {
                if (col.selStartFrac >= 0)
                    col.selEndFrac = slotMA.fracAt(mouse.y)
                else
                    col.hoverHour = Math.floor((mouse.y - root.topPad) / root.hourPx) + col.startH
            }
            onReleased: mouse => {
                if (col.selStartFrac < 0) return
                var lo = Math.min(col.selStartFrac, col.selEndFrac)
                var hi = Math.max(col.selStartFrac, col.selEndFrac)
                col.selStartFrac = -1
                col.selEndFrac = -1
                if (hi - lo < 0.25) hi = lo + 1 // click (no real drag) → 1h event
                if (root.main) root.openNew(col.day, lo, hi)
            }
            onExited: { if (col.selStartFrac < 0) col.hoverHour = -1 }
            onCanceled: { col.selStartFrac = -1; col.selEndFrac = -1; col.hoverHour = -1 }
        }

        // timed events, absolutely positioned by time, packed into lanes
        Repeater {
            model: col.packed
            delegate: Rectangle {
                id: evRect
                required property var modelData
                property var ev: modelData.ev
                property color base: ev.color
                property real dayStartMs: (new Date(col.day.getFullYear(), col.day.getMonth(), col.day.getDate())).getTime()
                property real sH: (ev.start.getTime() - dayStartMs) / 3600000
                property real eH: (ev.end.getTime() - dayStartMs) / 3600000
                property real topH: Math.max(sH, col.startH)
                property real botH: Math.min(Math.max(eH, sH + 0.25), col.endH)
                property real laneW: (col.width - 4) / modelData.lanes
                property bool hovered: evMA.containsMouse
                visible: eH > col.startH && sH < col.endH
                x: 2 + modelData.lane * laneW
                width: laneW - 1
                y: (topH - col.startH) * root.hourPx + root.topPad
                height: Math.max((botH - topH) * root.hourPx, 14)
                radius: Style.radiusXS
                color: Qt.rgba(evRect.base.r, evRect.base.g, evRect.base.b, evRect.hovered ? 0.42 : 0.22)
                border.width: evRect.hovered ? 1 : 0
                border.color: evRect.base
                Behavior on color { ColorAnimation { duration: 100 } }

                Rectangle { width: 3; height: parent.height; radius: 1; color: evRect.base }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 2
                    anchors.topMargin: 1
                    spacing: 0
                    NText {
                        Layout.fillWidth: true
                        text: evRect.ev.summary
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                        elide: Text.ElideRight
                    }
                    NText {
                        visible: evRect.height > 28
                        text: Qt.formatDateTime(evRect.ev.start, "hh:mm")
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                }
                MouseArea {
                    id: evMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openInspect(evRect.ev)
                }
            }
        }

        // current-time indicator (only on today), updated live by the Timer
        Rectangle {
            visible: col.showNow && col.nowFrac >= col.startH && col.nowFrac <= col.endH
            y: (col.nowFrac - col.startH) * root.hourPx + root.topPad
            width: col.width
            height: 2
            color: Color.mError
            Behavior on y { NumberAnimation { duration: 300 } }
        }
    }

    // ====================================================================== //
    //  Month view
    // ====================================================================== //
    Component {
        id: monthComp
        ColumnLayout {
            spacing: Style.marginXS

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: root.weekdayNames()
                    delegate: NText {
                        required property var modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                }
            }

            GridLayout {
                id: monthGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: Style.marginXS
                columnSpacing: Style.marginXS

                property var gridStart: root.main ? root.main.startOfWeek(root.main.startOfMonth(root.main.selectedDate)) : new Date()

                Repeater {
                    model: 42
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Style.radiusS
                        property var day: root.main ? root.main.addDays(monthGrid.gridStart, index) : new Date()
                        property bool inMonth: root.main && day.getMonth() === root.main.selectedDate.getMonth()
                        property bool isToday: root.main && root.main.sameDay(day, new Date())
                        property var dayEvents: root.main ? root.main.eventsOnDay(day) : []
                        property bool hovered: cellMA.containsMouse

                        color: hovered ? Color.mHover
                                       : (inMonth ? Color.mSurface : "transparent")
                        border.width: isToday ? 2 : (hovered ? 1 : 0)
                        border.color: isToday ? Color.mPrimary : Color.mOutline
                        Behavior on color { ColorAnimation { duration: 100 } }

                        MouseArea {
                            id: cellMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.main) { root.main.selectedDate = cell.day; root.main.setView("day") } }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Style.marginXS
                            spacing: 1

                            NText {
                                text: cell.day.getDate()
                                pointSize: Style.fontSizeXS
                                color: cell.inMonth ? (cell.isToday ? Color.mPrimary : Color.mOnSurface) : Color.mOnSurfaceVariant
                            }

                            Repeater {
                                model: Math.min(cell.dayEvents.length, 3)
                                delegate: Rectangle {
                                    id: chip
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: lbl.implicitHeight + 2
                                    radius: 2
                                    property var ev: cell.dayEvents[index]
                                    property color base: ev.color
                                    color: chipMA.containsMouse ? Qt.rgba(base.r, base.g, base.b, 0.22) : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 2
                                        Rectangle { width: 3; height: parent.height; radius: 1; color: chip.ev.color }
                                        NText {
                                            id: lbl
                                            Layout.fillWidth: true
                                            text: (chip.ev.allDay ? "" : Qt.formatDateTime(chip.ev.start, "hh:mm") + " ") + chip.ev.summary
                                            pointSize: Style.fontSizeXS
                                            color: Color.mOnSurface
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        id: chipMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openInspect(chip.ev)
                                    }
                                }
                            }

                            NText {
                                visible: cell.dayEvents.length > 3
                                text: "+" + (cell.dayEvents.length - 3)
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurfaceVariant
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Week view (7 day columns over an hour grid)
    // ====================================================================== //
    Component {
        id: weekComp
        ColumnLayout {
            id: weekWrap
            spacing: Style.marginXS
            property var weekStart: root.main ? root.main.startOfWeek(root.main.selectedDate) : new Date()
            property int sH: root.main ? root.main.dayStartHour() : 7
            property int eH: root.main ? root.main.dayEndHour() : 22

            function allDayFor(i) {
                if (!root.main) return []
                return root.main.eventsOnDay(root.main.addDays(weekWrap.weekStart, i)).filter(function (e) { return e.allDay })
            }
            function timedFor(i) {
                if (!root.main) return []
                return root.main.eventsOnDay(root.main.addDays(weekWrap.weekStart, i)).filter(function (e) { return !e.allDay })
            }
            function anyAllDay() {
                for (var i = 0; i < 7; i++) if (allDayFor(i).length) return true
                return false
            }

            // Day headers
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Item { Layout.preferredWidth: root.gutterW }
                Repeater {
                    model: 7
                    delegate: Rectangle {
                        id: hdrRect
                        required property int index
                        property var day: root.main ? root.main.addDays(weekWrap.weekStart, index) : new Date()
                        property bool isToday: root.main && root.main.sameDay(day, new Date())
                        Layout.fillWidth: true
                        implicitHeight: wh.implicitHeight + Style.marginXS * 2
                        radius: Style.radiusS
                        color: hdrRect.isToday ? Color.mPrimary
                                               : (hdrMA.containsMouse ? Color.mHover : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }
                        ColumnLayout {
                            id: wh
                            anchors.centerIn: parent
                            spacing: 0
                            NText { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(hdrRect.day, "ddd"); pointSize: Style.fontSizeXS; color: hdrRect.isToday ? Color.mOnPrimary : Color.mOnSurfaceVariant }
                            NText { Layout.alignment: Qt.AlignHCenter; text: hdrRect.day.getDate(); pointSize: Style.fontSizeM; color: hdrRect.isToday ? Color.mOnPrimary : Color.mOnSurface }
                        }
                        MouseArea { id: hdrMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.main) { root.main.selectedDate = hdrRect.day; root.main.setView("day") } } }
                    }
                }
            }

            // All-day strip
            RowLayout {
                Layout.fillWidth: true
                visible: weekWrap.anyAllDay()
                spacing: 0
                Item { Layout.preferredWidth: root.gutterW }
                Repeater {
                    model: 7
                    delegate: ColumnLayout {
                        id: adCol
                        required property int index
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 2
                        property var ad: weekWrap.allDayFor(index)
                        Repeater {
                            model: adCol.ad
                            delegate: Rectangle {
                                id: adChip
                                required property var modelData
                                property color base: modelData.color
                                Layout.fillWidth: true
                                implicitHeight: 16
                                radius: Style.radiusXS
                                color: Qt.rgba(adChip.base.r, adChip.base.g, adChip.base.b, adChipMA.containsMouse ? 0.42 : 0.22)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                NText { anchors.fill: parent; anchors.leftMargin: 4; verticalAlignment: Text.AlignVCenter; text: adChip.modelData.summary; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight }
                                MouseArea { id: adChipMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openInspect(adChip.modelData) }
                            }
                        }
                    }
                }
            }

            // Hour grid timeline
            Flickable {
                id: wflick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: wrow.implicitHeight
                Component.onCompleted: Qt.callLater(function () { root.scrollToNow(wflick, weekWrap.sH) })
                RowLayout {
                    id: wrow
                    width: wflick.width
                    spacing: 0
                    HourGutter { Layout.alignment: Qt.AlignTop; startH: weekWrap.sH; endH: weekWrap.eH }
                    Repeater {
                        model: 7
                        delegate: HourColumn {
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            day: root.main ? root.main.addDays(weekWrap.weekStart, index) : new Date()
                            events: weekWrap.timedFor(index)
                            startH: weekWrap.sH
                            endH: weekWrap.eH
                            showNow: root.main && root.main.sameDay(day, new Date())
                            showLeftDivider: index > 0
                        }
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Day view (single-day hour grid)
    // ====================================================================== //
    Component {
        id: dayComp
        ColumnLayout {
            id: dayWrap
            spacing: Style.marginXS
            property var dayList: root.main ? root.main.eventsOnDay(root.main.selectedDate) : []
            property var allDayEvents: dayWrap.dayList.filter(function (e) { return e.allDay })
            property var timed: dayWrap.dayList.filter(function (e) { return !e.allDay })
            property int sH: root.main ? root.main.dayStartHour() : 7
            property int eH: root.main ? root.main.dayEndHour() : 22

            // All-day strip
            RowLayout {
                Layout.fillWidth: true
                visible: dayWrap.allDayEvents.length > 0
                spacing: 0
                Item { Layout.preferredWidth: root.gutterW }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: dayWrap.allDayEvents
                        delegate: Rectangle {
                            id: adRect
                            required property var modelData
                            property color base: modelData.color
                            Layout.fillWidth: true
                            implicitHeight: 20
                            radius: Style.radiusXS
                            color: Qt.rgba(adRect.base.r, adRect.base.g, adRect.base.b, adRectMA.containsMouse ? 0.42 : 0.22)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 4
                                Rectangle { width: 3; Layout.fillHeight: true; radius: 1; color: adRect.base }
                                NText { Layout.fillWidth: true; text: adRect.modelData.summary; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight }
                            }
                            MouseArea { id: adRectMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openInspect(adRect.modelData) }
                        }
                    }
                }
            }

            // Hour grid timeline
            Flickable {
                id: dflick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: drow.implicitHeight
                Component.onCompleted: Qt.callLater(function () { root.scrollToNow(dflick, dayWrap.sH) })
                RowLayout {
                    id: drow
                    width: dflick.width
                    spacing: 0
                    HourGutter { Layout.alignment: Qt.AlignTop; startH: dayWrap.sH; endH: dayWrap.eH }
                    HourColumn {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        day: root.main ? root.main.selectedDate : new Date()
                        events: dayWrap.timed
                        startH: dayWrap.sH
                        endH: dayWrap.eH
                        showNow: root.main && root.main.sameDay(root.main.selectedDate, new Date())
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Event inspection overlay (read-only; "Edit" switches to the editor)
    // ====================================================================== //
    Component {
        id: inspectComp
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true // capture hover so the calendar underneath stops reacting
            onClicked: root.inspecting = false // click outside closes

            NBox {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.marginL * 2, 480 * Style.uiScaleRatio)
                implicitHeight: iform.implicitHeight + Style.marginL * 2
                MouseArea { anchors.fill: parent; onClicked: {} } // swallow inside clicks

                ColumnLayout {
                    id: iform
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS

                    // Title + source dot + recurring badge
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 10; height: 10; radius: 5
                            color: root.insEvent ? root.insEvent.color : Color.mPrimary
                        }
                        NText {
                            Layout.fillWidth: true
                            text: root.insEvent ? root.insEvent.summary : ""
                            pointSize: Style.fontSizeL
                            color: Color.mOnSurface
                            wrapMode: Text.WordWrap
                        }
                        Rectangle {
                            visible: root.insEvent && root.insEvent.recurring === true
                            Layout.alignment: Qt.AlignVCenter
                            radius: Style.radiusXS
                            color: Color.mSecondary
                            implicitWidth: recurLbl.implicitWidth + Style.marginS
                            implicitHeight: recurLbl.implicitHeight + 4
                            NText {
                                id: recurLbl
                                anchors.centerIn: parent
                                text: root.tr("inspect.recurring", "Recurring")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSecondary
                            }
                        }
                    }

                    // Date + time range
                    NText {
                        Layout.fillWidth: true
                        text: root.insEvent ? (Qt.formatDate(root.insEvent.start, "dddd d MMMM yyyy") + "  ·  " + root.timeRange(root.insEvent)) : ""
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    // Location
                    NText {
                        visible: root.insEvent && root.insEvent.location
                        Layout.fillWidth: true
                        text: "📍  " + (root.insEvent ? root.insEvent.location : "")
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    // Video-conference link (Google Meet)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.insEvent && root.insEvent.meetLink
                        NButton {
                            text: root.tr("inspect.join", "Join with Google Meet")
                            icon: "external-link"
                            onClicked: if (root.insEvent && root.insEvent.meetLink) Qt.openUrlExternally(root.insEvent.meetLink)
                        }
                        Item { Layout.fillWidth: true }
                    }

                    NDivider { Layout.fillWidth: true }

                    // Description (multi-line, scrollable)
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(descText.implicitHeight, 220 * Style.uiScaleRatio)
                        contentWidth: width
                        contentHeight: descText.implicitHeight
                        clip: true
                        NText {
                            id: descText
                            width: parent.width
                            // Google event descriptions are HTML — render them formatted.
                            richTextEnabled: root.insEvent && !!root.insEvent.description
                            text: (root.insEvent && root.insEvent.description) ? root.insEvent.description : root.tr("inspect.noDesc", "No description")
                            pointSize: Style.fontSizeS
                            color: (root.insEvent && root.insEvent.description) ? Color.mOnSurface : Color.mOnSurfaceVariant
                            wrapMode: Text.WordWrap
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.marginXS
                        spacing: Style.marginS
                        Item { Layout.fillWidth: true }
                        NButton {
                            text: root.tr("inspect.close", "Close")
                            onClicked: root.inspecting = false
                        }
                        NButton {
                            text: root.tr("inspect.edit", "Edit")
                            icon: "pencil"
                            onClicked: root.editFromInspect()
                        }
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Event editor overlay
    // ====================================================================== //
    Component {
        id: editorComp
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true // capture hover so the calendar underneath stops reacting
            onClicked: {} // swallow clicks behind the dialog

            NBox {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.marginL * 2, 480 * Style.uiScaleRatio)
                implicitHeight: form.implicitHeight + Style.marginL * 2

                ColumnLayout {
                    id: form
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS

                    NText {
                        text: root.edId === "" ? root.tr("editor.new", "New event") : root.tr("editor.edit", "Edit event")
                        pointSize: Style.fontSizeL
                        color: Color.mOnSurface
                    }

                    // Recurring-event scope (this / following / all).
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.edRecurring && root.edId !== ""
                        spacing: Style.marginXXS
                        NText {
                            text: root.tr("editor.recurring", "Recurring event")
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }
                        NComboBox {
                            Layout.fillWidth: true
                            model: root.scopeModel()
                            currentKey: root.edScope
                            onSelected: (key) => root.edScope = key
                        }
                    }

                    NTextInput {
                        Layout.fillWidth: true
                        text: root.edSummary
                        placeholderText: root.tr("editor.summary", "Title")
                        onEditingFinished: root.edSummary = text
                    }

                    NToggle {
                        Layout.fillWidth: true
                        label: root.tr("editor.allDay", "All day")
                        checked: root.edAllDay
                        onToggled: (v) => root.edAllDay = v
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NTextInput {
                            Layout.fillWidth: true
                            text: root.edStartDate
                            placeholderText: "YYYY-MM-DD"
                            onEditingFinished: root.edStartDate = text
                        }
                        NTextInput {
                            Layout.preferredWidth: 90 * Style.uiScaleRatio
                            visible: !root.edAllDay
                            text: root.edStartTime
                            placeholderText: "HH:MM"
                            onEditingFinished: root.edStartTime = text
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NTextInput {
                            Layout.fillWidth: true
                            text: root.edEndDate
                            placeholderText: "YYYY-MM-DD"
                            onEditingFinished: root.edEndDate = text
                        }
                        NTextInput {
                            Layout.preferredWidth: 90 * Style.uiScaleRatio
                            visible: !root.edAllDay
                            text: root.edEndTime
                            placeholderText: "HH:MM"
                            onEditingFinished: root.edEndTime = text
                        }
                    }

                    NTextInput {
                        Layout.fillWidth: true
                        text: root.edLocation
                        placeholderText: root.tr("editor.location", "Location")
                        onEditingFinished: root.edLocation = text
                    }
                    NTextInput {
                        Layout.fillWidth: true
                        text: root.edDesc
                        placeholderText: root.tr("editor.desc", "Description")
                        onEditingFinished: root.edDesc = text
                    }

                    NComboBox {
                        Layout.fillWidth: true
                        model: root.sourceModel()
                        currentKey: root.edSource
                        onSelected: (key) => root.edSource = key
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.marginXS
                        spacing: Style.marginS

                        NButton {
                            visible: root.edId !== ""
                            text: root.tr("editor.delete", "Delete")
                            icon: "trash"
                            onClicked: {
                                if (root.main) {
                                    if (root.edRecurring)
                                        root.main.deleteEvent(root.edId, root.edScope, root.edInstanceStart)
                                    else
                                        root.main.deleteEvent(root.edId)
                                }
                                root.editing = false
                            }
                        }
                        Item { Layout.fillWidth: true }
                        NButton {
                            text: root.tr("editor.cancel", "Cancel")
                            onClicked: root.editing = false
                        }
                        NButton {
                            text: root.tr("editor.save", "Save")
                            icon: "check"
                            onClicked: root.saveEditor()
                        }
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Kanban board view (columns + cards + drag-drop)
    // ====================================================================== //
    Component {
        id: boardComp
        Item {
            id: boardRoot

            // ── Drag state ────────────────────────────────────────────────────
            property string dragId: ""
            property var dragCard: null
            property bool dragging: false
            property real dragX: 0
            property real dragY: 0
            property real grabDX: 0
            property real grabDY: 0
            property real dragW: 200
            property int hoverCol: -1

            function startDrag(card, item, gx, gy) {
                var tl = item.mapToItem(boardRoot, 0, 0)
                boardRoot.dragW = item.width
                boardRoot.grabDX = gx - tl.x
                boardRoot.grabDY = gy - tl.y
                boardRoot.dragCard = card
                boardRoot.dragId = card.id
                boardRoot.dragging = true
                boardRoot.updateDrag(gx, gy)
            }
            function updateDrag(gx, gy) {
                boardRoot.dragX = gx - boardRoot.grabDX
                boardRoot.dragY = gy - boardRoot.grabDY
                boardRoot.hoverCol = boardRoot.columnAt(gx, gy)
            }
            function endDrag() {
                var ci = boardRoot.hoverCol
                var cols = root.boardColumns()
                if (ci >= 0 && ci < cols.length && root.main) {
                    var order = boardRoot.dropOrder(ci, boardRoot.dragY + boardRoot.grabDY)
                    root.main.moveCard(boardRoot.dragId, cols[ci].id, order)
                }
                boardRoot.dragging = false
                boardRoot.dragId = ""
                boardRoot.dragCard = null
                boardRoot.hoverCol = -1
            }
            function columnAt(gx, gy) {
                for (var i = 0; i < colsRepeater.count; i++) {
                    var it = colsRepeater.itemAt(i)
                    if (!it) continue
                    var tl = it.mapToItem(boardRoot, 0, 0)
                    if (gx >= tl.x && gx <= tl.x + it.width && gy >= tl.y && gy <= tl.y + it.height)
                        return i
                }
                return -1
            }
            function dropOrder(colIndex, gy) {
                var it = colsRepeater.itemAt(colIndex)
                if (!it || !it.cardListRepeater) return -1
                var rep = it.cardListRepeater
                var idx = 0
                for (var i = 0; i < rep.count; i++) {
                    var cardItem = rep.itemAt(i)
                    if (!cardItem || !cardItem.cardData) continue
                    if (cardItem.cardData.id === boardRoot.dragId) continue
                    var c = cardItem.mapToItem(boardRoot, 0, cardItem.height / 2)
                    if (gy < c.y) return idx
                    idx++
                }
                return idx
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginS

                // Board header: add-column + error
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NText {
                        visible: root.main && root.main.boardError !== ""
                        Layout.fillWidth: true
                        text: root.main ? root.main.boardError : ""
                        color: Color.mError
                        pointSize: Style.fontSizeXS
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillWidth: true; visible: !(root.main && root.main.boardError !== "") }
                    NButton {
                        visible: root.main && root.main.tasksEnabled()
                        text: root.tr("board.syncTasks", "Sync Tasks")
                        icon: "refresh-dot"
                        onClicked: if (root.main) root.main.syncTasks()
                    }
                    NButton {
                        text: root.tr("board.addColumn", "Add column")
                        icon: "plus"
                        onClicked: { root.cgName = ""; root.columnEditing = true }
                    }
                }

                // Empty state
                NText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.boardColumns().length === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.tr("board.empty", "No columns yet.")
                    color: Color.mOnSurfaceVariant
                }

                // Columns
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.boardColumns().length > 0
                    spacing: Style.marginS

                    Repeater {
                        id: colsRepeater
                        model: root.boardColumns()
                        delegate: Rectangle {
                            id: colItem
                            required property int index
                            required property var modelData
                            property alias cardListRepeater: cardsRep
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Style.radiusM
                            color: Color.mSurface
                            border.width: (boardRoot.dragging && boardRoot.hoverCol === index) ? 2 : 1
                            border.color: (boardRoot.dragging && boardRoot.hoverCol === index) ? Color.mPrimary : Color.mOutline

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Style.marginS
                                spacing: Style.marginXS

                                // Column header
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.marginXS
                                    NText {
                                        text: colItem.modelData.name
                                        pointSize: Style.fontSizeM
                                        color: Color.mOnSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    NText {
                                        text: root.cardsIn(colItem.modelData.id).length
                                        pointSize: Style.fontSizeXS
                                        color: Color.mOnSurfaceVariant
                                    }
                                    NIconButton {
                                        baseSize: Math.round(Style.baseWidgetSize * 0.7)
                                        icon: "plus"
                                        tooltipText: root.tr("board.addCard", "Add card")
                                        onClicked: root.openNewCard(colItem.modelData.id)
                                    }
                                    NIconButton {
                                        baseSize: Math.round(Style.baseWidgetSize * 0.7)
                                        visible: root.cardsIn(colItem.modelData.id).length === 0 && root.boardColumns().length > 1
                                        icon: "trash"
                                        tooltipText: root.tr("board.rmColumn", "Remove empty column")
                                        onClicked: if (root.main) root.main.rmColumn(colItem.modelData.id)
                                    }
                                }

                                NDivider { Layout.fillWidth: true }

                                // Card list
                                Flickable {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    contentWidth: width
                                    contentHeight: cardsCol.implicitHeight
                                    ColumnLayout {
                                        id: cardsCol
                                        width: parent.width
                                        spacing: Style.marginXS

                                        Repeater {
                                            id: cardsRep
                                            model: root.cardsIn(colItem.modelData.id)
                                            delegate: Rectangle {
                                                id: cardItem
                                                required property var modelData
                                                property var cardData: modelData
                                                Layout.fillWidth: true
                                                implicitHeight: cardCol.implicitHeight + Style.marginS * 2
                                                radius: Style.radiusS
                                                color: Color.mSurfaceVariant
                                                opacity: (boardRoot.dragId === modelData.id) ? 0.3 : 1.0

                                                // priority accent
                                                Rectangle {
                                                    width: 3
                                                    height: parent.height
                                                    radius: 1
                                                    color: root.priorityColor(cardItem.modelData.priority)
                                                }

                                                ColumnLayout {
                                                    id: cardCol
                                                    anchors.fill: parent
                                                    anchors.margins: Style.marginS
                                                    anchors.leftMargin: Style.marginS + 4
                                                    spacing: 3

                                                    NText {
                                                        Layout.fillWidth: true
                                                        text: cardItem.modelData.title
                                                        pointSize: Style.fontSizeS
                                                        color: Color.mOnSurface
                                                        elide: Text.ElideRight
                                                        wrapMode: Text.WordWrap
                                                        maximumLineCount: 2
                                                    }

                                                    // progress bar
                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        visible: cardItem.modelData.progress > 0
                                                        height: 4
                                                        radius: 2
                                                        color: Color.mSurface
                                                        Rectangle {
                                                            width: parent.width * (cardItem.modelData.progress / 100)
                                                            height: parent.height
                                                            radius: 2
                                                            color: root.priorityColor(cardItem.modelData.priority)
                                                        }
                                                    }

                                                    // due + sync indicator
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Style.marginXS
                                                        visible: !!cardItem.modelData.due || !!cardItem.modelData.googleTaskId
                                                        NText {
                                                            visible: !!cardItem.modelData.due
                                                            text: "⏱ " + (cardItem.modelData.due || "")
                                                            pointSize: Style.fontSizeXS
                                                            color: Color.mOnSurfaceVariant
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        NText {
                                                            visible: !!cardItem.modelData.googleTaskId
                                                            text: root.tr("board.synced", "✓ Tasks")
                                                            pointSize: Style.fontSizeXS
                                                            color: Color.mPrimary
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    preventStealing: true
                                                    property real pgx: 0
                                                    property real pgy: 0
                                                    property bool armed: false
                                                    onPressed: mouse => {
                                                        var p = mapToItem(boardRoot, mouse.x, mouse.y)
                                                        pgx = p.x; pgy = p.y; armed = true
                                                    }
                                                    onPositionChanged: mouse => {
                                                        var p = mapToItem(boardRoot, mouse.x, mouse.y)
                                                        if (!boardRoot.dragging) {
                                                            if (armed && (Math.abs(p.x - pgx) + Math.abs(p.y - pgy)) > 8)
                                                                boardRoot.startDrag(cardItem.cardData, cardItem, p.x, p.y)
                                                        } else {
                                                            boardRoot.updateDrag(p.x, p.y)
                                                        }
                                                    }
                                                    onReleased: {
                                                        if (boardRoot.dragging) boardRoot.endDrag()
                                                        else if (armed) root.openCard(cardItem.cardData)
                                                        armed = false
                                                    }
                                                    onCanceled: {
                                                        if (boardRoot.dragging) boardRoot.endDrag()
                                                        armed = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Floating drag ghost
            Rectangle {
                visible: boardRoot.dragging
                x: boardRoot.dragX
                y: boardRoot.dragY
                width: boardRoot.dragW
                height: ghostText.implicitHeight + Style.marginM
                z: 1000
                radius: Style.radiusS
                color: Color.mPrimary
                opacity: 0.92
                NText {
                    id: ghostText
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    text: boardRoot.dragCard ? boardRoot.dragCard.title : ""
                    color: Color.mOnPrimary
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ── Card editor overlay ───────────────────────────────────────────────────
    Component {
        id: cardEditorComp
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true // capture hover so the calendar underneath stops reacting
            onClicked: {} // swallow clicks behind the dialog

            NBox {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.marginL * 2, 460 * Style.uiScaleRatio)
                implicitHeight: cform.implicitHeight + Style.marginL * 2

                ColumnLayout {
                    id: cform
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS

                    NText {
                        text: root.cdId === "" ? root.tr("board.newCard", "New card") : root.tr("board.editCard", "Edit card")
                        pointSize: Style.fontSizeL
                        color: Color.mOnSurface
                    }

                    NTextInput {
                        Layout.fillWidth: true
                        text: root.cdTitle
                        placeholderText: root.tr("board.title", "Title")
                        onEditingFinished: root.cdTitle = text
                    }
                    NTextInput {
                        Layout.fillWidth: true
                        text: root.cdNotes
                        placeholderText: root.tr("board.notes", "Notes")
                        onEditingFinished: root.cdNotes = text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginXXS
                            NText { text: root.tr("board.column", "Column"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                            NComboBox {
                                Layout.fillWidth: true
                                model: root.columnModel()
                                currentKey: root.cdColumn
                                onSelected: key => root.cdColumn = key
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginXXS
                            NText { text: root.tr("board.priority", "Priority"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                            NComboBox {
                                Layout.fillWidth: true
                                model: root.priorityModel()
                                currentKey: root.cdPriority
                                onSelected: key => root.cdPriority = key
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginXXS
                        NText {
                            text: root.tr("board.progress", "Progress") + ": " + root.cdProgress + "%"
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }
                        NSlider {
                            Layout.fillWidth: true
                            from: 0; to: 100; stepSize: 5
                            value: root.cdProgress
                            onValueChanged: root.cdProgress = value
                        }
                    }

                    NTextInput {
                        Layout.fillWidth: true
                        text: root.cdDue
                        placeholderText: root.tr("board.due", "Due (YYYY-MM-DD)")
                        onEditingFinished: root.cdDue = text
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.marginXS
                        spacing: Style.marginS

                        NButton {
                            visible: root.cdId !== ""
                            text: root.tr("editor.delete", "Delete")
                            icon: "trash"
                            onClicked: root.deleteCard()
                        }
                        Item { Layout.fillWidth: true }
                        NButton {
                            text: root.tr("editor.cancel", "Cancel")
                            onClicked: root.cardEditing = false
                        }
                        NButton {
                            text: root.tr("editor.save", "Save")
                            icon: "check"
                            enabled: root.cdTitle !== ""
                            onClicked: root.saveCard()
                        }
                    }
                }
            }
        }
    }

    // ── Add-column overlay ────────────────────────────────────────────────────
    Component {
        id: columnEditorComp
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {}

            NBox {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.marginL * 2, 360 * Style.uiScaleRatio)
                implicitHeight: gform.implicitHeight + Style.marginL * 2

                ColumnLayout {
                    id: gform
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS

                    NText {
                        text: root.tr("board.addColumn", "Add column")
                        pointSize: Style.fontSizeL
                        color: Color.mOnSurface
                    }
                    NTextInput {
                        Layout.fillWidth: true
                        text: root.cgName
                        placeholderText: root.tr("board.columnName", "Column name")
                        onEditingFinished: root.cgName = text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Style.marginXS
                        spacing: Style.marginS
                        Item { Layout.fillWidth: true }
                        NButton {
                            text: root.tr("editor.cancel", "Cancel")
                            onClicked: root.columnEditing = false
                        }
                        NButton {
                            text: root.tr("editor.save", "Save")
                            icon: "check"
                            enabled: root.cgName !== ""
                            onClicked: {
                                if (root.main) root.main.addColumn(root.cgName)
                                root.columnEditing = false
                            }
                        }
                    }
                }
            }
        }
    }

    // Add-column overlay loader.
    Loader {
        anchors.fill: parent
        active: root.columnEditing
        sourceComponent: columnEditorComp
    }
}
