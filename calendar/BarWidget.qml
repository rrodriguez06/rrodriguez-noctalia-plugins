import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

// Bar widget: a Clock-style capsule showing date + time (mirrors Noctalia's
// official Clock). Left-click opens the calendar panel; right-click shows the
// context menu; hover shows a tooltip with today's date, event count and the
// next upcoming event.
Item {
    id: root
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0
    property var pluginApi: null

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property var pset: pluginApi?.pluginSettings ?? null

    // Bar geometry/typography, resolved per-screen like the official Clock.
    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
    readonly property var now: Time.now

    // Display formats (overridable via plugin settings; defaults match the Clock).
    readonly property string formatHorizontal: (pset && pset.barFormat) ? pset.barFormat : "HH:mm ddd, MMM dd"
    readonly property string formatVertical: (pset && pset.barFormatVertical) ? pset.barFormatVertical : "HH mm - dd MM"

    readonly property color textColor: Color.resolveColorKey("none")

    readonly property real contentWidth: isBarVertical ? capsuleHeight : Math.round(horizontalLoader.implicitWidth + Style.margin2M)
    readonly property real contentHeight: isBarVertical ? Math.round(verticalLoader.implicitHeight + Style.margin2S) : capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    function tip() {
        var t = Qt.formatDateTime(new Date(), "dddd d MMMM")
        if (!main) return t
        if (main.todayCount > 0) t += "  ·  " + main.todayCount + " évén."
        if (main.nextLabel) t += "\n→ " + main.nextLabel
        return t
    }

    // ── Visual capsule ────────────────────────────────────────────────────────
    Rectangle {
        id: visualClock
        width: root.contentWidth
        height: root.contentHeight
        anchors.centerIn: parent
        radius: Style.radiusL
        color: Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        Item {
            anchors.centerIn: parent

            // Horizontal bars: a single line (or two if the format has a newline).
            Loader {
                id: horizontalLoader
                active: !root.isBarVertical
                anchors.centerIn: parent
                sourceComponent: ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Settings.data.bar.showCapsule ? -5 : -3
                    Repeater {
                        id: hRepeater
                        model: I18n.locale.toString(root.now, root.formatHorizontal.trim()).split("\\n")
                        NText {
                            visible: text !== ""
                            text: modelData
                            family: Settings.data.ui.fontDefault
                            Binding on pointSize {
                                value: {
                                    if (hRepeater.model.length === 1)
                                        return root.barFontSize
                                    if (hRepeater.model.length === 2)
                                        return (index === 0) ? Math.round(root.barFontSize * 0.9) : Math.round(root.barFontSize * 0.75)
                                    return Math.round(root.barFontSize * 0.75)
                                }
                            }
                            applyUiScale: false
                            color: root.textColor
                            wrapMode: Text.WordWrap
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            features: ({ "tnum": 1 })
                        }
                    }
                }
            }

            // Vertical bars: one stacked token per space-separated chunk.
            Loader {
                id: verticalLoader
                active: root.isBarVertical
                anchors.centerIn: parent
                sourceComponent: ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -2
                    Repeater {
                        model: I18n.locale.toString(root.now, root.formatVertical.trim()).split(" ")
                        delegate: NText {
                            visible: text !== ""
                            text: modelData
                            family: Settings.data.ui.fontDefault
                            pointSize: root.barFontSize
                            applyUiScale: false
                            color: root.textColor
                            wrapMode: Text.WordWrap
                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                            features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }

    // ── Tooltip (event-aware) ─────────────────────────────────────────────────
    MouseArea {
        id: clockMouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: {
            if (!(root.main && root.main.panelOpen)) {
                TooltipService.show(root, root.tip(), BarService.getTooltipDirection(root.screenName))
                tooltipRefreshTimer.start()
            }
        }
        onExited: {
            tooltipRefreshTimer.stop()
            TooltipService.hide()
        }
        onClicked: mouse => {
            TooltipService.hide()
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, root.screen)
            } else if (root.pluginApi) {
                root.pluginApi.togglePanel(root.screen, visualClock)
            }
        }
    }

    // Keep the tooltip's date/event info fresh while hovering.
    Timer {
        id: tooltipRefreshTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (clockMouseArea.containsMouse && !(root.main && root.main.panelOpen))
                TooltipService.updateText(root.tip())
        }
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": root.pluginApi ? root.pluginApi.tr("context.today") : "Today", "action": "today", "icon": "calendar" },
            { "label": root.pluginApi ? root.pluginApi.tr("context.refresh") : "Refresh", "action": "refresh", "icon": "refresh" },
            { "label": root.pluginApi ? root.pluginApi.tr("context.settings") : "Settings", "action": "settings", "icon": "settings" }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)
            if (!root.pluginApi) return
            if (action === "settings")
                BarService.openPluginSettings(root.screen, root.pluginApi.manifest)
            else if (action === "refresh" && root.main)
                root.main.syncNow()
            else if (action === "today" && root.main)
                root.main.goToday()
        }
    }
}
