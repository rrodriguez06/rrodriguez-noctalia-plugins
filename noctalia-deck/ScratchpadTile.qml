import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import NoctaliaScratchpad 1.0

// Tuile « scratchpad computationnel ». Comme TerminalTile, c'est un Item possédé par Main et re-parenté
// visuellement par le Panel ; elle remplit le MÊME contrat (start/focusTerminal/refresh/finished/lostFocus
// + props fontFamily/fontSize/colorScheme/width/height/autoRelaunch + liveCapable/applySchemeFile) pour que
// Main/Panel la traitent à l'identique.
//
// STAGE 0 : wrapper minimal autour de l'éditeur C++ (ScratchpadEdit), thémé via les tokens Color.* (donc
// PAS de fichier .colorscheme : applySchemeFile est un no-op et liveCapable=false). Le moteur qalc, la
// persistance et l'API setInlays() complète arrivent aux stages suivants ; ici l'éditeur affiche son texte
// de démo + un inlay codé en dur pour valider la plateforme (focus/IME/re-parentage).
Item {
    id: tile

    // ── Contrat tuile (entrées poussées par Main) ───────────────────────────
    property string shellProgram: ""        // ignoré (pas de PTY)
    property var shellArgs: []               // ignoré
    property bool autoRelaunch: false        // toujours false : pas de relance
    property string fontFamily: "monospace"
    property int fontSize: 11
    property string colorScheme: ""          // ignoré : theming par tokens Color.*

    // Theming live : assuré par les bindings Color.* ci-dessous, pas par un .colorscheme.
    readonly property bool liveCapable: false

    // ── Signaux du contrat (jamais émis ici) ────────────────────────────────
    signal finished()
    signal lostFocus()

    // ── API du contrat ──────────────────────────────────────────────────────
    function start() { /* rien à démarrer (persistance au Stage 3) */ }
    function focusTerminal() { editor.forceActiveFocus() }
    function refresh() { editor.forceRepaint() }   // repaint après re-parentage du Panel
    function applySchemeFile(path) { /* no-op : theming via tokens */ }

    ScratchpadEdit {
        id: editor
        anchors.fill: parent

        fontFamily: tile.fontFamily
        fontSize: tile.fontSize

        // Theming live : bindings directs sur la palette Noctalia → repaint au changement de wallpaper.
        bgColor: Color.mSurface
        textColor: Color.mOnSurface
        dimColor: Color.mOnSurfaceVariant
        accentColor: Color.mPrimary
    }

    // Presse-papier via wl-clipboard : QClipboard est inerte en surface layer-shell Quickshell
    // (même contrainte que TerminalTile). copyRequested porte le texte sélectionné (fantômes exclus).
    Connections {
        target: editor
        function onCopyRequested(text) {
            if (!text || text.length === 0)
                return
            var esc = text.replace(/'/g, "'\\''")   // échappement single-quote pour sh
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + esc + "' | wl-copy"])
        }
        function onPasteRequested() {
            if (!pasteProc.running)
                pasteProc.running = true
        }
    }

    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {}
        onExited: (code, status) => {
            if (code === 0) {
                var t = String(pasteProc.stdout.text)
                if (t.length > 0)
                    editor.insertPlainText(t)
            }
        }
    }
}
