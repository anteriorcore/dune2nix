{
  diffutils,
  dune2nix,
  makeWrapper,
}:

dune2nix.mkDuneProject {
  src = ./.;
  nativeBuildInputs = [
    diffutils
    makeWrapper
  ];
  separateDepsDeriv = true;
  postInstall = ''
    for b in $out/bin/*; do
      wrapProgram "$b" --add-flag "hard-coded using makeWrapper"
    done
  '';
  doInstallCheck = true;
  expected = ''
    [1] hard-coded using makeWrapper
    [2] foo
    [3] bar
  '';
  passAsFile = [ "expected" ];
  installCheckPhase = ''
    $out/bin/make_wrapper foo               bar > test.txt
    diff -u test.txt $expectedPath
  '';
}
