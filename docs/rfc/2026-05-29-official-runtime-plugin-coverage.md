# RFC: Complete Official OpenClaw Runtime Plugin Coverage

- Date: 2026-05-29
- Status: Draft
- Audience: OpenClaw and nix-openclaw maintainers

## Executive Model

The first runtime-plugin RFC proved the ownership model:

1. Nix builds an immutable plugin root.
2. nix-openclaw renders normal OpenClaw config that points at that root.
3. OpenClaw discovers and loads the plugin through its existing plugin loader.

V1b should not change that model. It should remove the artificial four-plugin
ceiling by generating support for the OpenClaw-owned official external plugins
that already fit this model at the pinned OpenClaw release.

The exact boundary:

> Support every `source = "official"` external runtime plugin in the pinned
> OpenClaw source whose exact `@openclaw/*@${releaseVersion}` npm tarball exists
> and is already self-contained.

This intentionally does not solve arbitrary npm, ClawHub artifacts,
third-party catalog entries, or packages that still need dependency
materialization.

## Decision

Replace the hardcoded V1a `runtimePlugins` list with a generated lock set
derived from the pinned OpenClaw source plus exact npm tarballs.

User-facing config stays the same:

```nix
programs.openclaw.runtimePlugins = [
  "slack"
  "whatsapp"
  "matrix"
  "voice-call"
];

programs.openclaw.config = {
  channels.whatsapp.enabled = true;
  channels.matrix.enabled = true;

  plugins.entries.voice-call.config = {
    provider = "twilio";
  };
};
```

`runtimePlugins` only selects plugin artifacts. Runtime configuration stays in
upstream OpenClaw config:

- channel plugins: `channels.<id>`;
- provider/tool/plugin settings: `plugins.entries.<id>.config`;
- plugin trust policy: `plugins.entries.<id>.hooks`, `subagent`, `llm`, `env`,
  `apiKey`, and the existing OpenClaw fields.

Do not add a Nix-only per-plugin config surface.

## What "All Built-In Plugins" Means

OpenClaw's generated plugin inventory has three classes:

1. **Core npm package plugins** are already included in the `openclaw` package.
   nix-openclaw should not make users list these in `runtimePlugins`.
2. **Official external packages** are OpenClaw-owned plugins omitted from the
   core package and installed on mutable OpenClaw with `openclaw plugins
   install`. This is the real nix-openclaw gap.
3. **Source checkout only** plugins are repo-local QA/dev plugins. They are not
   packaged runtime artifacts and are not user-facing nix-openclaw support
   targets.

So V1b does not mean "make every core plugin installable." Core plugins are
already present. V1b means "complete the official external package coverage
that can be represented as immutable Nix-built plugin roots."

## Current State At The Pin

nix-openclaw currently pins OpenClaw `releaseVersion = "2026.5.26"`.

The V1a implementation supports four ids:

```nix
[
  "brave"
  "diagnostics-prometheus"
  "discord"
  "slack"
]
```

The pinned OpenClaw source's official external catalogs expose 30
OpenClaw-owned official external entries:

- 4 are already supported by V1a;
- 23 more are published at `2026.5.26` and should be eligible if their tarballs
  pass the self-contained package invariant;
- 3 are published but require dependency materialization and stay deferred.

Current upstream `main` has two additional official external entries
(`diffs-language-pack`, `pixverse`). They are useful watchlist data, but they
are not V1b generator input until nix-openclaw advances its OpenClaw pin.

## V1b Candidate Set

These ids should be generated as supported if their exact tarballs pass
validation.

| id | npm package | class |
| --- | --- | --- |
| `brave` | `@openclaw/brave-plugin` | existing V1a |
| `diagnostics-prometheus` | `@openclaw/diagnostics-prometheus` | existing V1a |
| `discord` | `@openclaw/discord` | existing V1a |
| `slack` | `@openclaw/slack` | existing V1a |
| `amazon-bedrock` | `@openclaw/amazon-bedrock-provider` | new V1b |
| `amazon-bedrock-mantle` | `@openclaw/amazon-bedrock-mantle-provider` | new V1b |
| `anthropic-vertex` | `@openclaw/anthropic-vertex-provider` | new V1b |
| `diagnostics-otel` | `@openclaw/diagnostics-otel` | new V1b |
| `diffs` | `@openclaw/diffs` | new V1b |
| `feishu` | `@openclaw/feishu` | new V1b |
| `google-meet` | `@openclaw/google-meet` | new V1b |
| `googlechat` | `@openclaw/googlechat` | new V1b |
| `line` | `@openclaw/line` | new V1b |
| `lobster` | `@openclaw/lobster` | new V1b |
| `matrix` | `@openclaw/matrix` | new V1b |
| `msteams` | `@openclaw/msteams` | new V1b |
| `nextcloud-talk` | `@openclaw/nextcloud-talk` | new V1b |
| `nostr` | `@openclaw/nostr` | new V1b |
| `openshell` | `@openclaw/openshell-sandbox` | new V1b |
| `qqbot` | `@openclaw/qqbot` | new V1b |
| `synology-chat` | `@openclaw/synology-chat` | new V1b |
| `tlon` | `@openclaw/tlon` | new V1b |
| `twitch` | `@openclaw/twitch` | new V1b |
| `voice-call` | `@openclaw/voice-call` | new V1b |
| `whatsapp` | `@openclaw/whatsapp` | new V1b |
| `zalo` | `@openclaw/zalo` | new V1b |
| `zalouser` | `@openclaw/zalouser` | new V1b |

This table is not a hand-maintained support promise. The generated lock set is
the support promise. If the generator cannot prove an id, it must skip the id
and record the reason.

## Deferred Classes

### Dependency Materialization Required

These official external plugins are published at `2026.5.26`, but their
tarballs do not bundle all runtime dependencies:

```nix
[
  "acpx"
  "codex"
  "memory-lancedb"
]
```

They need a separate RFC because the builder must decide how to produce
`node_modules` reproducibly without running registry resolution during user
builds. That is a different problem from copying a self-contained package root
into the Nix store.

Do not smuggle that into V1b.

### Current-Main Watchlist

These entries exist in current OpenClaw `main` but not in the pinned source used
by nix-openclaw today:

```nix
[
  "diffs-language-pack"
  "pixverse"
]
```

They become normal candidates when nix-openclaw advances the OpenClaw pin and
the exact release artifacts exist. The V1b generator should not consult current
upstream `main`; it should use the pinned source only.

### Third-Party Catalog Entries

OpenClaw's external catalog also includes trusted third-party entries such as
WeCom, Yuanbao, and Weixin:

```nix
[
  "wecom-openclaw-plugin"
  "openclaw-plugin-yuanbao"
  "openclaw-weixin"
]
```

Their versions are not tied to OpenClaw's release version. Their trust anchor
is the catalog's exact version and integrity metadata, not
`@openclaw/<package>@${releaseVersion}`. They need a separate catalog-pinned
third-party RFC.

## Candidate Algorithm

The lock updater should use only pinned-source inputs and deterministic filters.

Pseudo-code:

```text
releaseVersion = nix/sources/openclaw-source.nix.releaseVersion
catalogs = pinnedOpenClawSource/scripts/lib/official-external-*.json

for entry in catalogs:
  if entry.source != "official":
    skip "third-party-catalog-entry"

  install = entry.openclaw.install
  if install.npmSpec is missing:
    skip "no-npm-source-in-v1b"

  if install.npmSpec package name is not in the @openclaw scope:
    skip "non-openclaw-npm-source-in-v1b"

  if install.npmSpec has a selector and selector != releaseVersion:
    skip "npm-selector-not-release-version"

  if install.npmSpec has a tag, range, protocol, alias, file path, or URL:
    skip "unsupported-npm-spec-shape"

  id =
    entry.openclaw.plugin.id
    or entry.openclaw.channel.id
    or entry.openclaw.providers[0].id
  if id is missing:
    skip "missing-plugin-id"

  if semver.satisfies(releaseVersion, install.minHostVersion) is false:
    skip "min-host-version-not-satisfied"

  packageName = package name parsed from install.npmSpec
  targetVersion = releaseVersion
  npmVersion = npm registry metadata for packageName at targetVersion
  if npmVersion is missing:
    skip "missing-pinned-npm-version"

  tarball = npmVersion.dist.tarball
  lock = inspect tarball

  if lock.packageJson.name != packageName:
    skip "package-name-mismatch"
  if lock.packageJson.version != releaseVersion:
    skip "package-version-mismatch"
  if lock.manifest.id != id:
    skip "plugin-id-mismatch"
  if peer/compat ranges do not accept the pinned OpenClaw package:
    skip "host-compatibility-mismatch"
  if package is not self-contained:
    skip "dependency-materialization-required"

  write supported lock entry
```

Hyphenated ids keep their user-facing id. Nix attr names may be generated by
camel-casing or by quoting attr names, but the mapping must be stable and
stored in the lock.

Stale generated lock files must be deleted when an id is no longer supported.

Use `node-semver` semantics for `install.minHostVersion`,
`peerDependencies.openclaw`, and `packageJson.openclaw.compat.pluginApi`.
Prerelease handling should follow `node-semver`; do not implement ad hoc string
comparison for date-like OpenClaw versions.

If the updater remains a standalone Node script, the Nix app wrapper should
provide the semver implementation. If semver is unavailable, the updater should
fail closed instead of treating ranges as satisfied.

## Self-Contained Package Invariant

A package is self-contained when the extracted npm tarball already contains
everything needed for OpenClaw to import its runtime entries, except for the
`openclaw` peer symlink that nix-openclaw intentionally points at the packaged
gateway.

For V1b, the updater should classify a package as self-contained only if:

- runtime entries from `package.json.openclaw.runtimeExtensions` and
  `runtimeSetupEntry` are relative paths inside the plugin root and exist;
- every `dependencies` and `optionalDependencies` package root is present in
  `node_modules`;
- `bundleDependencies` or `bundledDependencies` names cover the runtime
  dependency set when dependencies exist;
- `npm-shrinkwrap.json` exists when runtime dependencies exist;
- every bundled `node_modules` package root has a matching shrinkwrap package
  entry;
- every shrinkwrap runtime package entry records name, version, resolved URL,
  integrity, optional/dev flags, os/cpu constraints, bin metadata, and
  lifecycle-script flags;
- the extracted tarball contains no extra `node_modules` package roots outside
  the checked shrinkwrap graph;
- symlinks stay inside the plugin root except for the intentional `openclaw`
  peer link.

If that predicate fails, the package is not supported by V1b. The report should
say `dependency-materialization-required` or the more specific validation
failure.

This is deliberately conservative for optional and platform-gated
dependencies. If a package relies on missing optional dependency roots being
resolved differently per platform, V1b should skip it and leave it for the
dependency materialization RFC.

## Lock Schema

Each generated lock entry should include at least:

```nix
{
  id = "matrix";
  attrName = "matrix";
  packageName = "@openclaw/matrix";
  version = "2026.5.26";
  tarballUrl = "https://registry.npmjs.org/@openclaw/matrix/-/matrix-2026.5.26.tgz";
  npmIntegrity = "sha512-...";
  npmShasum = "...";
  nixHash = "sha256-...";
  manifestId = "matrix";
  catalogSource = "official";
  catalogKind = "channel";
  catalogDefaultChoice = "clawhub";
  openclawCompat = ">=2026.5.26";
  peerOpenClaw = ">=2026.5.26";
  runtimeExtensions = [ "./dist/index.js" ];
  runtimeSetupEntry = "./dist/setup-entry.js";
  providers = [ ];
  channels = [ "matrix" ];
  contracts = { };
  dependencies = { };
  optionalDependencies = { };
  bundleDependencies = [ ];
  bundledPackageRoots = [ ];
  shrinkwrapPackages = { };
}
```

`shrinkwrapPackages` is intentionally more detailed than V1a's
`bundledPackageRoots`. It is the audit surface for dependency graph drift.

## Version And Drift Policy

Official external plugin versions are tied to the pinned OpenClaw release.

For a nix-openclaw pin with:

```nix
releaseVersion = "2026.5.26";
```

the updater attempts:

```text
<npm package>@2026.5.26
```

It does not use npm `latest`, npm `beta`, OpenClaw update channel defaults, or
ClawHub default choices during user builds.

If `releaseVersion` did not change, an existing generated lock entry must not
change. Any drift in tarball URL, npm integrity, shasum, Nix hash, manifest id,
runtime entries, peer/compat ranges, dependency metadata, shrinkwrap graph, or
bundled roots is a hard failure. Do not silently bless same-version registry
drift.

New lock entries for previously unsupported ids are allowed when V1b expands
coverage, but they must be visibly new in the generated report. They are not
"drift" because no prior checked-in lock existed for that id.

If registry drift is real, the maintainer response is a dedicated incident
commit or an OpenClaw pin update, not an automatic updater rewrite.

## ClawHub-Preferred Official Plugins

Some OpenClaw-owned official entries, such as Matrix and WhatsApp, prefer
ClawHub in mutable OpenClaw but also publish npm packages.

V1b's trust base is:

- the pinned OpenClaw source saying this is an official external plugin;
- the exact npm package name from that source;
- the exact npm version equal to the OpenClaw release;
- npm integrity, shasum, and Nix hash recorded in the lock;
- builder validation of the extracted runtime plugin root.

V1b does not query ClawHub, consume ClawHub verdicts, or compare npm and ClawHub
artifacts. If OpenClaw removes the npm spec or requires ClawHub-only semantics
for a plugin, that plugin becomes unsupported until the ClawHub artifact RFC.

This is a Nix source-selection decision. It is not a claim that mutable
OpenClaw should prefer npm.

## Generated Artifacts

V1b should make generated ownership explicit:

- `nix/generated/openclaw-runtime-plugins/*.nix`: one lock per supported id.
- `nix/generated/openclaw-runtime-plugins/default.nix`: imports every supported
  lock.
- `nix/generated/openclaw-runtime-plugins/report.json`: deterministic report
  with `supported`, `skipped`, and `driftFailed` sections.
- README supported-id table: generated or checked against the lock set.

The report should include id, package name, catalog file/class, target version,
status, and skip reason. CI should fail if regenerating locks or docs changes
the tree.

`flake.nix` should expose runtime plugin packages from the generated package
set, not from a hand-maintained four-id list.

Report shape:

```json
{
  "releaseVersion": "2026.5.26",
  "openclawRev": "10ad3aa16068baa84a1bd9ac4f7d42ae725cedb7",
  "supported": [
    {
      "id": "matrix",
      "packageName": "@openclaw/matrix",
      "version": "2026.5.26",
      "catalog": "official-external-channel-catalog.json",
      "status": "supported"
    }
  ],
  "skipped": [
    {
      "id": "codex",
      "packageName": "@openclaw/codex",
      "reason": "dependency-materialization-required"
    },
    {
      "id": "openclaw-weixin",
      "packageName": "@tencent-weixin/openclaw-weixin",
      "reason": "third-party-catalog-entry"
    }
  ],
  "driftFailed": []
}
```

Reason strings are part of the check contract. Tests should assert them.

## Updater Interface

Expose the updater as a flake app:

```bash
nix run .#update-openclaw-runtime-plugin-locks
nix run .#update-openclaw-runtime-plugin-locks -- --check
```

The flake app should pass the pinned OpenClaw source path to the Node script,
for example through `OPENCLAW_PINNED_SOURCE`. The source path should come from
the same `fetchFromGitHub` input used by the packaged gateway, not from a local
checkout and not from current upstream `main`.

`--check` regenerates locks, report, and generated docs into a temporary
directory and fails if they differ from the checked-in files. Normal update
mode writes the generated files and deletes stale generated lock files.

## User-Facing Documentation

The README should show three examples:

1. Slack or Discord channel plugin, because that was the original user pain.
2. WhatsApp or Matrix, because these are ClawHub-preferred upstream but
   Nix-selected as exact npm tarballs in V1b.
3. Voice-call or Brave, because not every runtime plugin is a channel plugin.

Each example should repeat the rule: `runtimePlugins` installs/selects the
artifact; runtime config stays in upstream OpenClaw config.

The docs should not claim support for any id that is not in the generated lock
set.

## Implementation Plan

1. Teach the lock updater to read the pinned OpenClaw source catalogs.
2. Implement the deterministic candidate algorithm and skip report.
3. Extend lock generation with `shrinkwrapPackages` and drift checks.
4. Regenerate runtime plugin locks and delete stale generated lock files.
5. Expose runtime plugin packages from the generated package set in `flake.nix`.
6. Keep the existing Home Manager option and generated OpenClaw config shape.
7. Update README docs from or against the generated lock set.
8. Extend eval tests so every generated id is accepted and deferred ids such as
   `codex` fail with useful messages.
9. Build every generated runtime plugin package in the CI aggregate.
10. Add a runtime-load proof for all generated ids.

## Runtime Proof Fixture

The runtime proof has two layers:

1. cold registry discovery for every generated id;
2. runtime import/registration for every generated id.

Both layers should avoid credentials and networked service startup.

Cold discovery fixture:

```json
{
  "plugins": {
    "load": {
      "paths": [
        "/nix/store/...-openclaw-runtime-plugin-slack",
        "/nix/store/...-openclaw-runtime-plugin-whatsapp"
      ]
    },
    "entries": {
      "slack": { "enabled": true },
      "whatsapp": { "enabled": true }
    }
  }
}
```

Command:

```bash
OPENCLAW_NIX_MODE=1 \
OPENCLAW_CONFIG_PATH="$fixture/openclaw.json" \
openclaw plugins list --json
```

Assertions:

- every generated id appears exactly once;
- every generated id has `origin = "config"`;
- every generated id has `enabled = true`;
- every generated id has `status = "loaded"`;
- provider ids, channel ids, and contract ids from the manifest appear in the
  JSON when the plugin declares them;
- no diagnostic reports blocked ownership, missing runtime entries, missing
  bundled dependencies, invalid symlinks, or host compatibility failure.

Runtime import command:

```bash
OPENCLAW_NIX_MODE=1 \
OPENCLAW_CONFIG_PATH="$fixture/openclaw.json" \
openclaw plugins inspect "$id" --runtime --json
```

Run this once per generated id. It must prove the plugin can import and
register its runtime surfaces without requiring credentials, network calls,
service startup, or host-tool checks during inspection.

Runtime assertions:

- the inspected id matches the selected plugin id;
- native runtime import succeeds;
- provider, channel, tool, skill, command, hook, service, and gateway-method
  surfaces reported by OpenClaw match the plugin manifest/runtime metadata;
- missing user credentials are reported only as inert config/setup state, not as
  runtime import failure;
- no diagnostic indicates network access, subprocess startup, mutable install
  repair, or host package-manager work.

If any plugin performs credential checks, network calls, service startup, or
host-tool checks during cold discovery or runtime inspection, that is either an
OpenClaw plugin bug or a reason to skip that plugin from V1b until its cold-load
behavior is fixed.

## Proof Gates

Minimum gates for V1b:

```bash
nix fmt
git diff --check
nix build --no-link .#checks.aarch64-darwin.ci .#checks.x86_64-linux.ci
nix flake check --no-build
```

Runtime-specific gates:

- `nix run .#update-openclaw-runtime-plugin-locks -- --check` leaves the tree
  unchanged;
- every `.#packages.<system>.openclaw-runtime-plugin-*` package builds;
- generated report and README supported-id table agree with the generated lock
  set;
- Home Manager evaluation accepts every supported id;
- Home Manager evaluation rejects deferred ids such as `codex`,
  `memory-lancedb`, `openclaw-weixin`, and arbitrary unknown ids with direct
  messages;
- `openclaw plugins list --json` passes the cold discovery proof on
  Darwin and Linux;
- `openclaw plugins inspect <id> --runtime --json` passes the runtime import
  proof for every supported id on Darwin and Linux.

## What Would Falsify This Design?

- A candidate package does not publish an exact version matching the OpenClaw
  release pin.
- A candidate package requires dependency installation instead of shipping a
  self-contained runtime tarball.
- A candidate plugin runs side effects during cold plugin-list discovery.
- The generated docs drift from the generated package set.
- OpenClaw changes official external metadata so npm tarballs are no longer a
  valid source for ClawHub-preferred official plugins.
- Same-version npm registry metadata or tarball bytes drift after a lock is
  already checked in.

If any of these happen, the right response is to narrow the generated set and
name the skipped reason. Do not run package managers in user builds. Do not
write mutable OpenClaw install receipts.

## Threat Boundary

V1b prevents:

- mutable `openclaw plugins install` during activation;
- npm, pnpm, yarn, corepack, or ClawHub network access during user builds;
- semver, dist-tag, or update-channel resolution during user builds;
- silent same-version registry drift in generated locks.

V1b does not prove plugin code is harmless. OpenClaw runtime plugins are code.
Users still choose which plugin ids to enable and which trust permissions to
grant under upstream OpenClaw config.

## Future RFCs

1. **Dependency materialization RFC** for `codex`, `memory-lancedb`, and any
   future official package whose tarball is not self-contained. ACPX is a
   separate bundled-runtime packaging audit because nix-openclaw already
   consumes it from OpenClaw's built `dist-runtime/extensions/acpx` tree.
2. **ClawHub artifact RFC** for packages where the correct Nix source should be
   a ClawHub artifact, including verdict metadata and artifact hashes.
3. **Catalog-pinned third-party RFC** for WeCom, Yuanbao, Weixin, and similar
   trusted catalog entries with exact versions and integrity metadata.
4. **Arbitrary npm RFC** for user-selected npm package specs. This must require
   exact versions and hashes; it must not accept `latest` or runtime registry
   resolution.

## Evidence

- OpenClaw `docs/plugins/plugin-inventory.md`: generated inventory defines core
  npm package, official external package, and source checkout only.
- OpenClaw `scripts/lib/official-external-*-catalog.json`: install metadata for
  official external channels, providers, and plugins.
- OpenClaw `src/plugins/official-external-plugin-catalog.ts`: runtime helper
  resolves official external ids, labels, install specs, and package lookups
  from the catalog files.
- OpenClaw `docs/tools/plugin.md`: mutable OpenClaw supports ClawHub, npm, git,
  local path, and marketplace installs, but treats plugin installs as running
  code and recommends pinned versions for reproducible production.
- OpenClaw `docs/gateway/configuration-reference.md`: runtime plugin config
  lives in `plugins.entries.<id>.config`, while channel runtime settings live
  under `channels.<id>`.
- nix-openclaw `nix/scripts/update-openclaw-runtime-plugin-locks.mjs`: current
  V1a lock updater is hardcoded to four curated ids and validates exact npm
  tarballs into generated Nix locks.
- npm registry check on 2026-05-29 against nix-openclaw's pinned
  `releaseVersion = "2026.5.26"`: the pinned official external catalog has 30
  OpenClaw-owned entries; 27 can be candidates for the self-contained tarball
  path; 3 require dependency materialization.
