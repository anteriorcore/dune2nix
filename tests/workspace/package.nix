{ dune2nix }:

dune2nix.mkDuneWorkspace {
  name = "workspace";
  src = ./.;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
