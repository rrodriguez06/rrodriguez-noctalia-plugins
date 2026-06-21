import QtQuick

// Launcher commands (prefix `>cal…`): open the panel, jump to today.
Item {
    id: root
    property var pluginApi: null
    property var launcher: null
    property string name: "Calendar"

    function handleCommand(searchText) {
        return searchText.startsWith(">cal-today")
    }

    function commands() {
        return [
            {
                "name": ">cal",
                "description": pluginApi ? pluginApi.tr("launcher.openDesc") : "Open the calendar",
                "icon": "calendar",
                "isTablerIcon": true,
                "onActivate": function () {
                    if (root.pluginApi)
                        root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
                }
            },
            {
                "name": ">cal-today",
                "description": pluginApi ? pluginApi.tr("launcher.todayDesc") : "Jump to today",
                "icon": "calendar-event",
                "isTablerIcon": true,
                "onActivate": function () {
                    var main = root.pluginApi?.mainInstance
                    if (main) main.goToday()
                    if (root.pluginApi)
                        root.pluginApi.withCurrentScreen(s => root.pluginApi.togglePanel(s))
                }
            }
        ]
    }

    function getResults(searchText) { return [] }
}
