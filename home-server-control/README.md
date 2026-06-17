# Home Server Control

Plugin Noctalia pour **monitorer et piloter des services Docker** — sur ta machine locale ou sur un
serveur distant via SSH. Par défaut il n'a besoin que du CLI `docker` : il inspecte et contrôle les
conteneurs directement. Aucun secret n'est stocké côté plugin (l'accès distant passe par tes alias
`~/.ssh/config`).

Si l'optionnel [Home-Server-Runner](https://github.com/rrodriguez06) (`manager.py`) est présent sur
l'hôte, le plugin le détecte et débloque en plus les **déploiements git-aware** (rebuild des seuls
services dont le repo a bougé).

## Backends (par hôte)

Chaque hôte a un **mode** dans les réglages :

| Mode | Quand l'utiliser | Ce que tu obtiens |
|------|------------------|-------------------|
| **Auto** *(défaut)* | tu ne sais pas / les deux | sonde `manager.py` sur l'hôte → bascule HSR si présent, sinon Docker |
| **Docker** | n'importe quel hôte avec `docker` | liste/état/santé/ports/URLs, logs, shell, start/stop/restart, « relancer tout » |
| **Home-Server-Runner** | tu utilises HSR | tout Docker **+** « Vérifier les MAJ », « Mettre à jour », « Redéploiement complet », retard de commits |
| **Cloud Run (gcloud)** | services GCP Cloud Run | état des services (par région) + logs Cloud Logging + URL `*.run.app`. Lecture seule (v1). |

En mode Docker, les conteneurs sont regroupés par **projet docker compose** (label
`com.docker.compose.project`), avec un bucket **`standalone`** pour les conteneurs hors compose.
Les boutons et badges git-aware sont automatiquement masqués (Docker n'a pas de notion de rebuild git).

### Mode Cloud Run (gcloud)

Renseigne le **projet GCP** (et une **région** optionnelle ; vide = toutes) sur l'hôte. Le plugin
utilise le CLI `gcloud` avec le **compte actif** (`gcloud config get-value account`) :

- **Service Account** (`*.gserviceaccount.com`) → accès **lecture seule** ;
- **compte utilisateur** (après `gcloud auth login`) → marqué **inscriptible**.

Un badge dans l'en-tête indique le compte connecté et son niveau d'accès ; les actions sont
masquées/affichées en conséquence. v1 = status + logs uniquement (Cloud Run n'a pas de stop/restart
natifs). Après un changement d'auth (`gcloud auth login` / `activate-service-account`), clique
**Rafraîchir** pour re-détecter l'accès. Les services sont regroupés par **région**. Comme pour
Docker, `gcloud` peut tourner en **local** (alias SSH vide) ou sur un hôte distant.

## Local vs SSH

- **Local** : laisse l'**alias SSH vide** → les commandes `docker` tournent directement sur la machine
  où tourne Noctalia.
- **Distant** : renseigne un **alias `~/.ssh/config`** → tout passe par `ssh <alias> …`.

## Fonctionnalités

- **Pastille de barre** : état agrégé (vert / ambre / rouge / injoignable) + compteur dans le tooltip.
- **Panneau** : sélecteur d'hôte, jauges RAM/disque + charge/uptime, projets repliables, et par service :
  état + santé, URL Traefik cliquable, **logs en direct**, **start/stop/restart**, **shell** dans le conteneur.
- **Mises à jour intelligentes** *(HSR uniquement)* : « Vérifier les MAJ » (`update --check-only`) liste les
  services dont le repo a de nouveaux commits ; « Mettre à jour » ne reconstruit que ceux-là.
- **Watchdog** : toast + notification desktop quand un service passe `exited` / `unhealthy`.
- **Launcher** : `>srv` (ouvrir le panneau), `>srv-restart <svc>`, `>srv-shell <svc>`.
- **Centre de contrôle** : carte d'ouverture du panneau.
- **IPC / keybinds** : voir plus bas.

## Pré-requis

1. **Côté hôte (mode Docker)** : seulement le CLI `docker` accessible par l'utilisateur (local ou SSH).
   Pour le bouton « relancer tout » d'un projet compose, `docker compose` v2 est utilisé si disponible
   (fallback automatique : restart conteneur par conteneur).
2. **Côté hôte (mode HSR, optionnel)** : le dépôt Home-Server-Runner avec un `manager.py` exposant les
   commandes JSON (`status`, `host-info`, `service`, `update`, `deploy`, `logs`).
3. **Côté poste (mode distant)** : un accès SSH par clé dans `~/.ssh/config`, p. ex. :

   ```sshconfig
   Host home-server
       HostName 192.168.1.20
       User romain
       IdentityFile ~/.ssh/id_ed25519
   ```

4. `xdg-open` (URLs), `notify-send` (notifications — optionnel), un terminal (`kitty -e` par défaut).

## Configuration

Paramètres → onglet **Hôtes** : ajoute un hôte avec son *nom*, son *alias SSH* (vide = local), son
*backend* (Auto / Docker / Home-Server-Runner) et, pour Auto/HSR, le *chemin de Home-Server-Runner*
sur l'hôte. Le bouton **Tester la connexion** récupère le hostname.

Coche **Lecture seule** sur un hôte sensible (p. ex. prod) pour masquer toutes les actions de contrôle.

## IPC / keybinds

```bash
qs -c noctalia-shell ipc call plugin:home-server-control togglePanel
qs -c noctalia-shell ipc call plugin:home-server-control refresh
qs -c noctalia-shell ipc call plugin:home-server-control selectHost 0
qs -c noctalia-shell ipc call plugin:home-server-control restart myapp web
qs -c noctalia-shell ipc call plugin:home-server-control update myapp   # HSR uniquement
```

Exemple Hyprland :

```ini
bind = $mod, S, exec, qs -c noctalia-shell ipc call plugin:home-server-control togglePanel
```

## Architecture (drivers)

La logique de commande est isolée dans `drivers/` (modules JS `.pragma library`) :

- `Shared.js` — quoting, wrapping local/SSH, snippet host-info, regex Traefik ;
- `DockerDriver.js` — `docker inspect` / `docker …` brut → schéma normalisé ;
- `HsrDriver.js` — `manager.py … --json` (git-aware) ;
- `Registry.js` — sélection du driver + sonde d'auto-détection.

Chaque driver expose la même interface (builders d'argv + parsers + `capabilities`), ce qui rend
l'UI agnostique du backend. Un futur driver (p. ex. **gcloud** via Service Account) s'ajoute ici sans
toucher au reste.

## Notes

- Le polling SSH réutilise une connexion persistante (`ControlMaster`/`ControlPersist`) → les
  rafraîchissements sont quasi instantanés après le premier.
- Quand le panneau est fermé, le poll est léger (en mode HSR : `status --no-fetch`, sans `git fetch`).
- Si `docker` est absent ou le daemon est arrêté sur l'hôte, l'état passe « injoignable » proprement.
- Noctalia ne recharge pas le QML d'un plugin à chaud : après mise à jour, relogue / redémarre le shell.
