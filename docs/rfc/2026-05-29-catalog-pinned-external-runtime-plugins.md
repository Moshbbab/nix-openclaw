# RFC: Catalog-Pinned External Runtime Plugins

- Date: 2026-05-29
- Status: Draft
- Audience: OpenClaw and nix-openclaw maintainers

## Executive Model

OpenClaw has a small class of external runtime plugins that are not owned by the
OpenClaw npm org but are listed in the pinned OpenClaw catalog with exact npm
versions and `expectedIntegrity`.

These are not arbitrary npm plugins. OpenClaw has already chosen the package,
version, plugin id, channel metadata, and expected root tarball integrity in
source control.

That root pin is not enough to make the current packages buildable in Nix. The
current external candidates have runtime dependencies, no bundled
`node_modules`, and no package-owned lock file. Supporting them would require a
deterministic dependency lock for third-party transitive packages, not npm
install during activation or build.

So this RFC's first implementation is report-only: classify catalog-pinned
external plugin candidates, prove why they are skipped today, and define the
source/trust contract for the later dependency-lock RFC.

## Decision

Add a generated runtime-plugin source classification:

```nix
source.kind = "catalog-pinned-npm";
```

For now, this class does not add supported runtime plugin ids unless a candidate
also fits an already-proven builder. At the current OpenClaw pin, all known
external candidates should be skipped as `dependency-lock-missing`.

The user-facing API shape after a future proof gate still stays the same:

```nix
programs.openclaw.runtimePlugins = [
  "openclaw-weixin"
];

programs.openclaw.config.channels.openclaw-weixin = {
  enabled = true;
};
```

Do not add README install examples for these ids until the generated lock marks
them supported.

## Current Candidate Set

At pinned OpenClaw `2026.5.26`, the external catalog entries with exact npm
versions and expected integrity are:

| runtime plugin id | channel id | npm spec | current result |
| --- | --- | --- | --- |
| `wecom-openclaw-plugin` | `wecom` | `@wecom/wecom-openclaw-plugin@2026.5.7` | skip: runtime deps, no lock |
| `openclaw-plugin-yuanbao` | `yuanbao` | `openclaw-plugin-yuanbao@2.13.1` | skip: runtime deps, no lock |
| `openclaw-weixin` | `openclaw-weixin` | `@tencent-weixin/openclaw-weixin@2.4.3` | skip: runtime deps, no lock |

Registry metadata confirms all three have runtime `dependencies`. The root npm
tarball integrity matches the OpenClaw catalog `expectedIntegrity`, but the
transitive dependency graph is not pinned by the catalog.

The support promise is the generated lock, not this table. A report-only row is
not user support.

## Why This Is Separate From Arbitrary npm

Arbitrary npm support starts from a user-provided package spec. That needs a
user-owned lock file, update workflow, trust wording, and stronger warnings.

Catalog-pinned external support starts from the pinned OpenClaw source tree.
OpenClaw already uses these entries for onboarding and install-on-demand. The
catalog row contains an exact `npmSpec` and `expectedIntegrity`, and upstream
docs say catalog entries should pair exact specs with expected integrity so
install/update flows fail closed on root artifact drift.

That makes this class closer to official runtime-plugin coverage than arbitrary
npm for root artifact selection. It is still third-party code, and its
transitive dependencies are not currently locked.

## Non-Goals

This RFC does not support:

- user-supplied npm specs;
- npm package names without exact versions;
- npm dist-tags, semver ranges, aliases, registry URLs, `file:`, or `git:`;
- catalog entries without `expectedIntegrity`;
- package-manager install during activation or build;
- mutable `openclaw plugins install`;
- generic lifecycle scripts;
- source choices outside the pinned OpenClaw catalogs;
- claiming WeCom, Yuanbao, or Weixin work in nix-openclaw before dependency
  locks and runtime smoke pass.

## Candidate Selection

The generator only reads the pinned OpenClaw source used by nix-openclaw's
gateway package, not a local OpenClaw checkout and not upstream `main`.

Catalog files:

- `scripts/lib/official-external-channel-catalog.json`;
- `scripts/lib/official-external-plugin-catalog.json`;
- `scripts/lib/official-external-provider-catalog.json`.

A row enters the catalog-pinned npm report when all of these are true:

- `source = "external"`;
- `openclaw.install.defaultChoice = "npm"`;
- `openclaw.install.npmSpec` parses as exactly `<package>@<version>`;
- `openclaw.install.expectedIntegrity` is a non-empty npm integrity string;
- `openclaw.install.minHostVersion`, when present, is satisfied by the pinned
  OpenClaw version;
- the catalog entry name and parsed npm package name match;
- upstream catalog gives a stable runtime plugin id.

Rows with `clawhubSpec`, non-npm default choice, missing default choice, floating
specs, or missing integrity are skipped with stable reasons. Source selection
must be a pure function of the pinned catalog row, not which builder classes are
implemented today.

The npm spec parser should split on the final `@`, so scoped packages like
`@tencent-weixin/openclaw-weixin@2.4.3` are valid while tags, ranges, aliases,
protocols, URLs, `file:`, and `git:` are not.

## Version Model

Official OpenClaw-owned packages are co-versioned with OpenClaw. These external
packages are not.

For this class, the version source of truth is the exact version in the pinned
catalog `npmSpec`, not the OpenClaw release version and not the npm `latest`
tag. If OpenClaw bumps `@tencent-weixin/openclaw-weixin@2.4.3` to `2.4.4` in a
future pinned source update, nix-openclaw sees that as a normal catalog drift
event.

If npm registry metadata for the same exact package version returns a different
integrity than the catalog `expectedIntegrity`, generation fails closed.

## Report Shape

The report should make catalog trust, registry root integrity, and dependency
lock status visible:

```json
{
  "releaseVersion": "2026.5.26",
  "openclawRev": "...",
  "supported": [],
  "skipped": [
    {
      "id": "openclaw-weixin",
      "source": "catalog-pinned-npm",
      "reason": "dependency-lock-missing",
      "catalogFile": "official-external-channel-catalog.json",
      "catalogEntryName": "@tencent-weixin/openclaw-weixin",
      "packageName": "@tencent-weixin/openclaw-weixin",
      "version": "2.4.3",
      "channelIds": ["openclaw-weixin"],
      "expectedIntegrity": "sha512-...",
      "registryIntegrity": "sha512-...",
      "tarballUrl": "https://registry.npmjs.org/@tencent-weixin/openclaw-weixin/-/openclaw-weixin-2.4.3.tgz",
      "dependencyLockStatus": "missing",
      "dependenciesPresent": true,
      "packageOwnedLockPresent": false,
      "bundledNodeModulesPresent": false
    }
  ],
  "driftFailed": []
}
```

Stable skip reasons should include:

- `missing-expected-integrity`;
- `floating-npm-spec`;
- `non-npm-default`;
- `catalog-package-name-mismatch`;
- `min-host-version-unsatisfied`;
- `unbundled-runtime-dependencies`;
- `dependency-lock-missing`;
- `lifecycle-script-present`;
- `plugin-id-mismatch`.

Registry integrity drift is not an ordinary skip reason. If registry metadata for
an exact package/version disagrees with catalog `expectedIntegrity`, the report
goes to `driftFailed` before dependency-lock classification.

`lifecycle-script-present` means a lifecycle script the generic builder would
have to execute for install/build/runtime materialization. Normal package
scripts that are not part of the Nix builder path are not enough to skip a row.

## Future Lock Shape

When a candidate gets a deterministic dependency lock, generated lock entries
should make the catalog trust boundary explicit:

```nix
{
  id = "openclaw-weixin";
  source = {
    kind = "catalog-pinned-npm";
    openclawRev = "...";
    releaseVersion = "2026.5.26";
    catalogFile = "official-external-channel-catalog.json";
    catalogEntryName = "@tencent-weixin/openclaw-weixin";
    catalogSource = "external";
    selectedInstallSource = "npm";
    packageName = "@tencent-weixin/openclaw-weixin";
    version = "2.4.3";
    npmSpec = "@tencent-weixin/openclaw-weixin@2.4.3";
    expectedIntegrity = "sha512-...";
    registryIntegrity = "sha512-...";
    tarballUrl = "https://registry.npmjs.org/@tencent-weixin/openclaw-weixin/-/openclaw-weixin-2.4.3.tgz";
    nixSha256 = "sha256-...";
    minHostVersion = ">=2026.3.22";
  };
  pluginId = "openclaw-weixin";
  channelIds = [ "openclaw-weixin" ];
  dependencyLock = ./openclaw-weixin-dependencies.nix;
}
```

The dependency lock is not optional for packages with runtime dependencies. It
must record exact dependency tarball URLs, npm integrity, Nix hashes, lifecycle
policy, and drift checks. That dependency-lock design belongs in the next RFC.

## Builder Contract

The current builder action for this class is to skip all dependency-bearing rows
without package-owned locks or a nix-openclaw dependency lock.

Once a candidate has a deterministic dependency lock:

1. fetch the exact root npm tarball URL as a fixed-output derivation;
2. validate `nixSha256`;
3. validate root tarball npm integrity against `expectedIntegrity`;
4. validate tar member safety;
5. validate package name/version against the lock;
6. validate `openclaw.plugin.json.id` against the catalog plugin id;
7. validate channel ids and runtime entries are consistent with the catalog;
8. materialize transitive dependencies only from the checked dependency lock;
9. skip packages requiring generic lifecycle scripts or native rebuilds until a
   package-specific derivation exists.

No activation step runs npm, pnpm, yarn, corepack, or `openclaw plugins install`.

## Runtime Ids And Channel Ids

This class exposes an existing awkwardness: plugin id and channel id can differ.

Examples:

- WeCom plugin id: `wecom-openclaw-plugin`; channel id: `wecom`;
- Yuanbao plugin id: `openclaw-plugin-yuanbao`; channel id: `yuanbao`;
- Weixin plugin id and channel id: `openclaw-weixin`.

`runtimePlugins` should continue selecting plugin ids because OpenClaw
`plugins.entries.<id>` and plugin manifests use plugin ids. Channel config should
continue using upstream channel ids:

```nix
programs.openclaw.runtimePlugins = [
  "wecom-openclaw-plugin"
];

programs.openclaw.config.channels.wecom = {
  enabled = true;
};
```

Do not add channel-id aliases in this source RFC. If the plugin/channel id split
is painful enough, it deserves a small ergonomics RFC after the source classes
are correct.

## User-Facing Documentation

Do not add these ids to the README supported table until they pass dependency
locking, build validation, and runtime smoke.

Future docs, after support exists, must explicitly show both the plugin id and
the channel config path:

```nix
programs.openclaw.runtimePlugins = [
  "openclaw-plugin-yuanbao"
];

programs.openclaw.config.channels.yuanbao = {
  enabled = true;
};
```

Bad:

```bash
openclaw plugins install @tencent-weixin/openclaw-weixin
```

Bad:

```nix
programs.openclaw.customPlugins = [
  { source = "npm:@tencent-weixin/openclaw-weixin"; }
];
```

Docs should say: these are third-party runtime plugins pinned by the OpenClaw
catalog and packaged immutably by nix-openclaw after proof gates pass.
nix-openclaw does not endorse or audit the external service behavior.

## Drift Contract

Regeneration fails in check mode when any selected catalog or registry fact
changes for the same package/version:

- catalog file/path;
- catalog `source`;
- catalog entry name;
- selected install source/defaultChoice;
- `npmSpec`;
- `expectedIntegrity`;
- plugin id;
- channel ids;
- `minHostVersion`;
- npm registry integrity;
- tarball URL;
- Nix fixed-output hash;
- package name or version;
- manifest plugin id;
- runtime entry metadata;
- dependency materialization class.

The report should include `driftFailed` rows with old and new values. A
maintainer accepts drift only by reviewing and committing the generated diff.

## Proof Gates

Generator checks:

- exact npm spec required;
- `expectedIntegrity` required;
- selected source must be npm by catalog rule;
- catalog package name must match parsed npm package name;
- host version floor must be satisfied;
- npm registry metadata integrity must match `expectedIntegrity`;
- runtime dependencies without deterministic dependency locks are skipped.

Builder checks after dependency locks exist:

- tar traversal and unsafe symlinks fail;
- package name/version mismatch fails;
- plugin id mismatch fails;
- missing runtime entries fail;
- missing dependency lock for materialized dependencies fails;
- generic lifecycle scripts skip the package.

Home Manager checks after supported ids exist:

- supported ids render load path plus `plugins.entries.<id>.enabled = true`;
- selecting channel id `wecom` fails with a direct message to select plugin id
  `wecom-openclaw-plugin` and configure `channels.wecom`;
- denied, disabled, duplicate, collision, and raw-load-path checks behave like
  existing runtime plugins.

Runtime smoke after supported ids exist:

- `openclaw plugins list --json` sees the plugin id from the Nix store load
  path;
- `openclaw status` does not report "plugin not installed" for selected ids;
- at least one candidate with different plugin/channel ids reaches the
  configured-channel startup path on Darwin and Linux.

The generator needs `--check` mode that asserts the current-pin report. While
the supported set is empty, CI should fail if README examples imply support for
these ids or if any candidate disappears without a catalog-drift report row.

## Rollout

1. Extend the generator in report-only mode for external exact npm catalog rows.
2. Confirm WeCom, Yuanbao, and Weixin skip as `dependency-lock-missing` at the
   current pin.
3. Draft the third-party dependency-lock RFC before adding supported ids.
4. Add README examples only for ids that pass dependency lock, build, and
   runtime proof gates.

## Rejected Designs

### Treat Catalog-Pinned External Plugins As Arbitrary npm

Rejected. The pinned OpenClaw catalog is the root artifact selection source for
this class. User-provided npm specs need their own lock/update RFC.

### Resolve Transitive Dependencies With npm

Rejected. Root tarball integrity does not pin dependency ranges. Running npm
would reintroduce registry resolution and supply-chain drift.

### Accept Floating Catalog Specs

Rejected. A floating catalog spec is useful for mutable OpenClaw install flows,
but nix-openclaw should skip it until upstream pins a version and integrity, or
until a later RFC defines a separate lock owner.

### Add Channel Id Aliases Now

Rejected. Aliases are an ergonomics feature, not part of the source trust model.
The first implementation should be boring: plugin ids select plugins; upstream
channel ids configure channels.

### Run OpenClaw Install Commands

Rejected. This class still uses immutable Nix-built plugin roots and rendered
OpenClaw config. Mutable install records remain out of scope.
