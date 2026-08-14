{
  dune2nix,
  autoconf,
  cctools,
  lib,
  rsync,
  stdenv,
  which,
}:
dune2nix.mkDuneProject {
  src = ./.;

  duneSeparateDeps = true;

  nativeBuildInputs = [
    autoconf
    rsync
    which
  ]
  ++ lib.optionals stdenv.isDarwin [ cctools ];

  srcOverrides =
    final: prev:
    lib.concatMapAttrs (
      n: v:
      lib.optionalAttrs (lib.hasPrefix "oxcaml-compiler" n && lib.hasSuffix ".pkg" n) {
        ${n} = v.overrideAttrs (
          old:
          lib.recursiveUpdate old ({
            passthru.sexp.source.copy = old.passthru.sexp.source.copy.overrideAttrs {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace Makefile Makefile.ox \
                  --replace-fail 'SHELL = /usr/bin/env bash' 'SHELL = bash'
              '';
            };
          })
        );
      }
    ) prev;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/hello_oxcaml | grep -q "2.000000"
  '';
}
