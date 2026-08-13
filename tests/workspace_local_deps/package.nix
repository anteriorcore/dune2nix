{ dune2nix }:

dune2nix.mkDuneWorkspace {
  name = "workspace_local_deps";
  src = ./.;
  duneSeparateDeps = true;
}
