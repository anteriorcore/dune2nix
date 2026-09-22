{ dune2nix }:

dune2nix.mkDuneProject {
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;

  src = ./.;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/demo | grep -q "🐫"
  '';
}
