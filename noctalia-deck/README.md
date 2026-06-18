# Noctalia Deck

Un **terminal flottant persistant** pour Noctalia, attaché à la barre comme un widget classique
(panel natif Noctalia : coins arrondis intelligents, focus clavier, fermeture au clic en dehors).
Le terminal est un **vrai émulateur** (`qmltermwidget`, PTY réel) rendu dans l'UI du shell.

Particularité : **la session survit aux ouvertures/fermetures** (shell, processus en cours, scrollback)
**sans tmux**. Le terminal est possédé par la couche logique du plugin (`Main.qml`) et seulement
*re-parenté* dans le panel le temps de l'affichage — il n'est jamais détruit.

C'est aussi le **socle d'un host de tuiles flottantes** : aujourd'hui une tuile « terminal », demain
une session `claude`, un TUI (btop, lazygit…), ou une vue QML native.

## Dépendance

```sh
sudo pacman -S qmltermwidget
```

Puis **redémarre le shell** (relog ou redémarrage de Noctalia) — un simple rechargement par l'UI ne
recharge pas le QML déjà en cours d'exécution.

### Thème dynamique (couleurs calées sur le wallpaper)

Pour que le mode de couleurs **« Thème Noctalia (auto) »** suive les accents extraits du wallpaper,
qmltermwidget doit lire les schémas générés par le plugin via `COLORSCHEMES_DIR`. **Important** : son
`ColorSchemeManager` ignore définitivement ce dossier s'il n'existe pas encore au lancement de `qs` →
le dossier doit être créé **avant** la session. Fichier d'env fourni :

```sh
# ~/.config/uwsm/env-hyprland.d/noctalia-deck.sh   (sourcé avant qs)
export COLORSCHEMES_DIR="$HOME/.local/share/noctalia-deck/colorschemes"
mkdir -p "$COLORSCHEMES_DIR"
cp -n /usr/lib/qt6/qml/QMLTermWidget/color-schemes/*.colorscheme "$COLORSCHEMES_DIR"/ 2>/dev/null || true
```

→ **relogin unique** pour que la session crée le dossier et prenne la variable en compte. Sans ça, le
mode auto retombe sur un schéma clair/sombre, et le mode « Schéma terminal » fonctionne toujours.

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
  accents extraits du wallpaper) et le **régénère à chaque changement de wallpaper**. Nécessite
  `COLORSCHEMES_DIR` (cf. *Thème dynamique* ci-dessus) ; sinon repli clair/sombre.
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
