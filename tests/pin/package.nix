{ dune2nix }:

dune2nix.mkDuneProject {
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;
  src = ./.;
}
