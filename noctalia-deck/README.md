# Noctalia Deck

Un **terminal flottant persistant** pour Noctalia, affichable/masquable au keybind ou au clic
(style *Quake*), intégré au thème de ton shell. Contrairement aux terminaux déroulants classiques,
il ne repose pas sur un workspace scratchpad Hyprland : le terminal est un **vrai émulateur rendu
directement dans une surface Noctalia** (via `qmltermwidget`), possédée par le plugin et jamais
détruite — **ta session shell survit aux toggles, sans tmux**.

C'est aussi le **socle d'un host de tuiles flottantes** : aujourd'hui une tuile « terminal », demain
une session `claude`, un TUI (btop, lazygit…), ou une vue QML native.

## Dépendance

Le plugin nécessite le paquet **`qmltermwidget`** (le portage QML de qtermwidget, dépôt officiel) :

```sh
sudo pacman -S qmltermwidget
```

Puis **redémarre le shell** (relog ou redémarrage de Noctalia) — un simple rechargement par l'UI ne
recharge pas le QML déjà en cours d'exécution.

## Usage

- **Widget de barre** : un clic bascule le terminal. Clic droit → *Nouvelle session* / *Réglages*.
- **Centre de contrôle** : bouton terminal pour basculer.
- **Launcher** : commande `>deck`.
- **Keybind** (recommandé pour le feeling Quake) — à ajouter à ta config Hyprland :

  ```ini
  bind = $mod, grave, exec, qs -c noctalia-shell ipc call plugin:noctalia-deck toggle
  ```

  IPC disponibles : `toggle`, `show`, `hide`, `newSession`.

## Réglages

**Fenêtre** : largeur, hauteur, marge haute (pour passer sous ta barre), mode de focus clavier
(*à la demande* vs *exclusif*), fermeture à la perte de focus, programme shell (`$SHELL` par défaut).

**Apparence** : source des couleurs, police, taille.

### Couleurs

- **Thème Noctalia (auto)** — suit le clair/sombre du thème global (défini par ton wallpaper).
- **Schéma terminal** — un des schémas fournis par qmltermwidget (Solarized, Falcon, Tango…).

> **Note** — Le mode « auto » sélectionne pour l'instant un schéma clair/sombre. Le *match exact* des
> couleurs Noctalia (génération d'un `.colorscheme` à partir des tokens du thème) nécessite que
> `qmltermwidget` lise un dossier de schémas inscriptible via la variable d'environnement
> `COLORSCHEMES_DIR` au démarrage du shell. C'est une évolution prévue (voir *Roadmap*).

## Placement

La fenêtre descend du bord **haut**, **centrée en largeur**, à la largeur/hauteur réglées — le feeling
*Quake* classique, mais avec l'idiome Noctalia (couche layer-shell, thème, intégration UI).

## Architecture (pour l'extension)

```
Main.qml            → logique + PanelWindow flottant (jamais détruit, juste masqué) + IPC
 └─ TerminalTile.qml → tuile réutilisable : QMLTermWidget + QMLTermSession (command/cwd/env/colorScheme)
```

Une nouvelle tuile = un nouveau composant (ou `TerminalTile` avec une autre `command`). La v1
n'expose qu'une tuile shell ; l'archi est prête pour les onglets et d'autres types de tuiles.

## Roadmap

- Onglets / multi-tuiles.
- Tuile preset `claude` (session Claude Code persistante).
- Tuiles TUI (btop, lazygit, lazydocker…) et tuiles QML natives.
- Match exact des couleurs Noctalia (génération de `.colorscheme` + `COLORSCHEMES_DIR`).
- Animation de descente, drag-resize à la souris.

## Licence

MIT
