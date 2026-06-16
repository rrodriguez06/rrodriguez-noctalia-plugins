import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

// Panneau principal : sélecteur d'hôte + jauges + cartes projet/service (actions) + overlay logs.
Item {
    id: root
    property var pluginApi: null
    readonly property var main: pluginApi?.mainInstance ?? null

    // Contrat panneau Noctalia.
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 600 * Style.uiScaleRatio
    property real contentPreferredHeight: 640 * Style.uiScaleRatio
    anchors.fill: parent

    property bool viewingLogs: false
    readonly property bool readOnly: main ? main.isReadOnly() : false
    readonly property bool confirmDestructive: pluginApi?.pluginSettings?.confirmDestructive ?? true

    // Liste d'hôtes pour le NComboBox.
    function hostModel() {
        var hs = pluginApi?.pluginSettings?.hosts ?? []
        var out = []
        for (var i = 0; i < hs.length; i++)
            out.push({ "key": String(i), "name": hs[i].name || hs[i].sshAlias || ("hôte " + i) })
        return out
    }
    readonly property string activeHostKey: String(pluginApi?.pluginSettings?.activeHostIndex ?? 0)

    // Couleurs d'état (indicateurs : couleurs littérales volontaires).
    function dotColor(s) {
        if (!s || s.status !== "running") return "#f85149"
        if (s.health === "unhealthy") return "#f85149"
        if (s.health === "starting") return "#d29922"
        return "#3fb950"
    }

    function fmtUptime(sec) {
        if (!sec && sec !== 0) return "?"
        var d = Math.floor(sec / 86400)
        var h = Math.floor((sec % 86400) / 3600)
        var m = Math.floor((sec % 3600) / 60)
        if (d > 0) return d + "j " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    onVisibleChanged: {
        if (!main) return
        main.setPanelOpen(visible)
        if (!visible) { main.stopLogs(); root.viewingLogs = false }
    }

    // ── Vue principale ────────────────────────────────────────────────────────
    Item {
        id: panelContainer
        anchors.fill: parent
        visible: opacity > 0
        opacity: root.viewingLogs ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            // ── BLOC 1 : en-tête + sélecteur d'hôte + jauges ──────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: headerCol.implicitHeight + Style.marginL * 2

                ColumnLayout {
                    id: headerCol
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginM

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NHeader {
                            Layout.fillWidth: true
                            label: pluginApi?.tr("panel.title") ?? "Home Server Control"
                            description: pluginApi?.tr("panel.subtitle") ?? ""
                        }
                        NComboBox {
                            visible: (pluginApi?.pluginSettings?.hosts ?? []).length > 1
                            Layout.preferredWidth: 160 * Style.uiScaleRatio
                            model: root.hostModel()
                            currentKey: root.activeHostKey
                            onSelected: (key) => { if (root.main) root.main.selectHost(parseInt(key)) }
                        }
                        NIconButton {
                            icon: "refresh"
                            tooltipText: pluginApi?.tr("panel.refresh")
                            onClicked: if (root.main) root.main.pollStatus(true)
                        }
                        NIconButton {
                            icon: "terminal-2"
                            tooltipText: pluginApi?.tr("panel.openSsh")
                            onClicked: if (root.main) root.main.openHostSsh()
                        }
                    }

                    // Jauges host-info (RAM / disque) + charge + uptime.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.main && root.main.reachable && root.main.hostInfo && root.main.hostInfo.hostname
                        spacing: Style.marginM

                        Repeater {
                            model: {
                                if (!root.main || !root.main.hostInfo) return []
                                var hi = root.main.hostInfo
                                var out = []
                                if (hi.mem && hi.mem.usedPct !== null && hi.mem.usedPct !== undefined)
                                    out.push({ "label": "RAM", "pct": hi.mem.usedPct })
                                if (hi.disks && hi.disks.length && hi.disks[0].usedPct !== null)
                                    out.push({ "label": "Disque", "pct": hi.disks[0].usedPct })
                                return out
                            }
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.preferredWidth: 110 * Style.uiScaleRatio
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    NText { text: modelData.label; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; Layout.fillWidth: true }
                                    NText { text: Math.round(modelData.pct) + "%"; pointSize: Style.fontSizeXS }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 4
                                    radius: 2
                                    color: Color.mSurface
                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, modelData.pct / 100))
                                        height: parent.height
                                        radius: parent.radius
                                        color: modelData.pct >= 90 ? "#f85149" : (modelData.pct >= 75 ? "#d29922" : Color.mPrimary)
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        NText {
                            visible: root.main && root.main.hostInfo && root.main.hostInfo.loadavg
                            text: {
                                var hi = root.main ? root.main.hostInfo : null
                                if (!hi) return ""
                                var la = hi.loadavg ? hi.loadavg.map(function (x) { return x.toFixed(2) }).join(" ") : "?"
                                return (pluginApi?.tr("panel.load") ?? "load") + " " + la + "  ·  "
                                     + (pluginApi?.tr("panel.uptime") ?? "uptime") + " " + root.fmtUptime(hi.uptimeSeconds)
                            }
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }
                    }
                }
            }

            // ── Message si aucun hôte / injoignable ───────────────────────────
            NBox {
                Layout.fillWidth: true
                visible: (pluginApi?.pluginSettings?.hosts ?? []).length === 0
                Layout.preferredHeight: noHostCol.implicitHeight + Style.marginL * 2
                ColumnLayout {
                    id: noHostCol
                    anchors.centerIn: parent
                    spacing: Style.marginXS
                    NText { text: pluginApi?.tr("panel.noHosts") ?? "No host"; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                    NText { text: pluginApi?.tr("panel.noHostsHint") ?? ""; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // ── BLOC 2 : liste des projets (cartes dépliables) ────────────────
            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: (pluginApi?.pluginSettings?.hosts ?? []).length > 0

                NListView {
                    id: projectsList
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginXS
                    model: root.main ? root.main.projectsModel : null

                    delegate: Rectangle {
                        id: card
                        required property string pid
                        required property string mode
                        required property int serviceCount
                        required property int downCount
                        required property int behind
                        property bool expanded: true

                        width: ListView.view ? ListView.view.width : 0
                        implicitHeight: cardCol.implicitHeight + Style.marginS * 2
                        radius: Style.radiusS
                        color: Color.mSurfaceVariant

                        ColumnLayout {
                            id: cardCol
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            spacing: Style.marginXS

                            // En-tête projet.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginXS

                                NIconButton {
                                    icon: card.expanded ? "chevron-down" : "chevron-right"
                                    onClicked: card.expanded = !card.expanded
                                }
                                NText {
                                    text: card.pid
                                    pointSize: Style.fontSizeL
                                    elide: Text.ElideRight
                                }
                                // badge services down.
                                Rectangle {
                                    visible: card.downCount > 0
                                    implicitWidth: db.implicitWidth + Style.marginS * 2
                                    implicitHeight: db.implicitHeight + Style.marginXS
                                    radius: Style.radiusXS
                                    color: "#f85149"
                                    NText { id: db; anchors.centerIn: parent; text: card.downCount + " down"; pointSize: Style.fontSizeXS; color: Color.mOnError }
                                }
                                // badge commits en retard.
                                Rectangle {
                                    visible: card.behind > 0
                                    implicitWidth: bb.implicitWidth + Style.marginS * 2
                                    implicitHeight: bb.implicitHeight + Style.marginXS
                                    radius: Style.radiusXS
                                    color: "#d29922"
                                    NText { id: bb; anchors.centerIn: parent; text: card.behind + " ↑"; pointSize: Style.fontSizeXS; color: Color.mOnError }
                                }
                                Item { Layout.fillWidth: true }

                                NIconButton {
                                    icon: "cloud-download"
                                    tooltipText: pluginApi?.tr("panel.checkUpdate")
                                    onClicked: if (root.main) root.main.checkUpdates(card.pid)
                                }
                                NIconButton {
                                    visible: !root.readOnly
                                    icon: "refresh-dot"
                                    tooltipText: pluginApi?.tr("panel.update")
                                    colorFgHover: Color.mPrimary
                                    onClicked: if (root.main) root.main.updateProject(card.pid)
                                }
                            }

                            // Corps : services.
                            ColumnLayout {
                                visible: card.expanded
                                Layout.fillWidth: true
                                spacing: Style.marginXS

                                Repeater {
                                    // On lit statusData dans l'expression pour que QML retrace la dépendance
                                    // et reconstruise les lignes à chaque poll (l'opérateur virgule renvoie servicesOf).
                                    model: card.expanded && root.main ? (root.main.statusData, root.main.servicesOf(card.pid)) : []
                                    delegate: RowLayout {
                                        id: svcRow
                                        required property var modelData
                                        property string confirming: ""
                                        Layout.fillWidth: true
                                        Layout.leftMargin: Style.marginS
                                        spacing: Style.marginS

                                        Timer { id: confirmTimer; interval: 3000; onTriggered: svcRow.confirming = "" }

                                        function act(action) {
                                            if (root.confirmDestructive && svcRow.confirming !== action) {
                                                svcRow.confirming = action
                                                confirmTimer.restart()
                                                return
                                            }
                                            svcRow.confirming = ""
                                            root.main.serviceAction(card.pid, modelData.name, action)
                                        }

                                        Rectangle {
                                            implicitWidth: 9; implicitHeight: 9; radius: 5
                                            color: root.dotColor(modelData)
                                        }
                                        NText {
                                            text: modelData.name
                                            pointSize: Style.fontSizeS
                                            Layout.preferredWidth: 130 * Style.uiScaleRatio
                                            elide: Text.ElideRight
                                        }
                                        NText {
                                            text: modelData.status + (modelData.health && modelData.health !== "none" ? " · " + modelData.health : "")
                                                + (modelData.repoBehind > 0 ? "  ↑" + modelData.repoBehind : "")
                                            pointSize: Style.fontSizeXS
                                            color: Color.mOnSurfaceVariant
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        NIconButton {
                                            visible: (modelData.urls && modelData.urls.length > 0)
                                            icon: "external-link"
                                            tooltipText: (modelData.urls && modelData.urls.length) ? modelData.urls[0] : ""
                                            onClicked: if (root.main && modelData.urls && modelData.urls.length) root.main.openUrl(modelData.urls[0])
                                        }
                                        NIconButton {
                                            icon: "file-text"
                                            tooltipText: pluginApi?.tr("panel.logs")
                                            enabled: !!modelData.containerName
                                            onClicked: {
                                                if (!root.main) return
                                                root.main.streamLogs(modelData.name, modelData.containerName)
                                                root.viewingLogs = true
                                            }
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && modelData.status === "running"
                                            icon: svcRow.confirming === "restart" ? "alert-triangle" : "rotate"
                                            tooltipText: svcRow.confirming === "restart" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.restart")
                                            colorFg: svcRow.confirming === "restart" ? Color.mError : Color.mPrimary
                                            colorFgHover: Color.mPrimary
                                            onClicked: svcRow.act("restart")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && modelData.status === "running"
                                            icon: svcRow.confirming === "stop" ? "alert-triangle" : "player-stop"
                                            tooltipText: svcRow.confirming === "stop" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.stop")
                                            colorFg: svcRow.confirming === "stop" ? Color.mError : Color.mPrimary
                                            colorFgHover: Color.mError
                                            onClicked: svcRow.act("stop")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && modelData.status !== "running"
                                            icon: "player-play"
                                            tooltipText: pluginApi?.tr("panel.start")
                                            colorFgHover: Color.mPrimary
                                            onClicked: if (root.main) root.main.serviceAction(card.pid, modelData.name, "start")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly
                                            icon: "terminal"
                                            tooltipText: pluginApi?.tr("panel.shell")
                                            enabled: !!modelData.containerName
                                            onClicked: if (root.main) root.main.openShell(modelData.containerName)
                                        }
                                    }
                                }

                                NText {
                                    visible: card.serviceCount === 0
                                    text: pluginApi?.tr("panel.noServices") ?? ""
                                    pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                    Layout.leftMargin: Style.marginS
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Overlay logs ──────────────────────────────────────────────────────────
    Item {
        id: logsView
        anchors.fill: parent
        anchors.margins: Style.marginM
        visible: opacity > 0
        opacity: root.viewingLogs ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            spacing: Style.marginM

            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: logHead.implicitHeight + Style.marginL * 2
                RowLayout {
                    id: logHead
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginS
                    NIcon { icon: "file-text"; color: Color.mPrimary }
                    NText { text: root.main ? root.main.logTitle : ""; pointSize: Style.fontSizeL; Layout.fillWidth: true; elide: Text.ElideRight }
                    NIconButton {
                        icon: "x"
                        tooltipText: pluginApi?.tr("panel.closeLogs")
                        onClicked: { if (root.main) root.main.stopLogs(); root.viewingLogs = false }
                    }
                }
            }

            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                NListView {
                    id: logList
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    clip: true
                    model: root.main ? root.main.logModel : null
                    delegate: NText {
                        required property string line
                        width: ListView.view ? ListView.view.width : 0
                        text: line
                        pointSize: Style.fontSizeXS
                        font.family: "monospace"
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        // Auto-scroll vers le bas à chaque nouvelle ligne.
        Connections {
            target: root.main ? root.main.logModel : null
            function onCountChanged() { logList.positionViewAtEnd() }
        }
    }
}
