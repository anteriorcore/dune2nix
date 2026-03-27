{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  enableIncrementalBuild = true;
}
