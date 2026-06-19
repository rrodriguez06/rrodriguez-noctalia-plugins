import QtQuick
import qs.Commons
import qs.Widgets

// Tuile de REPLI affichée à la place d'une tuile dont le module/composant n'a pas pu se charger
// (ex. le module C++ NoctaliaScratchpad n'est pas installé). Elle remplit le contrat tuile en no-op,
// pour qu'un module manquant casse UNIQUEMENT son onglet — le shell et le moniteur restent fonctionnels.
Item {
    id: tile
    property var pluginApi: null

    // ── Contrat tuile (no-op) ───────────────────────────────────────────────
    property string shellProgram: ""
    property var shellArgs: []
    property bool autoRelaunch: false
    property string fontFamily: "monospace"
    property int fontSize: 11
    property string colorScheme: ""
    readonly property bool liveCapable: false

    signal finished()
    signal lostFocus()

    function start() {}
    function focusTerminal() {}
    function refresh() {}
    function applySchemeFile(path) {}

    NText {
        anchors.centerIn: parent
        width: parent.width - Style.marginXL * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Color.mOnSurface
        text: tile.pluginApi ? tile.pluginApi.tr("error.missingScratchpadModule")
                             : "Module éditeur 'NoctaliaScratchpad' manquant.\n\n  cd noctalia-scratchpad && makepkg -si\n\npuis redémarrez le shell."
    }
}
