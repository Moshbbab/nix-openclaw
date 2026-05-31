{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.28";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.28/OpenClaw-2026.5.28.zip";
    hash = "sha256-8LqpJbLM8QYF/HMbOIwOniT9kybhZH16sSjNgrZ/A80=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
