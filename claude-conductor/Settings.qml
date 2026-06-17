import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null
    spacing: Style.marginM

    property bool notifyOnWaiting: true
    property bool notifyOnDone: true
    property bool enrichOnOpen: true
    property bool trackCli: true
    property bool trackVscode: true
    property string terminalCommand: "kitty -e"
    property int doneMinSeconds: 20
    property int tailLines: 200
    property int pollIdle: 12000
    property int pollOpen: 4000
    property bool _loaded: false

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
        notifyOnWaiting = s.notifyOnWaiting ?? true
        notifyOnDone = s.notifyOnDone ?? true
        enrichOnOpen = s.enrichOnOpen ?? true
        var te = s.trackEntrypoints ?? ["cli", "claude-vscode"]
        trackCli = te.indexOf("cli") !== -1
        trackVscode = te.indexOf("claude-vscode") !== -1
        terminalCommand = s.terminalCommand ?? "kitty -e"
        doneMinSeconds = s.doneMinSeconds ?? 20
        tailLines = s.tailLines ?? 200
        pollIdle = s.pollLivenessIdleMs ?? 12000
        pollOpen = s.pollLivenessOpenMs ?? 4000
        _loaded = true
    }

    Component.onCompleted: { _load(); if (mainInstance) mainInstance.refreshHooksStatus() }
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
        s.notifyOnWaiting = root.notifyOnWaiting
        s.notifyOnDone = root.notifyOnDone
        s.enrichOnOpen = root.enrichOnOpen
        var te = []
        if (root.trackCli) te.push("cli")
        if (root.trackVscode) te.push("claude-vscode")
        s.trackEntrypoints = te
        s.terminalCommand = root.terminalCommand
        s.doneMinSeconds = root.doneMinSeconds
        s.tailLines = root.tailLines
        s.pollLivenessIdleMs = root.pollIdle
        s.pollLivenessOpenMs = root.pollOpen
        pluginApi.saveSettings()
    }

    NTabBar {
        id: tabBar
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
        distributeEvenly: true
        currentIndex: tabView.currentIndex

        NTabButton {
            icon: "settings"
            text: pluginApi?.tr("settings.tabs.behavior")
            pointSize: Style.fontSizeL
            tabIndex: 0
            checked: tabBar.currentIndex === 0
        }
        NTabButton {
            icon: "plug"
            text: pluginApi?.tr("settings.tabs.hooks")
            pointSize: Style.fontSizeL
            tabIndex: 1
            checked: tabBar.currentIndex === 1
        }
    }

    NTabView {
        id: tabView
        currentIndex: tabBar.currentIndex

        // ── Onglet « Comportement » ──────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.notifyOnWaiting")
                description: pluginApi?.tr("settings.notifyOnWaitingDesc")
                checked: root.notifyOnWaiting
                onToggled: (v) => { root.notifyOnWaiting = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.notifyOnDone")
                description: pluginApi?.tr("settings.notifyOnDoneDesc")
                checked: root.notifyOnDone
                onToggled: (v) => { root.notifyOnDone = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.enrichOnOpen")
                description: pluginApi?.tr("settings.enrichOnOpenDesc")
                checked: root.enrichOnOpen
                onToggled: (v) => { root.enrichOnOpen = v; saveSettings() }
            }

            NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

            NLabel { label: pluginApi?.tr("settings.trackEntrypoints"); description: pluginApi?.tr("settings.trackEntrypointsDesc") }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.trackVscode")
                checked: root.trackVscode
                onToggled: (v) => { root.trackVscode = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.trackCli")
                checked: root.trackCli
                onToggled: (v) => { root.trackCli = v; saveSettings() }
            }

            NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.terminalCommand"); description: pluginApi?.tr("settings.terminalCommandDesc") }
                NTextInput {
                    Layout.fillWidth: true
                    text: root.terminalCommand
                    onEditingFinished: { root.terminalCommand = text; saveSettings() }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.doneMinSeconds"); description: pluginApi?.tr("settings.doneMinSecondsDesc") + " (" + root.doneMinSeconds + "s)" }
                NSlider {
                    Layout.fillWidth: true
                    from: 5; to: 120; stepSize: 5
                    value: root.doneMinSeconds
                    onValueChanged: { root.doneMinSeconds = value; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.tailLines"); description: pluginApi?.tr("settings.tailLinesDesc") + " (" + root.tailLines + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 50; to: 1000; stepSize: 50
                    value: root.tailLines
                    onValueChanged: { root.tailLines = value; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.pollIdle"); description: pluginApi?.tr("settings.pollIdleDesc") + " (" + root.pollIdle + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 5000; to: 60000; stepSize: 1000
                    value: root.pollIdle
                    onValueChanged: { root.pollIdle = value; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.pollOpen"); description: pluginApi?.tr("settings.pollOpenDesc") + " (" + root.pollOpen + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 1000; to: 15000; stepSize: 1000
                    value: root.pollOpen
                    onValueChanged: { root.pollOpen = value; saveSettings() }
                }
            }
        }

        // ── Onglet « Hooks » ─────────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NLabel { label: pluginApi?.tr("settings.hooksTitle"); description: pluginApi?.tr("settings.hooksDesc") }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NIcon {
                    icon: (root.mainInstance && root.mainInstance.hooksInstalled) ? "circle-check" : "circle-x"
                    color: (root.mainInstance && root.mainInstance.hooksInstalled) ? "#3fb950" : Color.mOnSurfaceVariant
                }
                NText {
                    Layout.fillWidth: true
                    text: (root.mainInstance && root.mainInstance.hooksInstalled)
                          ? (pluginApi?.tr("settings.hooksInstalled") ?? "Installés")
                          : (pluginApi?.tr("settings.hooksNotInstalled") ?? "Non installés")
                    pointSize: Style.fontSizeS
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NButton {
                    visible: !(root.mainInstance && root.mainInstance.hooksInstalled)
                    text: pluginApi?.tr("settings.hooksInstall")
                    icon: "plug-connected"
                    onClicked: if (root.mainInstance) root.mainInstance.installHooks()
                }
                NButton {
                    visible: root.mainInstance && root.mainInstance.hooksInstalled
                    text: pluginApi?.tr("settings.hooksUninstall")
                    icon: "plug-connected-x"
                    onClicked: if (root.mainInstance) root.mainInstance.uninstallHooks()
                }
                NIconButton {
                    icon: "refresh"
                    tooltipText: pluginApi?.tr("context.refresh")
                    onClicked: if (root.mainInstance) root.mainInstance.refreshHooksStatus()
                }
            }

            NText {
                Layout.fillWidth: true
                text: pluginApi?.tr("settings.hooksNote") ?? ""
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }
}
