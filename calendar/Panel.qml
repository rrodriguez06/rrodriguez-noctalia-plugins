import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

// Calendar panel: header (period nav + view switch + actions), month/week/day
// views, and an event editor overlay. All data comes from main (the CLI bridge).
Item {
    id: root
    property var pluginApi: null
    readonly property var main: pluginApi?.mainInstance ?? null

    // Noctalia panel contract.
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 920 * Style.uiScaleRatio
    property real contentPreferredHeight: 680 * Style.uiScaleRatio
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

    onVisibleChanged: {
        if (main) main.setPanelOpen(visible)
        if (!visible) root.editing = false
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
            if (s && !seen[s]) { seen[s] = true; out.push({ "key": s, "name": s }) }
        }
        if (out.length === 0) {
            out.push({ "key": "perso", "name": "perso" })
            out.push({ "key": "work", "name": "work" })
        }
        return out
    }

    // ── Editor helpers ───────────────────────────────────────────────────────
    function openNew(day) {
        var d = day ? day : (main ? main.selectedDate : new Date())
        root.edId = ""
        root.edSummary = ""
        root.edAllDay = false
        root.edStartDate = Qt.formatDate(d, "yyyy-MM-dd")
        root.edEndDate = Qt.formatDate(d, "yyyy-MM-dd")
        root.edStartTime = "09:00"
        root.edEndTime = "10:00"
        root.edLocation = ""
        root.edDesc = ""
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
        root.editing = true
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
            main.editEvent(root.edId, {
                "summary": root.edSummary, "start": start, "end": end,
                "allDay": root.edAllDay, "location": root.edLocation, "desc": root.edDesc
            })
        }
        root.editing = false
    }

    function timeRange(ev) {
        if (ev.allDay) return root.tr("panel.allDay", "All day")
        return Qt.formatDateTime(ev.start, "hh:mm") + "–" + Qt.formatDateTime(ev.end, "hh:mm")
    }

    Item {
        id: panelContainer
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM
            opacity: root.editing ? 0.15 : 1.0

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NIconButton { icon: "chevron-left"; onClicked: if (root.main) root.main.goPrev() }
                NIconButton { icon: "chevron-right"; onClicked: if (root.main) root.main.goNext() }
                NButton {
                    text: root.tr("panel.today", "Today")
                    onClicked: if (root.main) root.main.goToday()
                }
                NText {
                    Layout.leftMargin: Style.marginS
                    text: root.periodLabel()
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurface
                }

                Item { Layout.fillWidth: true }

                NButton {
                    text: root.tr("panel.month", "Month")
                    enabled: !root.main || root.main.viewMode !== "month"
                    onClicked: if (root.main) root.main.setView("month")
                }
                NButton {
                    text: root.tr("panel.week", "Week")
                    enabled: !root.main || root.main.viewMode !== "week"
                    onClicked: if (root.main) root.main.setView("week")
                }
                NButton {
                    text: root.tr("panel.day", "Day")
                    enabled: !root.main || root.main.viewMode !== "day"
                    onClicked: if (root.main) root.main.setView("day")
                }

                NIconButton {
                    Layout.leftMargin: Style.marginS
                    icon: "refresh"
                    tooltipText: root.tr("panel.refresh", "Refresh")
                    onClicked: if (root.main) root.main.syncNow()
                }
                NIconButton {
                    icon: "plus"
                    tooltipText: root.tr("panel.add", "New event")
                    onClicked: root.openNew(null)
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

            // ── Body ─────────────────────────────────────────────────────────
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: !root.main ? null
                                 : (root.main.viewMode === "week" ? weekComp
                                    : (root.main.viewMode === "day" ? dayComp : monthComp))
            }
        }

        // ── Editor overlay ───────────────────────────────────────────────────
        Loader {
            anchors.fill: parent
            active: root.editing
            sourceComponent: editorComp
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
        implicitHeight: (endH - startH) * root.hourPx + root.topPad * 2

        // hour grid lines
        Repeater {
            model: (col.endH - col.startH + 1)
            delegate: Rectangle {
                required property int index
                y: index * root.hourPx + root.topPad
                width: col.width
                height: 1
                color: Color.mSurfaceVariant
            }
        }

        // timed events, absolutely positioned by time
        Repeater {
            model: col.events
            delegate: Rectangle {
                id: evRect
                required property var modelData
                property color base: modelData.color
                property real dayStartMs: (new Date(col.day.getFullYear(), col.day.getMonth(), col.day.getDate())).getTime()
                property real sH: (modelData.start.getTime() - dayStartMs) / 3600000
                property real eH: (modelData.end.getTime() - dayStartMs) / 3600000
                property real topH: Math.max(sH, col.startH)
                property real botH: Math.min(Math.max(eH, sH + 0.25), col.endH)
                visible: eH > col.startH && sH < col.endH
                x: 2
                width: col.width - 4
                y: (topH - col.startH) * root.hourPx + root.topPad
                height: Math.max((botH - topH) * root.hourPx, 14)
                radius: Style.radiusXS
                color: Qt.rgba(evRect.base.r, evRect.base.g, evRect.base.b, 0.22)

                Rectangle { width: 3; height: parent.height; radius: 1; color: evRect.base }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 2
                    anchors.topMargin: 1
                    spacing: 0
                    NText {
                        Layout.fillWidth: true
                        text: modelData.summary
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                        elide: Text.ElideRight
                    }
                    NText {
                        visible: evRect.height > 28
                        text: Qt.formatDateTime(modelData.start, "hh:mm")
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: root.openEdit(modelData) }
            }
        }

        // current-time indicator (only on today)
        Rectangle {
            property real nowH: {
                var n = new Date()
                return n.getHours() + n.getMinutes() / 60
            }
            visible: col.showNow && nowH >= col.startH && nowH <= col.endH
            y: (nowH - col.startH) * root.hourPx + root.topPad
            width: col.width
            height: 2
            color: Color.mError
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

                        color: inMonth ? Color.mSurface : Color.mSurfaceVariant
                        border.width: isToday ? 2 : 0
                        border.color: Color.mPrimary

                        MouseArea {
                            anchors.fill: parent
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
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: lbl.implicitHeight + 2
                                    radius: 2
                                    color: Qt.rgba(0, 0, 0, 0)
                                    property var ev: cell.dayEvents[index]
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 2
                                        Rectangle { width: 3; height: parent.height; radius: 1; color: ev.color }
                                        NText {
                                            id: lbl
                                            Layout.fillWidth: true
                                            text: (ev.allDay ? "" : Qt.formatDateTime(ev.start, "hh:mm") + " ") + ev.summary
                                            pointSize: Style.fontSizeXS
                                            color: Color.mOnSurface
                                            elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.openEdit(ev) }
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
                        color: hdrRect.isToday ? Color.mPrimary : Color.mSurfaceVariant
                        ColumnLayout {
                            id: wh
                            anchors.centerIn: parent
                            spacing: 0
                            NText { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(hdrRect.day, "ddd"); pointSize: Style.fontSizeXS; color: hdrRect.isToday ? Color.mOnPrimary : Color.mOnSurfaceVariant }
                            NText { Layout.alignment: Qt.AlignHCenter; text: hdrRect.day.getDate(); pointSize: Style.fontSizeM; color: hdrRect.isToday ? Color.mOnPrimary : Color.mOnSurface }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { if (root.main) { root.main.selectedDate = hdrRect.day; root.main.setView("day") } } }
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
                                color: Qt.rgba(adChip.base.r, adChip.base.g, adChip.base.b, 0.22)
                                NText { anchors.fill: parent; anchors.leftMargin: 4; verticalAlignment: Text.AlignVCenter; text: modelData.summary; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight }
                                MouseArea { anchors.fill: parent; onClicked: root.openEdit(modelData) }
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
                            color: Qt.rgba(adRect.base.r, adRect.base.g, adRect.base.b, 0.22)
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 4
                                Rectangle { width: 3; Layout.fillHeight: true; radius: 1; color: adRect.base }
                                NText { Layout.fillWidth: true; text: modelData.summary; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.openEdit(modelData) }
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
    //  Event editor overlay
    // ====================================================================== //
    Component {
        id: editorComp
        MouseArea {
            anchors.fill: parent
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
                            onClicked: { if (root.main) root.main.deleteEvent(root.edId); root.editing = false }
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
}
