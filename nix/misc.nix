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
            expr = config.legacyPackages.tests.demo.meta.mainProgram;
            expected = "demo";
          };

          # regression test for anteriorcore/dune2nix#18
          "test passthru not overridden" = {
            expr =
              (dune2nix.mkDuneProject {
                src = ../tests/no_deps;
                passthru.foo = 123;
              }).foo or null;
            expected = 123;
          };
        };
      };

      packages = { inherit (inputs'.tools.packages) nix-flake-check-changed nix-grep-to-build; };

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
                { "${lib.concatStringsSep "/" curr}" = v; }
            ) attrs;
        in
        go [ ] (
          lib.packagesFromDirectoryRecursive {
            callPackage = lib.callPackageWith (pkgs // { inherit dune2nix; });
            directory = ../tests;
          }
        );

      # Build all tests as a check.
      checks = lib.mapAttrs' (k: v: lib.nameValuePair "build-${k}" v) config.legacyPackages.tests;
    };
}
