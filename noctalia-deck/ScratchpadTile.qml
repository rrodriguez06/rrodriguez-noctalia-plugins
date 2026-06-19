import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import NoctaliaScratchpad 1.0

// Tuile « scratchpad computationnel ». Comme TerminalTile, c'est un Item possédé par Main et re-parenté
// visuellement par le Panel ; elle remplit le MÊME contrat (start/focusTerminal/refresh/finished/lostFocus
// + props fontFamily/fontSize/colorScheme/width/height/autoRelaunch + liveCapable/applySchemeFile).
//
// Rôle : wrapper autour de l'éditeur C++ (ScratchpadEdit, thémé via Color.*) + orchestration du moteur
// qalc (libqalculate) et persistance disque.
//   • L'éditeur détecte tout seul les spans calculables (detectSpans) et expose le texte logique (sans inlays).
//   • À chaque frappe (debounce), on envoie les spans à qalc et on repose les inlays (setInlays).
//   • Le contenu (texte logique) est sauvegardé/chargé dans ~/.local/share/noctalia-deck/scratchpad.txt.
Item {
    id: tile

    // ── Contrat tuile ───────────────────────────────────────────────────────
    property string shellProgram: ""        // ignoré
    property var shellArgs: []               // ignoré
    property bool autoRelaunch: false
    property string fontFamily: "monospace"
    property int fontSize: 11
    property string colorScheme: ""          // ignoré : theming par tokens Color.*
    readonly property bool liveCapable: false

    signal finished()
    signal lostFocus()

    function start() {
        if (tile._loaded)
            return
        tile._loaded = true
        loadProc.running = true
    }
    function focusTerminal() { editor.forceActiveFocus() }
    function refresh() { editor.forceRepaint() }
    function applySchemeFile(path) { /* no-op : theming via tokens */ }

    // ── État interne ────────────────────────────────────────────────────────
    readonly property string _savePath: (Quickshell.env("HOME") || "/tmp") + "/.local/share/noctalia-deck/scratchpad.txt"
    property bool _loaded: false
    property bool _qalcDirty: false          // un recompute est arrivé pendant que qalc tournait
    property var _pendingSpans: []           // spans de la requête qalc en cours
    property string _pendingInput: ""        // entrée stdin de la requête qalc en cours

    ScratchpadEdit {
        id: editor
        anchors.fill: parent

        fontFamily: tile.fontFamily
        fontSize: tile.fontSize

        // Theming live : bindings directs sur la palette Noctalia → repaint au changement de wallpaper.
        bgColor: Color.mSurface
        textColor: Color.mOnSurface
        dimColor: Color.mOnSurfaceVariant
        // Coloration distincte par rôle (lisibilité) :
        accentColor: Color.mPrimary            // RÉSULTAT (inlay) — la couleur la plus distincte + gras
        numberColor: Color.mTertiary           // chiffres / devises / variables
        operatorColor: Color.mOnSurfaceVariant // opérateurs (atténués, ce sont des « liants »)
        unitColor: Color.mSecondary            // unités / mots-clés (to, en, today…)
    }

    // ── Recalcul (debounce) ───────────────────────────────────────────────────
    Timer { id: recomputeDebounce; interval: 220; onTriggered: tile._recompute() }
    Timer { id: saveDebounce; interval: 1000; onTriggered: tile._save() }

    Connections {
        target: editor
        // Presse-papier via wl-clipboard (QClipboard inerte en layer-shell).
        function onCopyRequested(text) {
            if (!text || text.length === 0)
                return
            var esc = text.replace(/'/g, "'\\''")
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + esc + "' | wl-copy"])
        }
        function onPasteRequested() {
            if (!pasteProc.running)
                pasteProc.running = true
        }
        // Toute édition → recalcul des inlays + sauvegarde, tous deux débouncés.
        function onTextChanged() {
            recomputeDebounce.restart()
            saveDebounce.restart()
        }
    }

    function _recompute() {
        var spans = editor.detectSpans()
        tile._pendingSpans = spans
        tile._pendingInput = ""
        if (spans.length > 0) {
            var lines = []
            for (var i = 0; i < spans.length; i++)
                lines.push(tile._massage(spans[i].text))
            tile._pendingInput = lines.join("\n") + "\n"
        }
        // Sérialise les appels qalc : si un est en cours, on marque « dirty » et on relancera à sa fin.
        if (qalcProc.running) {
            tile._qalcDirty = true
            return
        }
        tile._runQalc()
    }

    function _runQalc() {
        if (tile._pendingInput.length === 0) {
            editor.setInlays([])   // plus aucun span → on retire les inlays
            return
        }
        // Invocation ÉPINGLÉE : locale C.UTF-8 (point décimal + €), couleur off, pas d'auto-conversion de
        // devises (sinon « 2$+4$ » serait converti en €). L'entrée (les spans, un par ligne) passe en $1.
        qalcProc.command = ["sh", "-c",
            'printf "%s" "$1" | LANG=C.UTF-8 LC_ALL=C.UTF-8 qalc -t -set "color 0" -set "currency_conversion 0" 2>/dev/null',
            "sh", tile._pendingInput]
        qalcProc.running = true
    }

    Process {
        id: qalcProc
        stdout: StdioCollector { id: qalcOut }
        onExited: (code, status) => {
            tile._applyQalc(String(qalcOut.text), tile._pendingSpans)
            if (tile._qalcDirty) {
                tile._qalcDirty = false
                tile._runQalc()
            }
        }
    }

    // Parse la sortie batch de qalc et repose les inlays. Format (après strip ANSI) :
    //   > <echo entrée>\n   \n   <résultat (indenté 2 espaces)>\n   \n   … (répété), terminé par « > ».
    function _applyQalc(raw, spans) {
        var clean = raw.replace(/\x1b\[[0-9;]*m/g, "")   // strip ANSI (le $ ressort en italique même color 0)
        var lines = clean.split("\n")
        var results = []
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("> ") === 0) {           // marqueur d'écho → le résultat est la ligne non-vide suivante
                for (var j = i + 1; j < lines.length; j++) {
                    if (lines[j].trim().length > 0) { results.push(lines[j].trim()); break }
                }
            }
        }
        var inlays = []
        for (var k = 0; k < spans.length && k < results.length; k++) {
            var res = results[k]
            if (res.length >= 2 && res.charAt(0) === '"' && res.charAt(res.length - 1) === '"')
                res = res.substring(1, res.length - 1)     // dates renvoyées entre guillemets
            if (tile._isBadResult(res, tile._massage(spans[k].text)))
                continue
            // Nettoie les zéros traînants ($1747.200000 → $1747.2, 100.00 → 100) ; n'altère ni dates ni entiers.
            res = res.replace(/(\.\d*?)0+(?=\D|$)/g, "$1").replace(/\.(?=\D|$)/g, "")
            inlays.push({ "block": spans[k].block, "col": spans[k].endCol, "text": " = " + res })
        }
        editor.setInlays(inlays)
    }

    // Gate secondaire (filet) : rejette les résultats vides, la « salade d'unités » (middot ·), les erreurs,
    // et les non-évalués (résultat == entrée, ex. « 1/0 » → « 1 / 0 »).
    function _isBadResult(res, input) {
        if (!res || res.length === 0)
            return true
        if (res.indexOf("·") >= 0)        // · → prose interprétée comme unités
            return true
        if (res.toLowerCase().indexOf("error") >= 0)
            return true
        var nr = res.replace(/\s+/g, ""), ni = input.replace(/\s+/g, "")
        if (nr === ni)
            return true
        return false
    }

    // Traduit quelques mots FR vers ce que qalc comprend (EN), AVANT envoi (l'inlay affiche le résultat qalc).
    function _massage(text) {
        return text
            .replace(/\ben\b/gi, "to")
            .replace(/\binto\b/gi, "to")
            .replace(/aujourd['’]?hui/gi, "today")
            .replace(/\bdemain\b/gi, "tomorrow")
            .replace(/\bhier\b/gi, "yesterday")
            .replace(/\bsemaines?\b/gi, "weeks")
            .replace(/\bjours?\b/gi, "days")
            .replace(/\bmois\b/gi, "months")
            .replace(/\b(ans?|années?)\b/gi, "years")
            .replace(/\bheures?\b/gi, "hours")
            .replace(/\bminutes?\b/gi, "minutes")
            .replace(/\bmaintenant\b/gi, "now")
    }

    // ── Persistance ───────────────────────────────────────────────────────────
    Process {
        id: loadProc
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null", "sh", tile._savePath]
        stdout: StdioCollector { id: loadOut }
        onExited: (code, status) => {
            editor.text = String(loadOut.text)   // setText → textChanged → recompute (inlays) + save debounce
        }
    }
    function _save() {
        // Écrit le texte LOGIQUE (sans inlays). Argv évite tout échappement.
        Quickshell.execDetached(["sh", "-c",
            'd="$(dirname "$1")"; mkdir -p "$d"; printf "%s" "$2" > "$1"',
            "sh", tile._savePath, editor.text])
    }

    // Coller : lit wl-paste puis insère dans l'éditeur.
    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector { id: pasteOut }
        onExited: (code, status) => {
            if (code === 0) {
                var t = String(pasteOut.text)
                if (t.length > 0)
                    editor.insertPlainText(t)
            }
        }
    }
}
