# soften-omarchy

A system-level soft-minimalist pass over Omarchy: rounded windows, no colored
borders anywhere, motion you feel rather than watch, and one status icon in the
bar with everything behind it.

It is not a theme, and it does not touch fonts. Nothing here replaces your
colors — `omarchy theme set` keeps working, and this look survives it, because
every file lands in the layer that sits *above* the active theme. The bar and
the terminals keep whatever `omarchy font set` last chose.

```
./install.sh        apply it (backs up everything it touches first)
./restore.sh        put it all back, exactly as it was
./restore.sh --last undo only the most recent install.sh run
./restore.sh -l     list available backups
```

## What it changes

| File | What lands there |
|---|---|
| `~/.config/hypr/looknfeel.lua` | `rounding = 12`, `border_size = 0`, neutral shadow, blur, motion curves |
| `~/.config/omarchy/shell.toml` | Bar translucency, borderless controls, neutral hairlines |
| `~/.config/omarchy/shell.json` | The `bar` subtree only — layout and widgets |
| `~/.config/omarchy/plugins/soften.status/` | The status widget |

Your idle/lock timings, keybindings, monitors, input settings, fonts and theme
are not touched.

## The four ideas

**One radius for the whole desktop.** `decoration:rounding` in `looknfeel.lua`
is the only place a corner radius is written down. The Omarchy shell reads that
value back out of Hyprland at startup, so bar popups, notifications, the menu,
the polkit prompt and the lock screen all round to match. Change the number,
reload, and the whole system follows.

**Depth instead of outline.** `border_size = 0` removes the window frame
entirely, which is what kills the theme's tinted active-border gradient. Focus
is carried by a plain black shadow instead — no hue, so it never fights the
wallpaper or the theme. The shell surfaces follow the same rule: `[controls]`
in `shell.toml` sets every border width to 0 and lets buttons state themselves
by fill alone, and each popup trades its accent-colored frame for a 10%-alpha
neutral hairline.

**Motion you don't wait for.** Three bezier curves and nothing over ~220ms.
Windows arrive from 94% and leave a little faster than they came; workspace
switching gets a 15% slide that Omarchy ships turned off. The point is that
nothing appears out of nowhere — not that you get to watch it happen.

**One icon, not a dashboard.** The bar is left, right, and nothing in the
middle: menu, workspaces and the focused window's title on the left; the widget
row and the clock on the right. The status widget is a single glyph that only
changes color when something has actually failed. Click it and the panel has
the detail.

## The status widget

`soften.status` is a bar widget in `~/.config/omarchy/plugins/soften.status/`. It
shows one server glyph. The panel behind it lists:

- **Services** — every watched systemd unit that is actually installed, with
  its live sub-state. Candidates cover the usual databases, container runtimes
  and web servers; anything not installed is silently dropped, so the list only
  ever shows what this machine really runs. Click a row to open
  `systemctl status` for it in a terminal.
- **Listening** — every listening TCP socket, with the process name where the
  kernel will tell an unprivileged process. Anything bound off loopback is
  tagged `exposed`.

Nothing runs in the background: `collect.sh` (two `systemctl` calls and one
`ss`) fires when the panel opens and every 5s while it stays open. Nothing
needs root.

Add units of your own, or change the refresh rate, on the widget's entry in
`shell.json`:

```json
{ "id": "soften.status", "units": "gitea vaultwarden", "interval": 3000 }
```

## Tuning

Both config files hot-reload on save.

- softer / sharper corners → `rounding` in `looknfeel.lua` (`rounding_power`
  bends a circular corner towards a squircle)
- more / less glass → `[bar] background-alpha` in `shell.toml`
- blur too expensive → `decoration.blur.enabled = false` in `looknfeel.lua`
- snappier / slower motion → the `hl.animation` speed values (hundredths of a
  second, so higher is slower)
- move a widget → `omarchy bar move omarchy.clock --section center`

## Backups

`install.sh` copies each file it is about to write into
`backups/<timestamp>/files/`, and records which paths did not exist yet.
`restore.sh` replays that: existing files copied back byte for byte, created
files deleted again. Re-running `install.sh` takes a fresh backup each time, so
nothing is ever overwritten in place.

The first run also writes `backups/ORIGINAL`, and never moves it again. That is
the one `restore.sh` defaults to — after a second install, the newest backup
describes a machine that already had soften on it, which is not what "put it
back" means. `--last` is there when undoing just the last run is what you
actually want.

## Why the scripts move in a particular order

Mutating a plugin directory while the shell still has that plugin loaded makes
it hot-reload, and Quickshell 0.3.0 segfaults on that path — a bad
`dynamic_cast` in `IpcHandler::updateRegistration` during Repeater
regeneration. So both scripts write a `shell.json` with the soften widgets
dropped first, let the shell settle, and only then swap the plugin directory.
Config writes go through a temp file and a rename, so a watcher never reads
half a file.
