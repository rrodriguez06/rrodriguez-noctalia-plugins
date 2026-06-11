import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance

    // Contrat panneau noctalia
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    // En mode édition, le panneau grandit modérément (mais reste docké à la barre).
    property real contentPreferredWidth: (editingLayoutName !== "" ? 780 : 460) * Style.uiScaleRatio
    property real contentPreferredHeight: (editingLayoutName !== "" ? 640 : 600) * Style.uiScaleRatio
    anchors.fill: parent

    property bool confirmingClean: false
    // Layout en cours d'édition ("" = aucun -> on affiche la liste).
    property string editingLayoutName: ""

    // Réglages d'apparence/comportement (lus depuis pluginApi.pluginSettings).
    readonly property bool colorizeAppIcons: (pluginApi?.pluginSettings?.colorizeAppIcons ?? false)
                                             && (pluginApi?.pluginSettings?.appIconColor ?? "primary") !== "none"
    readonly property color appIconTint: Color.resolveColorKey(pluginApi?.pluginSettings?.appIconColor ?? "primary")
    readonly property bool closePanelOnAction: pluginApi?.pluginSettings?.closePanelOnAction ?? false
    readonly property bool confirmDelete: pluginApi?.pluginSettings?.confirmDelete ?? true
    // Mode de chargement par défaut : "add" | "replace" | "merge".
    readonly property string defaultLoadMode: pluginApi?.pluginSettings?.defaultLoadMode ?? "add"
    // Ordre d'affichage des boutons de chargement : défaut en tête, puis les deux autres.
    readonly property var loadModeOrder: {
        var all = ["add", "replace", "merge"]
        return [defaultLoadMode].concat(all.filter(m => m !== defaultLoadMode))
    }
    function loadModeIcon(m) {
        return m === "replace" ? "replace" : (m === "merge" ? "arrows-exchange" : "download")
    }
    function loadModeLabel(m) {
        return m === "replace" ? "Remplacer" : (m === "merge" ? "Fusionner" : "Charger")
    }

    // Ferme le panneau après une action mutante si l'option est activée.
    function _afterAction() {
        if (closePanelOnAction && pluginApi)
            pluginApi.withCurrentScreen(s => pluginApi.closePanel(s))
    }

    onVisibleChanged: {
        if (visible && mainInstance) {
            mainInstance.refresh()
            mainInstance.refreshMonitors()
        }
        confirmingClean = false
        editingLayoutName = ""
    }
    Component.onCompleted: {
        if (mainInstance) {
            mainInstance.refresh()
            mainInstance.refreshMonitors()
        }
    }

    function startEdit(name) {
        if (!mainInstance) return
        mainInstance.refreshMonitors()
        mainInstance.refreshWorkspaceRules()
        var detail = mainInstance.layoutsDetail[name]
        layoutEditor.load(name, detail ? detail.windows : [],
                          detail ? detail.trees : ({}), detail ? detail.region : ({}))
        editingLayoutName = name
    }

    // Résout l'icône d'une appli depuis sa classe (vide si introuvable → glyphe de repli).
    function appIcon(cls) {
        if (!cls) return ""
        var e = DesktopEntries.heuristicLookup(cls)
        var name = (e && e.icon) ? e.icon : ("" + cls).toLowerCase()
        return Quickshell.iconPath(name, true)
    }

    // Nom lisible de l'appli (et non le titre de la fenêtre, non restaurable) ; repli sur la classe.
    function appName(cls) {
        if (!cls) return "?"
        var e = DesktopEntries.heuristicLookup(cls)
        return (e && e.name) ? e.name : ("" + cls)
    }

    // Méta d'une fenêtre : workspace / écran / taille flottante.
    function winMeta(w) {
        var parts = []
        if (w.special) parts.push("scratchpad")
        else parts.push("ws " + (w.workspace_name || w.workspace))
        if (w.monitor) parts.push(w.monitor)
        if (w.floating && w.size) parts.push("float " + Math.round(w.size[0]) + "×" + Math.round(w.size[1]))
        return parts.join("  ·  ")
    }

    Timer { id: confirmResetTimer; interval: 3000; onTriggered: root.confirmingClean = false }

    // Éditeur visuel (affiché à la place de la liste quand editingLayoutName != "").
    LayoutEditor {
        id: layoutEditor
        anchors.fill: parent
        pluginApi: root.pluginApi
        monitors: root.mainInstance ? root.mainInstance.monitorsGeometry : []
        workspaceRules: root.mainInstance ? root.mainInstance.workspaceRules : ({})
        visible: opacity > 0
        opacity: root.editingLayoutName !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
        onSaved: {
            root.editingLayoutName = ""
            if (root.mainInstance) root.mainInstance.refresh()
        }
        onCancelled: root.editingLayoutName = ""
    }

    // Conteneur transparent : les espaces entre les blocs laissent voir l'arrière-plan de la barre.
    Item {
        id: panelContainer
        anchors.fill: parent
        visible: opacity > 0
        opacity: root.editingLayoutName !== "" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            // ── BLOC 1 : titre / sous-titre + champ de sauvegarde ──────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: headerCol.implicitHeight + Style.marginL * 2

                ColumnLayout {
                    id: headerCol
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginM

                    NHeader {
                        Layout.fillWidth: true
                        label: "Hypr Layout"
                        description: "Sauvegarde & restaure tes dispositions de fenetres"
                    }

                    // --- sauver la disposition actuelle ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NTextInput {
                            id: saveInput
                            Layout.fillWidth: true
                            placeholderText: "Nom du layout…"
                        }
                        NButton {
                            text: "Sauver"
                            icon: "device-floppy"
                            enabled: saveInput.text.trim().length > 0
                            onClicked: {
                                root.mainInstance.saveLayout(saveInput.text)
                                saveInput.text = ""
                                root._afterAction()
                            }
                        }
                    }
                }
            }

            // ── BLOC 2 : liste des layouts (cartes dépliables) ─────────────────────
            NBox {
                Layout.fillWidth: true
                Layout.fillHeight: true

                NListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: Style.marginL
                    spacing: Style.marginXS
                    model: root.mainInstance ? root.mainInstance.layoutsModel : null

                    delegate: Rectangle {
                    id: card
                    required property string name
                    required property int windowCount
                    required property int workspaces
                    required property int monitors
                    property bool expanded: false
                    property bool editing: false
                    property bool confirmingDelete: false

                    Timer { id: confirmDeleteTimer; interval: 3000; onTriggered: card.confirmingDelete = false }

                    width: ListView.view ? ListView.view.width : 0
                    implicitHeight: cardCol.implicitHeight + Style.marginS * 2
                    radius: Style.radiusS
                    color: Color.mSurfaceVariant

                    ColumnLayout {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: Style.marginS
                        spacing: Style.marginXS

                        // --- en-tête ---
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginXS

                            NIconButton {
                                icon: card.expanded ? "chevron-down" : "chevron-right"
                                enabled: !card.editing
                                tooltipText: card.expanded ? "Replier" : "Déplier"
                                onClicked: card.expanded = !card.expanded
                            }

                            // mode normal : nom (largeur fixe, crop) + badge + actions
                            NText {
                                visible: !card.editing
                                Layout.preferredWidth: 110 * Style.uiScaleRatio
                                Layout.maximumWidth: 110 * Style.uiScaleRatio
                                text: card.name
                                pointSize: Style.fontSizeL
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                visible: !card.editing
                                implicitWidth: badge.implicitWidth + Style.marginS * 2
                                implicitHeight: badge.implicitHeight + Style.marginXS
                                radius: Style.radiusXS
                                color: Color.mSurface
                                NText {
                                    id: badge
                                    anchors.centerIn: parent
                                    text: card.windowCount + (card.windowCount > 1 ? " fenêtres" : " fenêtre")
                                    pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                            // Pousse les actions vers la droite, laissant une largeur fixe au titre.
                            Item {
                                visible: !card.editing
                                Layout.fillWidth: true
                            }
                            // Boutons de chargement : mode par défaut en tête (accentué),
                            // puis les deux autres modes (atténués).
                            Repeater {
                                model: root.loadModeOrder
                                delegate: NIconButton {
                                    required property string modelData
                                    required property int index
                                    visible: !card.editing
                                    icon: root.loadModeIcon(modelData)
                                    tooltipText: root.loadModeLabel(modelData)
                                    colorFg: index === 0 ? Color.mPrimary : Color.mOnSurfaceVariant
                                    colorFgHover: Color.mPrimary
                                    onClicked: {
                                        root.mainInstance.loadLayout(card.name, modelData)
                                        root._afterAction()
                                    }
                                }
                            }
                            NIconButton {
                                visible: !card.editing
                                icon: "layout-grid"
                                tooltipText: "Éditer la disposition"
                                colorFgHover: Color.mPrimary
                                onClicked: root.startEdit(card.name)
                            }
                            NIconButton {
                                visible: !card.editing
                                icon: "pencil"
                                tooltipText: "Renommer"
                                onClicked: {
                                    renameInput.text = card.name
                                    card.editing = true
                                    renameInput.forceActiveFocus()
                                }
                            }
                            NIconButton {
                                visible: !card.editing
                                icon: card.confirmingDelete ? "alert-triangle" : "trash"
                                tooltipText: card.confirmingDelete ? "Confirmer la suppression" : "Supprimer"
                                colorFg: card.confirmingDelete ? Color.mError : Color.mPrimary
                                colorFgHover: Color.mError
                                onClicked: {
                                    if (root.confirmDelete && !card.confirmingDelete) {
                                        card.confirmingDelete = true
                                        confirmDeleteTimer.restart()
                                    } else {
                                        card.confirmingDelete = false
                                        root.mainInstance.deleteLayout(card.name)
                                        root._afterAction()
                                    }
                                }
                            }

                            // mode édition : champ + valider / annuler
                            NTextInput {
                                id: renameInput
                                visible: card.editing
                                Layout.fillWidth: true
                                placeholderText: "Nouveau nom…"
                            }
                            NIconButton {
                                visible: card.editing
                                icon: "check"
                                tooltipText: "Valider"
                                colorFgHover: Color.mPrimary
                                onClicked: {
                                    root.mainInstance.renameLayout(card.name, renameInput.text)
                                    card.editing = false
                                    root._afterAction()
                                }
                            }
                            NIconButton {
                                visible: card.editing
                                icon: "x"
                                tooltipText: "Annuler"
                                onClicked: card.editing = false
                            }
                        }

                        // --- corps déplié : applis du layout ---
                        ColumnLayout {
                            visible: card.expanded
                            Layout.fillWidth: true
                            Layout.topMargin: Style.marginXS
                            spacing: Style.marginXS

                            Repeater {
                                model: (card.expanded && root.mainInstance && root.mainInstance.layoutsDetail[card.name])
                                       ? root.mainInstance.layoutsDetail[card.name].windows : []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Style.marginS
                                    spacing: Style.marginS

                                    AppIcon {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        iconSource: root.appIcon(modelData["class"])
                                        colorize: root.colorizeAppIcons
                                        tintColor: root.appIconTint
                                    }
                                    NText {
                                        Layout.fillWidth: true
                                        text: root.appName(modelData["class"])
                                        pointSize: Style.fontSizeS
                                        elide: Text.ElideRight
                                    }
                                    NText {
                                        text: root.winMeta(modelData)
                                        pointSize: Style.fontSizeXS
                                        color: Color.mOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }

            // ── BLOC 3 : fermer toutes les fenêtres (confirmation optionnelle) ─────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: cleanBtn.implicitHeight + Style.marginM * 2

                NButton {
                    id: cleanBtn
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    text: root.confirmingClean ? "Confirmer : tout fermer ?" : "Tout fermer (clean)"
                    icon: root.confirmingClean ? "alert-triangle" : "x"
                    backgroundColor: Color.mError
                    textColor: Color.mOnError
                    onClicked: {
                        var needConfirm = root.pluginApi?.pluginSettings?.confirmClean ?? true
                        if (needConfirm && !root.confirmingClean) {
                            root.confirmingClean = true
                            confirmResetTimer.restart()
                        } else {
                            root.confirmingClean = false
                            root.mainInstance.cleanAll()
                        }
                    }
                }
            }
        }
    }
}
