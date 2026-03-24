# dune2nix

Turn [Dune](https://dune.build)-based OCaml projects into
[Nix](https://nixos.org) derivations.

Unlike other lang2nix tools, `dune2nix` parses Dune's lockfiles fully at Nix
eval time, which gives us: no codegen, no
[Import From Derivation (IFD)](https://nix.dev/manual/nix/2.26/language/import-from-derivation),
no hardcoded hash.

## Overlay

The version of Dune included in the current Nixpkgs release (25.11) has critical
bugs related to lockfile handling. `dune2nix` provides an optional overlay that
uses the latest build that address these issues. For more details, see
[`./nix/overlays.nix`](./nix/overlays.nix).

## Demo

There is a minimal demo project that uses
[`janestreet/core`](https://github.com/janestreet/core) in
[`./tests/demo`](./tests/demo).

## Related Projects

- [opam-nix](https://github.com/tweag/opam-nix): Turns
  [Opam](https://opam.ocaml.org) projects into Nix, requires IFD.
- [opam2nix](https://github.com/timbertson/opam2nix): Classical lang2nix
  approach, requires codegen.

## Copyright & License

`dune2nix` is authored by Anterior, based in NYC, USA.

We’re hiring! If you got this far, e-mail us at hiring+oss@anterior.com and
mention this project.

The code is available under the AGPLv3 license (not later).

See the [LICENSE](./LICENSE) file.
