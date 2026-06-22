import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

// Plugin settings: calendar mapping (id → source/color/visibility) and view
// preferences. "Detect" runs `calsync calendars` to discover available ones.
ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null
    spacing: Style.marginM

    property var calendarsLocal: []
    property string defaultView: "month"
    property int weekStartsOn: 1
    property bool syncOnOpen: true
    property bool ensureDaemon: true
    property bool enableTasks: false
    property string binPath: "calsync"
    property string barFormat: "HH:mm ddd, MMM dd"
    property string barFormatVertical: "HH mm - dd MM"
    property bool _loaded: false

    function tr(k, fb) { return pluginApi ? pluginApi.tr(k) : fb }

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
        calendarsLocal = (s.calendars ?? []).map(function (c) {
            return {
                "id": c.id ?? "",
                "source": c.source ?? "perso",
                "color": c.color ?? "#7C4DFF",
                "summary": c.summary ?? "",
                "visible": c.visible !== false
            }
        })
        defaultView = s.defaultView ?? "month"
        weekStartsOn = s.weekStartsOn ?? 1
        syncOnOpen = s.syncOnOpen !== false
        ensureDaemon = s.ensureDaemon !== false
        enableTasks = s.enableTasks === true
        binPath = s.binPath ?? "calsync"
        barFormat = s.barFormat ?? "HH:mm ddd, MMM dd"
        barFormatVertical = s.barFormatVertical ?? "HH mm - dd MM"
        _loaded = true
    }

    Component.onCompleted: _load()
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
        s.calendars = root.calendarsLocal
        s.defaultView = root.defaultView
        s.weekStartsOn = root.weekStartsOn
        s.syncOnOpen = root.syncOnOpen
        s.ensureDaemon = root.ensureDaemon
        s.enableTasks = root.enableTasks
        s.binPath = root.binPath
        s.barFormat = root.barFormat
        s.barFormatVertical = root.barFormatVertical
        pluginApi.saveSettings()
    }

    function updateCal(i, key, val) {
        if (i < 0 || i >= calendarsLocal.length) return
        var copy = calendarsLocal.slice()
        copy[i] = Object.assign({}, copy[i])
        copy[i][key] = val
        calendarsLocal = copy
        saveSettings()
    }
    function addCal() {
        var copy = calendarsLocal.slice()
        copy.push({ "id": "", "source": "perso", "color": "#7C4DFF", "summary": "", "visible": true })
        calendarsLocal = copy
        saveSettings()
    }
    function removeCal(i) {
        var copy = calendarsLocal.slice()
        copy.splice(i, 1)
        calendarsLocal = copy
        saveSettings()
    }

    // ── Detect calendars via the CLI ─────────────────────────────────────────
    Process {
        id: detectProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed
                try { parsed = JSON.parse(this.text || "{}") } catch (e) { return }
                var live = (parsed && parsed.calendars) ? parsed.calendars : []
                var copy = root.calendarsLocal.slice()
                for (var i = 0; i < live.length; i++) {
                    var found = false
                    for (var j = 0; j < copy.length; j++)
                        if (copy[j].id === live[i].id) { found = true; copy[j] = Object.assign({}, copy[j], { "summary": live[i].summary }); break }
                    if (!found)
                        copy.push({ "id": live[i].id, "source": live[i].primary ? "perso" : "work",
                                    "color": "#7C4DFF", "summary": live[i].summary ?? "", "visible": true })
                }
                root.calendarsLocal = copy
                root.saveSettings()
            }
        }
    }
    function detect() {
        detectProc.running = false
        detectProc.command = [root.binPath, "calendars"]
        detectProc.running = true
    }

    // ── UI ───────────────────────────────────────────────────────────────────
    NLabel {
        label: root.tr("settings.calendars", "Calendars")
        description: root.tr("settings.calendarsDesc", "Map each Google calendar to a source, color and visibility.")
    }

    Repeater {
        model: root.calendarsLocal
        delegate: Rectangle {
            required property int index
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: calCol.implicitHeight + Style.marginM * 2
            radius: Style.radiusS
            color: Color.mSurfaceVariant

            ColumnLayout {
                id: calCol
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NTextInput {
                        Layout.fillWidth: true
                        text: modelData.id
                        placeholderText: root.tr("settings.idPlaceholder", "calendar id (e.g. you@gmail.com)")
                        onEditingFinished: root.updateCal(index, "id", text)
                    }
                    NIconButton {
                        icon: "trash"
                        tooltipText: root.tr("settings.removeCal", "Remove")
                        colorFgHover: Color.mError
                        onClicked: root.removeCal(index)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NComboBox {
                        Layout.preferredWidth: 130 * Style.uiScaleRatio
                        model: [
                            { "key": "perso", "name": root.tr("settings.perso", "Personal") },
                            { "key": "work", "name": root.tr("settings.work", "Work") }
                        ]
                        currentKey: modelData.source
                        onSelected: (key) => root.updateCal(index, "source", key)
                    }
                    NTextInput {
                        Layout.preferredWidth: 110 * Style.uiScaleRatio
                        text: modelData.color
                        placeholderText: "#RRGGBB"
                        onEditingFinished: root.updateCal(index, "color", text)
                    }
                    Rectangle { width: 22; height: 22; radius: Style.radiusXS; color: modelData.color || Color.mPrimary }
                    Item { Layout.fillWidth: true }
                    NToggle {
                        label: root.tr("settings.visible", "Visible")
                        checked: modelData.visible
                        onToggled: (v) => root.updateCal(index, "visible", v)
                    }
                }
                NText {
                    visible: modelData.summary !== ""
                    text: modelData.summary
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NButton { text: root.tr("settings.addCal", "Add calendar"); icon: "plus"; onClicked: root.addCal() }
        NButton { text: root.tr("settings.detect", "Detect from Google"); icon: "refresh"; onClicked: root.detect() }
    }

    NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

    NLabel { label: root.tr("settings.view", "View") }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NComboBox {
            Layout.preferredWidth: 150 * Style.uiScaleRatio
            model: [
                { "key": "month", "name": root.tr("panel.month", "Month") },
                { "key": "week", "name": root.tr("panel.week", "Week") },
                { "key": "day", "name": root.tr("panel.day", "Day") }
            ]
            currentKey: root.defaultView
            onSelected: (key) => { root.defaultView = key; root.saveSettings() }
        }
        NComboBox {
            Layout.preferredWidth: 150 * Style.uiScaleRatio
            model: [
                { "key": "1", "name": root.tr("settings.monday", "Monday") },
                { "key": "0", "name": root.tr("settings.sunday", "Sunday") }
            ]
            currentKey: String(root.weekStartsOn)
            onSelected: (key) => { root.weekStartsOn = parseInt(key); root.saveSettings() }
        }
    }

    NToggle {
        Layout.fillWidth: true
        label: root.tr("settings.syncOnOpen", "Sync when opening the panel")
        checked: root.syncOnOpen
        onToggled: (v) => { root.syncOnOpen = v; root.saveSettings() }
    }
    NToggle {
        Layout.fillWidth: true
        label: root.tr("settings.ensureDaemon", "Start the live-sync daemon if needed")
        description: root.tr("settings.ensureDaemonDesc", "Runs `systemctl --user enable --now calsync` when the panel opens and the daemon isn't running.")
        checked: root.ensureDaemon
        onToggled: (v) => { root.ensureDaemon = v; root.saveSettings() }
    }
    NToggle {
        Layout.fillWidth: true
        label: root.tr("settings.enableTasks", "Link the board to Google Tasks")
        description: root.tr("settings.enableTasksDesc", "Shows a “Sync Tasks” button on the board. Requires re-running `calsync auth` to grant the Tasks scope.")
        checked: root.enableTasks
        onToggled: (v) => { root.enableTasks = v; root.saveSettings() }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        NLabel { label: root.tr("settings.binPath", "calsync binary"); description: root.tr("settings.binPathDesc", "Path or name of the calsync CLI (must be on PATH).") }
        NTextInput {
            Layout.fillWidth: true
            text: root.binPath
            onEditingFinished: { root.binPath = text; root.saveSettings() }
        }
    }

    NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

    NLabel {
        label: root.tr("settings.bar", "Bar widget")
        description: root.tr("settings.barDesc", "Date/time format shown in the bar (Qt format, e.g. HH:mm ddd, MMM dd).")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS
            NLabel { label: root.tr("settings.barFormat", "Horizontal bar") }
            NTextInput {
                Layout.fillWidth: true
                text: root.barFormat
                placeholderText: "HH:mm ddd, MMM dd"
                onEditingFinished: { root.barFormat = text; root.saveSettings() }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXS
            NLabel { label: root.tr("settings.barFormatVertical", "Vertical bar") }
            NTextInput {
                Layout.fillWidth: true
                text: root.barFormatVertical
                placeholderText: "HH mm - dd MM"
                onEditingFinished: { root.barFormatVertical = text; root.saveSettings() }
            }
        }
    }
}
