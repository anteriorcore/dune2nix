{ dune2nix }:

dune2nix.mkDuneWorkspace {
  name = "workspace";
  src = ./.;
  enableIncrementalBuild = true;
}
