#!/usr/bin/env bash
set -euo pipefail

link_agent() {
  local label="$1"
  local target="$HOME/Library/LaunchAgents/${label}.plist"

  local candidate=""
  local hm_gen
  hm_gen="$(realpath "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null || true)"
  if [ -n "$hm_gen" ] && [ -e "$hm_gen/LaunchAgents/${label}.plist" ]; then
    candidate="$hm_gen/LaunchAgents/${label}.plist"
  fi

  if [ -z "$candidate" ]; then
    return 0
  fi

  local current
  current="$(/usr/bin/readlink "$target" 2>/dev/null || true)"

  if [ "$current" != "$candidate" ]; then
    /bin/mkdir -p "${target%/*}"
    /bin/ln -sfn "$candidate" "$target"
    /bin/launchctl bootout "gui/$UID" "$target" 2>/dev/null || true
    if /bin/launchctl bootstrap "gui/$UID" "$target" 2>/dev/null; then
      return 0
    fi
  fi

  /bin/launchctl kickstart -k "gui/$UID/$label" 2>/dev/null || true
}

for label in "$@"; do
  link_agent "$label"
done
