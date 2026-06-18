import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

// Contenu du panel natif Noctalia. Ne POSSÈDE PAS le terminal : il re-parente la tuile persistante
// de Main le temps de l'affichage (Component.onCompleted), et la rend à Main à la destruction
// (Component.onDestruction → reclaimTile). Le panel natif gère attache-barre, coins, focus, clic-dehors.
Item {
    id: root
    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance ?? null

    // Contrat lu par SmartPanel/PluginPanelSlot.
    readonly property var geometryPlaceholder: clip
    readonly property bool allowAttach: true
    readonly property bool panelAnchorHorizontalCenter: (mainInstance && mainInstance.cfgPosition === "centered")
    property real contentPreferredWidth: (mainInstance ? mainInstance.cfgWidth : 900) * Style.uiScaleRatio
    property real contentPreferredHeight: (mainInstance ? mainInstance.cfgHeight : 480) * Style.uiScaleRatio

    anchors.fill: parent

    // Hôte du contenu, arrondi (clippe les coins carrés du terminal).
    ClippingRectangle {
        id: clip
        anchors.fill: parent
        radius: Style.radiusL
        color: Color.mSurface

        // Message si la dépendance manque (pas de tuile).
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

    function _attachTile() {
        var t = root.mainInstance ? root.mainInstance.tileItem : null
        if (t) {
            t.parent = clip
            Qt.callLater(t.focusTerminal)
        }
    }

    Component.onCompleted: _attachTile()
    onMainInstanceChanged: if (mainInstance) _attachTile()

    // Rendre la tuile à Main AVANT que ce panel ne soit détruit (sinon parent visuel pendouille).
    Component.onDestruction: if (root.mainInstance) root.mainInstance.reclaimTile()
}
