import QtQuick
import qs.Commons

// Commandes du launcher Noctalia (préfixe `>hl-…`) pour save/load/clean.
Item {
    id: root

    property var pluginApi: null
    property var launcher: null
    property string name: "Hypr Layout"

    // Le launcher route vers getResults() quand handleCommand() renvoie true.
    function handleCommand(searchText) {
        return searchText.startsWith(">hl-load")
            || searchText.startsWith(">hl-replace")
            || searchText.startsWith(">hl-save")
    }

    // Entrées affichées quand l'utilisateur tape ">".
    function commands() {
        return [
            {
                "name": ">hl-load",
                "description": pluginApi.tr("launcher.load"),
                "icon": "folder-open",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">hl-load ") }
            },
            {
                "name": ">hl-replace",
                "description": pluginApi.tr("launcher.replace"),
                "icon": "replace",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">hl-replace ") }
            },
            {
                "name": ">hl-save",
                "description": pluginApi.tr("launcher.save"),
                "icon": "device-floppy",
                "isTablerIcon": true,
                "onActivate": function () { launcher.setSearchText(">hl-save ") }
            },
            {
                "name": ">hl-clean",
                "description": pluginApi.tr("launcher.clean"),
                "icon": "x",
                "isTablerIcon": true,
                "onActivate": function () { root.pluginApi.mainInstance.cleanAll() }
            }
        ]
    }

    function _layoutNames() {
        var out = []
        var m = root.pluginApi?.mainInstance?.layoutsModel
        if (!m) return out
        for (var i = 0; i < m.count; i++)
            out.push(m.get(i).name)
        return out
    }

    function _loadResults(query, mode) {
        var q = query.trim().toLowerCase()
        var results = []
        var names = _layoutNames()
        var desc = mode === "replace" ? pluginApi.tr("launcher.replaceDesc")
                 : mode === "merge" ? pluginApi.tr("launcher.mergeDesc")
                 : pluginApi.tr("launcher.loadDesc")
        var ico = mode === "replace" ? "replace"
                : mode === "merge" ? "arrows-exchange" : "folder-open"
        for (var i = 0; i < names.length; i++) {
            var nm = names[i]
            if (q.length > 0 && nm.toLowerCase().indexOf(q) === -1)
                continue
            results.push({
                "name": nm,
                "description": desc,
                "icon": ico,
                "isTablerIcon": true,
                "onActivate": (function (n, mo) {
                    return function () { root.pluginApi.mainInstance.loadLayout(n, mo) }
                })(nm, mode)
            })
        }
        return results
    }

    function getResults(searchText) {
        if (searchText.startsWith(">hl-merge"))
            return _loadResults(searchText.slice(">hl-merge".length), "merge")
        if (searchText.startsWith(">hl-load"))
            return _loadResults(searchText.slice(">hl-load".length), "add")
        if (searchText.startsWith(">hl-replace"))
            return _loadResults(searchText.slice(">hl-replace".length), "replace")
        if (searchText.startsWith(">hl-save")) {
            var nm = searchText.slice(">hl-save".length).trim()
            if (nm.length === 0)
                return []
            return [{
                "name": pluginApi.tr("launcher.saveAs") + " « " + nm + " »",
                "description": pluginApi.tr("launcher.saveDesc"),
                "icon": "device-floppy",
                "isTablerIcon": true,
                "onActivate": (function (n) {
                    return function () { root.pluginApi.mainInstance.saveLayout(n) }
                })(nm)
            }]
        }
        return []
    }
}
