import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import NoctaliaScratchpad 1.0

// Tuile « scratchpad computationnel » multi-notes. Remplit le contrat tuile (start/focusTerminal/refresh/
// finished/lostFocus + props). Compose : un drawer latéral de notes (créer/ouvrir/supprimer), une barre de
// titre éditable, et l'éditeur C++ (ScratchpadEdit) + l'orchestration qalc.
//
// Stockage : ~/.local/share/noctalia-deck/scratchpad/
//   • notes.json            → { notes:[{id,title}], currentId }
//   • <id>.txt              → contenu (texte logique, sans inlays) de chaque note
// Migration : l'ancien fichier unique scratchpad.txt devient « Note 1 » au premier lancement.
Item {
    id: tile

    // ── Contrat tuile ───────────────────────────────────────────────────────
    property var pluginApi: null            // pour l'i18n (passé par Main)
    property string shellProgram: ""
    property var shellArgs: []
    property bool autoRelaunch: false
    property string fontFamily: "monospace"
    property int fontSize: 11
    property string colorScheme: ""
    readonly property bool liveCapable: false

    signal finished()
    signal lostFocus()

    function start() {
        if (tile._loaded)
            return
        tile._loaded = true
        indexLoadProc.running = true
    }
    function focusTerminal() { editor.forceActiveFocus() }
    function refresh() { editor.forceRepaint() }
    function applySchemeFile(path) { /* no-op : theming via tokens */ }

    function _tr(key, fallback) { return tile.pluginApi ? tile.pluginApi.tr(key) : fallback }

    // ── Stockage multi-notes ──────────────────────────────────────────────────
    readonly property string _baseDir: (Quickshell.env("HOME") || "/tmp") + "/.local/share/noctalia-deck"
    readonly property string _dir: tile._baseDir + "/scratchpad"
    readonly property string _indexPath: tile._dir + "/notes.json"
    readonly property string _oldPath: tile._baseDir + "/scratchpad.txt"   // ancien fichier unique (migration)
    function _contentPath(id) { return tile._dir + "/" + id + ".txt" }

    property bool _loaded: false
    property bool _saveAfterLoad: false
    property var notes: []                  // [{ id, title }]
    property string currentId: ""
    property bool drawerOpen: false

    readonly property string currentTitle: {
        for (var i = 0; i < tile.notes.length; i++)
            if (tile.notes[i].id === tile.currentId)
                return tile.notes[i].title
        return ""
    }
    function _hasNote(id) {
        for (var i = 0; i < tile.notes.length; i++)
            if (tile.notes[i].id === id)
                return true
        return false
    }
    // Quand on change de note, on resynchronise le champ titre (sans casser l'édition en cours).
    onCurrentIdChanged: titleField.text = tile.currentTitle

    // ── I/O notes ─────────────────────────────────────────────────────────────
    function _saveIndex() {
        var data = JSON.stringify({ "notes": tile.notes, "currentId": tile.currentId })
        Quickshell.execDetached(["sh", "-c",
            'd="$(dirname "$1")"; mkdir -p "$d"; printf "%s" "$2" > "$1"', "sh", tile._indexPath, data])
    }
    function _saveContent() {
        if (!tile.currentId)
            return
        Quickshell.execDetached(["sh", "-c",
            'd="$(dirname "$1")"; mkdir -p "$d"; printf "%s" "$2" > "$1"', "sh", tile._contentPath(tile.currentId), editor.text])
    }
    function _loadContent(path, saveAfter) {
        tile._saveAfterLoad = (saveAfter === true)
        contentLoadProc.command = ["sh", "-c", 'cat "$1" 2>/dev/null', "sh", path]
        contentLoadProc.running = true
    }

    Process {
        id: indexLoadProc
        command: ["sh", "-c", 'cat "$1" 2>/dev/null', "sh", tile._indexPath]
        stdout: StdioCollector { id: indexOut }
        onExited: (code, status) => tile._onIndexLoaded(String(indexOut.text))
    }
    Process {
        id: contentLoadProc
        stdout: StdioCollector { id: contentOut }
        onExited: (code, status) => {
            editor.text = String(contentOut.text)   // setText → textChanged → recompute (inlays) + save debounce
            if (tile._saveAfterLoad) {
                tile._saveAfterLoad = false
                tile._saveContent()                  // migration : persiste l'ancien contenu sous le nouvel id
            }
        }
    }

    function _onIndexLoaded(txt) {
        var ok = false
        try {
            var d = JSON.parse(txt)
            if (d && d.notes && d.notes.length > 0) {
                tile.notes = d.notes
                tile.currentId = (d.currentId && tile._hasNote(d.currentId)) ? d.currentId : d.notes[0].id
                ok = true
            }
        } catch (e) {}
        if (ok) {
            _loadContent(tile._contentPath(tile.currentId), false)
        } else {
            // Bootstrap + migration de l'ancien fichier unique.
            tile.notes = [{ "id": "n1", "title": tile._tr("scratchpad.firstNoteTitle", "Note 1") }]
            tile.currentId = "n1"
            _saveIndex()
            _loadContent(tile._oldPath, true)
        }
    }

    function _newNote() {
        saveDebounce.stop(); _saveContent()
        var id = "n" + Date.now()
        var title = tile._tr("scratchpad.noteWord", "Note") + " " + (tile.notes.length + 1)
        var arr = tile.notes.slice(); arr.push({ "id": id, "title": title }); tile.notes = arr
        tile.currentId = id
        _saveIndex()
        editor.text = ""
        _saveContent()
        editor.forceActiveFocus()
    }
    function _openNote(id) {
        tile.drawerOpen = false
        if (id === tile.currentId)
            return
        saveDebounce.stop(); _saveContent()
        tile.currentId = id
        _saveIndex()
        _loadContent(tile._contentPath(id), false)
    }
    function _renameNote(id, title) {
        var t = (title && title.trim().length > 0) ? title : tile._tr("scratchpad.untitled", "Untitled")
        var arr = tile.notes.slice()
        for (var i = 0; i < arr.length; i++)
            if (arr[i].id === id)
                arr[i] = { "id": id, "title": t }
        tile.notes = arr
        _saveIndex()
    }
    function _deleteNote(id) {
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1"', "sh", tile._contentPath(id)])
        var arr = tile.notes.filter(function (n) { return n.id !== id })
        if (arr.length === 0)
            arr = [{ "id": "n" + Date.now(), "title": tile._tr("scratchpad.firstNoteTitle", "Note 1") }]
        tile.notes = arr
        if (tile.currentId === id) {
            tile.currentId = arr[0].id
            _loadContent(tile._contentPath(tile.currentId), false)
        }
        _saveIndex()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Drawer latéral (notes)
        Rectangle {
            id: drawer
            Layout.fillHeight: true
            Layout.preferredWidth: tile.drawerOpen ? Math.round(220 * Style.uiScaleRatio) : 0
            clip: true
            color: Color.mSurfaceVariant
            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginXS
                visible: drawer.width > 10

                RowLayout {
                    Layout.fillWidth: true
                    NText {
                        Layout.fillWidth: true
                        text: tile._tr("scratchpad.notes", "Notes")
                        font.weight: Style.fontWeightBold
                        color: Color.mOnSurface
                    }
                    NIconButton {
                        baseSize: Style.baseWidgetSize * 0.8
                        icon: "plus"
                        tooltipText: tile._tr("scratchpad.newNote", "New note")
                        onClicked: tile._newNote()
                    }
                }
                NDivider { Layout.fillWidth: true }

                ListView {
                    id: notesList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Math.round(2 * Style.uiScaleRatio)
                    model: tile.notes
                    delegate: Rectangle {
                        id: noteRow
                        required property var modelData
                        width: ListView.view ? ListView.view.width : 0
                        height: Math.round(34 * Style.uiScaleRatio)
                        radius: Style.radiusS
                        readonly property bool isCurrent: noteRow.modelData.id === tile.currentId
                        color: isCurrent ? Color.smartAlpha(Color.mPrimary)
                                         : (rowMouse.containsMouse ? Color.mHover : "transparent")

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tile._openNote(noteRow.modelData.id)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.marginS
                            anchors.rightMargin: Style.marginXS
                            spacing: Style.marginXS
                            NText {
                                Layout.fillWidth: true
                                text: noteRow.modelData.title
                                elide: Text.ElideRight
                                color: noteRow.isCurrent ? Color.mPrimary : Color.mOnSurface
                            }
                            NIconButton {
                                baseSize: Style.baseWidgetSize * 0.7
                                icon: "trash"
                                visible: rowMouse.containsMouse || noteRow.isCurrent
                                tooltipText: tile._tr("scratchpad.deleteNote", "Delete note")
                                colorFg: Color.mError
                                colorFgHover: Color.mError
                                onClicked: tile._deleteNote(noteRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Colonne principale : barre de titre + éditeur
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Style.marginXS
                spacing: Style.marginXS
                NIconButton {
                    baseSize: Style.baseWidgetSize * 0.85
                    icon: "menu-2"
                    tooltipText: tile._tr("scratchpad.toggleDrawer", "Notes")
                    onClicked: tile.drawerOpen = !tile.drawerOpen
                }
                NTextInput {
                    id: titleField
                    Layout.fillWidth: true
                    label: ""
                    showClearButton: false
                    fontSize: Style.fontSizeL
                    placeholderText: tile._tr("scratchpad.titlePlaceholder", "Note title")
                    onEditingFinished: tile._renameNote(tile.currentId, titleField.text)
                    onAccepted: tile._renameNote(tile.currentId, titleField.text)
                }
            }

            ScratchpadEdit {
                id: editor
                Layout.fillWidth: true
                Layout.fillHeight: true

                fontFamily: tile.fontFamily
                fontSize: tile.fontSize

                // Coloration distincte par rôle (lisibilité), bindée sur la palette Noctalia.
                bgColor: Color.mSurface
                textColor: Color.mOnSurface
                dimColor: Color.mOnSurfaceVariant
                accentColor: Color.mPrimary            // RÉSULTAT (inlay) + gras
                numberColor: Color.mTertiary           // chiffres / devises / variables
                operatorColor: Color.mOnSurfaceVariant // opérateurs (atténués)
                unitColor: Color.mSecondary            // unités / mots-clés
            }
        }
    }

    // ── Recalcul qalc + sauvegarde (debounce) ──────────────────────────────────
    Timer { id: recomputeDebounce; interval: 220; onTriggered: tile._recompute() }
    Timer { id: saveDebounce; interval: 1000; onTriggered: tile._saveContent() }

    Connections {
        target: editor
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
        function onTextChanged() {
            recomputeDebounce.restart()
            saveDebounce.restart()
        }
    }

    // ── Moteur qalc ─────────────────────────────────────────────────────────────
    property bool _qalcDirty: false
    property var _pendingSpans: []
    property string _pendingInput: ""

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
        if (qalcProc.running) {
            tile._qalcDirty = true
            return
        }
        tile._runQalc()
    }
    function _runQalc() {
        if (tile._pendingInput.length === 0) {
            editor.setInlays([])
            return
        }
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
    function _applyQalc(raw, spans) {
        var clean = raw.replace(/\x1b\[[0-9;]*m/g, "")
        var lines = clean.split("\n")
        var results = []
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("> ") === 0) {
                for (var j = i + 1; j < lines.length; j++) {
                    if (lines[j].trim().length > 0) { results.push(lines[j].trim()); break }
                }
            }
        }
        var inlays = []
        for (var k = 0; k < spans.length && k < results.length; k++) {
            var res = results[k]
            if (res.length >= 2 && res.charAt(0) === '"' && res.charAt(res.length - 1) === '"')
                res = res.substring(1, res.length - 1)
            if (tile._isBadResult(res, tile._massage(spans[k].text)))
                continue
            res = res.replace(/(\.\d*?)0+(?=\D|$)/g, "$1").replace(/\.(?=\D|$)/g, "")
            inlays.push({ "block": spans[k].block, "col": spans[k].endCol, "text": " = " + res })
        }
        editor.setInlays(inlays)
    }
    function _isBadResult(res, input) {
        if (!res || res.length === 0)
            return true
        if (res.indexOf("·") >= 0)
            return true
        if (res.toLowerCase().indexOf("error") >= 0)
            return true
        var nr = res.replace(/\s+/g, ""), ni = input.replace(/\s+/g, "")
        if (nr === ni)
            return true
        return false
    }
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

    // ── Coller (wl-paste) ───────────────────────────────────────────────────────
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
