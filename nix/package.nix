{
  lib,
  swiftPackages,
  swift,
}:
swiftPackages.stdenv.mkDerivation {
  pname = "secret-prompt";
  version = "0.3.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [../Sources ../bin ../Makefile];
  };

  nativeBuildInputs = [swift];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
    "ARCHS=${swiftPackages.stdenv.hostPlatform.darwinArch}"
    "TARGET="
  ];

  meta = {
    description = "A themed macOS panel that asks the user for a secret on an agent's behalf, with asudo and with-secret on top";
    homepage = "https://github.com/theonewiththegun/secret-prompt";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "asudo";
  };
}
