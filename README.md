# dune2nix

Turn [Dune](https://dune.build)-based OCaml projects into
[Nix](https://nixos.org) derivations.

Unlike other lang2nix tools, `dune2nix` parses Dune's lockfiles fully at Nix
eval time, which gives us: no codegen, no IFD, no hardcoded hash.

## Overlay

The version of Dune included in the current Nixpkgs release (`25.11`) has a
critical bug related to lockfile handling. `dune2nix` provides an optional
overlay that applies a minimal patch to fix this. For more details, see
[`./nix/overlays.nix`](./nix/overlays.nix).

## Demo

There is a minimal demo project that uses
[`janestreet/core`](https://github.com/janestreet/core) in
[`./tests/demo`](./tests/demo).

## Related Projects

- [opam-nix](https://github.com/tweag/opam-nix): Turns
  [Opam](https://opam.ocaml.org) projects into Nix, requires IFD.
- [opam2nix](https://github.com/timbertson/opam2nix): Similar to opam-nix,
  requires codegen.
