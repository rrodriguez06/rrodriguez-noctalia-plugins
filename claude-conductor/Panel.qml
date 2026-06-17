import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets
import "drivers/Shared.js" as Shared

// Panneau : en-tête + liste des sessions groupées par projet (état + actions) + overlay Tail.
Item {
    id: root
    property var pluginApi: null
    readonly property var main: pluginApi?.mainInstance ?? null

    // Contrat panneau Noctalia.
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 580 * Style.uiScaleRatio
    property real contentPreferredHeight: 600 * Style.uiScaleRatio
    anchors.fill: parent

    property bool viewingTail: false

    function stateColor(state) {
        if (state === "waiting") return "#f85149"
        if (state === "running") return "#58a6ff"
        return "#3fb950"                       // idle / prête
    }
    function stateLabel(state) {
        if (state === "waiting") return pluginApi?.tr("panel.stateWaiting") ?? "t'attend"
        if (state === "running") return pluginApi?.tr("panel.stateRunning") ?? "travaille"
        return pluginApi?.tr("panel.stateIdle") ?? "prête"
    }

    onVisibleChanged: {
        if (!main) return
        main.setPanelOpen(visible)
        if (!visible) { main.stopTail(); root.viewingTail = false }
    }

    // ── Vue principale ────────────────────────────────────────────────────────
    Item {
        id: panelContainer
        anchors.fill: parent
        visible: opacity > 0
        opacity: root.viewingTail ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            // En-tête.
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: headCol.implicitHeight + Style.marginL * 2
                ColumnLayout {
                    id: headCol
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginXS

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NHeader {
                            Layout.fillWidth: true
                            label: pluginApi?.tr("panel.title") ?? "Claude Conductor"
                            description: pluginApi?.tr("panel.subtitle") ?? ""
                        }
                        NIconButton {
                            icon: "arrow-big-right"
                            tooltipText: pluginApi?.tr("panel.focusNext")
                            enabled: root.main && root.main.barTotal > 0
                            onClicked: if (root.main) root.main.focusNext()
                        }
                        NIconButton {
                            icon: "refresh"
                            tooltipText: pluginApi?.tr("panel.refresh")
                            onClicked: if (root.main) root.main.refreshNow()
                        }
                    }
                    // Avertissement si les hooks ne sont pas installés.
                    NText {
                        visible: root.main && !root.main.hooksInstalled
                        Layout.fillWidth: true
                        text: pluginApi?.tr("panel.hooksWarn") ?? ""
                        pointSize: Style.fontSizeXS
                        color: "#d29922"
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Aucun session.
            NBox {
                Layout.fillWidth: true
                visible: root.main && root.main.barTotal === 0
                Layout.preferredHeight: emptyCol.implicitHeight + Style.marginL * 2
                ColumnLayout {
                    id: emptyCol
                    anchors.centerIn: parent
                    spacing: Style.marginXS
                    NText { text: pluginApi?.tr("panel.empty") ?? "Aucune session"; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                    NText { text: pluginApi?.tr("panel.emptyHint") ?? ""; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // Liste des sessions (groupées par projet).
            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.main && root.main.barTotal > 0

                NListView {
                    id: sessList
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginXS
                    model: root.main ? root.main.sessionsModel : null

                    delegate: ColumnLayout {
                        id: row
                        required property int index
                        required property string sid
                        required property string project
                        required property string cwd
                        required property int pid
                        required property string entry
                        required property string title
                        required property string branch
                        required property string state
                        required property string reason
                        required property real lastActivity

                        // En-tête de groupe affiché sur la 1re ligne d'un projet.
                        readonly property bool showHeader: {
                            if (row.index === 0) return true
                            var m = root.main ? root.main.sessionsModel : null
                            if (!m || row.index < 1) return true
                            var prev = m.get(row.index - 1)
                            return !prev || prev.project !== row.project
                        }

                        width: ListView.view ? ListView.view.width : 0
                        spacing: Style.marginXS

                        // En-tête projet.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: row.showHeader ? Style.marginXS : 0
                            visible: row.showHeader
                            spacing: Style.marginXS
                            NIcon { icon: "folder"; color: Color.mOnSurfaceVariant }
                            NText {
                                text: row.project
                                pointSize: Style.fontSizeL
                                color: Color.mSecondary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Carte session.
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sCol.implicitHeight + Style.marginS * 2
                            radius: Style.radiusS
                            color: Color.mSurfaceVariant

                            RowLayout {
                                id: sCol
                                anchors.fill: parent
                                anchors.margins: Style.marginS
                                spacing: Style.marginS

                                // Pastille d'état.
                                Rectangle {
                                    implicitWidth: 10; implicitHeight: 10; radius: 5
                                    color: root.stateColor(row.state)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    NText {
                                        text: (row.title && row.title.length) ? row.title
                                              : ((pluginApi?.tr("launcher.status") ?? "Session") + " " + row.sid.substring(0, 8))
                                        pointSize: Style.fontSizeS
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    NText {
                                        text: {
                                            var bits = [root.stateLabel(row.state)]
                                            if (row.reason && row.state === "waiting") bits = [row.reason]
                                            if (row.branch) bits.push("⎇ " + row.branch)
                                            var age = Shared.relAge(row.lastActivity, root.main ? root.main.now : 0)
                                            if (age) bits.push(age)
                                            return bits.join("  ·  ")
                                        }
                                        pointSize: Style.fontSizeXS
                                        color: row.state === "waiting" ? "#f85149" : Color.mOnSurfaceVariant
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                NIcon {
                                    icon: row.entry === "claude-vscode" ? "brand-vscode" : "terminal-2"
                                    color: Color.mOnSurfaceVariant
                                }
                                NIconButton {
                                    icon: "target"
                                    tooltipText: pluginApi?.tr("panel.focus")
                                    colorFgHover: Color.mPrimary
                                    onClicked: if (root.main) root.main.focusSession(row.sid)
                                }
                                NIconButton {
                                    icon: "file-text"
                                    tooltipText: pluginApi?.tr("panel.tail")
                                    onClicked: {
                                        if (!root.main) return
                                        root.main.streamTail(row.sid)
                                        root.viewingTail = true
                                    }
                                }
                                NIconButton {
                                    icon: "player-play"
                                    tooltipText: pluginApi?.tr("panel.resume")
                                    colorFgHover: Color.mPrimary
                                    onClicked: if (root.main) root.main.resumeSession(row.sid)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Overlay Tail ──────────────────────────────────────────────────────────
    Item {
        id: tailView
        anchors.fill: parent
        anchors.margins: Style.marginM
        visible: opacity > 0
        opacity: root.viewingTail ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
        onVisibleChanged: if (visible) { tailFlick.followTail = true; tailEdit.applyPending(); Qt.callLater(tailFlick.toBottom) }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: tailHead.implicitHeight + Style.marginL * 2
                RowLayout {
                    id: tailHead
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS
                    NIcon { icon: "article"; color: Color.mPrimary }
                    NText { text: root.main ? root.main.logTitle : ""; pointSize: Style.fontSizeL; Layout.fillWidth: true; elide: Text.ElideRight }
                    NIconButton {
                        icon: "external-link"
                        tooltipText: pluginApi?.tr("panel.openInTerminal")
                        enabled: root.main && root.main.logSid.length > 0
                        onClicked: if (root.main) root.main.openTailInTerminal()
                    }
                    NIconButton {
                        icon: "x"
                        tooltipText: pluginApi?.tr("panel.closeTail")
                        onClicked: { if (root.main) root.main.stopTail(); root.viewingTail = false }
                    }
                }
            }

            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: tailFlick
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    property bool followTail: true
                    property bool userInteracting: false
                    function toBottom() { contentY = Math.max(0, contentHeight - height) }

                    onMovementStarted: userInteracting = true
                    onMovementEnded: { userInteracting = false; followTail = atYEnd }
                    onContentHeightChanged: if (followTail && !userInteracting) toBottom()

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Connections {
                        target: root.main
                        function onLogTitleChanged() {
                            tailFlick.followTail = true
                            tailEdit.applyPending()
                            Qt.callLater(tailFlick.toBottom)
                        }
                    }

                    TextArea.flickable: TextArea {
                        id: tailEdit
                        readOnly: true
                        selectByMouse: true
                        selectByKeyboard: true
                        persistentSelection: true
                        wrapMode: TextArea.WrapAnywhere
                        textFormat: TextArea.PlainText
                        font.family: "monospace"
                        font.pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                        selectionColor: Color.mPrimary
                        selectedTextColor: Color.mOnPrimary
                        background: null
                        padding: 0

                        property string pending: root.main ? root.main.logText : ""
                        onPendingChanged: applyPending()
                        onSelectedTextChanged: if (selectedText.length === 0) applyPending()
                        function applyPending() {
                            if (selectedText.length > 0) return
                            if (text === pending) return
                            text = pending
                            if (tailFlick.followTail && !tailFlick.userInteracting)
                                Qt.callLater(tailFlick.toBottom)
                        }
                    }
                }

                NIconButton {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.marginM
                    visible: !tailFlick.followTail
                    icon: "chevron-down"
                    tooltipText: pluginApi?.tr("panel.scrollBottom")
                    onClicked: { tailFlick.followTail = true; tailFlick.toBottom() }
                }
            }
        }
    }
}
