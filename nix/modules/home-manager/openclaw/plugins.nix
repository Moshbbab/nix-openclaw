{
  lib,
  pkgs,
  openclawLib,
  enabledInstances,
}:

let
  resolvePath = openclawLib.resolvePath;
  toRelative = openclawLib.toRelative;
  mkNpmRuntimePlugin = pkgs.callPackage ../../../lib/npm-runtime-plugin.nix { };

  normalizeOpenClawPlugin =
    pluginSource: name: entry:
    let
      id = entry.id or (throw "openclawPlugin ${name}: plugins entry missing id");
      path = entry.path or (throw "openclawPlugin ${name}: plugins.${id} missing path");
      enabled =
        if entry ? enable && !(entry ? enabled) then
          throw "openclawPlugin ${name}: plugins.${id}.enable is not supported; use enabled"
        else if entry ? enabled then
          if builtins.isBool entry.enabled then
            entry.enabled
          else
            throw "openclawPlugin ${name}: plugins.${id}.enabled must be a boolean"
        else
          true;
    in
    {
      inherit id path enabled;
      source = pluginSource;
      plugin = name;
    };

  resolveNpmRuntimePlugin =
    plugin:
    let
      id = plugin.id or (throw "OpenClaw npm runtime plugin ${plugin.source} requires id");
      # TODO: This is only a partial bridge for OpenClaw runtime plugins.
      # Proper support needs a structural fix that proves the gateway loads the
      # built plugin root and exposes its channel/register hook end to end.
      path = mkNpmRuntimePlugin {
        inherit id;
        source = plugin.source;
        hash = plugin.hash or lib.fakeHash;
      };
    in
    if (plugin.config or { }) != { } then
      throw "OpenClaw npm runtime plugin ${plugin.source} must put runtime config under programs.openclaw.config.plugins.entries.${id}.config, not customPlugins.config"
    else
      {
        source = plugin.source;
        name = id;
        skills = [ ];
        packages = [ ];
        plugins = [
          {
            inherit id path;
            enabled = plugin.enabled or true;
            source = plugin.source;
            plugin = id;
          }
        ];
        needs = {
          stateDirs = [ ];
          requiredEnv = [ ];
        };
        config = { };
      };

  resolveFlakePlugin =
    plugin:
    let
      _ =
        if (plugin.id or null) != null then
          throw "Plugin ${plugin.source}: id is only valid for npm: OpenClaw runtime plugin sources"
        else if (plugin.hash or lib.fakeHash) != lib.fakeHash then
          throw "Plugin ${plugin.source}: hash is only valid for npm: OpenClaw runtime plugin sources"
        else if (plugin.enabled or true) != true then
          throw "Plugin ${plugin.source}: enabled is only valid for npm: OpenClaw runtime plugin sources"
        else
          null;
      system = pkgs.stdenv.hostPlatform.system;
      flake = builtins.getFlake plugin.source;
      openclawPluginRaw =
        if flake ? openclawPlugin then
          flake.openclawPlugin
        else
          throw "openclawPlugin missing in ${plugin.source}";
      openclawPlugin =
        if builtins.isFunction openclawPluginRaw then openclawPluginRaw system else openclawPluginRaw;
      resolvedPlugin =
        if openclawPlugin == null then
          throw "openclawPlugin is null in ${plugin.source} for ${system}"
        else
          openclawPlugin;
      name = resolvedPlugin.name or (throw "openclawPlugin.name missing in ${plugin.source}");
      needs = resolvedPlugin.needs or { };
    in
    builtins.seq _ {
      source = plugin.source;
      inherit name;
      skills = resolvedPlugin.skills or [ ];
      packages = resolvedPlugin.packages or [ ];
      plugins = map (normalizeOpenClawPlugin plugin.source name) (resolvedPlugin.plugins or [ ]);
      needs = {
        stateDirs = needs.stateDirs or [ ];
        requiredEnv = needs.requiredEnv or [ ];
      };
      config = plugin.config or { };
    };

  resolvePlugin =
    plugin:
    if lib.hasPrefix "npm:" plugin.source then
      resolveNpmRuntimePlugin plugin
    else
      resolveFlakePlugin plugin;

  resolvedPluginsByInstance = lib.mapAttrs (
    instName: inst:
    let
      resolved = map resolvePlugin inst.plugins;
      counts = lib.foldl' (acc: p: acc // { "${p.name}" = (acc.${p.name} or 0) + 1; }) { } resolved;
      duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
      byName = lib.foldl' (acc: p: acc // { "${p.name}" = p; }) { } resolved;
      ordered = lib.attrValues byName;
    in
    if duplicates == [ ] then
      ordered
    else
      lib.warn "programs.openclaw.instances.${instName}: duplicate plugin names detected (${lib.concatStringsSep ", " duplicates}); last entry wins." ordered
  ) enabledInstances;

  pluginPackagesFor =
    instName: lib.flatten (map (p: p.packages) (resolvedPluginsByInstance.${instName} or [ ]));

  pluginPackagesAll = lib.flatten (map pluginPackagesFor (lib.attrNames enabledInstances));

  pluginStateDirsFor =
    instName:
    let
      dirs = lib.flatten (map (p: p.needs.stateDirs) (resolvedPluginsByInstance.${instName} or [ ]));
    in
    map (dir: resolvePath ("~/" + dir)) dirs;

  pluginStateDirsAll = lib.flatten (map pluginStateDirsFor (lib.attrNames enabledInstances));

  pluginEnvFor =
    instName:
    let
      entries = resolvedPluginsByInstance.${instName} or [ ];
      toPairs =
        p:
        let
          env = (p.config.env or { });
          required = p.needs.requiredEnv;
        in
        map (k: {
          key = k;
          value = env.${k} or "";
          plugin = p.name;
        }) required;
    in
    lib.flatten (map toPairs entries);

  pluginEnvAllFor =
    instName:
    let
      entries = resolvedPluginsByInstance.${instName} or [ ];
      toPairs =
        p:
        let
          env = (p.config.env or { });
        in
        map (k: {
          key = k;
          value = env.${k};
          plugin = p.name;
        }) (lib.attrNames env);
    in
    lib.flatten (map toPairs entries);

  openclawPluginsFor =
    instName: lib.flatten (map (p: p.plugins) (resolvedPluginsByInstance.${instName} or [ ]));

  openclawPluginLoadPathsFor = instName: map (p: toString p.path) (openclawPluginsFor instName);

  openclawPluginEntriesConfigFor =
    instName:
    let
      entries = openclawPluginsFor instName;
    in
    lib.optionalAttrs (entries != [ ]) {
      plugins = {
        entries = lib.listToAttrs (
          map (p: {
            name = p.id;
            value = {
              enabled = p.enabled;
            };
          }) entries
        );
      };
    };

  openclawPluginIdAssertions = lib.mapAttrsToList (
    instName: _inst:
    let
      ids = map (p: p.id) (openclawPluginsFor instName);
      counts = lib.foldl' (acc: id: acc // { "${id}" = (acc.${id} or 0) + 1; }) { } ids;
      duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
    in
    {
      assertion = duplicates == [ ];
      message = "programs.openclaw.instances.${instName}: duplicate OpenClaw plugin ids detected: ${lib.concatStringsSep ", " duplicates}";
    }
  ) enabledInstances;

  pluginAssertions =
    openclawPluginIdAssertions
    ++ lib.flatten (
      lib.mapAttrsToList (
        instName: inst:
        let
          plugins = resolvedPluginsByInstance.${instName} or [ ];
          envFor = p: (p.config.env or { });
          missingFor = p: lib.filter (req: !(builtins.hasAttr req (envFor p))) p.needs.requiredEnv;
          configMissingStateDir = p: (p.config.settings or { }) != { } && (p.needs.stateDirs or [ ]) == [ ];
          mkAssertion =
            p:
            let
              missing = missingFor p;
            in
            {
              assertion = missing == [ ];
              message = "programs.openclaw.instances.${instName}: plugin ${p.name} missing required env: ${lib.concatStringsSep ", " missing}";
            };
          mkConfigAssertion = p: {
            assertion = !(configMissingStateDir p);
            message = "programs.openclaw.instances.${instName}: plugin ${p.name} provides settings but declares no stateDirs (needed for config.json).";
          };
        in
        (map mkAssertion plugins) ++ (map mkConfigAssertion plugins)
      ) enabledInstances
    );

  pluginConfigFiles =
    let
      entryFor =
        instName: inst:
        let
          plugins = resolvedPluginsByInstance.${instName} or [ ];
          mkEntries =
            p:
            let
              cfg = p.config.settings or { };
              dir = if (p.needs.stateDirs or [ ]) == [ ] then null else lib.head (p.needs.stateDirs or [ ]);
            in
            if cfg == { } then
              [ ]
            else
              (
                if dir == null then
                  throw "plugin ${p.name} provides settings but no stateDirs are defined"
                else
                  [
                    {
                      name = toRelative (resolvePath ("~/" + dir + "/config.json"));
                      value = {
                        text = builtins.toJSON cfg;
                      };
                    }
                  ]
              );
        in
        lib.flatten (map mkEntries plugins);
      entries = lib.flatten (lib.mapAttrsToList entryFor enabledInstances);
    in
    lib.listToAttrs entries;

  pluginGuards =
    let
      renderCheck = entry: ''
        if [ -z "${entry.value}" ]; then
          echo "Missing env ${entry.key} for plugin ${entry.plugin} in instance ${entry.instance}." >&2
          exit 1
        fi
        if [ ! -f "${entry.value}" ] || [ ! -s "${entry.value}" ]; then
          echo "Required file for ${entry.key} not found or empty: ${entry.value} (plugin ${entry.plugin}, instance ${entry.instance})." >&2
          exit 1
        fi
      '';
      entriesForInstance =
        instName: map (entry: entry // { instance = instName; }) (pluginEnvFor instName);
      entries = lib.flatten (map entriesForInstance (lib.attrNames enabledInstances));
    in
    lib.concatStringsSep "\n" (map renderCheck entries);

in
{
  inherit
    resolvedPluginsByInstance
    pluginPackagesFor
    pluginPackagesAll
    pluginStateDirsFor
    pluginStateDirsAll
    pluginEnvFor
    pluginEnvAllFor
    openclawPluginsFor
    openclawPluginLoadPathsFor
    openclawPluginEntriesConfigFor
    pluginAssertions
    pluginConfigFiles
    pluginGuards
    ;
}
