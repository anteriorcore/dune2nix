{
  dune2nix,
  gmp,
  pkg-config,
}:

dune2nix.mkDuneProject {
  src = ./.;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ gmp ];
}
