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
    //  Week view (7 day columns, each a list of that day's events)
    // ====================================================================== //
    Component {
        id: weekComp
        RowLayout {
            id: weekRow
            spacing: Style.marginXS

            Repeater {
                model: 7
                delegate: ColumnLayout {
                    id: dayColW
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.marginXS
                    property var day: root.main ? root.main.addDays(root.main.startOfWeek(root.main.selectedDate), index) : new Date()
                    property bool isToday: root.main && root.main.sameDay(day, new Date())
                    property var dayEvents: root.main ? root.main.eventsOnDay(day) : []

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: hdr.implicitHeight + Style.marginXS * 2
                        radius: Style.radiusS
                        color: dayColW.isToday ? Color.mPrimary : Color.mSurfaceVariant
                        ColumnLayout {
                            id: hdr
                            anchors.centerIn: parent
                            spacing: 0
                            NText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Qt.formatDateTime(dayColW.day, "ddd")
                                pointSize: Style.fontSizeXS
                                color: dayColW.isToday ? Color.mOnPrimary : Color.mOnSurfaceVariant
                            }
                            NText {
                                Layout.alignment: Qt.AlignHCenter
                                text: dayColW.day.getDate()
                                pointSize: Style.fontSizeM
                                color: dayColW.isToday ? Color.mOnPrimary : Color.mOnSurface
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (root.main) { root.main.selectedDate = dayColW.day; root.main.setView("day") } }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ColumnLayout {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                model: dayColW.dayEvents
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: chipCol.implicitHeight + Style.marginXS * 2
                                    radius: Style.radiusXS
                                    color: Color.mSurface
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: Style.marginXS
                                        Rectangle { width: 3; Layout.fillHeight: true; radius: 1; color: modelData.color }
                                        ColumnLayout {
                                            id: chipCol
                                            Layout.fillWidth: true
                                            Layout.margins: Style.marginXS
                                            spacing: 0
                                            NText { Layout.fillWidth: true; text: modelData.summary; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight }
                                            NText { text: root.timeRange(modelData); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.openEdit(modelData) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ====================================================================== //
    //  Day view (agenda)
    // ====================================================================== //
    Component {
        id: dayComp
        ScrollView {
            clip: true
            ColumnLayout {
                id: dayCol
                width: parent.width
                spacing: Style.marginXS

                property var dayEvents: root.main ? root.main.eventsOnDay(root.main.selectedDate) : []

                NText {
                    visible: dayCol.dayEvents.length === 0
                    text: root.tr("panel.noEvents", "No events.")
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                }

                Repeater {
                    model: dayCol.dayEvents
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: row.implicitHeight + Style.marginM * 2
                        radius: Style.radiusS
                        color: Color.mSurfaceVariant
                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginM
                            Rectangle { width: 4; Layout.fillHeight: true; radius: 2; color: modelData.color }
                            NText {
                                Layout.preferredWidth: 110 * Style.uiScaleRatio
                                text: root.timeRange(modelData)
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurfaceVariant
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                NText { Layout.fillWidth: true; text: modelData.summary; pointSize: Style.fontSizeM; color: Color.mOnSurface; elide: Text.ElideRight }
                                NText { visible: modelData.location !== ""; Layout.fillWidth: true; text: modelData.location; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; elide: Text.ElideRight }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.openEdit(modelData) }
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
