{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;

  /**
    Create a separate derivation with only the dependencies (target
    ‘@pkg-install’). Caches the built dependencies and only rebuilds
    when there's a change in `dune-*` files. Later during the actual
    build, these cached dependencies will be made discoverable to
    `ocamlfind` via envvars.

    If you're using OCaml version prior to 5.5.0 (or OCaml variant
    that is not "relocatable"), this will rely on global toolchain
    cache, make sure to NOT turn it off! Refer to the docs for
    configuration options: https://dune.readthedocs.io/en/stable/reference/caches.html#configuration

    Internally, during the actual build, existing lockfiles disappear
    and Dune package management will be turned off. This may lead to
    unexpected behavior: use with caution.

    This is especially powerful for ocaml-compiler which takes very
    long time to build.

    <docsync>duneSeparateDeps</docsync>
  */
  duneSeparateDeps = true;

  /**
    Treeshake dependencies derivs by retaining only the dirs that are
    relevant to the build. Use with caution: by setting this you are
    depending on the Dune internals, and the benefit of treeshaking is
    minimal unless you have many GB worth of dependencies.

    <docsync>duneTreeshakeDeps</docsync>
  */
  duneTreeshakeDeps = true;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/demo | grep -q "🐫"
  '';
}
