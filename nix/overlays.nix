{ inputs, ... }:
{
  # An optional overlay to fix issues with Dune. It may break any packages that
  # uses Dune: use with caution, no warranty that this works for you.
  flake.overlays.dune = (
    final: prev:
    let
      dune = prev.dune.overrideAttrs (old: rec {
        # Dune has a critical bug with lockfile generation[1] that was fixed in
        # 3.21.0[2] (Nixpkgs 25.11 & unstable both has dune pinned at 3.20.2).
        # Nixpkgs staging has it pinned at 3.21.1[3], so we use this version.
        #
        # [1]: https://github.com/ocaml/dune/issues/12381 (dune pkg lock can select packages incompatible with itself #12381)
        # [2]: https://github.com/ocaml/dune/pull/12583 (Dune Pins itself #12583)
        # [3]: https://github.com/NixOS/nixpkgs/pull/489721 (dune: 3.20.2 -> 3.21.1 #489721)
        version = "3.21.1";

        src = final.fetchurl {
          url = "https://github.com/ocaml/dune/releases/download/${version}/dune-${version}.tbz";
          hash = "sha256-hPeoLG2ApxJPOEfppInoDPvq+3vtNXOsAShu9W/QjZQ=";
        };

        # Dune uses the "first" hash, i.e. prioritizes "m"d5 over
        # "s"ha256/512! The patch leverages `OpamHash::sort` to
        # prioritize "stronger" hash.
        patches = (old.patches or [ ]) ++ [ ../patches/dune.patch ];
      });

      pkgs = inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system};
    in
    {
      inherit dune;
      dune_3 = dune;

      # Pin OCaml packages that we don't want to rebuild here, because
      # ocamlPackages breaks after 3.20.2
      inherit (pkgs) ocamlformat;

      ocamlPackages = pkgs.ocamlPackages // {
        inherit (pkgs.ocamlPackages) ocaml-lsp;
      };
    }
  );
}
