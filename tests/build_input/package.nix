{
  dune2nix,
  gmp,
  pkg-config,
}:

dune2nix.mkDuneProject {
  src = ./.;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ gmp ];

  # This derivation only reuses build artifacts when they go through the global
  # cache
  DUNE_CACHE = "enabled";
}
