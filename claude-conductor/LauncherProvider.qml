import QtQuick
import qs.Commons

// Commandes du launcher Noctalia (préfixe `>cc…`) : ouvrir, focus, reprendre une session.
Item {
    id: root
    property var pluginApi: null
    property var launcher: null
    property string name: "Claude Conductor"

    function handleCommand(searchText) {
        return searchText.startsWith(">cc-focus") || searchText.startsWith(">cc-resume")
    }

    function commands() {
        return [
            {
                "name": ">cc",
                "description": pluginApi.tr("launcher.statusDesc"),
                "icon": "robot",
                "isTablerIcon": true,
                "onActivate": function () {
                    if (root.pluginApi)
                        root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
                }
            },
            {
                "name": ">cc-focus",
                "description": pluginApi.tr("launcher.focusDesc"),
                "icon": "target",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">cc-focus ") }
            },
            {
                "name": ">cc-resume",
                "description": pluginApi.tr("launcher.resumeDesc"),
                "icon": "player-play",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">cc-resume ") }
            }
        ]
    }

    // Liste à plat des sessions (depuis le modèle en mémoire du Main).
    function _sessions() {
        var out = []
        var m = root.pluginApi?.mainInstance?.sessionsModel ?? null
        if (!m) return out
        for (var i = 0; i < m.count; i++) {
            var r = m.get(i)
            out.push({ "id": r.sid, "project": r.project, "title": r.title, "state": r.state, "entry": r.entry })
        }
        return out
    }

    function _label(s) {
        return (s.title && s.title.length) ? s.title : (s.project + " · " + s.id.substring(0, 8))
    }

    function getResults(searchText) {
        var main = root.pluginApi?.mainInstance
        if (!main) return []

        if (searchText.startsWith(">cc-focus")) {
            var q1 = searchText.slice(">cc-focus".length).trim().toLowerCase()
            return root._sessions().filter(function (s) {
                return q1.length === 0 || _label(s).toLowerCase().indexOf(q1) !== -1 || s.project.toLowerCase().indexOf(q1) !== -1
            }).map(function (s) {
                return {
                    "name": root._label(s),
                    "description": s.project + " · " + s.state + " — " + root.pluginApi.tr("launcher.focus"),
                    "icon": "target",
                    "isTablerIcon": true,
                    "onActivate": (function (sess) { return function () { main.focusSession(sess.id) } })(s)
                }
            })
        }

        if (searchText.startsWith(">cc-resume")) {
            var q2 = searchText.slice(">cc-resume".length).trim().toLowerCase()
            return root._sessions().filter(function (s) {
                return q2.length === 0 || _label(s).toLowerCase().indexOf(q2) !== -1 || s.project.toLowerCase().indexOf(q2) !== -1
            }).map(function (s) {
                return {
                    "name": root._label(s),
                    "description": s.project + " · " + s.state + " — " + root.pluginApi.tr("launcher.resume"),
                    "icon": "player-play",
                    "isTablerIcon": true,
                    "onActivate": (function (sess) { return function () { main.resumeSession(sess.id) } })(s)
                }
            })
        }

        return []
    }
}
