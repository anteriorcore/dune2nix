{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;

  # TODO: Support custom lockdirs. Absolutely possible, but we'd need to apply
  # non-trivial patch to `dune-workspace` and I'm too lazy to implement that
  # right now. Who uses custom lockdir anyways? - shun 2026-08
  duneSeparateDeps = false;
}
