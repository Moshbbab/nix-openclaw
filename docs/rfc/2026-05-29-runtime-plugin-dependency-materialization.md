# RFC: Materialized Dependencies For Official Runtime Plugins

- Date: 2026-05-29
- Status: Draft
- Audience: OpenClaw and nix-openclaw maintainers

## Executive Model

The first runtime-plugin RFCs make Nix build an immutable plugin root in
`/nix/store` and render normal OpenClaw config so the gateway loads that root.
They only work when the published plugin tarball is already complete: no runtime
dependencies, or a bundled `node_modules` tree.

Some official OpenClaw plugins instead publish an exact
`@openclaw/*@${releaseVersion}` tarball with `npm-shrinkwrap.json`, runtime
dependencies, and no bundled `node_modules`. The missing step is not mutable
OpenClaw plugin installation; it is Nix materializing the locked dependency
tree before OpenClaw starts.

## Decision

Add a second official runtime-plugin build class on generated lock entries:

```nix
materialization.kind = "npm-shrinkwrap";
```

This class is only for official OpenClaw runtime plugins from the pinned
OpenClaw release whose package tarball has runtime dependencies,
`npm-shrinkwrap.json`, no bundled `node_modules`, and no truthy bundled-runtime
dependency marker such as `bundleRuntimeDependencies` or `bundleDependencies`.
False, absent, or empty bundled markers do not prove bundling; extracted
tarball contents and shrinkwrap validation are authoritative.

The user-facing API does not change for ids that pass the proof gate:

```nix
programs.openclaw.runtimePlugins = [
  "memory-lancedb"
];
```

Runtime configuration still stays in upstream OpenClaw config:

```nix
programs.openclaw.config = {
  plugins = {
    slots.memory = "memory-lancedb";
    entries."memory-lancedb" = {
      config.embedding = {
        provider = "openai";
        model = "text-embedding-3-small";
      };
    };
  };
};
```

`runtimePlugins` selects artifacts. It does not become a Nix-only runtime
configuration surface.

## Current Candidates

At pinned OpenClaw `2026.5.26`, after excluding ACPX because nix-openclaw
already consumes the bundled runtime artifact, the materialization candidates
missing from complete-tarball support are:

| id | package | why V1b excludes it |
| --- | --- | --- |
| `memory-lancedb` | `@openclaw/memory-lancedb` | has runtime dependencies, shrinkwrap, no bundled `node_modules`; no lifecycle scripts in the current lock |
| `codex` | `@openclaw/codex` | same package shape, but the current lock has lifecycle-script metadata and must stay skipped until a package-specific proof passes |

Evidence: pinned OpenClaw lists `memory-lancedb` in
`scripts/lib/official-external-plugin-catalog.json` and `codex` in
`scripts/lib/official-external-provider-catalog.json`. Their exact published
tarballs include runtime dependencies and `npm-shrinkwrap.json`, mark runtime
dependencies as not bundled, and do not include `package/node_modules`.

`acpx` is not part of this materialization RFC even though the external catalog
also lists `@openclaw/acpx`. nix-openclaw already treats ACPX as a bundled
OpenClaw runtime artifact from the gateway package's built
`dist-runtime/extensions/acpx` tree. The right ACPX follow-up is a packaging
audit: prove that Nix users can select the bundled ACPX backend through
upstream `acp` config, and fix that bundled path if not. Adding a second
materialized `@openclaw/acpx` root would create two ownership paths for the
same backend.

## Why This Is Not `openclaw plugins install`

Mutable OpenClaw installs choose a source, resolve metadata, install
dependencies into OpenClaw-owned state, write install records, and update plugin
config. nix-openclaw should not emulate that mutable lifecycle.

For this class, source selection is already done by the OpenClaw pin and the
generated runtime-plugin lock. Dependency resolution is already done by the
published shrinkwrap. nix-openclaw should only materialize those exact locked
dependencies into an immutable plugin root and render the same config shape
that V1a already renders.

No activation step runs package managers. No gateway startup step mutates plugin
install state. No user build resolves `latest`, dist-tags, semver ranges, or
ClawHub search results.

## Non-Goals

This RFC does not support arbitrary npm package specs, third-party catalog
entries, ClawHub artifacts, git/path plugins, packages without a checked lock
file, or packages whose generic install requires lifecycle scripts.

If a package cannot be materialized from exact tarball URLs and integrity
entries in its lock file, it is not supported by the generic materializer.

## Builder Contract

### 1. Normalize The Package Root

Start from the exact official plugin tarball recorded in the generated lock.

Validate tar members stay under `package/`, package name/version match the
generated lock, `openclaw.plugin.json.id` matches the runtime plugin id,
runtime entries point to existing files, and `npm-shrinkwrap.json` uses a
supported lockfile version.

Then remove source-workspace-only fields that must not affect runtime
materialization: `devDependencies` and `devDependenciesMeta`. Published
official plugin tarballs currently keep `@openclaw/plugin-sdk = "workspace:*"`
in dev dependencies. Do not edit runtime `dependencies` or
`optionalDependencies`. If `workspace:*` appears anywhere in runtime
dependencies, fail the lock update. Normalize the root package entry in
`npm-shrinkwrap.json` the same way, and fail on `workspace:`, `file:`, `link:`,
or `git:` specs in any runtime dependency field.

### 2. Materialize The Locked Runtime Dependencies

Use the normalized, checked-in `npm-shrinkwrap.json` as the source of truth.
Preferred implementation:

- import the shrinkwrap with nixpkgs `importNpmLock`;
- fetch every dependency tarball from a supported `resolved` URL, initially
  HTTPS `registry.npmjs.org` tarballs only, with its lockfile `integrity`;
- assemble `node_modules` from those fixed Nix store inputs.

Required build invariants: no network access, registry metadata lookup,
lifecycle scripts, dependency versions outside the shrinkwrap, dependency
tarballs without integrity hashes, or generated mutable install records. If
nixpkgs hooks are used, both install and rebuild must run with scripts disabled,
or rebuild must be disabled entirely. The check suite must include a fixture
whose lifecycle script fails the build if it runs.
`lifecycleScriptPackages` is derived from shrinkwrap `hasInstallScript` flags
and dependency package manifests, then drift-checked.

Direct `buildNpmPackage` over the raw published tarball is not sufficient. It
sees source-workspace dev dependencies such as `workspace:*` before the plugin
package can be normalized. The materializer needs an explicit normalized source
stage first. Do not use import-from-derivation to create that normalized input;
the generator writes the normalized `package.json` and `npm-shrinkwrap.json` to
`nix/generated/openclaw-runtime-plugins/<id>/`.

### 3. Assemble The Plugin Root

The final derivation copies the normalized package root and materialized
`node_modules` into one immutable output, then checks package identity, manifest
id, OpenClaw compat, runtime entries, dependency roots, non-escaping symlinks,
and `passthru.openclawRuntimePlugin.loadPath`.

## Generated Lock Shape

The existing generated lock entries should grow an exhaustive materialization
section only when needed. This abbreviated example omits some package roots:

```nix
{
  id = "memory-lancedb";
  packageName = "@openclaw/memory-lancedb";
  version = "2026.5.26";
  tarballUrl = "https://registry.npmjs.org/@openclaw/memory-lancedb/-/memory-lancedb-2026.5.26.tgz";
  npmIntegrity = "...";
  nixHash = "...";

  materialization = {
    kind = "npm-shrinkwrap";
    normalizedPackageJson = ./memory-lancedb/package.json;
    normalizedShrinkwrap = ./memory-lancedb/npm-shrinkwrap.json;
    shrinkwrapHash = "...";
    lockfileVersion = 3;
    packageCount = 39;
    lifecycleScriptPackages = [ ];
    platformOptionalPackages = [
      "node_modules/@lancedb/lancedb-darwin-arm64"
      "node_modules/@lancedb/lancedb-linux-x64-gnu"
    ];
    materializedPackageRoots = [
      "node_modules/@lancedb/lancedb"
      "node_modules/apache-arrow"
    ];
  };
}
```

The generator also writes `nix/generated/openclaw-runtime-plugins/report.json`
with supported ids, skipped ids, drift failures, and proof summaries.

Do not add an id to `runtimePlugins` support until the package-specific proof
gate passes on both Linux and Darwin.

## Candidate-Specific Notes

`memory-lancedb` is the best first package for this RFC. A local Darwin proof
showed that a normalized package root plus `importNpmLock.buildNodeModules` can
materialize its shrinkwrapped dependencies without using the mutable OpenClaw
plugin lifecycle.

`codex` stays in this RFC as a skipped candidate. Its closure includes
install-script metadata and platform fan-out. Do not ship it just because
evaluation passes; it launches an external agent runtime, so script policy,
runtime import, and a minimal configured smoke test are mandatory.

## User-Facing Documentation

The README should keep one install section for OpenClaw runtime plugins. Do not
split users by build class. `runtimePlugins` renders
`plugins.entries.<id>.enabled = true`; users only write plugin-specific runtime
settings.

Good after `memory-lancedb` appears in the generated supported lock set:

```nix
programs.openclaw.runtimePlugins = [
  "memory-lancedb"
];

programs.openclaw.config.plugins = {
  slots.memory = "memory-lancedb";
  entries."memory-lancedb" = {
    config.embedding = {
      provider = "openai";
      model = "text-embedding-3-small";
    };
  };
};
```

Future only after `codex` appears in the generated supported lock set:

```nix
programs.openclaw.runtimePlugins = [
  "codex"
];

programs.openclaw.config.agents.defaults.model = "openai/gpt-5.5";
```

Bad:

```bash
openclaw plugins install @openclaw/codex
```

Bad:

```nix
programs.openclaw.runtimePlugins.codex.config = { };
```

The docs should say that nix-openclaw builds the plugin and locked dependencies
into `/nix/store`, then points OpenClaw at that immutable plugin root through
normal OpenClaw config.

## Tests And Proof Gates

Evaluation tests:

- `runtimePlugins = [ "memory-lancedb" ]` renders a load path and enabled
  plugin entry;
- `runtimePlugins = [ "codex" ]` keeps failing until the generated supported
  lock set includes `codex`;
- duplicate, denied, disabled, and raw-load-path conflicts still fail;
- materialized plugins use the same per-instance override semantics as V1a.

Builder tests:

- normalized source removes dev-only `workspace:*` fields;
- runtime `workspace:*` fields fail;
- missing `npm-shrinkwrap.json` fails;
- dependency lock entries without integrity fail;
- unsupported `resolved` values fail;
- non-empty `lifecycleScriptPackages` skips the generic materializer unless a
  package-specific derivation is explicitly reviewed;
- lifecycle script packages are reported;
- final plugin root contains expected `node_modules` package roots;
- final plugin root has no broken symlinks or escaping symlinks.

Runtime proof:

- build each enabled candidate on Linux and Darwin;
- run `openclaw plugins list --json` against generated config and confirm the
  plugin is enabled, config-origin, and dependency-clean, including
  `dependencyStatus.requiredInstalled == true`;
- run `openclaw plugins inspect <id> --runtime --json` and confirm runtime
  registrations are present;
- for `memory-lancedb`, run a minimal memory backend smoke test;
- for `codex`, run a minimal Codex harness discovery or dry-run smoke test.

CI should not claim support for a materialized plugin id until the full proof
gate passes for that id.

## Implementation Order

1. Extend generated locks with `materialization.kind`.
2. Generate normalized package inputs and `report.json` without exporting new
   supported ids.
3. Add normalized package source derivation and shrinkwrap materialization.
4. Validate `materializedPackageRoots` in the runtime-plugin installer.
5. Enable `memory-lancedb` after Linux and Darwin proofs pass.
6. Attempt `codex`; if it needs lifecycle scripts or bespoke wrapping, keep it
   skipped with an explicit generated reason and open a package-specific RFC.
7. Update README supported ids only for ids whose proof gates pass.
8. Add CI aggregate builds for materialized plugin packages.

## Alternatives Rejected

### Run `openclaw plugins install` In Activation

Rejected. That writes mutable OpenClaw state and reintroduces npm/ClawHub
installation into a Nix-managed lifecycle.

### Accept User-Supplied npm Specs

Rejected for this RFC. The whole point of this slice is official packages tied
to the pinned OpenClaw release. Arbitrary npm needs its own exact-version,
exact-hash trust model.

### Use Raw `buildNpmPackage` Directly On Plugin Tarballs

Rejected as the generic design. The published official plugin tarballs can
contain source-workspace dev dependencies such as `@openclaw/plugin-sdk =
"workspace:*"`. Those are not runtime dependencies and must be normalized away
before dependency materialization.

### Copy Dependencies From The OpenClaw Gateway Package

Rejected as the primary design. The gateway package may contain many workspace
dependencies, but using its installed `node_modules` as the source of truth
would couple external plugin packages to a build-layout accident. The package's
own shrinkwrap is the clearer source of truth.

## Version And Drift Policy

For a fixed OpenClaw `releaseVersion`, lock regeneration must fail closed if any
materialized candidate changes tarball URL, npm integrity, Nix hash, normalized
source hash, shrinkwrap hash, dependency `resolved`/`integrity` graph,
lifecycle-script list, platform optional list, or materialized package-root
list. The failure belongs in `report.json.driftFailed`; it must not silently
rewrite the supported lock.

## Security Boundary

This RFC still packages JavaScript plugin code. It does not prove that plugin
code is harmless.

It does prove a narrower supply-chain boundary:

- plugin package versions come from the pinned OpenClaw release;
- dependency versions and tarball integrity come from the package shrinkwrap;
- user builds do not resolve semver or registry dist-tags;
- generic materialization does not run lifecycle scripts;
- runtime and activation do not run package managers.

If a plugin needs a lifecycle script to work, that is not a generic
materializer feature. It requires a reviewed package-specific derivation that
states exactly what script behavior is being replaced or allowed.

## Open Questions

These are implementation proof questions, not product questions:

- Can `codex` be materialized without npm requesting registry metadata in
  offline mode after lock normalization?
- Does `memory-lancedb` need platform-pruned dependency locks to avoid carrying
  irrelevant native packages, or is the full optional package fan-out acceptable
  for the first slice?
- Does the existing bundled ACPX path fully satisfy Nix users who configure
  `acp.backend = "acpx"`, or does it need a separate packaging fix?

The answers decide which ids ship first. They do not change the API.
