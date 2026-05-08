{ dune2nix }:

dune2nix.mkDuneWorkspace {
  name = "workspace_local_deps";
  src = ./.;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
