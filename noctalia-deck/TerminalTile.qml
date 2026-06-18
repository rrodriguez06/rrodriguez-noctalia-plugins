import QtQuick
import qs.Commons
import QMLTermWidget 2.0

// Tuile « terminal » : encapsule un vrai émulateur (PTY) via QMLTermWidget + QMLTermSession.
//
// IMPORTANT — persistance : cet objet est créé et possédé par Main.qml (parent QObject persistant).
// Le Panel ne fait que le RE-PARENTER visuellement (parent = sa zone de contenu) à l'ouverture, et
// le rend à Main à la fermeture. L'objet survit donc à la destruction du panel → session + scrollback
// intacts, sans tmux. `useFBORendering: false` (rendu CPU) sécurise le déplacement entre fenêtres.
//
// C'est aussi LE point d'extensibilité : une future tuile « claude » = même composant avec command:"claude".
Item {
    id: tile
    anchors.fill: parent   // remplit le parent courant (Main au repos, la zone du panel quand affiché)

    // --- entrées (poussées par Main) ---
    property string shellProgram: ""        // vide => $SHELL
    property var shellArgs: []
    property string cwd: ""
    property var envv: []
    property string colorScheme: "Solarized"
    property string fontFamily: "monospace"
    property int fontSize: 11

    // --- état ---
    property bool started: false
    readonly property bool alive: tile.started && session.hasActiveProcess
    readonly property string foregroundName: session.foregroundProcessName

    // --- signaux ---
    signal finished()
    signal lostFocus()

    // --- API ---
    function start() {
        if (tile.started)
            return
        if (tile.shellProgram && tile.shellProgram.length > 0)
            session.shellProgram = tile.shellProgram
        if (tile.shellArgs && tile.shellArgs.length > 0)
            session.shellProgramArgs = tile.shellArgs
        if (tile.cwd && tile.cwd.length > 0)
            session.initialWorkingDirectory = tile.cwd
        if (tile.envv && tile.envv.length > 0)
            session.setEnvironment(tile.envv)
        session.startShellProgram()
        tile.started = true
    }

    function restart() {
        session.startShellProgram()
        tile.started = true
        Qt.callLater(tile.focusTerminal)
    }

    function focusTerminal() { term.forceActiveFocus() }
    function copy() { term.copyClipboard() }
    function paste() { term.pasteClipboard() }

    // Live theming : présent uniquement avec le fork qmltermwidget-noctalia (slot applyColorSchemeFile).
    readonly property bool liveCapable: (typeof term.applyColorSchemeFile === "function")
    function applySchemeFile(path) {
        if (typeof term.applyColorSchemeFile === "function")
            term.applyColorSchemeFile(path)
    }

    QMLTermWidget {
        id: term
        anchors.fill: parent   // remplit tout (padding symétrique) ; la scrollbar se superpose

        font.family: tile.fontFamily
        font.pointSize: tile.fontSize
        colorScheme: tile.colorScheme

        // Rendu CPU (QImage) plutôt que FBO/GL : indépendant du contexte de la fenêtre,
        // donc robuste quand la tuile change de fenêtre (re-parentage par le Panel).
        useFBORendering: false

        enableBold: true
        enableItalic: true
        blinkingCursor: true

        session: QMLTermSession {
            id: session
            onFinished: tile.finished()
            onTermLostFocus: tile.lostFocus()
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (w) => term.simulateWheel(w.x, w.y, w.buttons, w.modifiers, w.angleDelta)
        }

        // Scrollbar maison : le thumb reste clampé entre [pad, height-pad] (pad = rayon des coins)
        // et détaché du bord droit, pour ne jamais empiéter sur les coins arrondis.
        Rectangle {
            id: sb
            readonly property real pad: Style.radiusM
            readonly property int total: term.lines + term.scrollbarMaximum
            readonly property real range: term.scrollbarMaximum - term.scrollbarMinimum
            readonly property real trackH: Math.max(0, term.height - 2 * pad)

            visible: term.scrollbarMaximum > 0
            width: 4 * Style.uiScaleRatio
            radius: width / 2
            color: Color.mOnSurfaceVariant
            anchors.right: parent.right
            anchors.rightMargin: 3 * Style.uiScaleRatio

            height: total > 0 ? Math.max(20 * Style.uiScaleRatio, trackH * (term.lines / total)) : 0
            y: pad + (range > 0 ? (trackH - height) * ((term.scrollbarCurrentValue - term.scrollbarMinimum) / range) : 0)

            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            Connections {
                target: term
                function onScrollbarValueChanged() { sb.opacity = 1; hideTimer.restart() }
            }
            Timer { id: hideTimer; interval: 1200; onTriggered: sb.opacity = 0 }
        }
    }

    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: term.copyClipboard() }
    Shortcut { sequence: "Ctrl+Shift+V"; onActivated: term.pasteClipboard() }
}
