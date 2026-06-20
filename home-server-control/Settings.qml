import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null
    spacing: Style.marginM

    // Hôtes (copie locale éditable).
    property var hostsLocal: []
    // Comportement.
    property bool confirmDestructive: true
    property bool showToasts: true
    property bool notifyOnStateChange: true
    property bool closePanelOnAction: false
    property string terminalCommand: "kitty -e"
    property bool logsInDeck: false
    property int logTailLines: 200
    property int pollIdle: 45000
    property int pollOpen: 8000

    property bool _loaded: false

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
        // Migration : les hôtes existants n'ont pas de `mode`/`project`/`region` -> défauts (re-persistés au save).
        hostsLocal = (s.hosts ?? []).map(function (h) {
            return { "name": h.name ?? "", "sshAlias": h.sshAlias ?? "", "hsrPath": h.hsrPath ?? "~/Home-Server-Runner",
                     "readOnly": h.readOnly ?? false, "mode": h.mode ?? "auto",
                     "project": h.project ?? "", "region": h.region ?? "" }
        })
        confirmDestructive = s.confirmDestructive ?? true
        showToasts = s.showToasts ?? true
        notifyOnStateChange = s.notifyOnStateChange ?? true
        closePanelOnAction = s.closePanelOnAction ?? false
        terminalCommand = s.terminalCommand ?? "kitty -e"
        logsInDeck = s.logsInDeck ?? false
        logTailLines = s.logTailLines ?? 200
        pollIdle = s.pollIdle ?? s.pollIntervalIdleMs ?? 45000
        pollOpen = s.pollOpen ?? s.pollIntervalOpenMs ?? 8000
        _loaded = true
    }

    Component.onCompleted: _load()
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
        s.hosts = root.hostsLocal
        if ((s.activeHostIndex ?? 0) >= root.hostsLocal.length)
            s.activeHostIndex = 0
        s.confirmDestructive = root.confirmDestructive
        s.showToasts = root.showToasts
        s.notifyOnStateChange = root.notifyOnStateChange
        s.closePanelOnAction = root.closePanelOnAction
        s.terminalCommand = root.terminalCommand
        s.logsInDeck = root.logsInDeck
        s.logTailLines = root.logTailLines
        s.pollIntervalIdleMs = root.pollIdle
        s.pollIntervalOpenMs = root.pollOpen
        pluginApi.saveSettings()
    }

    function updateHost(i, key, val) {
        if (i < 0 || i >= hostsLocal.length) return
        var copy = hostsLocal.slice()
        copy[i] = Object.assign({}, copy[i])
        copy[i][key] = val
        hostsLocal = copy
        saveSettings()
    }

    function addHost() {
        var copy = hostsLocal.slice()
        copy.push({ "name": "", "sshAlias": "", "hsrPath": "~/Home-Server-Runner", "readOnly": false, "mode": "auto",
                    "project": "", "region": "" })
        hostsLocal = copy
        saveSettings()
    }

    function removeHost(i) {
        if (i < 0 || i >= hostsLocal.length) return
        var copy = hostsLocal.slice()
        copy.splice(i, 1)
        hostsLocal = copy
        saveSettings()
    }

    // ── Onglets ────────────────────────────────────────────────────────────
    NTabBar {
        id: tabBar
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
        distributeEvenly: true
        currentIndex: tabView.currentIndex

        NTabButton {
            icon: "server"
            text: pluginApi?.tr("settings.tabs.hosts")
            pointSize: Style.fontSizeL
            tabIndex: 0
            checked: tabBar.currentIndex === 0
        }
        NTabButton {
            icon: "settings"
            text: pluginApi?.tr("settings.tabs.behavior")
            pointSize: Style.fontSizeL
            tabIndex: 1
            checked: tabBar.currentIndex === 1
        }
    }

    NTabView {
        id: tabView
        currentIndex: tabBar.currentIndex

        // ── Onglet « Hôtes » ─────────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NLabel {
                label: pluginApi?.tr("settings.hosts")
                description: pluginApi?.tr("settings.hostsDesc")
            }

            Repeater {
                model: root.hostsLocal
                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: hostCol.implicitHeight + Style.marginM * 2
                    radius: Style.radiusS
                    color: Color.mSurfaceVariant

                    ColumnLayout {
                        id: hostCol
                        anchors.fill: parent
                        anchors.margins: Style.marginM
                        spacing: Style.marginS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS
                            NTextInput {
                                Layout.fillWidth: true
                                text: modelData.name
                                placeholderText: pluginApi?.tr("settings.namePlaceholder")
                                onEditingFinished: root.updateHost(index, "name", text)
                            }
                            NIconButton {
                                icon: "plug-connected"
                                tooltipText: pluginApi?.tr("settings.testConnection")
                                onClicked: if (root.mainInstance) root.mainInstance.testConnection(index)
                            }
                            NIconButton {
                                icon: "trash"
                                tooltipText: pluginApi?.tr("settings.removeHost")
                                colorFgHover: Color.mError
                                onClicked: root.removeHost(index)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS
                            NTextInput {
                                Layout.fillWidth: true
                                text: modelData.sshAlias
                                placeholderText: pluginApi?.tr("settings.aliasPlaceholder")
                                onEditingFinished: root.updateHost(index, "sshAlias", text)
                            }
                            NComboBox {
                                Layout.preferredWidth: 150 * Style.uiScaleRatio
                                model: [
                                    { "key": "auto", "name": pluginApi?.tr("settings.modeAuto") ?? "Auto" },
                                    { "key": "docker", "name": pluginApi?.tr("settings.modeDocker") ?? "Docker" },
                                    { "key": "hsr", "name": pluginApi?.tr("settings.modeHsr") ?? "Home-Server-Runner" },
                                    { "key": "gcloud", "name": pluginApi?.tr("settings.modeGcloud") ?? "Cloud Run (gcloud)" }
                                ]
                                currentKey: modelData.mode ?? "auto"
                                onSelected: (key) => root.updateHost(index, "mode", key)
                            }
                        }
                        // Chemin Home-Server-Runner : utile seulement en mode auto/hsr.
                        NTextInput {
                            Layout.fillWidth: true
                            visible: (modelData.mode ?? "auto") === "auto" || (modelData.mode ?? "auto") === "hsr"
                            text: modelData.hsrPath
                            placeholderText: pluginApi?.tr("settings.pathPlaceholder")
                            onEditingFinished: root.updateHost(index, "hsrPath", text)
                        }
                        // Projet / région GCP : mode gcloud uniquement (région vide = toutes).
                        RowLayout {
                            Layout.fillWidth: true
                            visible: (modelData.mode ?? "auto") === "gcloud"
                            spacing: Style.marginS
                            NTextInput {
                                Layout.fillWidth: true
                                text: modelData.project ?? ""
                                placeholderText: pluginApi?.tr("settings.projectPlaceholder")
                                onEditingFinished: root.updateHost(index, "project", text)
                            }
                            NTextInput {
                                Layout.fillWidth: true
                                text: modelData.region ?? ""
                                placeholderText: pluginApi?.tr("settings.regionPlaceholder")
                                onEditingFinished: root.updateHost(index, "region", text)
                            }
                        }
                        NToggle {
                            Layout.fillWidth: true
                            label: pluginApi?.tr("settings.readOnly")
                            description: pluginApi?.tr("settings.readOnlyDesc")
                            checked: modelData.readOnly
                            onToggled: (v) => root.updateHost(index, "readOnly", v)
                        }
                    }
                }
            }

            NButton {
                text: pluginApi?.tr("settings.addHost")
                icon: "plus"
                onClicked: root.addHost()
            }
        }

        // ── Onglet « Comportement » ──────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.confirmDestructive")
                description: pluginApi?.tr("settings.confirmDestructiveDesc")
                checked: root.confirmDestructive
                onToggled: (v) => { root.confirmDestructive = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.notifyOnStateChange")
                description: pluginApi?.tr("settings.notifyOnStateChangeDesc")
                checked: root.notifyOnStateChange
                onToggled: (v) => { root.notifyOnStateChange = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.showToasts")
                description: pluginApi?.tr("settings.showToastsDesc")
                checked: root.showToasts
                onToggled: (v) => { root.showToasts = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.closePanelOnAction")
                description: pluginApi?.tr("settings.closePanelOnActionDesc")
                checked: root.closePanelOnAction
                onToggled: (v) => { root.closePanelOnAction = v; saveSettings() }
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

            // Option « logs dans le Deck » : visible seulement si le plugin Noctalia Deck est installé.
            NToggle {
                Layout.fillWidth: true
                visible: root.mainInstance && root.mainInstance.deckInstalled
                label: pluginApi?.tr("settings.logsInDeck")
                description: pluginApi?.tr("settings.logsInDeckDesc")
                checked: root.logsInDeck
                onToggled: (v) => { root.logsInDeck = v; saveSettings() }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.logTailLines"); description: pluginApi?.tr("settings.logTailLinesDesc") + " (" + root.logTailLines + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 50; to: 1000; stepSize: 50
                    value: root.logTailLines
                    onValueChanged: { root.logTailLines = value; saveSettings() }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.pollIdle"); description: pluginApi?.tr("settings.pollIdleDesc") + " (" + root.pollIdle + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 10000; to: 120000; stepSize: 5000
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
                    from: 3000; to: 30000; stepSize: 1000
                    value: root.pollOpen
                    onValueChanged: { root.pollOpen = value; saveSettings() }
                }
            }
        }
    }
}
