#!/usr/bin/env bash
#
# soften — put everything install.sh touched back exactly the way it was.
#
#   ./restore.sh                 back to how things were before soften was ever
#                                applied
#   ./restore.sh --last          undo only the most recent install.sh run
#   ./restore.sh 20260828-1830   restore one specific backup
#   ./restore.sh --list          show what is available

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS="$ROOT/backups"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33m  ! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[31m  ! \033[0m%s\n' "$*" >&2; exit 1; }

settle() { sleep 1; }

list_backups() {
  local found=0
  for dir in "$BACKUPS"/*/; do
    [[ -f "$dir/present.txt" ]] || continue
    found=1
    printf '  %s\n' "$(basename "$dir")"
  done
  [[ $found -eq 1 ]] || echo "  (none)"
}

if [[ ${1:-} == "--list" || ${1:-} == "-l" ]]; then
  say "Backups in $BACKUPS"
  list_backups
  [[ -f "$BACKUPS/ORIGINAL" ]] && info "pre-install: $(cat "$BACKUPS/ORIGINAL")"
  [[ -f "$BACKUPS/LATEST" ]] && info "most recent: $(cat "$BACKUPS/LATEST")"
  exit 0
fi

# ------------------------------------------------------------ pick a backup
#
# The default is ORIGINAL, not LATEST: after a second install.sh run, LATEST
# describes a machine that already had soften on it, which is not what "put it
# back" means.

STAMP="${1:-}"
case "$STAMP" in
  "")
    for marker in ORIGINAL LATEST; do
      if [[ -f "$BACKUPS/$marker" ]]; then
        STAMP="$(cat "$BACKUPS/$marker")"
        break
      fi
    done
    [[ -n $STAMP ]] || die "no backups yet — nothing to restore"
    ;;
  --last)
    [[ -f "$BACKUPS/LATEST" ]] || die "no backups/LATEST — run ./restore.sh --list"
    STAMP="$(cat "$BACKUPS/LATEST")"
    ;;
esac

BACKUP="$BACKUPS/$STAMP"
[[ -f "$BACKUP/present.txt" ]] || {
  warn "no backup called '$STAMP'. Available:"
  list_backups
  exit 1
}

say "Restoring backup $STAMP"

# ------------------------------------------------------------------ replay
#
# present.txt holds what existed before install.sh ran (copy it back);
# absent.txt holds what install.sh created from nothing (delete it again).
#
# Both lists are in install.sh's TRACKED order, which puts plugin directories
# last on purpose. Config files land first, so shell.json has already dropped
# the soften widgets by the time their directories go away — mutating a plugin
# directory while the shell still has it loaded makes it hot-reload, and
# Quickshell 0.3.0 segfaults on that path.

while IFS= read -r rel; do
  [[ -n $rel ]] || continue
  src="$BACKUP/files/$rel"
  dst="$HOME/$rel"
  [[ -e $src ]] || { warn "missing from backup, skipped: $rel"; continue; }
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  info "restored $rel"
done <"$BACKUP/present.txt"

settle

while IFS= read -r rel; do
  [[ -n $rel ]] || continue
  dst="$HOME/$rel"
  if [[ -e $dst ]]; then
    rm -rf "$dst"
    info "removed  $rel (did not exist before)"
  fi
done <"$BACKUP/absent.txt"

# ------------------------------------------------------------------- apply

say "Applying"
if command -v hyprctl >/dev/null; then
  hyprctl reload >/dev/null || warn "hyprctl reload failed"
fi
if command -v omarchy >/dev/null; then
  omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell; log out and back in"
fi

say "Done — back to the state from $STAMP."
