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
    // Taille EXPLICITE et stable, fixée par Main (deckContentW/H), à (0,0) du parent courant. On NE
    // remplit PAS le parent : ainsi la tuile ne suit pas l'animation d'ouverture du panel (termClip la
    // clippe pendant la révélation) → le terminal ne se redimensionne jamais → prompt en bas préservé.

    // --- entrées (poussées par Main) ---
    property string shellProgram: ""        // vide => $SHELL
    property var shellArgs: []
    property string cwd: ""
    property var envv: []
    property string colorScheme: "Solarized"
    property string fontFamily: "monospace"
    property int fontSize: 11

    // Onglet « service » : à relancer s'il se termine (ex. on quitte btop avec « q »). La décision de
    // relance est prise par Main (sur le signal `finished`), qui RECRÉE la tuile (session fraîche) —
    // relancer en place ne marche pas sur une session déjà terminée. `_startedAt`/`_minLifeMs` servent
    // à la garde anti-spin côté Main (ne pas reboucler si la commande échoue immédiatement).
    property bool autoRelaunch: false
    readonly property int _minLifeMs: 1500
    property double _startedAt: 0
    property bool _pendingStart: false

    // --- état ---
    property bool started: false
    readonly property bool alive: tile.started && session.hasActiveProcess
    readonly property string foregroundName: session.foregroundProcessName

    // --- signaux ---
    signal finished()            // Main y branche l'éventuelle relance (recréation) des onglets service
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
        // On « arme » seulement : launchTimer (re-déclenché à chaque changement de taille) lance le PTY
        // une fois la taille STABILISÉE → jamais à la taille transitoire du re-parentage (holder) → pas
        // d'artefact de redimensionnement.
        tile._pendingStart = true
        launchTimer.restart()
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

    function focusTerminal() { term.forceActiveFocus() }
    function copy() { term.copyClipboard() }
    function paste() { term.pasteClipboard() }

    // Force le re-dessin : après le re-parentage (changement de fenêtre), QMLTermWidget ne se repeint
    // pas tant que rien ne l'invalide (d'où l'écran « vide » jusqu'à un scroll). updateImage() re-récupère
    // l'image de l'écran du terminal et redessine — slot de base, dispo sans le fork.
    // Force un re-dessin COMPLET. updateImage() ne repeint que les cellules « sales » → après le
    // re-parentage (changement de fenêtre), seule une portion est redessinée (d'où l'affichage partiel
    // jusqu'à un scroll). On mime donc un scroll (haut puis bas, position nette inchangée) : ça rend
    // toutes les cellules sales → repaint complet. C'est exactement ce que fait le scroll manuel.
    function refresh() {
        term.simulateWheel(10, 10, 0, 0, Qt.point(0, 120))    // haut
        term.simulateWheel(10, 10, 0, 0, Qt.point(0, -120))   // bas (retour)
        if (typeof term.updateImage === "function") term.updateImage()
    }


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

        // Tant qu'un lancement est en attente, re-déclenche le timer à chaque changement de taille :
        // on ne démarre le programme qu'une fois la taille stabilisée (cf. launchTimer / _launchWhenSized).
        // [DIAG 0.3.8] log de tout resize du terminal (pour traquer l'artefact prompt-en-haut).
        onWidthChanged: if (tile._pendingStart) launchTimer.restart()
        onHeightChanged: if (tile._pendingStart) launchTimer.restart()

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

    // Démarre le programme une fois la taille du terminal stabilisée (anti-artefact de resize) et, en
    // cas de relance, après la fin propre de la session précédente. Voir start()/restart()/_launchWhenSized.
    Timer { id: launchTimer; interval: 60; onTriggered: tile._launchWhenSized() }

    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: term.copyClipboard() }
    Shortcut { sequence: "Ctrl+Shift+V"; onActivated: term.pasteClipboard() }
}
