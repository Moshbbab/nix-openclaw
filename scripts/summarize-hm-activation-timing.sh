#!/usr/bin/env bash
set -euo pipefail

system="${1:-x86_64-linux}"
label="${2:-${system}-hm-activation}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nix-openclaw-ci-meter"
safe_label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9_.-' '-')
log_path="$log_dir/${safe_label}.nixos-test.log"

mkdir -p "$log_dir"

if ! drv="$(nix eval --raw ".#checks.${system}.hm-activation.drvPath" --accept-flake-config 2>"$log_path.eval")"; then
  echo "nix-meter: unable to evaluate ${system} hm-activation drvPath; skipping timing summary" >&2
  sed -n '1,80p' "$log_path.eval" >&2 || true
  exit 0
fi

if ! nix log "$drv" > "$log_path" 2>&1; then
  echo "nix-meter: unable to read hm-activation Nix log for $drv; skipping timing summary" >&2
  sed -n '1,120p' "$log_path" >&2 || true
  exit 0
fi

"$repo_root/scripts/summarize-nixos-test-log.mjs" --label "$label" "$log_path" || true
