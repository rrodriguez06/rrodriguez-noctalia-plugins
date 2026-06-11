import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Widgets

// Icône d'application : image résolue depuis la classe + repli glyphe.
// Optionnellement teintée d'une couleur de la palette Noctalia (shader appicon_colorize),
// pour un rendu monochrome cohérent avec le thème.
Item {
    id: root

    property string iconSource: ""
    property bool colorize: false
    property color tintColor: Color.mPrimary

    IconImage {
        id: img
        anchors.fill: parent
        source: root.iconSource
        visible: source != ""
        asynchronous: true
        smooth: true
        layer.enabled: root.colorize && img.source != ""
        layer.effect: ShaderEffect {
            property color targetColor: root.tintColor
            property real colorizeMode: 2.0
            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
        }
    }

    NIcon {
        anchors.centerIn: parent
        visible: img.source == ""
        icon: "app-window"
        color: Color.mOnSurfaceVariant
    }
}
