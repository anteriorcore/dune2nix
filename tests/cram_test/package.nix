{ cowsay, dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;
  nativeBuildInputs = [ cowsay ];
  doCheck = true;
}
