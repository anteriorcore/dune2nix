{
  dune,
  dune2nix,
  runCommand,
}:

let
  one = dune2nix.mkDuneProject {
    src = ./.;
    duneIncludeBuildOutputs = true;
  };
  two = one.overrideAttrs { separateDepsDeriv = true; };
in
runCommand "test"
  {
    oneBuild = one.build;
    oneCache = one.cache;
    twoBuild = two.build;
    twoCache = two.cache;
    nativeBuildInputs = [ dune ];
  }
  ''
    dune trace cat --trace-file $oneBuild/trace.csexp > $out
    dune trace cat --trace-file $twoBuild/trace.csexp >> $out
    ls -R $oneCache >> $out
    ls -R $twoCache >> $out
  ''
