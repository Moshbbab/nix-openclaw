{
  lib,
  pkgs,
  stdenv,
  nodejs_22,
  openclawGateway,
}:

let
  stubModule =
    { lib, ... }:
    {
      options = {
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };

        home.homeDirectory = lib.mkOption {
          type = lib.types.str;
          default = "/tmp";
        };

        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };

        home.file = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        home.activation = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        launchd.agents = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        systemd.user.services = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        programs.git.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        lib = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  moduleEval = lib.evalModules {
    modules = [
      stubModule
      ../modules/home-manager/openclaw.nix
      (
        { lib, ... }:
        {
          config = {
            home.homeDirectory = "/tmp";
            programs.git.enable = false;
            lib.file.mkOutOfStoreSymlink = path: path;
            programs.openclaw = {
              enable = true;
              runtimePlugins = [ "slack" ];
              launchd.enable = false;
              systemd.enable = false;
              instances.default = {
                workspaceDir = expectedWorkspace;
                config = {
                  channels.telegram = {
                    enabled = true;
                    botToken = "123456:test-token";
                    dmPolicy = "open";
                    groupPolicy = "disabled";
                    allowFrom = [ "*" ];
                  };
                  channels.slack = {
                    enabled = true;
                    appToken.source = "env";
                    appToken.provider = "env";
                    appToken.id = "SLACK_APP_TOKEN";
                    botToken.source = "env";
                    botToken.provider = "env";
                    botToken.id = "SLACK_BOT_TOKEN";
                  };
                };
              };
            };
          };
        }
      )
    ];
    specialArgs = { inherit pkgs; };
  };

  configPathKey = ".openclaw/openclaw.json";
  configFile = moduleEval.config.home.file."${configPathKey}".source;
  expectedWorkspace = "/tmp/openclaw-explicit-workspace";

in
stdenv.mkDerivation {
  pname = "openclaw-config-validity";
  version = lib.getVersion openclawGateway;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    nodejs_22
    pkgs.openclawRuntimePlugins.slack
  ];

  env = {
    OPENCLAW_CONFIG_PATH = configFile;
    OPENCLAW_GATEWAY = openclawGateway;
    OPENCLAW_EXPECTED_WORKSPACE = expectedWorkspace;
  };

  doCheck = true;
  checkPhase = "${nodejs_22}/bin/node ${../scripts/check-config-validity.mjs}";
  installPhase = "${../scripts/empty-install.sh}";
}
