import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

// Plugin settings, organized in two tabs:
//   • Accounts — connect/disconnect Google accounts and choose which calendars
//     are synced + their per-calendar color. This is the single UI over calsync's
//     config.yaml (the source of truth for what syncs).
//   • General — view preferences, daemon, binary path and bar formats.
ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null
    spacing: Style.marginM

    property string activeTab: "accounts" // accounts | general

    // calsync config (config get): [{id, account, source, color, summary}]
    property var configCals: []
    // authenticated accounts (auth status): [{account, authenticated}]
    property var accounts: []
    // discovered calendars across accounts (calendars; network): model.Calendar[]
    property var discovered: []
    property bool discovering: false
    property bool authRunning: false

    // Reminder settings (mirrored from calsync config; written via set-reminders).
    property bool remEnabled: true
    property bool remBefore: true
    property int remLeadMinutes: 10
    property bool remAtStart: true

    // General settings (mirrored from pluginSettings).
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
    function bin() { return root.binPath || "calsync" }

    Component.onCompleted: { _load(); reloadAll() }
    onPluginApiChanged: { _load(); reloadAll() }

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
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

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
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

    // ── Data loading ─────────────────────────────────────────────────────────
    function reloadAll() { loadConfig(); loadAccounts() }

    Process {
        id: configGetProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed
                try { parsed = JSON.parse(this.text || "{}") } catch (e) { return }
                root.configCals = (parsed && parsed.calendars) ? parsed.calendars : []
                var rem = (parsed && parsed.reminders) ? parsed.reminders : {}
                root.remEnabled = rem.enabled !== false
                var lead = rem.leadMinutes || []
                root.remAtStart = lead.indexOf(0) >= 0
                var before = lead.filter(function (m) { return m > 0 })
                root.remBefore = before.length > 0
                if (before.length > 0) root.remLeadMinutes = before[0]
            }
        }
    }
    function loadConfig() {
        configGetProc.running = false
        configGetProc.command = [root.bin(), "config", "get"]
        configGetProc.running = true
    }

    Process {
        id: authStatusProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed
                try { parsed = JSON.parse(this.text || "{}") } catch (e) { return }
                root.accounts = (parsed && parsed.accounts) ? parsed.accounts : []
            }
        }
    }
    function loadAccounts() {
        authStatusProc.running = false
        authStatusProc.command = [root.bin(), "auth", "status"]
        authStatusProc.running = true
    }

    Process {
        id: calendarsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.discovering = false
                var parsed
                try { parsed = JSON.parse(this.text || "{}") } catch (e) { return }
                root.discovered = (parsed && parsed.calendars) ? parsed.calendars : []
            }
        }
        onExited: code => { root.discovering = false }
    }
    function loadDiscovered() {
        root.discovering = true
        calendarsProc.running = false
        calendarsProc.command = [root.bin(), "calendars"]
        calendarsProc.running = true
    }

    // Launch the interactive OAuth flow (opens a browser). Refresh on completion.
    Process {
        id: authProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.authRunning = false
                root.loadAccounts()
                root.loadDiscovered()
            }
        }
        onExited: code => { root.authRunning = false; root.loadAccounts() }
    }
    function addAccount() {
        if (root.authRunning) return
        root.authRunning = true
        authProc.running = false
        authProc.command = [root.bin(), "auth"]
        authProc.running = true
    }

    Process {
        id: logoutProc
        stdout: StdioCollector { onStreamFinished: { root.loadAccounts(); root.loadDiscovered() } }
    }
    function logout(account) {
        logoutProc.running = false
        logoutProc.command = [root.bin(), "auth", "logout", "--account", account]
        logoutProc.running = true
    }

    // Config mutations (set/rm calendar). Reload config + refresh the running
    // plugin's colors after each change.
    Process {
        id: cfgMutateProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadConfig()
                if (root.mainInstance) root.mainInstance._loadCalendars()
            }
        }
    }
    function cfgRun(cmd) {
        cfgMutateProc.running = false
        cfgMutateProc.command = cmd
        cfgMutateProc.running = true
    }

    // ── Config helpers ───────────────────────────────────────────────────────
    function configFor(id) {
        for (var i = 0; i < root.configCals.length; i++)
            if (root.configCals[i].id === id) return root.configCals[i]
        return null
    }
    function isSynced(id) { return root.configFor(id) !== null }
    function colorFor(cal) {
        var c = root.configFor(cal.id)
        if (c && c.color) return c.color
        return cal.color || "#7C4DFF"
    }
    function sourceFor(cal) {
        var c = root.configFor(cal.id)
        if (c && c.source) return c.source
        return cal.source || (cal.primary ? "perso" : "work")
    }

    function setSynced(cal, on) {
        if (on)
            root.cfgRun([root.bin(), "config", "set-calendar", "--id", cal.id,
                         "--account", cal.account || "", "--source", root.sourceFor(cal),
                         "--color", root.colorFor(cal), "--summary", cal.summary || ""])
        else
            root.cfgRun([root.bin(), "config", "rm-calendar", "--id", cal.id])
    }
    function setColor(cal, color) {
        if (!root.isSynced(cal.id)) return
        root.cfgRun([root.bin(), "config", "set-calendar", "--id", cal.id,
                     "--account", cal.account || "", "--source", root.sourceFor(cal),
                     "--color", color, "--summary", cal.summary || ""])
    }

    function accountCalendars(account) {
        return root.discovered.filter(function (c) { return (c.account || "") === account })
    }

    // ── Reminders ────────────────────────────────────────────────────────────
    function buildLeadCSV() {
        var arr = []
        if (root.remBefore && root.remLeadMinutes > 0) arr.push(root.remLeadMinutes)
        if (root.remAtStart) arr.push(0)
        return arr.join(",")
    }
    function saveReminders() {
        root.cfgRun([root.bin(), "config", "set-reminders",
                     "--enabled=" + (root.remEnabled ? "true" : "false"),
                     "--lead", root.buildLeadCSV()])
    }

    // ── Tab bar ────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NButton {
            text: root.tr("settings.tabAccounts", "Accounts")
            icon: "plugin"
            outlined: root.activeTab !== "accounts"
            onClicked: root.activeTab = "accounts"
        }
        NButton {
            text: root.tr("settings.tabGeneral", "General")
            icon: "settings"
            outlined: root.activeTab !== "general"
            onClicked: root.activeTab = "general"
        }
        Item { Layout.fillWidth: true }
    }

    NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

    // ── Accounts tab ───────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.activeTab === "accounts"
        spacing: Style.marginM

        NLabel {
            label: root.tr("settings.accounts", "Accounts")
            description: root.tr("settings.accountsDesc", "Connect Google accounts and choose which calendars are synced.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NButton {
                text: root.authRunning ? root.tr("settings.authRunning", "Waiting for browser…")
                                       : root.tr("settings.addAccount", "Add account")
                icon: "plus"
                enabled: !root.authRunning
                onClicked: root.addAccount()
            }
            NButton {
                text: root.discovering ? root.tr("settings.refreshing", "Refreshing…")
                                       : root.tr("settings.refreshCalendars", "Refresh calendars")
                icon: "refresh"
                enabled: !root.discovering
                onClicked: root.loadDiscovered()
            }
            Item { Layout.fillWidth: true }
        }

        NText {
            visible: root.accounts.length === 0
            text: root.tr("settings.noAccounts", "No account connected yet. Click “Add account”.")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
        }

        Repeater {
            model: root.accounts
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: accCol.implicitHeight + Style.marginM * 2
                radius: Style.radiusS
                color: Color.mSurfaceVariant

                ColumnLayout {
                    id: accCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 9; height: 9; radius: 5
                            color: modelData.authenticated ? Color.mPrimary : Color.mError
                        }
                        NText {
                            Layout.fillWidth: true
                            text: modelData.account
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                        }
                        NButton {
                            text: root.tr("settings.logout", "Disconnect")
                            outlined: true
                            onClicked: root.logout(modelData.account)
                        }
                    }

                    // Calendars for this account, each with a sync toggle + color.
                    Repeater {
                        model: root.accountCalendars(modelData.account)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Style.marginS
                            NToggle {
                                Layout.fillWidth: true
                                label: (modelData.summary && modelData.summary !== "") ? modelData.summary : modelData.id
                                checked: root.isSynced(modelData.id)
                                onToggled: (v) => root.setSynced(modelData, v)
                            }
                            NTextInput {
                                Layout.preferredWidth: 110 * Style.uiScaleRatio
                                visible: root.isSynced(modelData.id)
                                text: root.colorFor(modelData)
                                placeholderText: "#RRGGBB"
                                onEditingFinished: root.setColor(modelData, text)
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                visible: root.isSynced(modelData.id)
                                width: 22; height: 22; radius: Style.radiusXS
                                color: root.colorFor(modelData)
                            }
                        }
                    }

                    NText {
                        visible: root.accountCalendars(modelData.account).length === 0
                        text: root.discovering ? root.tr("settings.refreshing", "Refreshing…")
                                               : root.tr("settings.noCalendars", "No calendars loaded — click “Refresh calendars”.")
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                }
            }
        }
    }

    // ── General tab ────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.activeTab === "general"
        spacing: Style.marginM

        NLabel {
            label: root.tr("settings.reminders", "Reminders")
            description: root.tr("settings.remindersDesc", "Desktop notifications before and when events start.")
        }
        NToggle {
            Layout.fillWidth: true
            label: root.tr("settings.remEnabled", "Enable event reminders")
            checked: root.remEnabled
            onToggled: (v) => { root.remEnabled = v; root.saveReminders() }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            enabled: root.remEnabled
            NToggle {
                label: root.tr("settings.remBefore", "Before the event")
                checked: root.remBefore
                onToggled: (v) => { root.remBefore = v; root.saveReminders() }
            }
            NTextInput {
                Layout.preferredWidth: 60 * Style.uiScaleRatio
                text: String(root.remLeadMinutes)
                onEditingFinished: {
                    var n = parseInt(text)
                    root.remLeadMinutes = (isNaN(n) || n < 1) ? 1 : n
                    root.saveReminders()
                }
            }
            NText {
                text: root.tr("settings.remMinutes", "min before")
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
        }
        NToggle {
            Layout.fillWidth: true
            enabled: root.remEnabled
            label: root.tr("settings.remAtStart", "When the event starts")
            checked: root.remAtStart
            onToggled: (v) => { root.remAtStart = v; root.saveReminders() }
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
}
