.pragma library

.import "Shared.js" as Shared

// Lecture/parse de la liste des sessions vivantes (script cc-collect).

// argv pour le sweep bootstrap/liveness.
function collectCommand(pluginDir) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-collect")]
}

// Parse la sortie de cc-collect → tableau de records {sessionId,pid,cwd,entrypoint,startedAt,kind,alive}.
function parseCollect(text) {
    var arr = Shared.safeJson(text, [])
    return Array.isArray(arr) ? arr : []
}

// L'entrypoint passe-t-il le filtre utilisateur ? `tracked` = liste type ["cli","claude-vscode"].
// On normalise : tout ce qui contient "vscode"/"code" → "claude-vscode", sinon "cli".
function entrypointKind(entrypoint) {
    var e = String(entrypoint || "").toLowerCase()
    return (e.indexOf("vscode") !== -1 || e.indexOf("code") !== -1) ? "claude-vscode" : "cli"
}

function isTracked(entrypoint, tracked) {
    if (!tracked || !tracked.length) return true
    return tracked.indexOf(entrypointKind(entrypoint)) !== -1
}
