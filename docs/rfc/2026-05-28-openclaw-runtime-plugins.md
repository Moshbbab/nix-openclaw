# RFC: Declarative OpenClaw Runtime Plugins in nix-openclaw

- Date: 2026-05-28
- Status: Draft
- Audience: OpenClaw and nix-openclaw maintainers

## Executive Model

OpenClaw runtime plugin support has two separable jobs:

1. prepare a plugin directory that already contains the runtime code and dependencies;
2. tell OpenClaw to discover, trust, and start that prepared directory.

Mutable OpenClaw does both through `openclaw plugins install`. nix-openclaw should not run that command or forge its receipts. Nix should do job 1 by producing an immutable plugin root in `/nix/store`. nix-openclaw should do job 2 by rendering normal OpenClaw config: `plugins.load.paths`, `plugins.entries.<id>.enabled = true`, and an allowlist merge only when the user already has a restrictive allowlist.

This boundary drives the rest of the RFC.

## Decision

nix-openclaw will build OpenClaw runtime plugins as immutable Nix store plugin roots and feed those roots to OpenClaw through the existing `plugins.load.paths` mechanism.

That is the right first slice because OpenClaw already supports loading a prepared plugin directory whose dependencies are already present. Nix is good at producing that prepared directory. OpenClaw does not need to pretend `openclaw plugins install` ran.

V1a does need one small OpenClaw Nix-mode compatibility fix: config-origin plugin roots under `/nix/store` must pass the same Nix-store trust policy that OpenClaw already uses for hardlinked plugin files. Without that, remote Linux builders can expose copied Nix store paths as uid `65534`, and OpenClaw blocks the plugin as suspiciously owned even though the root is immutable store content. nix-openclaw carries that patch until OpenClaw upstream has it.

Because load-path plugins have `origin = "config"`, nix-openclaw must also generate the minimal upstream-shaped activation policy for selected runtime plugins:

```json
{
  "plugins": {
    "entries": {
      "slack": { "enabled": true }
    }
  }
}
```

If the user configured a restrictive `plugins.allow`, that same policy also includes the selected runtime plugin id in `plugins.allow`.

Without a rendered activation policy, nix-openclaw would be relying on OpenClaw's runtime auto-enable pass to synthesize one at gateway startup. That is not a declarative contract. The Nix-rendered `openclaw.json` must already say which plugin roots are selected and enabled, so config evaluation, status, and gateway startup all agree before mutable runtime state is involved.

OpenClaw's runtime auto-enable remains useful upstream behavior. nix-openclaw should treat it as a convenience layer, not as the source of truth for Nix-managed runtime plugins.

V1a scope is official OpenClaw runtime packages that need no dependency materialization inside nix-openclaw: packages with no runtime dependencies, or packages whose runtime dependencies are already bundled in the published tarball. Slack is the reported example. Packages that publish a shrinkwrap but still require dependency materialization, such as Codex, are V1b.

User-facing Nix:

```nix
programs.openclaw.runtimePlugins = [
  "slack"
];

programs.openclaw.config = {
  channels.slack = {
    mode = "socket";
    appToken.source = "env";
    appToken.provider = "env";
    appToken.id = "SLACK_APP_TOKEN";
    botToken.source = "env";
    botToken.provider = "env";
    botToken.id = "SLACK_BOT_TOKEN";
  };
};
```

Generated OpenClaw config shape:

```json
{
  "plugins": {
    "load": {
      "paths": [
        "/nix/store/...-openclaw-runtime-plugin-slack"
      ]
    },
    "entries": {
      "slack": { "enabled": true }
    }
  }
}
```

Do not add per-plugin runtime config under `runtimePlugins`. Runtime configuration stays in `programs.openclaw.config`, exactly where upstream OpenClaw defines it.

## Problem

OpenClaw externalized many user-facing integrations into runtime plugins. Slack is only the reported example.

On a mutable install, users run:

```bash
openclaw plugins install @openclaw/slack
```

That mutable command does four jobs:

1. resolves the npm or ClawHub package;
2. installs dependencies into OpenClaw-owned mutable state;
3. records install metadata in `$OPENCLAW_STATE_DIR/plugins/installs.json`;
4. enables and loads the plugin through OpenClaw's plugin registry.

In Nix mode, OpenClaw intentionally disables plugin install/update/uninstall and config mutation. That is correct. nix-openclaw must provide the plugin artifact declaratively.

## Goals and Non-Goals

Goals:

- restore complete-tarball OpenClaw runtime plugins, such as Slack, for nix-openclaw users without mutable installs;
- keep OpenClaw's runtime plugin model intact instead of inventing a parallel Nix-only plugin runtime;
- make plugin selection visible in rendered `openclaw.json`, not hidden in gateway startup heuristics;
- pin official plugin artifacts to the same OpenClaw release pin nix-openclaw already uses;
- make the first shipped builder use exact tarballs, fixed hashes, no semver resolution, and no package manager execution;
- remove or hard-block the current `customPlugins.source = "npm:..."` path before it becomes supported API.

Non-goals for V1a:

- arbitrary npm specs;
- third-party/community runtime plugins;
- ClawHub runtime plugins;
- raw `plugins.load.paths` mixed with `runtimePlugins` in the same instance;
- non-bundled dependency materialization;
- lifecycle scripts or native rebuilds;
- a new upstream OpenClaw install source;
- Nix-aware plugin provenance in OpenClaw status output.

Non-negotiables:

- user builds must not query npm;
- user builds must not run `npm install`, `pnpm`, `yarn`, or `corepack`;
- activation must not mutate OpenClaw plugin state;
- rollback must not leave stale installed-plugin records behind;
- selected runtime plugins must be explicit in the generated config;
- dependencies bundled in a plugin tarball must be reviewable through shrinkwrap-backed validation, not accepted as an opaque `node_modules`.

## What OpenClaw Already Supports

The important split in OpenClaw is:

- install/update commands prepare plugin directories and write mutable install records;
- runtime loading reads already-prepared plugin directories;
- startup and reload do not run package managers.

OpenClaw has two relevant prepared-directory paths today:

1. `plugins.load.paths`: explicit config-selected plugin directories.
2. installed plugin records: mutable install ledger entries whose `installPath` points at a prepared directory.

For Nix, `plugins.load.paths` plus `plugins.entries.<id>.enabled = true` is the better V1a fit. A Nix-built plugin root is an explicit, immutable, already-prepared directory. The generated entry is normal OpenClaw activation policy for a config-origin plugin. Together they match the ownership boundary: Nix prepares and selects the directory; OpenClaw loads and configures it.

This means the earlier "read-only installed index" idea is not required for the complete-tarball fix. It solves provenance and diagnostics, not loading.

There is one subtle upstream behavior worth naming: OpenClaw can auto-enable plugins at runtime when it sees related config, such as a configured channel or provider. Gateway startup applies that pass without writing config. That does not replace Nix activation for four reasons:

1. it is derived runtime config, not rendered declarative config;
2. startup planning still checks the raw activation source config when deciding whether a non-bundled configured-channel plugin is explicitly trusted;
3. it depends on OpenClaw's current auto-enable heuristics, not on the user's Nix selection;
4. for Nix, `runtimePlugins = [ "slack" ]` is the explicit selection and should be visible in generated `plugins.entries`, not inferred later from `channels.slack`.

So V1a uses OpenClaw's prepared-directory loader, but does not use OpenClaw's runtime auto-enable as the primary selection mechanism.

## Why Not Pretend `plugins install` Ran?

Because pretending creates mutable state that Nix cannot own correctly.

| Option | Verdict |
| --- | --- |
| Nix builds a plugin root, adds it to `plugins.load.paths`, and generates `plugins.entries.<id>.enabled = true`. | Selected V1a design. Existing OpenClaw surface, no mutable state, plus one Nix-mode ownership compatibility patch for `/nix/store` roots. |
| Write `plugins.installs` into `openclaw.json`. | Reject. OpenClaw marks this as internal transient command-flow state, omits it from the public schema, strips it on writes, and migrates it toward the installed index. |
| Write `$OPENCLAW_STATE_DIR/plugins/installs.json` during Home Manager activation. | Reject. Rollback would not roll back the mutable ledger. Stale state could claim a plugin is installed after Nix removed it. |
| Fake OpenClaw's npm root under `$OPENCLAW_STATE_DIR/npm`. | Reject. OpenClaw's recovery scan is specifically for mutable npm-root recovery. Nix must not impersonate npm-owned state. |
| Add an upstream read-only installed index now. | Reject for V1a. It improves `origin = nix` provenance and diagnostics, but is not needed to load, validate, or run the plugin when we use generated load paths. |
| Run `openclaw plugins install` during activation, or run networked/semver `npm install` during Nix builds. | Reject. Activation-time mutation and registry resolution are not declarative and widen the supply-chain attack surface. |

OpenClaw can already read a fully assembled plugin folder when config points at it and enables it. Nix makes that folder and emits that normal OpenClaw config. The rejected designs all try to forge OpenClaw's mutable receipt.

## User-Facing Model

`runtimePlugins` declares selected runtime plugin artifacts:

```nix
programs.openclaw.runtimePlugins = [
  "slack"
  "discord"
];
```

For each selected id, nix-openclaw generates:

```nix
programs.openclaw.config.plugins.load.paths = [
  "/nix/store/...-openclaw-runtime-plugin-slack"
];

programs.openclaw.config.plugins.entries.slack.enabled = true;
```

Plugin config remains upstream OpenClaw config. For channel plugins such as Slack, that means `channels.slack`, not `runtimePlugins` and not `plugins.entries.slack.config`.

For plugins that define their own entry config, the config still goes in the upstream location:

```nix
programs.openclaw.config.plugins.entries.somePlugin.config = {
  # OpenClaw-defined plugin entry config fields.
};
```

If the user already has a restrictive plugin allowlist, nix-openclaw adds selected runtime plugin ids to that allowlist. It must not create a restrictive allowlist when the user did not configure one.

```nix
programs.openclaw.config.plugins.allow = [
  # Existing user policy.
  "some-other-plugin"

  # Added by runtimePlugins = [ "slack" ].
  "slack"
];
```

It is an eval error to select a runtime plugin and also disable or deny it in raw OpenClaw config:

```nix
programs.openclaw.runtimePlugins = [ "slack" ];

# Contradiction: remove "slack" from runtimePlugins instead.
programs.openclaw.config.plugins.entries.slack.enabled = false;
programs.openclaw.config.plugins.deny = [ "slack" ];
```

It is also an eval error to:

- list the same `runtimePlugins` id twice;
- select a `runtimePlugins` id that collides with a nix-openclaw-managed plugin id;
- set raw `programs.openclaw.config.plugins.load.paths` in the same instance as `runtimePlugins`.

That raw load-path restriction does not reject load paths generated by nix-openclaw's own plugin contracts. It only blocks unmanaged OpenClaw runtime plugin paths from sharing the supported `runtimePlugins` lane.

Per-instance override:

```nix
programs.openclaw.runtimePlugins = [ "slack" ];

programs.openclaw.instances.work.runtimePlugins = [ "slack" "discord" ];
programs.openclaw.instances.personal.runtimePlugins = [ "discord" ];
```

Top-level `runtimePlugins` is the default for every instance. An instance-level list replaces it.

## Version Pinning Policy

Never use npm `latest` in user builds.

nix-openclaw already pins the OpenClaw source in `nix/sources/openclaw-source.nix`:

```nix
releaseVersion = "2026.5.26";
```

For official `@openclaw/*` runtime plugins, nix-openclaw ties the plugin package version to that OpenClaw release version:

```text
OpenClaw package:      2026.5.26
@openclaw/slack:      2026.5.26
@openclaw/discord:    2026.5.26
```

That is the V1a rule because the official packages are co-versioned with OpenClaw and declare host compatibility against the same release line. For example, `@openclaw/slack@2026.5.26` declares `peerDependencies.openclaw >=2026.5.26`, `openclaw.compat.pluginApi >=2026.5.26`, and runtime entries under `openclaw.runtimeExtensions`.

V1a lock generation does this:

1. read the selected OpenClaw `releaseVersion`;
2. read OpenClaw's official external plugin catalogs: `official-external-channel-catalog.json`, `official-external-provider-catalog.json`, and `official-external-plugin-catalog.json`;
3. for each curated id, map the catalog npm spec to an exact package spec, such as `@openclaw/slack@2026.5.26`;
4. fail if the selected id has no package published for that exact OpenClaw version;
5. record the root tarball URL, npm SRI integrity, and Nix hash;
6. read the package's published `npm-shrinkwrap.json` when present;
7. record the package graph from the shrinkwrap when present: package paths, names, versions, integrity metadata, optional flags, `os`, `cpu`, `bin`, and lifecycle-script metadata;
8. record the declared `dependencies`, `optionalDependencies`, `bundleDependencies`, and `bundledDependencies`;
9. write deterministic lock files under `nix/generated/openclaw-runtime-plugins/`.

The maintainer refresh command lives in `nix/scripts/update-openclaw-runtime-plugin-locks.mjs`. It is allowed to query npm because it is a maintainer lock-update command, not part of user builds. Its output is checked in and reviewed.

Each generated lock entry records:

```nix
{
  id = "slack";
  attrName = "slack";
  packageName = "@openclaw/slack";
  version = "2026.5.26";
  tarballUrl = "https://registry.npmjs.org/@openclaw/slack/-/slack-2026.5.26.tgz";
  npmIntegrity = "sha512-...";
  nixHash = "sha256-...";
  v1aClass = "bundled-dependencies";
  openclawCompat = ">=2026.5.26";
  peerOpenClaw = ">=2026.5.26";
  dependencies = {
    # declared package dependencies
  };
  optionalDependencies = {
    # declared optional dependencies
  };
  bundleDependencies = [
    # declared bundled dependency names
  ];
  shrinkwrapPackages = {
    # shrinkwrap package graph when present
  };
}
```

V1a builds consume the checked-in root lock plus the packaged shrinkwrap. They do not query npm and do not resolve semver. They also do not run npm/pnpm/yarn/corepack because V1a only accepts packages whose published tarball is already complete for runtime loading.

For packages with bundled dependencies, V1a does not fetch each dependency tarball independently. The root package tarball hash is the byte-for-byte authority for the bundled dependency tree. The extracted shrinkwrap graph is a review and validation artifact: it lets the builder reject missing, extra, or mismatched bundled package directories instead of blindly trusting an opaque tarball.

If an official catalog entry is not published for nix-openclaw's pinned OpenClaw version, nix-openclaw does not silently take a newer npm version. That plugin is unavailable for that nix-openclaw release until the OpenClaw pin moves.

Tradeoffs:

| Policy | Verdict |
| --- | --- |
| Tie official plugin versions to OpenClaw `releaseVersion`. | Selected V1a rule. Reproducible, compatible, reviewable. |
| Use npm `latest` or dist-tags. | Reject. Non-reproducible and supply-chain unsafe. |
| Let users write arbitrary npm specs and hashes. | Reject for V1a. Powerful but creates a support surface before the builder and diagnostics are proven. |
| Per-plugin explicit version overrides. | Reject for V1a. Hotfix overrides need their own exact-version policy and proof gates. |
| Third-party/community plugins. | Reject for V1a. They need explicit locks and compatibility policy; do not mix them into official-plugin V1a. |

## Builder

V1a builder: complete official packages.

The first shipped builder supports only packages whose published tarball is already complete enough to load without dependency installation. That includes packages with no runtime dependencies and packages that already publish bundled runtime dependencies. Slack is in the bundled class. This keeps the first fix small: unpack the official tarball, verify it, link the host `openclaw` peer, and expose the result through `plugins.load.paths`.

Example:

```nix
buildOpenClawRuntimePlugin {
  id = "slack";
  packageName = "@openclaw/slack";
  version = "2026.5.26";
  src = fetchurl {
    url = "https://registry.npmjs.org/@openclaw/slack/-/slack-2026.5.26.tgz";
    hash = "sha256-...";
  };
  npmIntegrity = "sha512-...";
  packageLock = ./generated/openclaw-runtime-plugins/slack-2026.5.26.nix;
  openclawPackage = pkgs.openclaw-gateway;
}
```

V1a rules:

1. unpack the root package tarball;
2. verify package name, version, plugin id, runtime entry, npm integrity, and OpenClaw host compatibility;
3. if the package declares runtime dependencies, verify those dependencies are declared as bundled;
4. for packages with runtime dependencies or a bundled `node_modules`, require `npm-shrinkwrap.json`;
5. verify bundled dependency directories are accounted for by the shrinkwrap graph;
6. use `bundleDependencies`/`bundledDependencies` only as a top-level cross-check, not as the dependency graph authority;
7. fail on unexpected bundled package directories or unbundled runtime dependencies;
8. create `node_modules/openclaw -> ${openclawPackage}/lib/openclaw` for packages that declare the `openclaw` peer;
9. verify there are no broken symlinks and the runtime entry exists.

Initial curated package map:

| `runtimePlugins` id | Nix attr | npm package | V1a class |
| --- | --- | --- | --- |
| `slack` | `openclawRuntimePlugins.slack` | `@openclaw/slack` | bundled dependencies |
| `discord` | `openclawRuntimePlugins.discord` | `@openclaw/discord` | bundled dependencies |
| `brave` | `openclawRuntimePlugins.brave` | `@openclaw/brave-plugin` | no runtime dependencies |
| `diagnostics-prometheus` | `openclawRuntimePlugins.diagnosticsPrometheus` | `@openclaw/diagnostics-prometheus` | no runtime dependencies |

Adding another official package to the curated set is a lock update plus the same builder and gateway proof gates. It is not a user-provided version override.

Deferred package class: non-bundled dependencies.

Packages like `@openclaw/codex` publish `npm-shrinkwrap.json` but do not bundle runtime dependencies. That is a separate problem. They are not part of the complete-tarball fix.

The next design must prove one of these before shipping those packages:

- an existing nixpkgs npm-dependency builder can materialize the checked-in lock data offline without lifecycle scripts or mutable package-manager state; or
- a custom materializer can reproduce npm lockfile semantics well enough to be safer than using the existing Nix/npm tooling.

That proof is intentionally outside V1a. Hand-rolling dependency materialization in this RFC would be bigger and riskier than the complete-tarball fix.

The current `customPlugins.source = "npm:..."` bridge must be removed or hard-blocked. `customPlugins` itself remains the nix-openclaw plugin surface for Nix-managed tools and skills; only the npm runtime-plugin bridge is unsafe. It runs `npm install` inside a fixed-output derivation and deletes the lock output after the copy. A recursive output hash proves final bytes, but it does not give maintainers a reviewable dependency graph.

## nix-openclaw Implementation

Add a curated package set:

```nix
pkgs.openclawRuntimePlugins.slack
pkgs.openclawRuntimePlugins.discord
pkgs.openclawRuntimePlugins.brave
pkgs.openclawRuntimePlugins.diagnosticsPrometheus
```

Each package exposes:

```nix
passthru.openclawRuntimePlugin = {
  id = "slack";
  packageName = "@openclaw/slack";
  version = "2026.5.26";
  source = "npm";
  integrity = "sha512-...";
  loadPath = "${finalPackage}";
};
```

The Home Manager module:

1. validates ids in `programs.openclaw.runtimePlugins`;
2. selects the matching package from `pkgs.openclawRuntimePlugins`;
3. prepends each package root to generated `plugins.load.paths`;
4. generates `plugins.entries.<id>.enabled = true` for each selected runtime plugin;
5. if the user already configured `plugins.allow`, merges selected runtime plugin ids into that allowlist;
6. rejects duplicate selected ids and collisions with nix-openclaw-managed plugin ids;
7. rejects raw user-authored `plugins.load.paths` in any instance that uses `runtimePlugins`;
8. sets no plugin-specific runtime config;
9. runs no package manager;
10. runs no OpenClaw plugin mutator;
11. writes no `plugins.installs`;
12. writes no `$OPENCLAW_STATE_DIR/plugins/installs.json`;
13. preserves the existing wrapper invariant `OPENCLAW_NIX_MODE=1` so OpenClaw accepts `/nix/store` plugin roots under the existing hardlink policy.

Target files:

- `nix/modules/home-manager/openclaw/options.nix`: add top-level `runtimePlugins`.
- `nix/modules/home-manager/openclaw/options-instance.nix`: add per-instance `runtimePlugins`.
- `nix/modules/home-manager/openclaw/config.nix`: merge generated load paths into rendered OpenClaw config.
- `nix/modules/home-manager/openclaw/options.nix`: remove or explicitly reject npm-only `customPlugins` fields such as `id`, `hash`, and `enabled`.
- `nix/modules/home-manager/openclaw/plugins.nix`: remove or reject `customPlugins` entries whose source starts with `npm:`.
- `nix/packages/default.nix`: expose `openclawRuntimePlugins`.
- `nix/lib/openclaw-runtime-plugin.nix`: build immutable plugin roots from locks.
- `nix/scripts/update-openclaw-runtime-plugin-locks.mjs`: maintainer lock refresh command.
- `nix/generated/openclaw-runtime-plugins/`: checked-in root tarball and package-graph lock data.
- `nix/checks/`: builder, module-eval, and gateway smoke checks.
- `AGENTS.md`, `README.md`, and `docs/`: remove guidance that presents `customPlugins.source = "npm:..."` as supported.

Implementation order:

1. remove or hard-block `customPlugins.source = "npm:..."`;
2. generate checked-in lock data for the official package ids supported in V1a;
3. add `buildOpenClawRuntimePlugin` for no-dependency and shrinkwrap-verified bundled-dependency packages;
4. expose `pkgs.openclawRuntimePlugins.<id>` for the curated V1a set;
5. add `programs.openclaw.runtimePlugins` and per-instance override support;
6. render load paths, explicit entries, allowlist merges, and contradiction assertions;
7. run the module, builder, and gateway proof gates before documenting the feature as supported.

## When Upstream Changes Become Worth It

A new OpenClaw plugin lifecycle surface is not required for V1a.

That claim depends on two things: the generated OpenClaw config must include both the load path and the explicit plugin entry, and OpenClaw must treat `/nix/store` plugin roots in `OPENCLAW_NIX_MODE=1` as trusted immutable roots for ownership checks. A load path alone is discovery, not a complete gateway-startup policy for config-origin channel plugins.

They become worth doing if V1a proves we need one of these:

- status/list/inspect to display `origin: nix` instead of `origin: config`;
- Nix-specific diagnostics when a Nix-generated load path fails;
- a first-class read-only installed index for Nix-managed provenance;
- OpenClaw docs that describe Nix-managed runtime plugins as a first-party install source.

Those are provenance and diagnostic improvements. They are not the core loading fix.

If we add a read-only installed index, it is an additive OpenClaw input that is ignored outside `OPENCLAW_NIX_MODE=1`. It must never write declarative records back to `plugins/installs.json`.

## What Would Falsify This Design?

The RFC is wrong, and an upstream OpenClaw change becomes required, if any of these are true after implementation:

- OpenClaw cannot discover a valid `/nix/store` plugin root from `plugins.load.paths` in `OPENCLAW_NIX_MODE=1`.
- A config-origin plugin with `plugins.entries.<id>.enabled = true` and any required allowlist entry still cannot be included in the gateway startup plan.
- `openclaw status` or config validation still reports "plugin not installed" when the generated load path is present and the plugin appears in the metadata snapshot.
- Slack's published package for the pinned OpenClaw version is not actually runtime-complete after unpacking and peer-linking OpenClaw.
- rejecting raw `plugins.load.paths` with `runtimePlugins` blocks a legitimate workflow that V1a must support.

Those are the hard gates. If one fails, do not paper over it in nix-openclaw with mutable state. Either narrow V1a further, fix the generated config, or make the smallest upstream change that removes the blocker.

## Supported V1a

Supported:

- curated official OpenClaw runtime plugin ids;
- exact package versions tied to nix-openclaw's OpenClaw release pin;
- complete published tarballs that need no runtime dependency installation;
- bundled runtime dependencies, when present, verified against `npm-shrinkwrap.json`;
- immutable plugin roots in the Nix store;
- loading through generated `plugins.load.paths`;
- runtime config through `programs.openclaw.config`;
- macOS and Linux.

Unsupported:

- arbitrary npm specs;
- arbitrary ClawHub specs;
- git/path runtime plugins through `runtimePlugins`;
- user-authored install records;
- activation-time or runtime plugin installs;
- networked or semver package-manager dependency resolution inside Nix builds;
- non-bundled npm dependency materialization;
- lifecycle scripts and native rebuilds unless explicitly modeled.

## Proof Gates

Before shipping V1a:

1. Run the lock refresh command twice for the curated V1a set and confirm the second run produces no diff.
2. Build every curated V1a package without invoking npm/pnpm/yarn/corepack.
3. Verify bundled package roots such as Slack and Discord have `package.json`, `openclaw.plugin.json`, runtime JS, bundled dependency tree, and `node_modules/openclaw` peer link.
4. Verify no-runtime-dependency packages such as Brave and diagnostics-prometheus do not require bundled dependency metadata.
5. Verify bundled dependency directories match `npm-shrinkwrap.json`; `bundleDependencies` alone is not accepted as graph evidence.
6. Verify packages with runtime dependencies but no bundled dependency tree are rejected as V1b.
7. Evaluate Home Manager config and confirm generated `plugins.load.paths` contains the Nix store plugin root.
8. Evaluate Home Manager config and confirm generated `plugins.entries.slack.enabled = true`.
9. Evaluate Home Manager config with an existing restrictive `plugins.allow` and confirm Slack is added to it.
10. Evaluate Home Manager config with `runtimePlugins = [ "slack" ]` plus `plugins.entries.slack.enabled = false` or `plugins.deny = [ "slack" ]` and confirm it fails with a direct contradiction error.
11. Evaluate Home Manager config with duplicate `runtimePlugins` ids and confirm it fails with a direct duplicate-id error.
12. Evaluate Home Manager config with `runtimePlugins = [ "slack" ]` plus raw `plugins.load.paths` and confirm it fails with a direct unsupported-mix error.
13. Start OpenClaw in `OPENCLAW_NIX_MODE=1` with Slack configured.
14. Verify Slack appears in plugin/channel discovery from the generated load path.
15. Verify the gateway startup plugin plan includes Slack.
16. Verify `openclaw status` does not report Slack as "plugin not installed."
17. Verify config validation accepts Slack channel config when the generated load path is present.
18. Verify Linux and Darwin.
19. Remove or hard-block the current `customPlugins.source = "npm:..."` bridge from public docs and supported paths.

Before shipping V1b:

1. Build `codex` from checked-in lock data with no network access.
2. Prove how lifecycle-script packages in the Codex shrinkwrap are handled.
3. Run runtime import/load checks for the Codex plugin entry.
4. Run the same gateway/status/config-validation checks as V1a.

## Evidence

OpenClaw source:

- `docs/plugins/dependency-resolution.md`: runtime loading does not run package managers; install/update owns dependency work.
- `src/plugins/discovery.ts`: `plugins.load.paths` are discovered as explicit config-origin plugin paths.
- `src/plugins/hardlink-policy.ts`: config-origin plugins under `/nix/store` are allowed in `OPENCLAW_NIX_MODE=1`.
- `src/plugins/config-activation-shared.ts`: non-bundled/config-origin plugins are explicitly selected by `plugins.entries.<id>.enabled = true` or `plugins.allow`.
- `src/plugins/gateway-startup-plugin-ids.ts`: configured channel plugins with non-bundled origins require explicit activation before gateway startup includes them.
- `src/gateway/server-startup-config.ts`: OpenClaw applies plugin auto-enable at gateway startup without writing config; nix-openclaw must not rely on that as its declarative selection source.
- `src/config/plugin-auto-enable.shared.ts`: auto-enable derives activation from configured channels/providers and may materialize effective config; it is a runtime convenience layer, not a Nix-rendered contract.
- `src/plugins/channel-plugin-ids.test.ts`: non-bundled configured-channel owners that are only auto-enabled are not treated as explicitly trusted for startup planning.
- `src/plugins/manifest-registry.ts`: duplicate config-origin load-path plugins get generic config precedence; V1a duplicate handling is a nix-openclaw responsibility.
- `src/channels/plugins/read-only.ts`: channel status/read-only discovery is built from the plugin metadata snapshot and loaded channel plugins.
- `src/config/validation.ts`: known plugin ids come from the plugin registry; missing install hints happen when the plugin is not known.
- `src/plugins/installed-plugin-index-record-reader.ts`: OpenClaw recovery scans the mutable npm root under the state directory, not arbitrary immutable package roots.
- `src/config/types.plugins.ts`: `plugins.installs` is internal transient state and must not be persisted.
- `src/cli/plugins-install-persist.ts`: mutable install commands write installed-plugin records and mutate config.

Published package checks:

- `@openclaw/slack@2026.5.26` has `runtimeExtensions`, `runtimeSetupEntry`, `openclaw.compat.pluginApi >=2026.5.26`, `peerDependencies.openclaw >=2026.5.26`, bundled runtime dependencies, and `npm-shrinkwrap.json`.
- `@openclaw/discord@2026.5.26` has `runtimeExtensions`, `runtimeSetupEntry`, `openclaw.compat.pluginApi >=2026.5.26`, `peerDependencies.openclaw >=2026.5.26`, bundled runtime dependencies, and `npm-shrinkwrap.json`.
- `@openclaw/brave-plugin@2026.5.26` and `@openclaw/diagnostics-prometheus@2026.5.26` have no runtime dependencies; they are V1a candidates even though they have no bundled dependency tree.
- `@openclaw/codex@2026.5.26` and `@openclaw/memory-lancedb@2026.5.26` have runtime dependencies but no bundled dependency tree; they need the later dependency-materialization RFC. `@openclaw/acpx@2026.5.26` has the same external npm shape, but nix-openclaw already consumes ACPX from OpenClaw's built `dist-runtime/extensions/acpx` tree, so its follow-up is a bundled-runtime packaging audit rather than another materialized npm root.

nix-openclaw source:

- `nix/sources/openclaw-source.nix`: current OpenClaw release pin is the source of truth for official plugin versions.
- `nix/modules/home-manager/openclaw/plugins.nix`: current `npm:` custom plugin bridge is marked partial and emits load paths plus entries.
- `nix/scripts/npm-runtime-plugin-install.sh`: current bridge runs npm resolution inside the build and must not become the supported path.
