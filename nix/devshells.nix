{ ... }: {
  perSystem = { pkgs, ... }: {
    devshells.default = {
      name = "dune2nix";
      packages = with pkgs; [
        dune

        # LSPs
        nixd
        ocamlPackages.ocaml-lsp

        # Opam uses homebrew / macport to install system deps, but I have
        # neither, nor do I want to install them. I still don't if this is the
        # right way, but the packages below are the result of my (and
        # community's) try-and-error.

        # Required for building ocaml-base-compiler (on my darwin laptop - if
        # you have xcode-select installed, you shouldn't need them).
        clang
        libllvm
        gnumake

        # Required for building janestreet/gel.
        # https://discuss.ocaml.org/t/issue-with-gel-prevents-install-of-jane-street-core-under-5-3-0/16909/5
        gnupatch
      ];
    };
  };
}
