{ dune2nix }:

dune2nix.mkDuneProject {
  src = ../.;
  duneProject = ./dune-project;

  # Redundant but making sure this works
  duneLock = ../dune.lock;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
