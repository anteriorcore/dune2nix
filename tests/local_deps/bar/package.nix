{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
