{ dune2nix }:

dune2nix.mkDuneProject {
  src = ../.;
  duneProject = ./dune-project;
  enableIncrementalBuild = true;
}
