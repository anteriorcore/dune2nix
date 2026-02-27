{ ... }:
{
  perSystem.treefmt.programs = {
    # keep-sorted start block=yes
    actionlint.enable = true;
    keep-sorted.enable = true;
    mdformat = {
      enable = true;
      settings = {
        wrap = 80;
        end-of-line = "lf";
      };
    };
    nixfmt = {
      enable = true;
      strict = true;
    };
    ocamlformat.enable = true;
    typos.enable = true;
    # keep-sorted end
  };
}
