import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance
    spacing: Style.marginM

    // Comportement
    property bool confirmClean: true
    property bool showToasts: true
    property bool closePanelOnAction: false
    property bool confirmDelete: true
    property string defaultLoadMode: "add"
    property int springLoadDelay: 250

    // Apparence
    property bool colorizeAppIcons: false
    property string appIconColor: "primary"

    property bool _loaded: false

    // champs de la ligne « ajouter une surcharge »
    property string newClass: ""
    property string newCommand: ""

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
        confirmClean = s.confirmClean ?? true
        showToasts = s.showToasts ?? true
        closePanelOnAction = s.closePanelOnAction ?? false
        confirmDelete = s.confirmDelete ?? true
        defaultLoadMode = s.defaultLoadMode ?? "add"
        springLoadDelay = s.springLoadDelay ?? 250
        colorizeAppIcons = s.colorizeAppIcons ?? false
        appIconColor = s.appIconColor ?? "primary"
        _loaded = true
        if (mainInstance) mainInstance.refreshOverrides()
    }

    Component.onCompleted: _load()
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
        s.confirmClean = root.confirmClean
        s.showToasts = root.showToasts
        s.closePanelOnAction = root.closePanelOnAction
        s.confirmDelete = root.confirmDelete
        s.defaultLoadMode = root.defaultLoadMode
        s.springLoadDelay = root.springLoadDelay
        s.colorizeAppIcons = root.colorizeAppIcons
        s.appIconColor = root.appIconColor
        pluginApi.saveSettings()
    }

    // ── Onglets ───────────────────────────────────────────────────────────────
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
            icon: "palette"
            text: pluginApi?.tr("settings.tabs.appearance")
            pointSize: Style.fontSizeL
            tabIndex: 1
            checked: tabBar.currentIndex === 1
        }
        NTabButton {
            icon: "terminal-2"
            text: pluginApi?.tr("settings.tabs.commands")
            pointSize: Style.fontSizeL
            tabIndex: 2
            checked: tabBar.currentIndex === 2
        }
    }

    NTabView {
        id: tabView
        currentIndex: tabBar.currentIndex

        // ── Onglet « Comportement » ─────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.confirmClean")
                description: pluginApi?.tr("settings.confirmCleanDesc")
                checked: root.confirmClean
                onToggled: (v) => { root.confirmClean = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.confirmDelete")
                description: pluginApi?.tr("settings.confirmDeleteDesc")
                checked: root.confirmDelete
                onToggled: (v) => { root.confirmDelete = v; saveSettings() }
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
            NComboBox {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.defaultLoadMode")
                description: pluginApi?.tr("settings.defaultLoadModeDesc")
                model: [
                    { "key": "add", "name": pluginApi?.tr("settings.loadModeAdd") },
                    { "key": "replace", "name": pluginApi?.tr("settings.loadModeReplace") },
                    { "key": "merge", "name": pluginApi?.tr("settings.loadModeMerge") }
                ]
                currentKey: root.defaultLoadMode
                onSelected: (key) => { root.defaultLoadMode = key; saveSettings() }
            }

            NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                NLabel {
                    label: pluginApi?.tr("settings.springLoadDelay")
                    description: pluginApi?.tr("settings.springLoadDelayDesc") + " (" + root.springLoadDelay + " ms)"
                }
                NSlider {
                    Layout.fillWidth: true
                    from: 100
                    to: 600
                    stepSize: 50
                    value: root.springLoadDelay
                    onValueChanged: { root.springLoadDelay = value; saveSettings() }
                }
            }
        }

        // ── Onglet « Apparence » ────────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.colorizeAppIcons")
                description: pluginApi?.tr("settings.colorizeAppIconsDesc")
                checked: root.colorizeAppIcons
                onToggled: (v) => { root.colorizeAppIcons = v; saveSettings() }
            }

            NColorChoice {
                Layout.fillWidth: true
                visible: root.colorizeAppIcons
                label: pluginApi?.tr("settings.appIconColor")
                description: pluginApi?.tr("settings.appIconColorDesc")
                currentKey: root.appIconColor
                onSelected: (key) => { root.appIconColor = key; saveSettings() }
            }
        }

        // ── Onglet « Commandes de lancement » ───────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            RowLayout {
                spacing: Style.marginS
                NIcon { icon: "terminal-2"; color: Color.mPrimary }
                NLabel { label: pluginApi?.tr("settings.overrides") }
            }

            NText {
                text: pluginApi?.tr("settings.overridesDesc")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // liste des surcharges existantes
            Repeater {
                model: root.mainInstance ? root.mainInstance.overridesModel : null
                delegate: RowLayout {
                    required property string cls
                    required property string command
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NText {
                        text: cls
                        pointSize: Style.fontSizeS
                        font.family: "monospace"
                        elide: Text.ElideRight
                        Layout.preferredWidth: 140 * Style.uiScaleRatio
                    }
                    NTextInput {
                        Layout.fillWidth: true
                        text: command
                        onEditingFinished: {
                            if (root.mainInstance && text.trim().length > 0)
                                root.mainInstance.setOverride(cls, text)
                        }
                    }
                    NIconButton {
                        icon: "trash"
                        tooltipText: pluginApi?.tr("settings.removeOverride")
                        colorFgHover: Color.mError
                        onClicked: if (root.mainInstance) root.mainInstance.unsetOverride(cls)
                    }
                }
            }

            // ajouter une surcharge
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.marginXS
                spacing: Style.marginS

                NTextInput {
                    id: classInput
                    Layout.preferredWidth: 140 * Style.uiScaleRatio
                    placeholderText: pluginApi?.tr("settings.classPlaceholder")
                    text: root.newClass
                    onTextChanged: root.newClass = text
                }
                NTextInput {
                    id: commandInput
                    Layout.fillWidth: true
                    placeholderText: pluginApi?.tr("settings.commandPlaceholder")
                    text: root.newCommand
                    onTextChanged: root.newCommand = text
                }
                NButton {
                    text: pluginApi?.tr("settings.addOverride")
                    icon: "plus"
                    enabled: root.newClass.trim().length > 0 && root.newCommand.trim().length > 0
                    onClicked: {
                        if (root.mainInstance) {
                            root.mainInstance.setOverride(root.newClass, root.newCommand)
                            root.newClass = ""
                            root.newCommand = ""
                        }
                    }
                }
            }
        }
    }
}
