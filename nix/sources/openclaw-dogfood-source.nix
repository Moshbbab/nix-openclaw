{
  owner = "openclaw";
  repo = "openclaw";
  releaseTag = "v2026.5.9-beta.1";
  releaseVersion = "2026.5.9-beta.1-dogfood.20260510";
  rev = "0d3141ee2438c2c990241b8a0941efd69d35382c";
  hash = "sha256-JswYsQWIFpefwSAr7qXnLuy5BHxmVAXY7m/b+WPd1lw=";
  pnpmDepsHash = "sha256-2ftORJU9UsIaN7FzAOg6PBhbvCTy9peuQ6ju7FKEt5Y=";
  fsSafeSource = {
    owner = "openclaw";
    repo = "fs-safe";
    rev = "c7ccb99d3058f2acf2ad2758ad2470c7e113a53c";
    hash = "sha256-jndOOSSFROyrK4RiwAsJfUuCJTj7qbmmm4Qz8BqtJ/c=";
  };

  publicSurfaceHardlinksPatch = ../patches/allow-package-public-surface-hardlinks-open-root.patch;
  applySkipPluginAutoEnableNixModePatch = false;
}
