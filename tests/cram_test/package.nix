{ cowsay, dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  nativeBuildInputs = [ cowsay ];
  doCheck = true;
}
