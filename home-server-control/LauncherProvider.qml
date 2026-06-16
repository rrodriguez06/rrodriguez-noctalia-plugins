import QtQuick
import qs.Commons

// Commandes du launcher Noctalia (préfixe `>srv…`) : statut, redémarrage, shell d'un service.
Item {
    id: root
    property var pluginApi: null
    property var launcher: null
    property string name: "Home Server Control"

    function handleCommand(searchText) {
        return searchText.startsWith(">srv-restart")
            || searchText.startsWith(">srv-shell")
    }

    function commands() {
        return [
            {
                "name": ">srv",
                "description": pluginApi.tr("launcher.statusDesc"),
                "icon": "server",
                "isTablerIcon": true,
                "onActivate": function () {
                    if (root.pluginApi)
                        root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
                }
            },
            {
                "name": ">srv-restart",
                "description": pluginApi.tr("launcher.restartDesc"),
                "icon": "rotate",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">srv-restart ") }
            },
            {
                "name": ">srv-shell",
                "description": pluginApi.tr("launcher.shellDesc"),
                "icon": "terminal",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">srv-shell ") }
            }
        ]
    }

    // Liste à plat {pid, name, container} des services de l'hôte actif (dernier poll).
    function _services() {
        var out = []
        var data = root.pluginApi?.mainInstance?.statusData ?? []
        for (var i = 0; i < data.length; i++) {
            var p = data[i]
            var svcs = p.services || []
            for (var j = 0; j < svcs.length; j++)
                out.push({ "pid": p.id, "name": svcs[j].name, "container": svcs[j].containerName, "status": svcs[j].status })
        }
        return out
    }

    function getResults(searchText) {
        var main = root.pluginApi?.mainInstance
        if (!main) return []

        if (searchText.startsWith(">srv-restart")) {
            var q1 = searchText.slice(">srv-restart".length).trim().toLowerCase()
            return _services().filter(function (s) {
                return q1.length === 0 || s.name.toLowerCase().indexOf(q1) !== -1
            }).map(function (s) {
                return {
                    "name": s.name,
                    "description": s.pid + " · " + s.status + " — " + root.pluginApi.tr("launcher.restart"),
                    "icon": "rotate",
                    "isTablerIcon": true,
                    "onActivate": (function (svc) {
                        return function () { main.serviceAction(svc.pid, svc.name, "restart") }
                    })(s)
                }
            })
        }

        if (searchText.startsWith(">srv-shell")) {
            var q2 = searchText.slice(">srv-shell".length).trim().toLowerCase()
            return _services().filter(function (s) {
                return s.container && (q2.length === 0 || s.name.toLowerCase().indexOf(q2) !== -1)
            }).map(function (s) {
                return {
                    "name": s.name,
                    "description": s.pid + " · " + root.pluginApi.tr("launcher.shell"),
                    "icon": "terminal",
                    "isTablerIcon": true,
                    "onActivate": (function (svc) {
                        return function () { main.openShell(svc.container) }
                    })(s)
                }
            })
        }

        return []
    }
}
