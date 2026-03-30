# Kitchen sink for project internal stuffs

{ inputs, self, ... }:
{
  perSystem =
    {
      system,
      config,
      pkgs,
      lib,
      inputs',
      ...
    }:
    let
      dune2nix = pkgs.callPackage self.lib.dune2nix { };
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ self.overlays.dune ];
      };

      nix-unit = {
        inherit inputs;
        allowNetwork = false;

        tests = {
          "test basic meta main program" = {
            expr = config.legacyPackages.tests.build-no_deps.meta.mainProgram;
            expected = "no_deps";
          };
        };
      };

      packages = { inherit (inputs'.tools.packages) nix-flake-check-changed nix-grep-to-build; };

      # Build all packages as a check.
      legacyPackages.tests =
        let
          go =
            path: attrs:
            lib.concatMapAttrs (
              k: v:
              let
                curr = path ++ [ k ];
              in
              if lib.isAttrs v && !lib.isDerivation v then
                go curr v
              else
                { "build-${lib.concatStringsSep "/" curr}" = v; }
            ) attrs;
        in
        go [ ] (
          lib.packagesFromDirectoryRecursive {
            callPackage = lib.callPackageWith (pkgs // { inherit dune2nix; });
            directory = ../tests;
          }
        );
      checks = config.legacyPackages.tests;
    };
}
