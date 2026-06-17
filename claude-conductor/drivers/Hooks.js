.pragma library

.import "Shared.js" as Shared

// Commandes d'install/désinstall/statut des hooks Claude Code (script cc-hooks-install).
//
// Mapping événement Claude Code → état de session (posé par cc-hooks-install) :
//   SessionStart      → start    (enregistre la session, état "idle")
//   UserPromptSubmit  → running  (l'agent travaille)
//   Notification      → waiting  (permission / inactivité : il t'attend)
//   Stop              → idle      (tour terminé, prêt)
//   SessionEnd        → end       (session retirée)

function installCommand(pluginDir) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-hooks-install")]
}

function uninstallCommand(pluginDir) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-hooks-install"), "--uninstall"]
}

function statusCommand(pluginDir) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-hooks-install"), "--status"]
}
