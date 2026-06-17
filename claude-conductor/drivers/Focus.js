.pragma library

.import "Shared.js" as Shared

// Construction des commandes de focus de fenêtre et de reprise de session.

// argv (fire-and-forget via execDetached) : focus la fenêtre hébergeant la session.
function focusCommand(pluginDir, session) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-focus"),
            String(session.pid || ""), String(session.cwd || ""), String(session.entrypoint || "")]
}

// argv : ouvre un terminal et reprend la session à son cwd (claude --resume).
// Utilise l'abonnement habituel — aucun coût ajouté par le plugin.
function resumeCommand(terminalArgv, session) {
    var inner = "cd " + Shared.shq(session.cwd || "~") + " && claude --resume " + Shared.shq(session.id || session.sessionId || "")
    return (terminalArgv || ["kitty", "-e"]).concat(["sh", "-lc", inner])
}
