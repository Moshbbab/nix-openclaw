---
written_by: ai
---

# Performance Audit

Commit-tied metrics for packaging and CI changes. Keep this file short: current
snapshot, decision-relevant history, and exact commands. Raw logs belong in
GitHub Actions, local `/tmp` captures, or ignored `.agent/` notes.

## Current Snapshot

- Compared refs:
  - main: `d69b1fc1e736bbe78b46bd886fcc1791b5b9d942`
  - PR: `fd1904b6b8ea6352569a9694882595052086db3d`
- PR: `#100`, `codex/npm-shrinkwrap-default`, base `main`, merge state `CLEAN`.
- Remote proof: GitHub Actions run `27062082132` passed at PR head; Garnix passed
  flake eval, Darwin `ci`, and stable `openclaw` / `openclaw-gateway` packages
  on Darwin and Linux.
- Product change: stable `openclaw-gateway` uses the upstream npm package and
  `npm-shrinkwrap.json` through `buildNpmPackage`; source/pnpm remains available
  for dogfood and explicit source overrides.

| Metric | main | PR | Change | Command |
| --- | ---: | ---: | ---: | --- |
| Gateway closure | 2,273,877,888 B | 904,981,328 B | 60.2% smaller | `nix path-info -S "$gateway"` |
| `openclaw` closure | 3,215,431,032 B | 1,846,534,464 B | 42.6% smaller | `nix path-info -S "$openclaw"` |
| Gateway output | 2,169,012,224 B | 339,697,664 B | 84.3% smaller | `du -sk "$gateway"` |
| Package manifests | 1,452 | 541 | 62.7% fewer | `find "$gateway/lib/openclaw" -name package.json \| wc -l` |
| Files under `lib/openclaw` | 97,909 | 32,840 | 66.5% fewer | `find "$gateway/lib/openclaw" -type f \| wc -l` |
| Darwin `ci` direct input drvs | 48 | 11 | 77.1% fewer | `nix derivation show "$(nix eval --raw <ref>#checks.aarch64-darwin.ci.drvPath)"` |
| Linux `ci` direct input drvs | 50 | 11 | 78.0% fewer | same |
| Darwin `default-instance` closure paths | 2,881 | 863 | 70.0% fewer | `nix-store -qR --include-outputs "$drv" \| wc -l` |
| Linux `default-instance` closure paths | 3,697 | 357 | 90.3% fewer | same |
| Darwin `default-instance` closure size | 9,087,336 B | 2,652,688 B | 70.8% smaller | `nix path-info --json --json-format 2 --closure-size "$drv"` |
| Linux `default-instance` closure size | 19,036,016 B | 2,185,584 B | 88.5% smaller | same |
| Garnix include targets | 10 | 5 | 50.0% fewer | `ruby -e 'require "yaml"; ...'` |
| Gateway forced rebuild | 399.37s then Nix determinism failure | 56.27s success | deterministic npm path | `/usr/bin/time -p nix build --rebuild --no-link <ref>#packages.aarch64-darwin.openclaw-gateway` |

## Current CI Cost

Remote run `27062082132` at `fd1904b6b8ea6352569a9694882595052086db3d`:

| Surface | Time | Main cost |
| --- | ---: | --- |
| GitHub Actions Linux job | 2m17s | Linux aggregate dominates |
| Linux aggregate step | 120s | 923 fetched paths, 932 MiB download, 4.2 GiB unpacked, 28 built drvs |
| Linux HM timing step | 7s | Reads NixOS test log after aggregate succeeds |
| Linux VM apply proof | 31.7s inside test log | TCP readiness 14.2s, Home Manager service success 11.4s, VM boot 11.1s |
| GitHub Actions macOS job | 1m46s | Darwin aggregate dominates |
| Darwin aggregate step | 67s | 226 fetched paths, 327 MiB download, 1.8 GiB unpacked, 0 built drvs |
| macOS HM activation | 6s job step, 2.07s parsed Nix step | Applies prebuilt activation package |
| Garnix total | 1m04s | Darwin `ci` 51s, stable packages 6-18s |

Interpretation:

- The largest durable win is package graph shrinkage, not runner variance.
- Linux still spends time building proof derivations and running the VM apply
  proof. The OpenClaw startup trace itself is sub-second to low-single-second;
  the visible wait is mostly systemd/VM/readiness orchestration.
- macOS is currently substitution/copy-bound. It builds no derivations in the
  aggregate on the sampled hosted runner.
- Garnix is still useful in this snapshot, but it is a sunset risk. Do not add
  new design dependence on Garnix-only behavior.

## Tooling Boundary

| Surface | Current status | Keep in this PR? | Why |
| --- | --- | --- | --- |
| `maintainers/scripts/ci-nix-build.sh` | CI wrapper around `nix build` | yes | Gives current remote copy/build evidence without changing derivations. |
| `maintainers/scripts/summarize-nix-build-log.mjs` | Parses CI Nix logs and GitHub log downloads | yes | This is useful audit tooling, not product code. It proves fetch/copy/build counts and stays under the 400-line file budget. |
| `maintainers/scripts/summarize-nix-build-closure.mjs` | Build-closure hotspot drill-down | opt-in | Useful when diagnosing cache/upload volume; default CI now leaves it off via `NIX_METER_BUILD_CLOSURE=0`. |
| `maintainers/scripts/summarize-hm-activation-timing.sh` and `maintainers/scripts/summarize-nixos-test-log.mjs` | Linux install/apply timing | yes for now | This directly answers where the Linux install/apply proof spends time. Gate or remove after the next CI-speed pass if it stops paying for itself. |
| `scripts/summarize-nix-eval-jobs.mjs` | Manual cache-status parser | no | Useful locally, but not wired into CI and not required for package correctness or speed. Keep this kind of tool in ignored `.agent/` notes or a separate CI-infra PR. |
| Long per-commit narrative history | Removed from repo ledger | no | It was useful while exploring but made the public repo harder to review. Commit SHAs, CI run ids, and current metrics are enough here. |

## Decision History

| Slice | Decision | Evidence |
| --- | --- | --- |
| npm default package | Accepted | Gateway closure 60.2% smaller; output 84.3% smaller; forced rebuild succeeds in 56.27s instead of failing after 399.37s. |
| source/pnpm default checks | Removed from default gate | Default stable install now uses npm shrinkwrap; source fallback remains for dogfood/source overrides. |
| default CI aggregate split | Accepted | Direct input drvs drop from 48/50 to 11 on Darwin/Linux while explicit optional checks remain addressable. |
| QMD and plugin proof split | Accepted as CI simplification | Optional surfaces stay as explicit checks and stop taxing every default install/apply run. |
| internal-json/eval parser support | Rejected for this PR | Plain timestamped Nix logs answer the current CI question with less code, quieter logs, and fewer meter knobs. |
| Magic Nix Cache | Rejected | Remote experiment made Linux slower and blocked macOS proof startup. |
| larger GitHub runners | Not in this PR | Could reduce wall time, but would not simplify package graph or prove downstream install behavior. Treat as CI-provider tuning after graph cleanup. |
| machine image prebundling | Not in this PR | Potential cold-start win, but provider-specific and orthogonal to Nix package correctness. Revisit after Garnix replacement/cache strategy is chosen. |

## Reproduction Commands

```bash
main_ref=d69b1fc1e736bbe78b46bd886fcc1791b5b9d942
head_ref=fd1904b6b8ea6352569a9694882595052086db3d

nix build --accept-flake-config --no-link --print-out-paths \
  "git+file://$PWD?rev=$main_ref#packages.aarch64-darwin.openclaw-gateway" \
  "git+file://$PWD?rev=$main_ref#packages.aarch64-darwin.openclaw" \
  "git+file://$PWD?rev=$head_ref#packages.aarch64-darwin.openclaw-gateway" \
  "git+file://$PWD?rev=$head_ref#packages.aarch64-darwin.openclaw"

nix path-info -S "$gateway"
du -sk "$gateway"
find "$gateway/lib/openclaw" -name package.json | wc -l
find "$gateway/lib/openclaw" -type f | wc -l

drv=$(nix eval --accept-flake-config --raw \
  "git+file://$PWD?rev=$head_ref#checks.aarch64-darwin.ci.drvPath")
nix derivation show "$drv" | jq '.derivations | to_entries[0].value.inputs.drvs | length'

gh run view 27062082132 --repo openclaw/nix-openclaw --log \
  > /tmp/nix-openclaw-ci-run-27062082132.log
maintainers/scripts/summarize-nix-build-log.mjs \
  --github-log /tmp/nix-openclaw-ci-run-27062082132.log
```
