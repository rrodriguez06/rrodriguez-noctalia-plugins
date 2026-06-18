import QtQuick
import qs.Commons

// Commande du launcher Noctalia : `>deck` bascule le terminal flottant.
Item {
    id: root
    property var pluginApi: null
    property var launcher: null
    property string name: "Noctalia Deck"

    function handleCommand(searchText) {
        return false
    }

    function commands() {
        return [
            {
                "name": ">deck",
                "description": pluginApi.tr("launcher.toggleDesc"),
                "icon": "terminal",
                "isTablerIcon": true,
                "onActivate": function () {
                    if (root.pluginApi && root.pluginApi.mainInstance)
                        root.pluginApi.mainInstance.toggle()
                }
            }
        ]
    }

    function getResults(searchText) {
        return []
    }
}
