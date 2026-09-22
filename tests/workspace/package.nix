{ dune2nix }:

dune2nix.mkDuneWorkspace {
  name = "workspace";
  src = ./.;
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;
}
