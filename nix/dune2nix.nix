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
      mkDuneProject =
        {
          src,
          duneProject ? src + "/dune-project",
          duneLock ? src + "/dune.lock",
          enableParallelBuilding ? true,
          ...
        }@args:
        let
          inherit (self.lib) sexp;

          # Patch "fetch" blocks (in "sources" and "extra_sources") to "copy"
          # block pointing to Nix store path.
          patchLock =
            parsed:
            let
              parseFetch =
                nodes:
                fetchurl {
                  url = sexp.scalar [ "fetch" "url" ] nodes;
                  # Dune uses "<algo>=<hash>" format, while Nix uses "<algo>:<hash>".
                  hash = lib.replaceStrings [ "=" ] [ ":" ] (sexp.scalar [ "fetch" "checksum" ] nodes);
                };

              source =
                let
                  source = sexp.get [ "source" ] parsed;
                in
                if source != null then parseFetch source else null;

              extraSources =
                let
                  extraSources = sexp.get [ "extra_sources" ] parsed;
                in
                lib.optionalAttrs (extraSources != null) (
                  lib.listToAttrs (
                    map (
                      extraSource: lib.nameValuePair (lib.head extraSource) (parseFetch (lib.tail extraSource))
                    ) extraSources
                  )
                );

              mkCopySource = name: path: [
                name
                [
                  "copy"
                  path
                ]
              ];

              base = lib.pipe parsed [
                (sexp.delete [ "source" ])
                (sexp.delete [ "extra_sources" ])
              ];

              sourceNode = lib.optional (source != null) (mkCopySource "source" source);

              extraSourcesNode = lib.optional (extraSources != { }) (
                [ "extra_sources" ] ++ lib.mapAttrsToList mkCopySource extraSources
              );
            in
            base ++ sourceNode ++ extraSourcesNode;

          patchedDuneLock = linkFarm "dune.lock" (
            lib.pipe (builtins.readDir duneLock) [
              (lib.optionalAttrs (lib.pathExists duneLock))
              (lib.mapAttrs (name: _: sexp.parseFile (duneLock + "/${name}")))
              (lib.mapAttrs (
                name: parsed:
                if name == "lock.dune" then
                  # Notiong to patch for `lock.dune`. Afaik it is only used
                  # during re-locking (i.e. *not*  used during building).
                  sexp.toString parsed
                else
                  sexp.toString (patchLock parsed)
              ))
              (lib.mapAttrs writeText)
            ]
          );

          project = sexp.parseFile duneProject;

          jobsFlag = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";
        in
        stdenv.mkDerivation {
          inherit src;
          pname = args.name or sexp.scalar [ "package" "name" ] project;
          version = args.version or "0.0.0";
          strictDeps = true;
          nativeBuildInputs = [
            dune
            # Dune tries to write in ~/.cache
            writableTmpDirAsHomeHook
          ];
          patchPhase = ''
            runHook prePatch

            rm -rf dune.lock
            cp -rL ${patchedDuneLock} dune.lock

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
