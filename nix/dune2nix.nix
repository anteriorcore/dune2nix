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

      # Creates a non-executable derivation that builds all projects in a
      # workspace. Think of this as running `dune build` in the workspace root.
      #
      # This is the core of the library and used internally by `mkDuneProject`.
      # Although it's public, I advise against using it directly, as it makes
      # granular source control impossible.
      #
      # `dune.lock/lock.dune` files contain a `dependency_hash`, which is
      # computed from all the `dune-project` files in the workspace. If there
      # is a hash mismatch during build, Dune will error out: this prevents
      # editing `dune-project` without updating the lockfiles. So in order to
      # build a _single_ project in a workspace, you need a source set of 1.
      # the project you're trying to build, and 2. all the `dune-project` files
      # in the workspace. Although this is a little heinous, it's still
      # possible - the problem is that Dune errors again because now there are
      # "empty" `dune-project`s - i.e. projects without user-defined stanzas in
      # `dune` files. So now we add `dune` files and guess what - Dune yet
      # again errors because the `dune` files are invalid (they don't have the
      # associated sources)! Dune does provide an `(allow_empty)` stanza that
      # can be added to `dune-project` to suppress empty project errors, but
      # this doesn't work either because it would change the `dependency_hash`.
      # The conclusion is that to build a single project in a workspace, you
      # need the entire workspace, which means a single line change in one
      # project causes a full rebuild of the workspace.
      #
      # Here's a tip for people who absolutely want to use workspaces: don't!
      #
      # https://dune.readthedocs.io/en/stable/explanation/scopes.html
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

            # NOMERGE
            __dangerouslyEnableIncrementalBuild ? false,
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
                # Replace (fetch ...) with (copy <store-path>)
                fetchToCopy =
                  nodes:
                  if sexp.has [ "fetch" ] nodes then
                    let
                      node = sexp.get [ "fetch" ] nodes;
                      drv = fetchurl {
                        url = sexp.scalar [ "url" ] node;
                        # Dune uses "<algo>=<hash>" format, while Nix uses "<algo>:<hash>".
                        hash = lib.replaceString "=" ":" (sexp.scalar [ "checksum" ] node);
                      };
                    in
                    [
                      [
                        "copy"
                        drv
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

            duneDeps = lib.mapAttrs' (
              name: _:
              let
                parsed = sexp.parseFile (duneLock + "/${name}");
                depList = lib.optionals (sexp.has [ "depends" ] parsed) (
                  lib.filter (x: x != "dune") (lib.head (sexp.get [ "depends" "all_platforms" ] parsed))
                );

                packageName = lib.head (lib.splitString "." name);

                # NOMERGE wtf
                packageTarget =
                  if (packageName == "ocaml-compiler") then
                    "_build/default/dune.lock/ocaml-compiler.5.4.1.pkg"
                  else
                    "_build/_private/${context}/.pkg/$(dune pkg print-digest ${packageName})";

              in
              lib.nameValuePair packageName (
                stdenv.mkDerivation {
                  name = packageName;
                  nativeBuildInputs = [
                    dune
                    writableTmpDirAsHomeHook
                  ]
                  ++ (lib.attrVals depList duneDeps);

                  src = lib.fileset.toSource {
                    root = src;
                    fileset = lib.fileset.unions [
                      # NOMERGE i think we need all the dune-projects
                      (src + "/dune-project")
                      # NOMERGE only select the ones we need
                      duneLock
                    ];
                  };
                  patchPhase = ''
                    rm -rf ${lockDir}
                    cp -rL ${patchedLock} ${lockDir}
                  '';
                  buildPhase = ''
                    dune build ${packageTarget}
                  '';
                  installPhase = ''
                    dune install --context ${packageTarget} --prefix $out
                  '';
                }
              )
            ) (
              # NOMERGE
              lib.filterAttrs (k: _: k != "lock.dune") (builtins.readDir duneLock));
          in
          {
            strictDeps = true;

            nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
              dune
              # Dune wants to write in ~/.cache
              writableTmpDirAsHomeHook

              (lib.attrValues duneDeps)
            ];

            passthru = { inherit duneDeps; };

            patchPhase = ''
              runHook prePatch

              ${lib.optionalString (lib.pathExists duneLock) ''
                rm -rf ${lockDir}

                ${lib.optionalString (!__dangerouslyEnableIncrementalBuild) ''
                  cp -rL ${patchedLock} ${lockDir}
                ''}
              ''}

              runHook postPatch
            '';

            buildPhase = ''
              runHook preBuild

              dune build --display=short ${target} ${flags}

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
          };

        excludeDrvArgNames = [
          "duneProject"
          "duneWorkspace"
          "duneLock"
          "context"
          "enableParallelBuilding"
          "__dangerouslyEnableIncrementalBuild"
        ];
      };

      # A directory with a `dune-project` file implicitly forms a Dune
      # workspace,  so this is a thin wrapper around mkDuneWorkspace that
      # parses the `dune-project` file.
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
