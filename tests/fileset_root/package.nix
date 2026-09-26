{ dune2nix, lib }:

dune2nix.mkDuneProject {
  duneRoot = ./.;
  src =
    with lib.fileset;
    toSource {
      root = ./.;
      fileset = difference ./. ./package.nix;
    };
  doCheck = true;
  checkPhase = ''
    [[ ! -f ./package.nix ]]
  '';
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;
}
