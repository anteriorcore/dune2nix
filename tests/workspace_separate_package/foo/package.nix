{ dune2nix }:

dune2nix.mkDuneProject {
  src = ../.;
  duneProject = ./dune-project;
  separateDepsDeriv = true;
}
