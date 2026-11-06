# Minimal demo to use dune2nix with [Nix flakes](https://nixos.wiki/wiki/flakes).
{
  inputs = {
    # keep-sorted start block=yes
    dune2nix = {
      # FIXME Change to:
      # url = "github:anteriorcore/dune2nix";"
      url = "..";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    # keep-sorted end
  };
  outputs =
    { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        {
          perSystem =
            { pkgs, system, ... }:
            let
              dune2nix = pkgs.callPackage inputs.dune2nix.lib.dune2nix {
                overrides = _final: _prev: {
                  # You may apply overlays here
                };
              };

              demo = dune2nix.mkDuneProject {
                duneSeparateDeps = true;
                duneTreeshakeDeps = true;

                src = ./.;

                doInstallCheck = true;
                installCheckPhase = ''
                  $out/bin/demo | grep -q "🐫"
                '';
              };
            in
            {
              _module.args.pkgs = import inputs.nixpkgs {
                inherit system;
                # dune2nix exposes an optional overlay to fix issues with Dune.
                # Most features _should_ work without it, but we highly recommend
                # applying it.
                overlays = [ inputs.dune2nix.overlays.dune ];
              };

              legacyPackages = {
                # `$ nix run .#demo`
                inherit demo;
              };
            };
        }
      ];
    };
}
