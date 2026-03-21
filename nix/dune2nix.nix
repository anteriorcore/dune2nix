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
        let
          # Default is "lock.dune", and can be customized via dune-workspace's
          # context.${name}.lock_dir stanza.
          resolveLockDir =
            duneWorkspace: context:
            let
              ctx = lib.pipe duneWorkspace [
                sexp.parseFile
                (sexp.get [
                  "context"
                  context
                ])
              ];
            in
            if (lib.pathExists duneWorkspace && sexp.has [ "lock_dir" ] ctx) then
              sexp.scalar [ "lock_dir" ] ctx
            else
              "dune.lock";
        in
        {
          src,
          duneProject ? src + "/dune-project",

          # Any directory containing a dune-project file implicitly acts as a
          # workspace root.
          duneWorkspace ? src + "/dune-workspace",

          # Context to build in. # TODO: Support Opam switch context.
          # https://dune.readthedocs.io/en/stable/reference/dune-workspace/context.html
          context ? "default",
          lock ? src + "/${resolveLockDir duneWorkspace context}",
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
              fetchToCopy =
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
              (sexp.update [ "source" ] fetchToCopy)
              (sexp.update [ "extra_sources" ] (
                map (entry: [ (lib.head entry) ] ++ fetchToCopy (lib.tail entry))
              ))
            ];

          lockDir = resolveLockDir duneWorkspace context;

          patchedLock = linkFarm lockDir (
            lib.mapAttrs (
              name: _:
              let
                text = lib.readFile (lock + "/${name}");
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
            ) (builtins.readDir lock)
          );

          project = sexp.parseFile duneProject;

          jobsFlag = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";
        in
        # Heavily inspied by: https://github.com/NixOS/nixpkgs/blob/27894d0586cf031cd5b3b345b6f9676c99ca6bac/pkgs/build-support/ocaml/dune.nix
        stdenv.mkDerivation {
          inherit src;
          name = sexp.scalar [ "package" "name" ] project;

          strictDeps = true;

          nativeBuildInputs = [
            dune
            # Dune wants to write in ~/.cache
            writableTmpDirAsHomeHook
          ];

          patchPhase = ''
            runHook prePatch

            ${lib.optionalString (lib.pathExists lock) ''
              rm -rf ${lockDir}
              cp -rL ${patchedLock} ${lockDir}
            ''}

            runHook postPatch
          '';

          # For some reason, `dune build` and `dune runtest` don't accept the
          # `--context` flag, instead, you specify the build target directory
          # (`_build/${context}`) - I _hope_ this works, but I wouldn't be
          # surprised at all even if this breaks.

          # https://github.com/ocaml/dune/issues/9672
          buildPhase = ''
            runHook preBuild

            dune build _build/${context}/ ${jobsFlag}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            dune install --context ${context} --prefix $out

            runHook postInstall
          '';

          # https://github.com/ocaml/dune/blob/33b6ab730ce2bf0a78aaac116d7e95db6c71c45c/bin/runtest.ml#L29
          checkPhase = ''
            runHook preCheck

            dune runtest _build/${context}/ ${jobsFlag}

            runHook postCheck
          '';
        }
        // lib.optionalAttrs (sexp.has [ "version" ] project) { version = sexp.get [ "version" ] project; };

      scope = lib.makeScope newScope (_: {
        inherit mkDuneProject;
      });
    in
    scope.overrideScope overrideScope;
}
