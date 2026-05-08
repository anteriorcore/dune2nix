{ dune2nix }:

dune2nix.mkDuneProject {
  src = ../.;
  duneProject = ./dune-project;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
