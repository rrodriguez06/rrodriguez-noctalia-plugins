import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI

// Couche logique + host flottant. Possède son PROPRE PanelWindow (jamais détruit, juste masqué)
// → la session shell de la tuile survit aux toggles, sans tmux. Le widget de barre / le centre de
// contrôle / le keybind IPC ne font que basculer la visibilité de cette fenêtre.
Item {
    id: root
    property var pluginApi: null

    // ── Réglages (avec repli sur les défauts du manifeste) ───────────────────
    readonly property var s: pluginApi?.pluginSettings ?? null
    readonly property int cfgWidth: (s && s.width) ? s.width : 900
    readonly property int cfgHeight: (s && s.height) ? s.height : 480
    readonly property int cfgTopMargin: (s && s.topMargin !== undefined) ? s.topMargin : 40
    readonly property string cfgThemeMode: (s && s.themeMode) ? s.themeMode : "noctalia"
    readonly property string cfgScheme: (s && s.schemeName) ? s.schemeName : "Solarized"
    readonly property string cfgFontFamily: (s && s.fontFamily && s.fontFamily.length > 0) ? s.fontFamily : "monospace"
    readonly property int cfgFontSize: (s && s.fontSize) ? s.fontSize : 11
    readonly property string cfgFocusMode: (s && s.keyboardFocusMode) ? s.keyboardFocusMode : "ondemand"
    readonly property string cfgShell: (s && s.shellProgram) ? s.shellProgram : ""
    readonly property bool cfgCloseOnFocusLost: (s && s.closeOnFocusLost !== undefined) ? s.closeOnFocusLost : false
    readonly property bool cfgShowToasts: (s && s.showToasts !== undefined) ? s.showToasts : true

    // ── Résolution du thème terminal ─────────────────────────────────────────
    // En mode "scheme" : schéma fixe choisi par l'utilisateur.
    // En mode "noctalia" : suit le clair/sombre du thème global (luminance de mSurface).
    // (Le match exact des couleurs nécessite COLORSCHEMES_DIR — cf. README, évolution future.)
    function _isDarkTheme() {
        var c = Color.mSurface
        var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return lum < 0.5
    }
    readonly property string effectiveScheme: {
        if (root.cfgThemeMode === "scheme")
            return root.cfgScheme
        return root._isDarkTheme() ? "Falcon" : "SolarizedLight"
    }

    // ── État exposé (barre / centre de contrôle) ─────────────────────────────
    property bool deckVisible: false
    readonly property var tile: tileLoader.item
    readonly property bool depAvailable: tileLoader.status !== Loader.Error
    readonly property bool tileAlive: tileLoader.item ? tileLoader.item.alive : false

    // ── Actions publiques ────────────────────────────────────────────────────
    function show() {
        if (root.pluginApi)
            root.pluginApi.withCurrentScreen(function (scr) {
                deckWindow.screen = scr
                root.deckVisible = true
            })
        else
            root.deckVisible = true
    }
    function hide() { root.deckVisible = false }
    function toggle() { if (root.deckVisible) root.hide(); else root.show() }
    function newSession() { if (tileLoader.item) tileLoader.item.restart() }

    Component.onCompleted: Qt.callLater(function () {
        if (tileLoader.status === Loader.Error)
            ToastService.showError(root.pluginApi ? root.pluginApi.tr("error.missingDep")
                                                  : "Noctalia Deck: qmltermwidget manquant (pacman -S qmltermwidget)")
    })

    // ── Le host flottant : un PanelWindow possédé par le plugin ──────────────
    PanelWindow {
        id: deckWindow
        visible: root.deckVisible
        color: "transparent"

        // Ancrage HAUT SEUL → centré horizontalement à la largeur demandée.
        anchors { top: true }
        margins { top: root.cfgTopMargin }
        implicitWidth: root.cfgWidth
        implicitHeight: root.cfgHeight

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "noctalia-deck"
        WlrLayershell.keyboardFocus: root.deckVisible
            ? (root.cfgFocusMode === "exclusive" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
            : WlrKeyboardFocus.None

        onVisibleChanged: if (visible && tileLoader.item) Qt.callLater(tileLoader.item.focusTerminal)

        Rectangle {
            id: chrome
            anchors.fill: parent
            color: Color.mSurface
            radius: Style.radiusL
            border.color: Color.mOutline
            border.width: Style.borderS

            // Tuile chargée dynamiquement : isole l'échec d'import QMLTermWidget
            // (dépendance absente → status Error, le reste du plugin survit).
            Loader {
                id: tileLoader
                anchors.fill: parent
                anchors.margins: Style.marginS
                source: "TerminalTile.qml"
                active: true
                onLoaded: {
                    item.shellProgram = root.cfgShell
                    item.fontFamily = Qt.binding(function () { return root.cfgFontFamily })
                    item.fontSize = Qt.binding(function () { return root.cfgFontSize })
                    item.colorScheme = Qt.binding(function () { return root.effectiveScheme })
                    item.start()
                }
            }

            // Message si la dépendance manque.
            Text {
                anchors.centerIn: parent
                visible: !root.depAvailable
                width: parent.width - Style.marginXL * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Color.mOnSurface
                text: root.pluginApi ? root.pluginApi.tr("error.missingDepLong")
                                     : "qmltermwidget est requis :\n  pacman -S qmltermwidget\npuis redémarrez le shell."
            }

            Connections {
                target: tileLoader.item
                ignoreUnknownSignals: true
                function onLostFocus() {
                    if (root.cfgCloseOnFocusLost && root.deckVisible)
                        root.hide()
                }
                function onFinished() {
                    if (root.cfgShowToasts)
                        ToastService.showNotice(root.pluginApi ? root.pluginApi.tr("toast.sessionEnded")
                                                               : "Session terminée")
                }
            }
        }
    }

    // ── IPC : qs -c noctalia-shell ipc call plugin:noctalia-deck <fn> ─────────
    IpcHandler {
        target: "plugin:noctalia-deck"
        function toggle() { root.toggle() }
        function show() { root.show() }
        function hide() { root.hide() }
        function newSession() { root.newSession() }
    }
}
