#!/usr/bin/env bash
#
# soften — apply the look.
#
# Everything it touches is backed up first, byte for byte, into
# backups/<timestamp>/ — run ./restore.sh to put the machine back exactly the
# way it was. Re-running this script is safe: it takes a fresh backup, then
# rebuilds from scratch.
#
# It does not touch fonts. The bar, the terminals and every shell surface keep
# whatever `omarchy font set` last chose.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$ROOT/config"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/backups/$STAMP"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

STATUS_ID="soften.status"
STATUS_REL=".config/omarchy/plugins/$STATUS_ID"
STATUS_DIR="$HOME/$STATUS_REL"
STAGING="$HOME/.cache/soften-status-staging"

# Everything this installer can write, relative to $HOME. restore.sh replays
# exactly this list, in this order — plain files first, plugin directories
# last (see "why the order matters" below).
TRACKED=(
  ".config/hypr/looknfeel.lua"
  ".config/omarchy/shell.toml"
  ".config/omarchy/shell.json"
  "$STATUS_REL"
)

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33m  ! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[31m  ! \033[0m%s\n' "$*" >&2; exit 1; }

# Give the running shell a moment to finish reacting to a config write before
# the next one lands on it.
settle() { sleep 1; }

# Write through a temp file in the same directory, so a watcher never reads a
# half-written config.
atomic_install() { # mode  src  dst
  local mode=$1 src=$2 dst=$3 tmp
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp "$(dirname "$dst")/.soften.XXXXXX")"
  cat "$src" >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$dst"
}

# ---------------------------------------------------------------- preflight

[[ -d $CONFIG ]] || die "config/ not found next to install.sh"
command -v hyprctl >/dev/null || die "hyprctl not found — this script expects a running Omarchy/Hyprland session"
command -v python3 >/dev/null || die "python3 not found"

# ------------------------------------------------------------------ backup

say "Backing up current state to backups/$STAMP"
mkdir -p "$BACKUP/files"
: >"$BACKUP/present.txt"
: >"$BACKUP/absent.txt"

for rel in "${TRACKED[@]}"; do
  src="$HOME/$rel"
  if [[ -e $src ]]; then
    mkdir -p "$BACKUP/files/$(dirname "$rel")"
    cp -a "$src" "$BACKUP/files/$rel"
    printf '%s\n' "$rel" >>"$BACKUP/present.txt"
    info "saved    $rel"
  else
    printf '%s\n' "$rel" >>"$BACKUP/absent.txt"
    info "absent   $rel"
  fi
done

printf '%s\n' "$STAMP" >"$ROOT/backups/LATEST"

# ORIGINAL is written exactly once and never moved: it names the backup taken
# before this look was ever applied. Re-running the installer must not let
# "the state before the second run" (which is already this look) become what
# restore.sh means by putting things back.
if [[ ! -f "$ROOT/backups/ORIGINAL" ]]; then
  printf '%s\n' "$STAMP" >"$ROOT/backups/ORIGINAL"
else
  info "pre-install state already recorded as $(cat "$ROOT/backups/ORIGINAL"); restore.sh still targets that one"
fi

# -------------------------------------------------------------------- hypr

say "Writing configs"
atomic_install 644 "$CONFIG/hypr/looknfeel.lua" "$HOME/.config/hypr/looknfeel.lua"
info "~/.config/hypr/looknfeel.lua"

# -------------------------------------------------------------- shell.json
#
# shell.json is merged, never replaced: the `bar` subtree is ours, idle
# timings and anything else in there stay yours.
#
# `plain` drops every soften.* widget from the layout, which is how the running
# shell is detached from a plugin directory before that directory is touched.

write_shell_json() { # "plain" | "full"
  python3 - "$HOME/.config/omarchy/shell.json" "$CONFIG/omarchy/bar.json" \
            "$OMARCHY_PATH/config/omarchy/shell.json" "$1" <<'PY'
import json, os, sys, tempfile

shell_path, bar_path, defaults_path, mode = sys.argv[1:5]

def load(path, fallback):
    try:
        with open(path) as fh:
            value = json.load(fh)
    except (OSError, ValueError):
        return fallback
    return value if isinstance(value, dict) else fallback

shell = load(shell_path, None)
if shell is None:
    # No user shell.json yet: start from Omarchy's shipped defaults so idle
    # timings and the plugin list keep their stock values.
    shell = load(defaults_path, {"version": 1})

bar = json.load(open(bar_path))
if mode == "plain":
    for section, entries in bar.get("layout", {}).items():
        bar["layout"][section] = [
            entry for entry in entries
            if not str(entry.get("id", "")).startswith("soften.")
        ]

shell["version"] = 1
shell["bar"] = bar
shell.setdefault("idle", {"screensaver": 150, "lock": 300})
shell.setdefault("plugins", [])

directory = os.path.dirname(shell_path) or "."
os.makedirs(directory, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".soften.")
with os.fdopen(fd, "w") as fh:
    json.dump(shell, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, shell_path)
PY
}

# ------------------------------------------------------------ status plugin
#
# Why the order matters: mutating a plugin directory *while the shell has that
# plugin loaded* makes it hot-reload, and Quickshell 0.3.0 segfaults on that
# path (a bad dynamic_cast in IpcHandler::updateRegistration during Repeater
# regeneration). So the widget is dropped from the layout first, the shell is
# given a moment to settle, and only then is the directory swapped in.

say "Status widget"
rm -rf "$STAGING"
mkdir -p "$(dirname "$STAGING")"
cp -r "$CONFIG/omarchy/plugins/$STATUS_ID" "$STAGING"
chmod +x "$STAGING/collect.sh"

write_shell_json plain
settle

rm -rf "$STATUS_DIR"
mkdir -p "$(dirname "$STATUS_DIR")"
mv "$STAGING" "$STATUS_DIR"
info "~/$STATUS_REL"

atomic_install 600 "$CONFIG/omarchy/shell.toml" "$HOME/.config/omarchy/shell.toml"
info "~/.config/omarchy/shell.toml"

write_shell_json full
info "~/.config/omarchy/shell.json (bar subtree only)"

# ------------------------------------------------------------------- apply

say "Applying"
hyprctl reload >/dev/null
errors="$(hyprctl configerrors 2>&1 || true)"
if [[ -n ${errors// /} && $errors != *"no errors"* ]]; then
  warn "hyprctl configerrors:"
  printf '%s\n' "$errors" >&2
fi

omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell; log out and back in"

say "Done."
info "undo everything:      $ROOT/restore.sh"
info "undo just this run:   $ROOT/restore.sh $STAMP"
info "backup taken:         backups/$STAMP"
