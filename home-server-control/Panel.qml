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
    // Capacités du driver de l'hôte actif (docker masque les features git-aware).
    // Dépendances explicites du binding : resolvedMode (résolution de la sonde auto) et
    // activeHostIndex (changement d'hôte) → ré-évaluation correcte dans les deux cas.
    readonly property var caps: (main && main.resolvedMode,
                                 pluginApi?.pluginSettings?.activeHostIndex,
                                 main ? main.capabilities() : ({}))

    // Jauges liées à hostInfo (réassigné à chaque poll) : MAJ fluide, sans recréer d'éléments.
    readonly property real ramPct: (main && main.hostInfo && main.hostInfo.mem && main.hostInfo.mem.usedPct != null)
                                   ? main.hostInfo.mem.usedPct : -1
    readonly property real diskPct: (main && main.hostInfo && main.hostInfo.disks && main.hostInfo.disks.length
                                     && main.hostInfo.disks[0].usedPct != null) ? main.hostInfo.disks[0].usedPct : -1

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
    function dotColor(status, health) {
        if (status !== "running") return "#f85149"
        if (health === "unhealthy") return "#f85149"
        if (health === "starting") return "#d29922"
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

                    // Jauges host-info (RAM / disque) + charge + uptime — liées à hostInfo,
                    // donc mises à jour en douceur sans recréer d'éléments (pas de blink).
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.main && root.main.reachable && root.main.hostInfo && root.main.hostInfo.hostname
                        spacing: Style.marginM

                        ColumnLayout {
                            visible: root.ramPct >= 0
                            Layout.preferredWidth: 110 * Style.uiScaleRatio
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                NText { text: "RAM"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; Layout.fillWidth: true }
                                NText { text: Math.round(root.ramPct) + "%"; pointSize: Style.fontSizeXS }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2; color: Color.mSurface
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, root.ramPct / 100))
                                    height: parent.height; radius: parent.radius
                                    color: root.ramPct >= 90 ? "#f85149" : (root.ramPct >= 75 ? "#d29922" : Color.mPrimary)
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.diskPct >= 0
                            Layout.preferredWidth: 110 * Style.uiScaleRatio
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                NText { text: "Disque"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; Layout.fillWidth: true }
                                NText { text: Math.round(root.diskPct) + "%"; pointSize: Style.fontSizeXS }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2; color: Color.mSurface
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, root.diskPct / 100))
                                    height: parent.height; radius: parent.radius
                                    color: root.diskPct >= 90 ? "#f85149" : (root.diskPct >= 75 ? "#d29922" : Color.mPrimary)
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
                        // Replié par défaut ; l'état est mémorisé par projet dans Main (survit aux polls).
                        property bool expanded: root.main ? root.main.isExpanded(card.pid) : false
                        // Confirmation des actions projet : "" | "restart" | "full".
                        property string confirmingProject: ""

                        width: ListView.view ? ListView.view.width : 0
                        implicitHeight: cardCol.implicitHeight + Style.marginS * 2
                        radius: Style.radiusS
                        color: Color.mSurfaceVariant

                        Timer { id: projConfirmTimer; interval: 3000; onTriggered: card.confirmingProject = "" }
                        function projAct(action) {
                            if (root.confirmDestructive && card.confirmingProject !== action) {
                                card.confirmingProject = action
                                projConfirmTimer.restart()
                                return
                            }
                            card.confirmingProject = ""
                            if (!root.main) return
                            if (action === "full") root.main.deployProject(card.pid, true)
                            else root.main.projectAction(card.pid, "restart")
                        }

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
                                    onClicked: if (root.main) root.main.toggleExpanded(card.pid)
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
                                    visible: card.behind > 0 && root.caps.gitBehind
                                    implicitWidth: bb.implicitWidth + Style.marginS * 2
                                    implicitHeight: bb.implicitHeight + Style.marginXS
                                    radius: Style.radiusXS
                                    color: "#d29922"
                                    NText { id: bb; anchors.centerIn: parent; text: card.behind + " ↑"; pointSize: Style.fontSizeXS; color: Color.mOnError }
                                }
                                Item { Layout.fillWidth: true }

                                NIconButton {
                                    visible: root.caps.checkUpdates === true
                                    icon: "cloud-download"
                                    tooltipText: pluginApi?.tr("panel.checkUpdate")
                                    onClicked: if (root.main) root.main.checkUpdates(card.pid)
                                }
                                NIconButton {
                                    visible: !root.readOnly && root.caps.update === true
                                    icon: "refresh-dot"
                                    tooltipText: pluginApi?.tr("panel.update")
                                    colorFgHover: Color.mPrimary
                                    onClicked: if (root.main) root.main.updateProject(card.pid)
                                }
                                NIconButton {
                                    visible: !root.readOnly && root.caps.restartAll === true
                                    icon: card.confirmingProject === "restart" ? "alert-triangle" : "reload"
                                    tooltipText: card.confirmingProject === "restart" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.restartAll")
                                    colorFg: card.confirmingProject === "restart" ? Color.mError : Color.mPrimary
                                    colorFgHover: Color.mPrimary
                                    onClicked: card.projAct("restart")
                                }
                                NIconButton {
                                    visible: !root.readOnly && root.caps.deploy === true
                                    icon: card.confirmingProject === "full" ? "alert-triangle" : "rocket"
                                    tooltipText: card.confirmingProject === "full" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.deployFull")
                                    colorFg: card.confirmingProject === "full" ? Color.mError : Color.mPrimary
                                    colorFgHover: Color.mError
                                    onClicked: card.projAct("full")
                                }
                            }

                            // Corps : services.
                            ColumnLayout {
                                visible: card.expanded
                                Layout.fillWidth: true
                                spacing: Style.marginXS

                                Repeater {
                                    // Modèle = ListModel par projet, MAJ en place côté Main : les lignes
                                    // ne sont pas recréées au poll (pas de blink, état « confirmation » conservé).
                                    model: root.main ? root.main.svcModelFor(card.pid) : null
                                    delegate: RowLayout {
                                        id: svcRow
                                        required property string name
                                        required property string containerName
                                        required property string status
                                        required property string health
                                        required property int repoBehind
                                        required property string url0
                                        required property bool hasUrl
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
                                            root.main.serviceAction(card.pid, svcRow.name, action)
                                        }

                                        Rectangle {
                                            implicitWidth: 9; implicitHeight: 9; radius: 5
                                            color: root.dotColor(svcRow.status, svcRow.health)
                                        }
                                        NText {
                                            text: svcRow.name
                                            pointSize: Style.fontSizeS
                                            Layout.preferredWidth: 130 * Style.uiScaleRatio
                                            elide: Text.ElideRight
                                        }
                                        NText {
                                            text: svcRow.status + (svcRow.health && svcRow.health !== "none" ? " · " + svcRow.health : "")
                                                + (root.caps.gitBehind && svcRow.repoBehind > 0 ? "  ↑" + svcRow.repoBehind : "")
                                            pointSize: Style.fontSizeXS
                                            color: Color.mOnSurfaceVariant
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        NIconButton {
                                            visible: svcRow.hasUrl
                                            icon: "external-link"
                                            tooltipText: svcRow.url0
                                            onClicked: if (root.main && svcRow.url0) root.main.openUrl(svcRow.url0)
                                        }
                                        NIconButton {
                                            icon: "file-text"
                                            tooltipText: pluginApi?.tr("panel.logs")
                                            enabled: svcRow.containerName.length > 0
                                            onClicked: {
                                                if (!root.main) return
                                                root.main.streamLogs(svcRow.name, svcRow.containerName)
                                                root.viewingLogs = true
                                            }
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && svcRow.status === "running"
                                            icon: svcRow.confirming === "restart" ? "alert-triangle" : "rotate"
                                            tooltipText: svcRow.confirming === "restart" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.restart")
                                            colorFg: svcRow.confirming === "restart" ? Color.mError : Color.mPrimary
                                            colorFgHover: Color.mPrimary
                                            onClicked: svcRow.act("restart")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && svcRow.status === "running"
                                            icon: svcRow.confirming === "stop" ? "alert-triangle" : "player-stop"
                                            tooltipText: svcRow.confirming === "stop" ? pluginApi?.tr("panel.confirm") : pluginApi?.tr("panel.stop")
                                            colorFg: svcRow.confirming === "stop" ? Color.mError : Color.mPrimary
                                            colorFgHover: Color.mError
                                            onClicked: svcRow.act("stop")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly && svcRow.status !== "running"
                                            icon: "player-play"
                                            tooltipText: pluginApi?.tr("panel.start")
                                            colorFgHover: Color.mPrimary
                                            onClicked: if (root.main) root.main.serviceAction(card.pid, svcRow.name, "start")
                                        }
                                        NIconButton {
                                            visible: !root.readOnly
                                            icon: "terminal"
                                            tooltipText: pluginApi?.tr("panel.shell")
                                            enabled: svcRow.containerName.length > 0
                                            onClicked: if (root.main) root.main.openShell(svcRow.containerName)
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
        // À l'ouverture de l'overlay : on (re)suit la fin du flux.
        onVisibleChanged: if (visible) { logList.followTail = true; Qt.callLater(logList.positionViewAtEnd) }

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
                        icon: "external-link"
                        tooltipText: pluginApi?.tr("panel.openInTerminal")
                        enabled: root.main && root.main.logContainer.length > 0
                        onClicked: if (root.main) root.main.openLogsInTerminal()
                    }
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

                ListView {
                    id: logList
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    clip: true
                    model: root.main ? root.main.logModel : null
                    // Pas d'overscroll (sinon on scrolle « sous » la dernière ligne + flicker).
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    cacheBuffer: 400

                    // Suivi du bas du flux, UNIQUEMENT tant que l'utilisateur est déjà en bas.
                    property bool followTail: true
                    property bool userInteracting: false

                    onMovementStarted: userInteracting = true
                    onMovementEnded: { userInteracting = false; followTail = atYEnd }
                    onDraggingChanged: if (dragging) followTail = false

                    // Reste collé en bas pendant que le contenu grandit (et que les lignes
                    // wrappées prennent leur hauteur finale) — sauf si l'utilisateur scrolle.
                    onContentHeightChanged: if (followTail && !userInteracting) positionViewAtEnd()
                    onCountChanged: if (followTail && !userInteracting) Qt.callLater(positionViewAtEnd)

                    // Nouveau service de logs -> on resuit la fin.
                    Connections {
                        target: root.main
                        function onLogTitleChanged() {
                            logList.followTail = true
                            Qt.callLater(logList.positionViewAtEnd)
                        }
                    }

                    delegate: NText {
                        required property string line
                        width: logList.width
                        text: line
                        pointSize: Style.fontSizeXS
                        font.family: "monospace"
                        wrapMode: Text.WrapAnywhere
                        color: Color.mOnSurface
                    }
                }

                // Revenir en bas quand on a scrollé vers le haut.
                NIconButton {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.marginM
                    visible: !logList.followTail
                    icon: "chevron-down"
                    tooltipText: pluginApi?.tr("panel.scrollBottom")
                    onClicked: { logList.followTail = true; logList.positionViewAtEnd() }
                }
            }
        }
    }
}
