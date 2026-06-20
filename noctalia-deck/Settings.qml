import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null
    spacing: Style.marginM

    property int width_: 900
    property int height_: 480
    property string position_: "attached"
    property string themeMode_: "noctalia"
    property string schemeName_: "Solarized"
    property string fontFamily_: ""
    property int fontSize_: 11
    property int scratchpadFontSize_: 13
    property string shellProgram_: ""
    property string procMonCommand_: "btop"
    property bool showToasts_: true
    property bool logsAutoClose_: true

    property bool _loaded: false

    function _load() {
        if (!pluginApi?.pluginSettings) return
        _loaded = false
        var s = pluginApi.pluginSettings
        width_ = s.width ?? 900
        height_ = s.height ?? 480
        position_ = s.position ?? "attached"
        themeMode_ = s.themeMode ?? "noctalia"
        schemeName_ = s.schemeName ?? "Solarized"
        fontFamily_ = s.fontFamily ?? ""
        fontSize_ = s.fontSize ?? 11
        scratchpadFontSize_ = s.scratchpadFontSize ?? 13
        shellProgram_ = s.shellProgram ?? ""
        procMonCommand_ = s.procMonCommand ?? "btop"
        showToasts_ = s.showToasts ?? true
        logsAutoClose_ = s.logsAutoClose ?? true
        _loaded = true
    }

    Component.onCompleted: _load()
    onPluginApiChanged: _load()

    function saveSettings() {
        if (!pluginApi || !_loaded) return
        var s = pluginApi.pluginSettings
        s.width = root.width_
        s.height = root.height_
        s.position = root.position_
        s.themeMode = root.themeMode_
        s.schemeName = root.schemeName_
        s.fontFamily = root.fontFamily_
        s.fontSize = root.fontSize_
        s.scratchpadFontSize = root.scratchpadFontSize_
        s.shellProgram = root.shellProgram_
        s.procMonCommand = root.procMonCommand_
        s.showToasts = root.showToasts_
        s.logsAutoClose = root.logsAutoClose_
        pluginApi.saveSettings()
    }

    readonly property var schemeModel: [
        { "key": "Solarized", "name": "Solarized" },
        { "key": "SolarizedLight", "name": "Solarized Light" },
        { "key": "Falcon", "name": "Falcon" },
        { "key": "DarkPastels", "name": "Dark Pastels" },
        { "key": "BreezeModified", "name": "Breeze" },
        { "key": "Tango", "name": "Tango" },
        { "key": "Linux", "name": "Linux" },
        { "key": "Ubuntu", "name": "Ubuntu" },
        { "key": "GreenOnBlack", "name": "Green on Black" },
        { "key": "WhiteOnBlack", "name": "White on Black" },
        { "key": "BlackOnWhite", "name": "Black on White" },
        { "key": "BlackOnLightYellow", "name": "Black on Light Yellow" },
        { "key": "cool-retro-term", "name": "Cool Retro Term" }
    ]

    NTabBar {
        id: tabBar
        Layout.fillWidth: true
        Layout.bottomMargin: Style.marginS
        distributeEvenly: true
        currentIndex: tabView.currentIndex

        NTabButton {
            icon: "layout-distribute-horizontal"
            text: pluginApi?.tr("settings.tabs.window")
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
    }

    NTabView {
        id: tabView
        currentIndex: tabBar.currentIndex

        // ── Onglet « Fenêtre » ───────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.position"); description: pluginApi?.tr("settings.positionDesc") }
                NComboBox {
                    Layout.fillWidth: true
                    model: [
                        { "key": "attached", "name": pluginApi?.tr("settings.posAttached") ?? "Attached to the widget" },
                        { "key": "centered", "name": pluginApi?.tr("settings.posCentered") ?? "Centered" }
                    ]
                    currentKey: root.position_
                    onSelected: (key) => { root.position_ = key; saveSettings() }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.width"); description: pluginApi?.tr("settings.widthDesc") + " (" + root.width_ + " px)" }
                NSlider {
                    Layout.fillWidth: true
                    from: 400; to: 2400; stepSize: 20
                    value: root.width_
                    onValueChanged: { root.width_ = value; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.height"); description: pluginApi?.tr("settings.heightDesc") + " (" + root.height_ + " px)" }
                NSlider {
                    Layout.fillWidth: true
                    from: 200; to: 1400; stepSize: 20
                    value: root.height_
                    onValueChanged: { root.height_ = value; saveSettings() }
                }
            }

            NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.shellProgram"); description: pluginApi?.tr("settings.shellProgramDesc") }
                NTextInput {
                    Layout.fillWidth: true
                    text: root.shellProgram_
                    placeholderText: "$SHELL"
                    onEditingFinished: { root.shellProgram_ = text; saveSettings() }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.procMonCommand"); description: pluginApi?.tr("settings.procMonCommandDesc") }
                NTextInput {
                    Layout.fillWidth: true
                    text: root.procMonCommand_
                    placeholderText: "btop"
                    onEditingFinished: { root.procMonCommand_ = text; saveSettings() }
                }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.showToasts")
                description: pluginApi?.tr("settings.showToastsDesc")
                checked: root.showToasts_
                onToggled: (v) => { root.showToasts_ = v; saveSettings() }
            }
            NToggle {
                Layout.fillWidth: true
                label: pluginApi?.tr("settings.logsAutoClose")
                description: pluginApi?.tr("settings.logsAutoCloseDesc")
                checked: root.logsAutoClose_
                onToggled: (v) => { root.logsAutoClose_ = v; saveSettings() }
            }
        }

        // ── Onglet « Apparence » ─────────────────────────────────────────────
        ColumnLayout {
            spacing: Style.marginM

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.themeMode"); description: pluginApi?.tr("settings.themeModeDesc") }
                NComboBox {
                    Layout.fillWidth: true
                    model: [
                        { "key": "noctalia", "name": pluginApi?.tr("settings.themeNoctalia") ?? "Noctalia theme (auto)" },
                        { "key": "scheme", "name": pluginApi?.tr("settings.themeScheme") ?? "Terminal scheme" }
                    ]
                    currentKey: root.themeMode_
                    onSelected: (key) => { root.themeMode_ = key; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.themeMode_ === "scheme"
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.scheme"); description: pluginApi?.tr("settings.schemeDesc") }
                NComboBox {
                    Layout.fillWidth: true
                    model: root.schemeModel
                    currentKey: root.schemeName_
                    onSelected: (key) => { root.schemeName_ = key; saveSettings() }
                }
            }

            NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.fontFamily"); description: pluginApi?.tr("settings.fontFamilyDesc") }
                NTextInput {
                    Layout.fillWidth: true
                    text: root.fontFamily_
                    placeholderText: "monospace"
                    onEditingFinished: { root.fontFamily_ = text; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.fontSize"); description: pluginApi?.tr("settings.fontSizeDesc") + " (" + root.fontSize_ + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 6; to: 28; stepSize: 1
                    value: root.fontSize_
                    onValueChanged: { root.fontSize_ = value; saveSettings() }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NLabel { label: pluginApi?.tr("settings.scratchpadFontSize"); description: pluginApi?.tr("settings.scratchpadFontSizeDesc") + " (" + root.scratchpadFontSize_ + ")" }
                NSlider {
                    Layout.fillWidth: true
                    from: 8; to: 28; stepSize: 1
                    value: root.scratchpadFontSize_
                    onValueChanged: { root.scratchpadFontSize_ = value; saveSettings() }
                }
            }
        }
    }
}
