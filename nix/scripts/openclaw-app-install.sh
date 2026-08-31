#!/bin/sh
set -e
mkdir -p "$out/Applications"
app_path="$(find "$src" -mindepth 1 -maxdepth 2 -type d -name '*.app' ! -path '*/__MACOSX/*' -print -quit)"
if [ -z "$app_path" ]; then
  echo "OpenClaw.app not found in $src" >&2
  exit 1
fi

# Canonical name going forward
cp -R "$app_path" "$out/Applications/OpenClaw.app"
