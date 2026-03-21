{ self, ... }:
{
  flake.lib.dune2nix =
    {
      lib,
      newScope,
      fetchurl,
      linkFarm,
      writeText,
      dune,
      stdenv,
      writableTmpDirAsHomeHook,
      overrideScope ? _: _: { },
    }:
    let
      inherit (self.lib) sexp;

      mkDuneProject =
        {
          src,
          duneProject ? src + "/dune-project",
          duneWorkspace ? src + "/dune-workspace",

          # TODO: support context
          duneLock ?
            let
              project = sexp.parseFile duneWorkspace;
            in
            src
            + "/${
              if (lib.pathExists duneWorkspace && sexp.has [ "lock_dir" "path" ] project) then
                sexp.scalar [ "lock_dir" "path" ] project
              else
                "dune.lock"
            }",

          enableParallelBuilding ? true,
          ...
        }@args:
        let
          # Patch "fetch" blocks (in "source" and "extra_sources") to "copy"
          # blocks pointing to Nix store paths.
          patchLock =
            let
              parseFetch =
                nodes:
                fetchurl {
                  url = sexp.scalar [ "url" ] nodes;
                  # Dune uses "<algo>=<hash>" format, while Nix uses "<algo>:<hash>".
                  hash = lib.replaceString "=" ":" (sexp.scalar [ "checksum" ] nodes);
                };

              # Replace (fetch ...) with (copy <store-path>) in children
              patchFetchToCopy =
                nodes:
                if sexp.has [ "fetch" ] nodes then
                  [
                    [
                      "copy"
                      (parseFetch (sexp.get [ "fetch" ] nodes))
                    ]
                  ]
                else
                  nodes;
            in
            parsed:
            lib.pipe parsed [
              (sexp.update [ "source" ] patchFetchToCopy)
              (sexp.update [ "extra_sources" ] (
                map (entry: [ (lib.head entry) ] ++ patchFetchToCopy (lib.tail entry))
              ))
            ];

          patchedDuneLock = linkFarm "dune.lock" (
            lib.mapAttrs (
              name: _:
              let
                text = lib.readFile (duneLock + "/${name}");
                patched =
                  if name == "lock.dune" then
                    # Nothing to patch for `lock.dune`, it's only used during
                    # relocking (i.e. not used during build).
                    text
                  else
                    lib.pipe text [
                      sexp.parse
                      patchLock
                      sexp.toString
                    ];
              in
              writeText name patched
            ) (builtins.readDir duneLock)
          );

          project = sexp.parseFile duneProject;

          jobsFlag = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";
        in
        # Heavily inspied by: https://github.com/NixOS/nixpkgs/blob/27894d0586cf031cd5b3b345b6f9676c99ca6bac/pkgs/build-support/ocaml/dune.nix
        stdenv.mkDerivation {
          inherit src;
          pname = args.name or sexp.scalar [ "package" "name" ] project;
          version = args.version or "0.0.0";

          strictDeps = true;

          nativeBuildInputs = [
            dune
            # Dune wants to write in ~/.cache
            writableTmpDirAsHomeHook
          ];

          patchPhase = ''
            runHook prePatch

            ${
              let
                relativePath = lib.removePrefix "${toString src}/" (toString duneLock);
              in
              lib.optionalString (lib.pathExists duneLock) ''
                rm -rf ${relativePath}
                cp -rL ${patchedDuneLock} ${relativePath}
              ''
            }

            runHook postPatch
          '';
          buildPhase = ''
            runHook preBuild

            dune build ${jobsFlag}

            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall

            dune install --prefix $out

            runHook postInstall
          '';
          checkPhase = ''
            runHook preCheck

            dune runtest ${jobsFlag}

            runHook postCheck
          '';
        };

      scope = lib.makeScope newScope (_: {
        inherit mkDuneProject;
      });
    in
    scope.overrideScope overrideScope;
}
