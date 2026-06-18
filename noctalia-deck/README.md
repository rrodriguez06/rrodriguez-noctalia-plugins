# Noctalia Deck

Un **terminal flottant persistant** pour Noctalia, attaché à la barre comme un widget classique
(panel natif Noctalia : coins arrondis intelligents, focus clavier, fermeture au clic en dehors).
Le terminal est un **vrai émulateur** (`qmltermwidget`, PTY réel) rendu dans l'UI du shell.

Particularité : **la session survit aux ouvertures/fermetures** (shell, processus en cours, scrollback)
**sans tmux**. Le terminal est possédé par la couche logique du plugin (`Main.qml`) et seulement
*re-parenté* dans le panel le temps de l'affichage — il n'est jamais détruit.

C'est aussi le **socle d'un host de tuiles flottantes** : aujourd'hui une tuile « terminal », demain
une session `claude`, un TUI (btop, lazygit…), ou une vue QML native.

## Dépendance : qmltermwidget

Le terminal est rendu par `qmltermwidget`. Deux variantes possibles :

- **Theming live (recommandé)** — le fork **[qmltermwidget-noctalia](https://github.com/rrodriguez06/qmltermwidget/tree/noctalia-live)**,
  qui ajoute un slot QML `applyColorSchemeFile()` permettant au terminal de **suivre en live** la
  palette Noctalia/wallpaper. Il s'installe à part (paquet système, indépendant du plugin) et remplace
  le paquet officiel (`provides`/`conflicts`) :
  ```sh
  git clone -b noctalia-live https://github.com/rrodriguez06/qmltermwidget.git
  cd qmltermwidget && makepkg -si
  # mise à jour ultérieure : git pull --rebase && makepkg -si
  ```

- **Stock** — `sudo pacman -S qmltermwidget`. Le terminal fonctionne, mais le mode de couleurs auto
  retombe sur un schéma built-in clair/sombre (pas de suivi live du wallpaper).

Après (ré)installation, **redémarre le shell** (relog) — un rechargement par l'UI ne recharge pas le
QML déjà en cours d'exécution.

### Pourquoi un fork ?

Le `qmltermwidget` stock ne sait appliquer que des schémas présents dans son dossier système au tout
premier scan (liste figée, cache par nom) et force `COLORSCHEMES_DIR` vers ce dossier — donc impossible
d'injecter ou de mettre à jour un schéma à chaud. Le fork ajoute une seule méthode,
`applyColorSchemeFile(path)`, qui lit un `.colorscheme` arbitraire et l'applique directement à la table
de rendu (sans cache, sans dossier système, sans `sudo`) → theming live. Le patch est isolé (un commit
sur la branche `noctalia-live`), rebasable sur l'upstream.

> Pour l'attache à la barre, l'option globale Noctalia **« attacher les panneaux à la barre »** doit
> être active (Réglages → interface). Sinon le terminal s'affiche flottant (clic-dehors, focus et
> coins arrondis restent fonctionnels).

## Usage

- **Widget de barre** : un clic ouvre/ferme le terminal. Clic droit → *Nouvelle session* / *Réglages*.
- **Centre de contrôle** : bouton terminal.
- **Launcher** : commande `>deck`.
- **Keybind** (Hyprland) :

  ```ini
  bind = $mod, grave, exec, qs -c noctalia-shell ipc call plugin:noctalia-deck toggle
  ```

  IPC : `toggle`, `show`, `hide`, `newSession`.

## Réglages

**Fenêtre** : position (*attaché au widget* / *centré*), largeur, hauteur, programme shell
(`$SHELL` par défaut), notifications.

**Apparence** : source des couleurs, police, taille.

### Couleurs

- **Thème Noctalia (auto)** — génère un `.colorscheme` depuis la palette Noctalia (fond, texte,
  accents du wallpaper). Avec le fork **qmltermwidget-noctalia** : appliqué **en live** à chaque
  changement de wallpaper. Avec le paquet stock : repli sur un built-in clair/sombre.
- **Schéma terminal** — un des schémas fournis par qmltermwidget (Solarized, Falcon, Tango…).

## Architecture (pour l'extension)

```text
Main.qml            → logique + PROPRIÉTAIRE persistant de la tuile (créée via createComponent)
 └─ TerminalTile.qml → QMLTermWidget + QMLTermSession (command/cwd/env/colorScheme), rendu CPU
Panel.qml           → panel natif : re-parente la tuile à l'ouverture, la rend à Main à la fermeture
```

La persistance vient de la séparation **durée de vie de la session ≠ durée de vie du panel**. Une
nouvelle tuile = un nouveau composant (ou `TerminalTile` avec une autre `command`). La v1 n'expose
qu'une tuile shell ; l'archi est prête pour les onglets et d'autres types de tuiles.

## Roadmap

- Onglets / multi-tuiles.
- Tuile preset `claude` (session Claude Code persistante).
- Tuiles TUI (btop, lazygit, lazydocker…) et tuiles QML natives.
- Réglage fin du mapping ANSI du thème auto.

## Licence

MIT
