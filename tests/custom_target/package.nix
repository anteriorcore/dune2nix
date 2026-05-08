{ dune2nix, linkFarm }:

# There are two ways to define a custom target:
let
  # 1: directly as an argument to the mk function:
  direct = dune2nix.mkDuneProject {
    src = ./.;
    target = "@pkg-install";
  };

  # 2: override the final derivation:
  overridden =
    (dune2nix.mkDuneProject {
      src = ./.;
      # NOMERGE just testing
      DUNE_CACHE = "enabled";
      separateDepsDeriv = true;
    }).overrideAttrs
      { target = "@pkg-install"; };
in
linkFarm "custom_target" (
  builtins.mapAttrs (
    _: v:
    v.overrideAttrs {
      # Just testing that we can build the dependencies
      installPhase = "touch $out";
    }
  ) { inherit direct overridden; }
)
