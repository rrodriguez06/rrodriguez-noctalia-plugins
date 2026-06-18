import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

// Contenu du panel natif Noctalia. Ne POSSÈDE PAS les tuiles : il re-parente les tuiles persistantes
// de Main le temps de l'affichage (Component.onCompleted), et les rend à Main à la destruction
// (Component.onDestruction → reclaimTiles). Le panel natif gère attache-barre, coins, focus, clic-dehors.
//
// Multi-onglets : une NTabBar (composants Noctalia) pilote l'onglet courant (mainInstance.currentTab,
// persistant), et toutes les tuiles sont empilées dans le ClippingRectangle arrondi — seule celle de
// l'onglet courant est visible/focus.
Item {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null

    // Contrat lu par SmartPanel/PluginPanelSlot.
    // geometryPlaceholder = bg (rect complet) → le fond arrondi natif est dessiné sur tout le panel.
    readonly property var geometryPlaceholder: bg
    readonly property bool allowAttach: true
    readonly property bool panelAnchorHorizontalCenter: (mainInstance ? mainInstance.cfgPosition === "centered" : false)
    property real contentPreferredWidth: (mainInstance ? mainInstance.cfgWidth : 900) * Style.uiScaleRatio
    property real contentPreferredHeight: (mainInstance ? mainInstance.cfgHeight : 480) * Style.uiScaleRatio

    anchors.fill: parent

    Item {
        id: bg
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS

            // ── Barre d'onglets (générée depuis tabsModel) ───────────────────────
            NTabBar {
                id: tabBar
                Layout.fillWidth: true
                distributeEvenly: true
                visible: root.mainInstance && root.mainInstance.depAvailable && root.mainInstance.tiles.length > 1

                onCurrentIndexChanged: if (root.mainInstance) root.mainInstance.currentTab = currentIndex

                Repeater {
                    model: root.mainInstance ? root.mainInstance.tabsModel : []
                    NTabButton {
                        icon: modelData.icon
                        text: root.pluginApi ? root.pluginApi.tr("tab." + modelData.id) : modelData.id
                        pointSize: Style.fontSizeM
                        tabIndex: index
                        checked: tabBar.currentIndex === index
                    }
                }
            }

            // ── Zone terminal : toutes les tuiles empilées, arrondies ────────────
            ClippingRectangle {
                id: termClip
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.radiusM
                color: Color.mSurface

                // Rapporte la taille de la zone terminal à Main, qui la STABILISE (debounce) → les tuiles
                // ne se redimensionnent pas pendant l'animation d'ouverture (termClip les clippe). Aucun
                // reflow → prompt en bas préservé à la ré-ouverture.
                onWidthChanged: if (root.mainInstance) root.mainInstance.reportContentSize(width, height)
                onHeightChanged: if (root.mainInstance) root.mainInstance.reportContentSize(width, height)

                NText {
                    anchors.centerIn: parent
                    visible: !(root.mainInstance && root.mainInstance.depAvailable)
                    width: parent.width - Style.marginXL * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Color.mOnSurface
                    text: root.pluginApi ? root.pluginApi.tr("error.missingDepLong")
                                         : "qmltermwidget requis :\n  pacman -S qmltermwidget\npuis redémarrez le shell."
                }
            }
        }
    }

    // Re-parente toutes les tuiles dans le contentItem du ClippingRectangle (indispensable pour
    // l'arrondi : sinon non capturé par le ShaderEffectSource), puis sync visibilité/focus.
    function _attachTiles() {
        if (!root.mainInstance)
            return
        var ts = root.mainInstance.tiles
        for (var i = 0; i < ts.length; i++) {
            ts[i].parent = termClip.contentItem
            ts[i].start()   // idempotent ; démarre (différé) à la taille réelle du panel, pas du holder
            ts[i].logState("ATTACH")   // [DIAG 0.3.8]
        }
        // Restaure l'onglet précédemment sélectionné (survit aux ouvertures/fermetures).
        tabBar.currentIndex = root.mainInstance.currentTab
        root._syncTabs()
        attachLateTimer.restart()   // [DIAG 0.3.8] état après animation d'ouverture
    }

    // Affiche uniquement la tuile de l'onglet courant ; les autres tournent en arrière-plan.
    function _syncTabs() {
        if (!root.mainInstance)
            return
        var ts = root.mainInstance.tiles
        var cur = root.mainInstance.currentTab
        for (var i = 0; i < ts.length; i++)
            ts[i].visible = (i === cur)
        if (cur >= 0 && cur < ts.length)
            Qt.callLater(ts[cur].focusTerminal)
    }

    // [DIAG 0.3.8] re-log l'état des tuiles une fois l'animation d'ouverture terminée.
    Timer {
        id: attachLateTimer
        interval: 600
        onTriggered: {
            if (!root.mainInstance) return
            var ts = root.mainInstance.tiles
            for (var i = 0; i < ts.length; i++) ts[i].logState("ATTACH-LATE")
        }
    }

    Component.onCompleted: _attachTiles()
    onMainInstanceChanged: if (mainInstance) _attachTiles()

    Connections {
        target: root.mainInstance
        function onTilesChanged() { root._attachTiles() }
        function onCurrentTabChanged() { root._syncTabs() }
    }

    // Rendre les tuiles à Main AVANT que ce panel ne soit détruit (sinon parent visuel pendouille).
    Component.onDestruction: if (root.mainInstance) root.mainInstance.reclaimTiles()
}
