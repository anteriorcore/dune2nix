{ inputs, ... }:
{
  # An optional overlay to fix issues with Dune, using the latest build from
  # upstream. It may break any packages that uses Dune: use with caution, no
  # guarantee that this works for you.
  flake.overlays.dune = (
    final: prev:
    let
      inherit (final.stdenv.hostPlatform) system;

      # [1]: https://github.com/ocaml/dune/pull/12583 (Dune Pins itself #12583)
      # [2]: https://github.com/ocaml/dune/pull/13901 (fix(pkg): prefer stronger hash in lock #13901)
      inherit (inputs.dune.packages.${system}) dune;

      inherit (inputs.nixpkgs.legacyPackages.${system}) ocamlformat ocamlPackages;
    in
    {
      inherit dune;
      dune_3 = dune;

      # Pin OCaml packages that we don't want to rebuild here, because
      # ocamlPackages breaks after 3.20.2
      inherit ocamlformat;
      ocamlPackages = ocamlPackages // {
        inherit (ocamlPackages) ocaml-lsp;
      };
    }
  );
}
