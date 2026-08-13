{ dune2nix }:

dune2nix.mkDuneProject {
  duneSeparateDeps = true;
  src = ./.;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/demo | grep -q "🐫"
  '';
}
