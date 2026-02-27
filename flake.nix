{
  inputs = {
    # keep-sorted start block=yes
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # keep-sorted end
  };
  outputs =
    {
      # keep-sorted start
      devshell,
      flake-parts,
      nix-unit,
      systems,
      treefmt-nix,
      # keep-sorted end
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;
      imports = [
        # keep-sorted start
        ./nix/devshells.nix
        ./nix/dune2nix.nix
        ./nix/lib.nix
        ./nix/misc.nix
        ./nix/overlays.nix
        ./nix/sexp.nix
        ./nix/treefmt.nix
        devshell.flakeModule
        nix-unit.modules.flake.default
        treefmt-nix.flakeModule
        # keep-sorted end
      ];
    };
}
