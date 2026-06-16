# Home Server Control

Plugin Noctalia pour **monitorer et piloter les services Docker d'un home server à distance en SSH**,
adossé au projet [Home-Server-Runner](https://github.com/rrodriguez06) (`manager.py`).

Le plugin est une **télécommande** : toute la logique serveur vit dans `manager.py`, que le plugin
appelle via `ssh <alias> python3 <chemin>/manager.py … --json`. Aucun secret n'est stocké côté plugin —
l'authentification passe par tes alias `~/.ssh/config`.

## Fonctionnalités

- **Pastille de barre** : état agrégé (vert / ambre / rouge / injoignable) + compteur dans le tooltip.
- **Panneau** : sélecteur d'hôte, jauges RAM/disque + charge/uptime, projets repliables, et par service :
  état + santé, URL Traefik cliquable, **logs en direct**, **start/stop/restart**, **shell** dans le conteneur.
- **Mises à jour intelligentes** : « Vérifier les MAJ » (`update --check-only`) liste les services dont le
  repo a de nouveaux commits ; « Mettre à jour » ne reconstruit que ceux-là (zéro downtime sur le reste).
- **Watchdog** : toast + notification desktop quand un service passe `exited` / `unhealthy`.
- **Launcher** : `>srv` (ouvrir le panneau), `>srv-restart <svc>`, `>srv-shell <svc>`.
- **Centre de contrôle** : carte d'ouverture du panneau.
- **IPC / keybinds** : voir plus bas.

## Pré-requis

1. **Côté serveur** : le dépôt Home-Server-Runner présent, avec un `manager.py` exposant les commandes
   JSON (`status`, `host-info`, `service`, `update`, `logs`, `deploy --full`). Docker + Docker Compose v2.
2. **Côté poste** : un accès SSH par clé configuré dans `~/.ssh/config`, p. ex. :

   ```sshconfig
   Host home-server
       HostName 192.168.1.20
       User romain
       IdentityFile ~/.ssh/id_ed25519
   ```

3. `xdg-open` (ouverture des URLs), `notify-send` (notifications — optionnel), un terminal (`kitty -e` par défaut).

## Configuration

Paramètres → onglet **Hôtes** : ajoute un hôte avec son *nom*, son *alias SSH* (celui de `~/.ssh/config`)
et le *chemin de Home-Server-Runner* sur le serveur (`~/Home-Server-Runner` par défaut). Le bouton
**Tester la connexion** lance `manager.py host-info` et affiche le hostname.

Coche **Lecture seule** sur un hôte sensible (p. ex. un serveur de prod) pour masquer toutes les actions
de contrôle (monitoring seul).

## IPC / keybinds

```bash
qs -c noctalia-shell ipc call plugin:home-server-control togglePanel
qs -c noctalia-shell ipc call plugin:home-server-control refresh
qs -c noctalia-shell ipc call plugin:home-server-control selectHost 0
qs -c noctalia-shell ipc call plugin:home-server-control restart negent_ai backend
qs -c noctalia-shell ipc call plugin:home-server-control update negent_ai
```

Exemple Hyprland :

```ini
bind = $mod, S, exec, qs -c noctalia-shell ipc call plugin:home-server-control togglePanel
```

## Notes

- Le polling réutilise une connexion SSH persistante (`ControlMaster`/`ControlPersist`) → les
  rafraîchissements sont quasi instantanés après le premier.
- Quand le panneau est fermé, le poll est léger (`status --no-fetch`, sans `git fetch`).
- La sortie de `manager.py status` est **sans secret** (les blocs `environment` ne sont jamais lus).
- Noctalia ne recharge pas le QML d'un plugin à chaud : après mise à jour, relogue / redémarre le shell.
