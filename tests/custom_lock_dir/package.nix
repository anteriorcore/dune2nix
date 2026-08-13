{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;

  # TODO: Support custom lockdirs. We'd need to patch `dune-workspace` and I'm
  # too lazy to implement that right now. Who uses custom lockdir anyways?
  duneSeparateDeps = false;
}
