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

    // Onglet « service » : relance le programme s'il se termine (ex. on quitte btop avec « q »).
    // Garde anti-spin : on ne relance pas si le process a vécu moins de _minLifeMs (commande absente
    // / échec immédiat) → l'onglet reste utilisable sans boucler.
    property bool autoRelaunch: false
    readonly property int _minLifeMs: 1500
    property double _startedAt: 0
    property bool _pendingStart: false

    // --- état ---
    property bool started: false
    readonly property bool alive: tile.started && session.hasActiveProcess
    readonly property string foregroundName: session.foregroundProcessName

    // --- signaux ---
    signal finished()
    signal lostFocus()

    // --- API ---
    function start() {
        if (tile.started || tile._pendingStart)
            return
        if (tile.shellProgram && tile.shellProgram.length > 0)
            session.shellProgram = tile.shellProgram
        if (tile.shellArgs && tile.shellArgs.length > 0)
            session.shellProgramArgs = tile.shellArgs
        if (tile.cwd && tile.cwd.length > 0)
            session.initialWorkingDirectory = tile.cwd
        if (tile.envv && tile.envv.length > 0)
            session.setEnvironment(tile.envv)
        // On « arme » seulement : le lancement réel attend que le widget atteigne sa taille FINALE via
        // onWidthChanged/onHeightChanged (post-layout). Lancer maintenant risquerait de créer le PTY à la
        // taille transitoire du re-parentage (holder), puis de le redimensionner → artefact de scroll.
        tile._pendingStart = true
    }

    function restart() {
        tile.started = false
        tile._pendingStart = true
        tile._launchWhenSized()
        Qt.callLater(tile.focusTerminal)
    }

    // Beaucoup de TUIs (btop…) lisent la taille du terminal AU LANCEMENT et abandonnent si le PTY est
    // en 0×0 (« Failed to get size of terminal! »). On n'exécute donc le programme qu'une fois la tuile
    // réellement dimensionnée (déclenché aussi par onWidthChanged/onHeightChanged du widget).
    function _launchWhenSized() {
        if (!tile._pendingStart || tile.started)
            return
        if (term.width > 0 && term.height > 0 && term.lines > 0 && term.columns > 0) {
            tile._pendingStart = false
            tile._startedAt = Date.now()
            session.startShellProgram()
            tile.started = true
        }
    }

    // Fin du process : signale toujours `finished()` (comportement shell inchangé), puis relance
    // si onglet service ET process suffisamment vivace (sinon garde anti-spin).
    function _onFinished() {
        tile.finished()
        if (tile.autoRelaunch && tile.started && (Date.now() - tile._startedAt) > tile._minLifeMs)
            tile.restart()
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

        // Lance le programme dès que le widget obtient une taille réelle (cf. _launchWhenSized).
        onWidthChanged: Qt.callLater(tile._launchWhenSized)
        onHeightChanged: Qt.callLater(tile._launchWhenSized)

        enableBold: true
        enableItalic: true
        blinkingCursor: true

        session: QMLTermSession {
            id: session
            onFinished: tile._onFinished()
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
