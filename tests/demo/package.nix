{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  # Stop-gap, but we should probably have a heuristic that disables fixup on any
  # dependency with a patch.  Right?
  srcOverrides =
    final: prev:
    lib.concatMapAttrs (
      n: v:
      lib.optionalAttrs (lib.hasPrefix "bin_prot" n) {
        ${n} = v.overrideAttrs (
          old:
          lib.recursiveUpdate old {
            passthru.sexp.source.copy = old.passthru.sexp.source.copy.overrideAttrs { dontFixup = true; };
          }
        );
      }
    ) prev;
}
