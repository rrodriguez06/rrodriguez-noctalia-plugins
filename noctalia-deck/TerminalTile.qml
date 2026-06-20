import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
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
    property string scrollBottomTooltip: ""   // libellé du bouton « revenir en bas » (fourni par Main, traduit)

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

    // Revenir tout en bas du scrollback (reprend le suivi de la sortie). QMLTermWidget n'expose pas
    // scrollToEnd() au QML → on simule une molette « vers le bas » d'amplitude suffisante pour couvrir
    // tout l'historique ; ScrollBar::setValue() clampe (qBound) au maximum, donc on atterrit pile en bas.
    function scrollToBottom() {
        var range = term.scrollbarMaximum - term.scrollbarMinimum
        if (range <= 0)
            return
        term.simulateWheel(Math.round(term.width / 2), Math.round(term.height / 2), 0, 0,
                           Qt.point(0, -120 * (range + 2)))
    }
    // Copy/paste sont pilotés par les signaux du fork (copyRequested/pasteRequested → Connections plus
    // bas), routés vers wl-copy/wl-paste car QClipboard est inerte dans une surface layer-shell Quickshell.
    function paste() { if (!pasteProc.running) pasteProc.running = true }

    // Force le re-dessin : après le re-parentage (changement de fenêtre), QMLTermWidget ne se repeint
    // pas tant que rien ne l'invalide (d'où l'écran « vide » jusqu'à un scroll). updateImage() re-récupère
    // l'image de l'écran du terminal et redessine — slot de base, dispo sans le fork.
    // Force un re-dessin COMPLET après le re-parentage (changement de fenêtre) : sinon updateImage()
    // ne repeint que les cellules « sales » → affichage partiel jusqu'à un scroll. forceRedraw() (fork)
    // fait un update() complet, sans effet de bord et même quand ce n'est pas scrollable. Fallback
    // updateImage() sur qmltermwidget stock (repaint partiel, mais sans injecter de séquences clavier).
    function refresh() {
        if (typeof term.forceRedraw === "function")
            term.forceRedraw()
        else if (typeof term.updateImage === "function")
            term.updateImage()
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

        // Bouton « revenir en bas » : apparaît dès qu'on remonte dans le scrollback (shell ET logs) ;
        // clic → bas, ce qui reprend le suivi de la sortie. Caché en bas / en écran alternatif (btop).
        NIconButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: Style.marginM
            anchors.bottomMargin: Style.marginM
            visible: term.scrollbarMaximum > 0 && term.scrollbarCurrentValue < term.scrollbarMaximum
            icon: "chevron-down"
            tooltipText: tile.scrollBottomTooltip
            onClicked: tile.scrollToBottom()
        }
    }

    // Démarre le programme une fois la taille du terminal stabilisée (anti-artefact de resize) et, en
    // cas de relance, après la fin propre de la session précédente. Voir start()/restart()/_launchWhenSized.
    Timer { id: launchTimer; interval: 60; onTriggered: tile._launchWhenSized() }

    // Copy/paste via wl-clipboard. Le fork émet copyRequested/pasteRequested sur Ctrl+Shift+C/V
    // (QClipboard est inerte dans une surface layer-shell Quickshell, tout comme dans Noctalia qui
    // passe lui aussi par wl-copy/wl-paste). copyRequested porte la sélection courante du terminal.
    Connections {
        target: term
        function onCopyRequested(text) {
            if (!text || text.length === 0)
                return
            // échappement single-quote pour sh : ' → '\'' (cf. ClipboardService.pasteText de Noctalia)
            var esc = text.replace(/'/g, "'\\''")
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + esc + "' | wl-copy"])
        }
        function onPasteRequested() { tile.paste() }
    }

    // Lit le presse-papier Wayland et l'injecte dans le PTY comme une saisie (session.sendText).
    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {}
        onExited: (code, status) => {
            if (code === 0) {
                var t = String(pasteProc.stdout.text)
                if (t.length > 0)
                    session.sendText(t)
            }
        }
    }
}
