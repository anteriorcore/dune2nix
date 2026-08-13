{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  duneSeparateDeps = true;
}
