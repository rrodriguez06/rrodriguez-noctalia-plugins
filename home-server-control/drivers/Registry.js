.pragma library
.import "Shared.js" as Shared
.import "HsrDriver.js" as Hsr
.import "DockerDriver.js" as Docker

// Sélection du driver selon le mode résolu d'un hôte.
// Modes : "hsr" | "docker" (le mode "auto" est résolu en amont par Main via probeCommand).
// Futur : ajouter "gcloud" ici + son GcloudDriver, sans toucher au reste.

function pickDriver(mode) {
    if (mode === "hsr") return Hsr
    return Docker          // défaut sûr (et cible du fallback public)
}

function capabilitiesFor(mode) {
    return (mode === "hsr") ? Hsr.capabilities : Docker.capabilities
}

// Sonde d'auto-détection (driver-agnostique) : présence de manager.py à hsrPath.
// `stat` pur (pas de lancement python) → cheap. Stdout = "HSR" ou "DOCKER".
// Exit 0 dans tous les cas : on découple le succès du transport SSH du résultat de la sonde.
function probeCommand(h, sshBase) {
    var path = (h && h.hsrPath) || "~/Home-Server-Runner"   // non quoté : ~ développé par le shell
    return Shared.wrap(h, sshBase, "[ -f " + path + "/manager.py ] && echo HSR || echo DOCKER")
}
