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

      packages = { inherit (inputs'.tools.packages) nix-flake-check-changed nix-grep-to-build; };

      legacyPackages.tests = lib.packagesFromDirectoryRecursive {
        callPackage = lib.callPackageWith (pkgs // { inherit dune2nix; });
        directory = ../tests;
      };

      checks =
        let
          # Build all tests as a check.
          builds = builtins.listToAttrs (
            lib.mapAttrsToListRecursiveCond (_: v: !(lib.isDerivation v)) (
              p: lib.nameValuePair "build-${(lib.concatStringsSep "/" p)}"
            ) config.legacyPackages.tests
          );

          failures = lib.runTests {
            "test basic meta main program" = {
              expr = config.legacyPackages.tests.demo.meta.mainProgram;
              expected = "demo";
            };
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
        in
        builds
        // {
          unit-tests = pkgs.runCommand "unit-tests" { failed = failures != [ ]; } ''
            if [[ -n "$failed" ]]; then
              >&2 echo "${lib.generators.toPretty { } failures}"
              exit 1
            fi
            touch $out
          '';
        };
    };
}
