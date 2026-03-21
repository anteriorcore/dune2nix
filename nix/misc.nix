# Kitchen sink for project internal stuffs

{ inputs, self, ... }:
{
  perSystem =
    {
      system,
      pkgs,
      lib,
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
      };

      # Build all packages as a check.
      checks =
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
    };
}
