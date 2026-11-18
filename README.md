# dune2nix

Turn [Dune](https://dune.build)-based OCaml projects into
[Nix](https://nixos.org) derivations.

`dune2nix` parses Dune's lockfiles fully at Nix eval time, which gives us: no
codegen, no
[Import From Derivation (IFD)](https://nix.dev/manual/nix/2.26/language/import-from-derivation),
no hardcoded hash.

## Demo

There is a demo project in [`./demo`](./demo) that uses dune2nix with
[Nix flakes](https://nixos.wiki/wiki/flakes).

## Copyright & License

`dune2nix` is authored by Anterior, based in NYC, USA.

We’re hiring! If you got this far, e-mail us at hiring+oss@anterior.com and
mention this project.

The code is available under the GPLv3 license (not later).

See the [LICENSE](./LICENSE) file.
