{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  separateDepsDeriv = true;
}
