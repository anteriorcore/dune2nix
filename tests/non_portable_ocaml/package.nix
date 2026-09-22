{ dune2nix }:

dune2nix.mkDuneProject {
  duneSeparateDeps = true;
  duneTreeshakeDeps = true;
  src = ./.;

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/non_portable_ocaml | grep -q "Hello from non-portable OCaml!"
  '';
}
