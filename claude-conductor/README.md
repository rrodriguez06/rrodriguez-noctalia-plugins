# Claude Conductor

Plugin Noctalia qui **orchestre tes sessions Claude Code**. Une pastille de barre te dit en
permanence combien d'agents **travaillent**, lequel **t'attend** (permission / inactivité) et lequel
a **fini** — sans chasser dans tes terminaux. Un keybind unique te **téléporte vers l'agent qui te
bloque**. Le panneau regroupe les sessions **par repo**, avec leur titre auto-généré, et propose
**Focus**, **Tail** (suivi du transcript en direct) et **Resume**.

> **100 % local — aucun coût ajouté.** Le plugin n'appelle aucun modèle. Il lit uniquement des
> fichiers que Claude Code écrit déjà (`~/.claude/sessions/*.json`, `~/.claude/projects/*/*.jsonl`,
> `~/.claude/ide/*.lock`), pose des hooks locaux, et focus des fenêtres via `hyprctl`. Pas de clé API,
> pas de token consommé. `Resume` lance `claude --resume` avec ton abonnement habituel, comme si tu
> tapais la commande toi-même.

## Comment ça marche

Deux sources réconciliées :

- **Hooks Claude Code (push, instantané)** — chaque transition d'état (`SessionStart`,
  `UserPromptSubmit`, `Notification`, `Stop`, `SessionEnd`) appelle un mini-script qui pousse l'état
  au plugin par IPC. C'est le **seul moyen fiable de détecter « t'attend »** (prompt de permission).
- **Sweep local léger** — lit `~/.claude/sessions/*.json` pour découvrir les sessions nées avant le
  plugin et retirer les process morts (les sorties propres passent par `SessionEnd`).

Les états : `running` (bleu, travaille) · `waiting` (rouge, t'attend) · `idle` (vert, prête).

## Installation

1. Place le dossier dans les plugins Noctalia (lien symbolique recommandé pour développer) :

   ```bash
   ln -s "$PWD/claude-conductor" ~/.config/noctalia/plugins/claude-conductor
   ```

2. Active **Claude Conductor** dans Noctalia, puis **relogue / redémarre le shell** (Noctalia ne
   recharge pas le QML d'un plugin à chaud).

3. Ouvre les **Réglages → onglet Hooks → « Installer les hooks »**. Ça fusionne un bloc `hooks` dans
   `~/.claude/settings.json` (sauvegarde `.bak` créée, désinstallable d'un clic). Les nouvelles
   sessions Claude Code remonteront alors leur état en temps réel.

> Les hooks enregistrent le **chemin absolu** du script `cc-hook` au moment de l'install. Si tu
> déplaces le plugin, ré-installe les hooks.

## Téléportation (keybind Hyprland)

```ini
bind = $mod, A, exec, qs -c noctalia-shell ipc call plugin:claude-conductor focusNext
```

`focusNext` cycle vers le prochain agent en **waiting** (sinon le **running** le plus récent) et
focus sa fenêtre — terminal **ou** VS Code.

## Pré-requis

`jq`, `hyprctl` (Hyprland), un terminal (`kitty -e` par défaut, configurable), `notify-send`
(optionnel, pour les notifications desktop).

## IPC / keybinds

```bash
qs -c noctalia-shell ipc call plugin:claude-conductor togglePanel
qs -c noctalia-shell ipc call plugin:claude-conductor focusNext
qs -c noctalia-shell ipc call plugin:claude-conductor refresh
qs -c noctalia-shell ipc call plugin:claude-conductor focus  <sessionId>
qs -c noctalia-shell ipc call plugin:claude-conductor resume <sessionId>
```

Launcher : `>cc` (panneau), `>cc-focus <filtre>` (aller à une session), `>cc-resume <filtre>`.

## Architecture

- `Main.qml` — registre des sessions, machine à états (IPC `event`), sweep liveness, enrichissement,
  notifications, focus/resume, Tail.
- `BarWidget.qml` / `Panel.qml` / `Settings.qml` / `ControlCenterWidget.qml` / `LauncherProvider.qml`
  — surfaces Noctalia.
- `drivers/*.js` (`.pragma library`) — `Shared` (utils + chemins), `Sessions` (cc-collect),
  `Transcript` (cc-enrich + rendu Tail), `Focus` (cc-focus + resume), `Hooks` (install/uninstall).
- `scripts/` — `cc-hook` (pont hook→IPC), `cc-collect` (sessions vivantes), `cc-enrich`
  (titre/branche/modèle/dernier message), `cc-focus` (résolution + focus de fenêtre), `cc-tail`
  (transcript en clair dans un terminal), `cc-hooks-install` (merge JSON des hooks).

## Notes

- Le sweep est purement local (lecture de quelques petits fichiers) ; léger quand le panneau est
  fermé, plus vif quand il est ouvert. L'enrichissement (lecture des transcripts) n'a lieu que panneau
  ouvert.
- Si Noctalia est éteint, le hook `qs ipc call` échoue en <100 ms sans bloquer Claude. Au redémarrage,
  le sweep reconstruit l'état.
- Aucun secret stocké ; aucune connexion réseau.
