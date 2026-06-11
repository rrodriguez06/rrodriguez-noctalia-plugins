# Hypr Layout

A [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) plugin to **save and restore window layouts in Hyprland**.

Define named profiles (e.g. `work`, `gaming`) capturing *which apps are open, on which workspace, on which monitor, and how they're arranged*, then restore them in one click — adding to your current windows or replacing them entirely.

The plugin is a thin UI over a self-contained Python CLI that ships **inside the plugin** (`scripts/hypr-layout`), so cloning the repo into your plugins folder is all you need — no script to install in your `$PATH` manually.

---

## Features

- **Save** the current window setup into a named profile.
- **Restore** a profile: relaunches the apps and places them on the right **workspace + monitor**, restores floating windows' size/position, and resizes tiled windows (best-effort).
- **Special workspace (scratchpad) support** — apps living in your special workspace (Slack, Notion, …) are restored there too.
- **Add or Replace** — restore on top of your current windows, or close everything first.
- **noctalia UI** — a bar widget, a **control center button**, and a panel library with **expandable layout cards** (per-app icons, titles, workspace/monitor, floating size) plus Load / Replace / **Rename** / Delete / Clean all.
- **Launcher commands** — type `>hl-` in the noctalia launcher to load/replace/save/clean.
- **Settings page** — confirm-before-clean toggle, toast notifications toggle, and a **launch-command editor** (class → command) to fix apps that get skipped on restore.
- **Toasts** — visual feedback on save / load / delete.
- **IPC commands** — drive it from a keybind or any script.
- **CLI** — the same engine is usable from a terminal (rofi selector included).

---

## Requirements

- **Hyprland** (uses `hyprctl`)
- **noctalia-shell** ≥ 4.5.0
- **python3** (standard library only)
- *Optional:* **rofi** — only for the CLI `pick` selector (the plugin panel doesn't need it)

---

## Installation

1. Clone into your noctalia plugins folder:
   ```bash
   git clone https://github.com/rrodriguez06/hypr-layout \
     ~/.config/noctalia/plugins/hypr-layout
   ```
2. Restart noctalia so it picks up the new plugin, then enable it:
   - **noctalia Settings → Plugins → Hypr Layout → enable**
3. *(Optional)* Add the bar button: **Settings → Bar →** add the *Hypr Layout* widget to a section.
4. *(Optional, recommended)* Pin a keybind to open the panel, in your Hyprland config:
   ```ini
   bind = SUPER SHIFT, L, exec, qs -c noctalia-shell ipc call plugin:hypr-layout togglePanel
   ```
5. *(Optional)* Expose the CLI in your `$PATH`:
   ```bash
   ln -s ~/.config/noctalia/plugins/hypr-layout/scripts/hypr-layout ~/.local/bin/hypr-layout
   ```

> **Reload note:** noctalia loads plugins at startup; after adding/updating the plugin, restart the shell — e.g. `qs kill -c noctalia-shell` then relaunch it (Hyprland's `exec-once = qs -c noctalia-shell`, or relog).

### Recommended Hyprland setup: pin workspaces to monitors

For apps to reliably land on the **right screen**, your workspaces must be bound to monitors (otherwise a new window lands on whatever monitor is focused). Example for two monitors (odd → left, even → right):

```ini
# monitors.conf
workspace = 1, monitor:HDMI-A-1, default:true
workspace = 3, monitor:HDMI-A-1
workspace = 2, monitor:DP-1, default:true
workspace = 4, monitor:DP-1
```

---

## Usage

### Panel (UI)
Open it via the bar widget, the control center button, or your keybind. You get:
- a **name field + Save** to snapshot the current setup,
- one **expandable card** per saved layout: a window-count badge, **Load** / **Replace**, **✎ Rename**, **🗑 Delete** — expand it to see the apps inside (icon, title, workspace/monitor, floating size),
- a **Clean all** button (closes every window; asks for confirmation unless disabled in settings).

### Launcher

Type `>` in the noctalia launcher to see:

- `>hl-load <name>` — restore a layout (add to current windows)
- `>hl-replace <name>` — restore a layout (close everything first)
- `>hl-save <name>` — snapshot the current windows under `<name>`
- `>hl-clean` — close all windows

### Settings

**noctalia Settings → Plugins → Hypr Layout → ⚙**:

- **Confirm before "Close all"** — guard the destructive clean.
- **Notifications** — toasts on save / load / delete.
- **Launch commands (class → command)** — edit the `commands.json` overrides from the UI; use this to fix apps reported as *skipped* on restore.

### IPC
```bash
qs -c noctalia-shell ipc call plugin:hypr-layout togglePanel      # open/close the panel
qs -c noctalia-shell ipc call plugin:hypr-layout refresh          # reload the layout list
qs -c noctalia-shell ipc call plugin:hypr-layout save <name>      # snapshot current windows
qs -c noctalia-shell ipc call plugin:hypr-layout load <name>      # restore (add)
qs -c noctalia-shell ipc call plugin:hypr-layout loadReplace <name>  # restore (replace)
qs -c noctalia-shell ipc call plugin:hypr-layout rename <old> <new>  # rename a profile
qs -c noctalia-shell ipc call plugin:hypr-layout clean            # close all windows
```

### CLI (if symlinked)
```bash
hypr-layout save <name>            # snapshot current windows
hypr-layout load <name> [--replace]# restore (--replace closes all first)
hypr-layout clean                  # close all windows
hypr-layout delete <name>          # remove a profile
hypr-layout rename <old> <new>     # rename a profile
hypr-layout list                   # list profiles
hypr-layout info                   # detailed JSON (apps per profile) — used by the UI
hypr-layout cmd-list               # show class→command overrides (commands.json)
hypr-layout cmd-set <class> <cmd>  # add/replace an override
hypr-layout cmd-unset <class>      # remove an override
hypr-layout pick [load|save]       # rofi selector (load: add/replace choice)
```

---

## How it works

```
Panel.qml / BarWidget.qml  ──(pluginApi)──>  Main.qml  ──(python3)──>  scripts/hypr-layout  ──>  hyprctl
        UI                                   model + IPC                    engine (CLI)        Hyprland
```

- **`Main.qml`** holds the list model, runs the engine via `python3` (a `Process` for `list`, `Quickshell.execDetached` for actions), and registers the `plugin:hypr-layout` IPC handler. The engine path is resolved relative to the plugin (`Qt.resolvedUrl("scripts/hypr-layout")`), so there is **no `$PATH` dependency**.
- **`scripts/hypr-layout`** is the single source of truth (the optional `~/.local/bin` symlink just points here).

### The engine (`scripts/hypr-layout`)

**Save** snapshots `hyprctl clients` into `~/.config/hypr/layouts/<name>.json` — for each window: `class`, launch `cmd`, `workspace`, `monitor`, `floating`, `at`, `size`. Special-workspace windows are captured too (`special: true`).

**Load**:
- *Normal windows:* focus the target workspace (which is bound to a monitor), launch the app, and **wait for its window** before the next — far more reliable than launch rules for multi-process apps (Steam, Chrome, VSCode).
- *Special-workspace windows:* register a **runtime windowrule** (`workspace special silent, match:class ^(Class)$`) then launch — the window lands in the scratchpad whenever it appears (robust for single-instance/tray apps like Slack/Notion).
- *Tiled windows* are resized to their saved size (`resizewindowpixel`, best-effort); *floating windows* get their size/position via launch rules.
- **Command resolution:** the window's *running* command is often a helper/subprocess that can't be relaunched, so the engine maps the window **class → a clean launch command** (e.g. `Google-chrome` → `google-chrome-stable`). Override or extend it via `~/.config/hypr/layouts/commands.json`:
  ```json
  { "my-class": "my-command --with-flags" }
  ```

### Layout profiles
Plain JSON in `~/.config/hypr/layouts/<name>.json` — **editable by hand** (change a workspace, a monitor, remove an app…).

---

## Gotchas & limitations

- **Screen placement requires monitor-pinned workspaces** (see install). Without them, apps land on the focused monitor.
- **Default special workspace target is `special`**, not `special:special` — Hyprland treats the latter as a *different* special workspace (the engine handles this).
- **Tiled arrangement is approximate** — Hyprland doesn't expose the tiling tree, so split ratios aren't perfectly restored.
- **Single-instance apps** (Chrome, VSCode) may consolidate into fewer windows than saved.
- **App state isn't restored** — apps relaunch fresh (no reopened files/tabs).
- Special-workspace windowrules are added at **runtime** (last for the session). Make them permanent in your Hyprland config if you want those apps always in the scratchpad.

---

## File structure

```
hypr-layout/
├── manifest.json            # plugin metadata + entry points
├── Main.qml                 # model + IPC, calls the engine
├── Panel.qml                # the layout library UI (expandable cards)
├── BarWidget.qml            # bar pill that opens the panel
├── ControlCenterWidget.qml  # control center button
├── LauncherProvider.qml     # `>hl-…` launcher commands
├── Settings.qml             # settings page (toggles + command editor)
├── i18n/                    # en.json / fr.json
├── scripts/
│   └── hypr-layout          # the Python engine (CLI)
└── README.md
```

## License

MIT
