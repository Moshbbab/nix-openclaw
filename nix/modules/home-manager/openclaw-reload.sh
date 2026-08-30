#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: openclaw-reload [test|prod|both]

Re-render OpenClaw config via Home Manager (no sudo) and restart gateway(s).

Defaults to: test
EOF
}

instance="${1:-test}"

case "$instance" in
  test)
    launchd_labels=(@openclawReloadTestLaunchdLabels@)
    systemd_units=(@openclawReloadTestSystemdUnits@)
    ;;
  prod)
    launchd_labels=(@openclawReloadProdLaunchdLabels@)
    systemd_units=(@openclawReloadProdSystemdUnits@)
    ;;
  both)
    launchd_labels=(@openclawReloadBothLaunchdLabels@)
    systemd_units=(@openclawReloadBothSystemdUnits@)
    ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 1 ;;
esac

if [[ ${#launchd_labels[@]} -eq 0 && ${#systemd_units[@]} -eq 0 ]]; then
  echo "[openclaw-reload] no services configured for '$instance'." >&2
  exit 1
fi

if command -v hm-apply >/dev/null 2>&1; then
  hm-apply
elif [[ -n "${OPENCLAW_RELOAD_HM_CMD:-}" ]]; then
  eval "$OPENCLAW_RELOAD_HM_CMD"
else
  echo "[openclaw-reload] no Home Manager command available." >&2
  echo "[openclaw-reload] install hm-apply or set OPENCLAW_RELOAD_HM_CMD." >&2
  exit 1
fi

if [[ ${#launchd_labels[@]} -gt 0 ]]; then
  for label in "${launchd_labels[@]}"; do
    /bin/launchctl kickstart -k "gui/$UID/$label"
  done
fi

if [[ ${#systemd_units[@]} -gt 0 ]]; then
  for unit in "${systemd_units[@]}"; do
    systemctl --user restart "$unit"
  done
fi
