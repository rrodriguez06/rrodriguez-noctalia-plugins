import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Couche logique non-visuelle : modèle des layouts + appels au CLI `hypr-layout` + IPC.
Item {
    id: root
    property var pluginApi: null

    // Script EMBARQUÉ dans le plugin (autonome) — appelé via python3, sans dépendance PATH.
    readonly property string script: Qt.resolvedUrl("scripts/hypr-layout").toString().replace("file://", "")
    function argv(extra) { return ["python3", root.script].concat(extra) }

    // Modèle consommé par la NListView du Panel (résumé par layout).
    property ListModel layoutsModel: ListModel {}
    // Détail par layout : { name: { windows: [...], summary: {...} } } — pour le dépliage.
    property var layoutsDetail: ({})
    // Surcharges classe→commande (commands.json), pour l'éditeur des settings.
    property ListModel overridesModel: ListModel {}

    function _showToasts() { return root.pluginApi?.pluginSettings?.showToasts ?? true }

    // --- info (capture JSON détaillé) ---
    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                var detail = {}
                try {
                    var arr = JSON.parse(this.text || "[]")
                } catch (e) {
                    Logger.w("HyprLayout", "info parse error: " + e)
                    return
                }
                root.layoutsModel.clear()
                for (var i = 0; i < arr.length; i++) {
                    var L = arr[i]
                    var s = L.summary || {}
                    root.layoutsModel.append({
                        "name": L.name,
                        "windowCount": s.windows || 0,
                        "workspaces": s.workspaces || 0,
                        "monitors": s.monitors || 0
                    })
                    detail[L.name] = { "windows": L.windows || [], "summary": s,
                                       "trees": L.trees || ({}), "region": L.region || ({}),
                                       "version": L.version || 1 }
                }
                root.layoutsDetail = detail
            }
        }
        onExited: code => { if (code !== 0) Logger.w("HyprLayout", "info exited " + code) }
    }

    function refresh() {
        infoProc.command = root.argv(["info"])
        infoProc.running = true
    }

    // --- géométrie des écrans live (pour l'éditeur visuel) ---
    property var monitorsGeometry: []
    Process {
        id: monitorsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitorsGeometry = JSON.parse(this.text || "[]")
                } catch (e) {
                    Logger.w("HyprLayout", "monitors parse error: " + e)
                }
            }
        }
    }

    function refreshMonitors() {
        monitorsProc.command = root.argv(["monitors"])
        monitorsProc.running = true
    }

    // --- binds workspace→écran (pour l'éditeur : numérotation des ws ajoutés) ---
    property var workspaceRules: ({})
    Process {
        id: wsRulesProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.workspaceRules = JSON.parse(this.text || "{}")
                } catch (e) {
                    Logger.w("HyprLayout", "ws-rules parse error: " + e)
                }
            }
        }
    }

    function refreshWorkspaceRules() {
        wsRulesProc.command = root.argv(["ws-rules"])
        wsRulesProc.running = true
    }

    // --- options de lancement par app (profils/dossiers/cwd) pour le menu contextuel de l'éditeur ---
    // Descripteur { kind, label, items:[{label,sub,cmd}], base, flag } émis par signal à l'éditeur.
    signal appOptionsReady(string cls, var data)
    property string _appOptPending: ""
    Process {
        id: appOptProc
        stdout: StdioCollector {
            onStreamFinished: {
                var data = { "kind": "none" }
                try {
                    data = JSON.parse(this.text || "{}")
                } catch (e) {
                    Logger.w("HyprLayout", "app-options parse error: " + e)
                }
                root.appOptionsReady(root._appOptPending, data)
            }
        }
    }

    function requestAppOptions(cls) {
        var c = ("" + (cls || "")).toLowerCase()
        if (c.length === 0)
            return
        root._appOptPending = c
        appOptProc.command = root.argv(["app-options", c])
        appOptProc.running = true
    }

    // Re-list peu après une action mutante (les ecritures JSON sont asynchrones).
    Timer { id: refreshTimer; interval: 300; onTriggered: root.refresh() }

    // --- surcharges classe→commande ---
    Process {
        id: overridesProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.overridesModel.clear()
                try {
                    var map = JSON.parse(this.text || "{}")
                } catch (e) {
                    Logger.w("HyprLayout", "cmd-list parse error: " + e)
                    return
                }
                var keys = Object.keys(map).sort()
                for (var i = 0; i < keys.length; i++)
                    root.overridesModel.append({ "cls": keys[i], "command": map[keys[i]] })
            }
        }
    }

    function refreshOverrides() {
        overridesProc.command = root.argv(["cmd-list"])
        overridesProc.running = true
    }

    function setOverride(cls, command) {
        var c = (cls || "").trim()
        var cmd = (command || "").trim()
        if (c.length === 0 || cmd.length === 0)
            return
        Quickshell.execDetached(root.argv(["cmd-set", c, cmd]))
        overridesRefreshTimer.restart()
    }

    function unsetOverride(cls) {
        if (!cls)
            return
        Quickshell.execDetached(root.argv(["cmd-unset", cls]))
        overridesRefreshTimer.restart()
    }

    Timer { id: overridesRefreshTimer; interval: 300; onTriggered: root.refreshOverrides() }

    // --- exécution avec retour toast (capture stdout/stderr) ---
    Component {
        id: actionComp
        Process {
            property string fallbackMsg: ""
            stdout: StdioCollector { id: outCol }
            stderr: StdioCollector { id: errCol }
            onExited: code => {
                var out = (outCol.text || "").trim()
                var err = (errCol.text || "").trim()
                if (code === 0)
                    ToastService.showNotice(out || fallbackMsg)
                else
                    ToastService.showError(err || out || ("hypr-layout: code " + code))
                destroy()
            }
        }
    }

    // Lance une action : avec toast (capture) si activé, sinon détaché (fire-and-forget).
    function dispatch(args, busyMsg, fallbackMsg) {
        if (root._showToasts()) {
            if (busyMsg)
                ToastService.showNotice(busyMsg)
            var p = actionComp.createObject(root, { command: root.argv(args), fallbackMsg: fallbackMsg || "" })
            if (p)
                p.running = true
            else
                Quickshell.execDetached(root.argv(args))
        } else {
            Quickshell.execDetached(root.argv(args))
        }
    }

    // --- actions ---
    // mode : "add" (défaut) | "replace" | "merge"
    function loadLayout(name, mode) {
        if (!name)
            return
        const extra = ["load", name]
        if (mode === "replace")
            extra.push("--replace")
        else if (mode === "merge")
            extra.push("--merge")
        root.dispatch(extra, "Chargement de « " + name + " »…", "✓ Layout chargé")
    }

    function saveLayout(name) {
        const n = (name || "").trim()
        if (n.length === 0)
            return
        root.dispatch(["save", n], "", "✓ Layout enregistré")
        refreshTimer.restart()
    }

    // Réécrit un layout depuis l'éditeur visuel. Payload v2 = objet {windows, trees, region}
    // (arbre dwindle autoritaire) ; une liste nue reste acceptée par le CLI (compat).
    function saveEditedLayout(name, payload) {
        const n = (name || "").trim()
        if (n.length === 0 || !payload)
            return
        root.dispatch(["edit-save", n, JSON.stringify(payload)], "", "✓ Layout modifié")
        refreshTimer.restart()
    }

    function deleteLayout(name) {
        if (!name)
            return
        root.dispatch(["delete", name], "", "✓ Layout supprimé")
        refreshTimer.restart()
    }

    function renameLayout(oldName, newName) {
        const a = (oldName || "").trim()
        const b = (newName || "").trim()
        if (a.length === 0 || b.length === 0 || a === b)
            return
        root.dispatch(["rename", a, b], "", "✓ Layout renommé")
        refreshTimer.restart()
    }

    function cleanAll() {
        root.dispatch(["clean"], "", "✓ Fenêtres fermées")
    }

    Component.onCompleted: root.refresh()

    // --- IPC : qs -c noctalia-shell ipc call plugin:hypr-layout <fn> [arg] ---
    IpcHandler {
        target: "plugin:hypr-layout"
        function togglePanel() {
            if (root.pluginApi)
                root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
        }
        function refresh() { root.refresh() }
        function load(name: string) { root.loadLayout(name, "add") }
        function loadReplace(name: string) { root.loadLayout(name, "replace") }
        function loadMerge(name: string) { root.loadLayout(name, "merge") }
        function save(name: string) { root.saveLayout(name) }
        function rename(oldName: string, newName: string) { root.renameLayout(oldName, newName) }
        function clean() { root.cleanAll() }
    }
}
