.pragma library

.import "Shared.js" as Shared

// Enrichissement (cc-enrich) + rendu JSONL → texte lisible pour le Tail.

// argv : enrichit une session (cc-enrich dérive le transcript depuis cwd+sessionId).
function enrichCommand(pluginDir, cwd, sessionId) {
    return ["sh", Shared.scriptPath(pluginDir, "cc-enrich"), String(cwd || ""), String(sessionId || "")]
}

function parseEnrich(text) {
    return Shared.safeJson(text, {})
}

// Chemin du transcript dérivé de cwd+sessionId (même règle que Claude Code : non [a-zA-Z0-9] → '-').
function transcriptPathSnippet(cwd, sessionId) {
    return 'enc=$(printf %s ' + Shared.shq(cwd) + " | sed 's/[^a-zA-Z0-9]/-/g'); "
         + 'tp="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$enc/' + String(sessionId) + '.jsonl"'
}

// argv : suit le transcript en direct (tail -f). Chaque ligne → renderLine().
function tailCommand(cwd, sessionId, lines) {
    var n = (lines && lines > 0) ? Math.floor(lines) : 200
    return ["sh", "-c", transcriptPathSnippet(cwd, sessionId) + '; tail -n ' + n + ' -f "$tp"']
}

function _contentText(c) {
    if (typeof c === "string") return c
    if (Array.isArray(c)) {
        var out = []
        for (var i = 0; i < c.length; i++)
            if (c[i] && c[i].type === "text" && c[i].text) out.push(c[i].text)
        return out.join(" ")
    }
    return ""
}

// Une ligne JSONL brute → texte affichable (ou "" si à ignorer). Utilisé par le Tail.
function renderLine(raw) {
    var o = Shared.safeJson(raw, null)
    if (!o || !o.type) return ""

    if (o.type === "user") {
        var ut = _contentText(o.message && o.message.content)
        return ut ? ("\n▶ " + ut) : ""
    }

    if (o.type === "assistant") {
        var parts = []
        var content = o.message && o.message.content
        if (Array.isArray(content)) {
            for (var i = 0; i < content.length; i++) {
                var b = content[i]
                if (!b) continue
                if (b.type === "text" && b.text) parts.push(b.text)
                else if (b.type === "tool_use") parts.push("  ⚙ " + (b.name || "tool"))
                else if (b.type === "thinking") parts.push("  …")
            }
        } else if (typeof content === "string") {
            parts.push(content)
        }
        return parts.length ? parts.join("\n") : ""
    }

    // queue-operation, ai-title, file-history-snapshot, attachment, last-prompt… → ignorés.
    return ""
}
