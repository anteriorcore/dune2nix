# Kitchen sink for project internal stuffs

{ inputs, self, ... }: {
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
                duneSeparateDeps = true;
              }).foo or null;
            expected = 123;
          };
        };
      };

      packages = { inherit (inputs'.tools.packages) nix-flake-check-changed nix-grep-to-build; };

      legacyPackages.tests = lib.packagesFromDirectoryRecursive {
        callPackage = lib.callPackageWith (pkgs // { inherit dune2nix; });
        directory = ../tests;
      };

      # Build all tests as a check.
      checks = builtins.listToAttrs (
        lib.mapAttrsToListRecursiveCond (_: v: !(lib.isDerivation v)) (
          p: lib.nameValuePair "build-${(lib.concatStringsSep "/" p)}"
        ) config.legacyPackages.tests
      );
    };
}
