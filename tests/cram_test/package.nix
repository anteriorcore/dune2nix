{ cowsay, dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  nativeBuildInputs = [ cowsay ];
  doCheck = true;
  # NOMERGE just testing
  DUNE_CACHE = "enabled";
  separateDepsDeriv = true;
}
