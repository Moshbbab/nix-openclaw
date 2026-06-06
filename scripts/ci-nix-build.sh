#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: scripts/ci-nix-build.sh <label> <nix-build-args...>" >&2
  exit 1
fi

label="$1"
shift

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
log_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nix-openclaw-ci-meter"
safe_label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9_.-' '-')
log_path="$log_dir/${safe_label}.nix.log"

mkdir -p "$log_dir"
: > "$log_path"

start_epoch=$(date +%s)
echo "nix-meter: start label=$label log=$log_path"

set +e
env NIX_SHOW_STATS="${NIX_SHOW_STATS:-1}" nix build "$@" 2> >(
  perl -MPOSIX=strftime -e '
    my $log_path = shift @ARGV;
    open my $log, ">>", $log_path or die "open $log_path: $!";
    while (my $line = <STDIN>) {
      chomp $line;
      print {$log} strftime("%Y-%m-%dT%H:%M:%SZ", gmtime), " ", $line, "\n";
      print STDERR $line, "\n";
      select($log); $| = 1;
      select(STDERR); $| = 1;
    }
  ' "$log_path"
)
status=$?
set -e

end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
echo "nix-meter: end label=$label status=$status seconds=$elapsed"

"$repo_root/scripts/summarize-nix-build-log.mjs" \
  --label "$label" \
  --seconds "$elapsed" \
  "$log_path" || true

exit "$status"
