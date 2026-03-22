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

      # Create a non-executable derivation that builds all projects in the
      # workspace: think of this as running `dune build` in the workspace root.
      mkDuneWorkspace = lib.extendMkDerivation {
        constructDrv = stdenv.mkDerivation;
        extendDrvArgs =
          finalAttrs:
          {
            src,
            duneWorkspace ? src + "/dune-workspace",

            # The build context. Dune supports "default" and Opam switch context,
            # but I'm not convinced that we should support the latter: if you're
            # using Opam switch (not managing package via Dune), you probably
            # don't want to use this library anyways.
            #
            # One situation where this might not be true, is when you manage
            # Dune via Opam, and rest of the packages via Dune. But that's also
            # unlikely because the user of this library would use Nix (via
            # devshell) to manage Dune.
            #
            # Devex would also be terrible: the user would have to commit the
            # Opam export file (generated via `opam export --freeze --full`),
            # which is extremely hard to keep in sync across the team, because
            # of Opam switch's impure nature.
            #
            # I will leave the door open, but I will not spend my complexity
            # budget here.
            #
            # https://dune.readthedocs.io/en/stable/reference/dune-workspace/context.html
            context ? "default",

            # Conventional flag used by many builders in nixpkgs including Dune.
            # In Dune, it's used to set `-j` (jobs) flag.
            enableParallelBuilding ? true,
            ...
          }@args:
          let
            # Default is "dune.lock", and can be customized via dune-workspace's
            # context.${name}.lock_dir stanza.
            lockDir =
              let
                parsed = sexp.parseFile duneWorkspace;
                ctx = lib.optionals (sexp.has [ "context" ] parsed) (sexp.get [ "context" context ] parsed);
              in
              if (lib.pathExists duneWorkspace && sexp.has [ "lock_dir" ] ctx) then
                sexp.scalar [ "lock_dir" ] ctx
              else
                "dune.lock";

            duneLock = args.duneLock or (src + "/${lockDir}");

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

                # Replace (fetch ...) with (copy <store-path>)
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
              (lib.flip lib.pipe) [
                (sexp.update [ "source" ] fetchToCopy)
                (sexp.update [ "extra_sources" ] (
                  map (entry: [ (lib.head entry) ] ++ fetchToCopy (lib.tail entry))
                ))
              ];

            patchedLock = linkFarm lockDir (
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

            # For some reason, `dune build` and `dune runtest` don't accept the
            # `--context` flag. Instead, you specify the build target directory
            # (`_build/${context}`) -- I _hope_ this works, but I wouldn't be
            # surprised at all even if this suddenly breaks. As I mentioned
            # above context support is best-effort: it's very possible that I
            # rip this out for a very minor issue.
            #
            # build:
            # https://github.com/ocaml/dune/issues/9672
            #
            # runtest:
            # https://github.com/ocaml/dune/blob/33b6ab730ce2bf0a78aaac116d7e95db6c71c45c/bin/runtest.ml#L29
            target = "_build/${context}";

            # Flags used for `dune build` and `runtest`.
            flags = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";
          in
          {
            strictDeps = true;

            nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
              dune
              # Dune wants to write in ~/.cache
              writableTmpDirAsHomeHook
            ];

            patchPhase = ''
              runHook prePatch

              ${lib.optionalString (lib.pathExists duneLock) ''
                rm -rf ${lockDir}
                cp -rL ${patchedLock} ${lockDir}
              ''}

              runHook postPatch
            '';

            buildPhase = ''
              runHook preBuild

              dune build ${target} ${flags}

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              dune install --context ${context} --prefix $out

              runHook postInstall
            '';

            checkPhase = ''
              runHook preCheck

              dune runtest ${target} ${flags}

              runHook postCheck
            '';

            passthru.duneProjects = lib.pipe src [
              lib.filesystem.listFilesRecursive
              (lib.filter (p: builtins.baseNameOf p == "dune-project"))
              (map (
                duneProject:
                let
                  project = sexp.parseFile duneProject;
                  dir = builtins.dirOf duneProject;
                in
                lib.nameValuePair (sexp.scalar [ "package" "name" ] project) (mkDuneProject {
                  src = lib.fileset.toSource {
                    root = src;
                    fileset = lib.fileset.unions [
                      duneLock
                      duneWorkspace
                      dir
                      (lib.fileset.fileFilter (file: file.name == "dune-project" || file.name == "dune") src)
                    ];
                  };
                  inherit duneProject duneLock;
                })
              ))
              lib.listToAttrs
            ];
          };

        excludeDrvArgNames = [
          "duneProject"
          "duneWorkspace"
          "duneLock"
          "context"
          "enableParallelBuilding"
        ];
      };

      # Directory containing a dune-project implicitly forms a Dune workspace.
      # Consider this a "dune-project parser" - the main logic lives in
      # mkDuneWorkspace.
      mkDuneProject = lib.extendMkDerivation {
        constructDrv = mkDuneWorkspace;
        extendDrvArgs =
          finalAttrs:
          {
            src,
            duneProject ? src + "/dune-project",
            ...
          }:
          let
            project = sexp.parseFile duneProject;
          in
          {
            name = sexp.scalar [ "package" "name" ] project;
          }
          // lib.optionalAttrs (sexp.has [ "version" ] project) {
            version = sexp.scalar [ "version" ] project;
          };

        excludeDrvArgNames = [ "duneProject" ];
      };

      scope = lib.makeScope newScope (_: {
        inherit mkDuneProject mkDuneWorkspace;
      });
    in
    scope.overrideScope overrideScope;
}
