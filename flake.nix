{
  description = "A themed macOS panel that asks the user for a secret on an agent's behalf";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["aarch64-darwin" "x86_64-darwin"];
    forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAll (pkgs: {
      default = pkgs.callPackage ./nix/package.nix {};
    });

    overlays.default = final: _: {
      secret-prompt = final.callPackage ./nix/package.nix {};
    };

    homeManagerModules.default = import ./nix/home-manager.nix self;

    checks = forAll (pkgs: {
      tests = pkgs.runCommand "secret-prompt-tests" {nativeBuildInputs = [pkgs.shellcheck];} ''
        cd ${self}
        shellcheck bin/* tests/*.sh scripts/*.sh
        HOME=$TMPDIR TEST_BASH=${pkgs.bash}/bin/bash \
          ${pkgs.bash}/bin/bash tests/run.sh ${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/secret-prompt
        touch $out
      '';
    });

    formatter = forAll (pkgs: pkgs.alejandra);
  };
}
