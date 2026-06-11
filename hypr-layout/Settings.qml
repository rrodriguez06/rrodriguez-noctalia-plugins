import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance
    spacing: Style.marginL

    property bool confirmClean: true
    property bool showToasts: true
    property bool _loaded: false

    // champs de la ligne « ajouter une surcharge »
    property string newClass: ""
    property string newCommand: ""

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        confirmClean = pluginApi.pluginSettings.confirmClean ?? true
        showToasts = pluginApi.pluginSettings.showToasts ?? true
        _loaded = true
        if (mainInstance) mainInstance.refreshOverrides()
    }

    Component.onCompleted: _load()
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        pluginApi.pluginSettings.confirmClean = root.confirmClean
        pluginApi.pluginSettings.showToasts = root.showToasts
        pluginApi.saveSettings()
    }

    // ── Comportement ────────────────────────────────────────────────────────────
    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.confirmClean")
        description: pluginApi?.tr("settings.confirmCleanDesc")
        checked: root.confirmClean
        onToggled: (v) => { root.confirmClean = v; saveSettings() }
    }

    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.showToasts")
        description: pluginApi?.tr("settings.showToastsDesc")
        checked: root.showToasts
        onToggled: (v) => { root.showToasts = v; saveSettings() }
    }

    NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginM; Layout.bottomMargin: Style.marginM }

    // ── Éditeur de commandes (classe → commande) ────────────────────────────────
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
