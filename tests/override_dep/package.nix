{
  dune2nix,
  gnused,
  lib,
}:

dune2nix.mkDuneProject {
  src = ./.;
  doCheck = true;
  enableIncrementalBuild = true; # NOMERGE
  srcOverrides =
    final: prev:
    lib.concatMapAttrs (
      n: v:
      lib.optionalAttrs (lib.hasPrefix "base64" n) {
        ${n} = v.overrideAttrs (
          old:
          lib.recursiveUpdate old ({
            passthru.sexp.source.copy = old.passthru.sexp.source.copy.overrideAttrs {
              nativeBuildInputs = old.nativeBuildInputs or [ ] ++ [ gnused ];
              postPatch = ''
                sed -i -e 's/ABCD[^"]\+/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/' src/*.ml
              '';
            };
          })
        );
      }
    ) prev;
}
