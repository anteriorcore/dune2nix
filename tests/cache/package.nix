{ dune2nix }:

dune2nix.mkDuneProject {
  src = ./.;
  doCheck = true;
  duneSeparateDeps = true;
  # Set this to force everything into the global cache (which is also stored in
  # the Nix store).  A regular separate-derivations build puts everything in
  # _build, but when cache is enabled it will go through a separate dir instead.
  # To be perfectly frank I’m not 100% on what the difference is, but I’m sure
  # there is some use case?  Either way the ocaml compiler must be relocatable
  # because the cache is first built separately, then copied to a new cache dir
  # for the final derivation.
  DUNE_CACHE = "enabled";
}
