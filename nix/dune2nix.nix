{ self, ... }:
{
  flake.lib.dune2nix =
    {
      lib,
      newScope,
      fetchurl,
      linkFarm,
      dune,
      stdenv,
      writableTmpDirAsHomeHook,
      writeText,
      zstd,
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
            srcOverrides ? _: _: { },
            duneWorkspace ? src + "/dune-workspace",

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
                ctx = lib.optionals (sexp.has [ "context" ] parsed) (
                  sexp.get [ "context" finalAttrs.context ] parsed
                );
              in
              if (lib.pathExists duneWorkspace && sexp.has [ "lock_dir" ] ctx) then
                sexp.scalar [ "lock_dir" ] ctx
              else
                "dune.lock";

            duneLock = args.duneLock or (src + "/${lockDir}");

            # Build a dune.lock/xxxx.pkg file from the structure defined in its
            # own passthru elements.  This is primarily useful as target for
            # overlays who want to change something about the dependency source
            # before it goes into the final large build.
            mkLockFile =
              name:
              stdenv.mkDerivation (
                self:
                let
                  fetch =
                    {
                      name,
                      url,
                      checksum,
                      ...
                    }:
                    stdenv.mkDerivation {
                      name = "${name}-src";
                      src = fetchurl {
                        inherit url;
                        # Dune uses "<algo>=<hash>" format, while Nix uses "<algo>:<hash>".
                        hash = lib.replaceString "=" ":" checksum;
                      };
                      # Some of the fixupPhases are extremely useful, others are
                      # actively harmful to a supposedly transparent tarball unpacking
                      # derivation.  Particularly block passes which change file
                      # locations.
                      dontMoveSbin = true;
                      # Extract single file archives into single file derivations
                      postHook = ''
                        unpackCmdHooks+=(singleFileArchive)
                        fileToCopy=.
                        singleFileArchive() {
                          for f in */ ; do
                            if [[ -d "$f" ]]; then
                              return 0
                            fi
                          done
                          mkdir source
                          fileToCopy="$1"
                        }
                        # This fixup phase has no individual flag, so override the
                        # implementing function (yuck)
                        _moveToShare() {
                          true
                        }
                      '';
                      # A very useful default phase, but there’s one particular
                      # type of dune build instruction which (apparently) risks
                      # causing build problems when combined with fixupPhase:
                      # (patch ...).  Heuristic for fixupPhase of the source is
                      # therefore a little complicated, but probably worth it:
                      # enable, unless the dune build instructions include
                      # patching.
                      dontFixup =
                        let
                          build = self.passthru.sexp.build or [ ];
                          imap0Recursive =
                            f: lib.imap0 (idx: el: if builtins.isList el then imap0Recursive f el else f idx el);
                          anyRecursive = f: builtins.any (el: if builtins.isList el then anyRecursive f el else f el);
                          iany0Recursive = f: els: anyRecursive lib.id (imap0Recursive f els);
                        in
                        iany0Recursive (idx: el: el == "patch" && idx == 0) build;
                      installPhase = ''
                        runHook preInstall

                        if [[ -d "$fileToCopy" ]]; then
                          cp -r "$fileToCopy" $out
                        else
                          cp "$fileToCopy" $out
                        fi

                        runHook postInstall
                      '';
                      phases = [
                        "unpackPhase"
                        "patchPhase"
                        "installPhase"
                        "fixupPhase"
                      ];
                    };

                  # Turn a dependency location sexp ([ "fetch" ... ], [ "copy" ... ])
                  # into an attrset.  Also converts a { fetch = ... } with a url and
                  # checksum into a { copy = <fixed output derivation fetcher of the
                  # url> }.
                  parseLocationSexp =
                    name: nodes:
                    let
                      a = sexp.fromAlist nodes;
                    in
                    if a ? fetch then
                      let
                        node = builtins.mapAttrs (_: builtins.head) (sexp.fromAlist a.fetch);
                        drv =
                          if (node ? checksum) then
                            fetch (
                              {
                                inherit name;
                                lockFileSexp = a;
                              }
                              // node
                            )
                          else
                            src + "/${lib.removePrefix "file://" node.url}";
                      in
                      {
                        copy = drv;
                      }
                    else
                      a;

                  locationToAlist =
                    a: sexp.toAlist (builtins.mapAttrs (_: v: if builtins.isList v then v else [ v ]) a);

                  # like mapAttrs but takes an attrset of functions, and applies each
                  # value from the input attrset to the function of the same name in
                  # the function map, if present.  If not present, the value is passed
                  # through verbatim.
                  mapAttrsOptional = fns: builtins.mapAttrs (n: fns.${n} or lib.id);

                  # Convert a parsed lock file in sexp mode to an attrset containing
                  # only its source(s), all as attrsets:
                  #
                  # [ .... ["source" ["fetch" ...]] ["extra_sources ["a" ..] ["b" ..]]]
                  #
                  # =>
                  #
                  # {
                  #   {
                  #     source.copy = <a derivation>;
                  #     extra_sources = {
                  #       a = ...;
                  #       b = ...;
                  #     };
                  #   }
                  # }
                  #
                  # Both fields are optional.
                  parseLockSexp =
                    name:
                    mapAttrsOptional {
                      source = parseLocationSexp name;
                      extra_sources = v: builtins.mapAttrs parseLocationSexp (sexp.fromAlist v);
                    };

                  # Convert a fully parsed lock file, with our custom sourceSpec
                  # semantics, back into its original sexp form.
                  lockFileToAlist =
                    a:
                    sexp.toAlist (
                      mapAttrsOptional {
                        source = locationToAlist;
                        extra_sources = v: sexp.toAlist (builtins.mapAttrs (_: locationToAlist) v);
                      } a
                    );

                  original = lib.readFile (duneLock + "/${name}");
                  # Assumption: lockfiles are alists at the toplevel.
                  a = sexp.fromAlist (sexp.parse original);
                in
                {
                  inherit name;
                  passthru = {
                    sexp = parseLockSexp name a;
                    # Nothing to patch for `lock.dune`, it's only used during
                    # relocking (i.e. not used during build).
                    text = if name == "lock.dune" then original else sexp.toString (lockFileToAlist self.passthru.sexp);
                  };
                  dontUnpack = true;
                  contents = writeText name self.passthru.text;
                  installPhase = "cp $contents $out";
                }
              );

            lockFiles = lib.fix (
              lib.extends srcOverrides (_: lib.mapAttrs (name: _: mkLockFile name) (builtins.readDir duneLock))
            );
            patchedLock = linkFarm lockDir lockFiles;

            # Flags used for `dune build` and `runtest`.
            flags = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";
          in
          {
            strictDeps = true;
            passthru = args.passthru or { } // {
              inherit patchedLock lockDir lockFiles;
            };

            nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
              dune
              # Dune wants to write in ~/.cache
              writableTmpDirAsHomeHook
            ];

            buildInputs = [
              # Almost every package installs ocaml-compiler, and if you don’t
              # provide zstd you get this message during the configure phase:
              #
              #   configure: WARNING: zstd library not found
              #   configure: WARNING: compressed compilation artefacts not supported
              #
              # Might as well just provide it by default.
              zstd
            ];

            patchPhase = ''
              runHook prePatch

              ${lib.optionalString (lib.pathExists duneLock) ''
                rm -rf ${lockDir}
                cp -rL ${patchedLock} ${lockDir}
              ''}

              runHook postPatch
            '';

            duneBuildFlags = [ "--display=short" ];

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
            context = args.context or "default";

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
            target = args.target or "_build/${finalAttrs.context}";

            buildPhase = ''
              runHook preBuild

              dune build $duneBuildFlags $target ${flags}

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              dune install --context $context --prefix $out

              runHook postInstall
            '';

            checkPhase = ''
              runHook preCheck

              dune runtest $target ${flags}

              runHook postCheck
            '';
          };

        excludeDrvArgNames = [
          "duneProject"
          "duneWorkspace"
          "duneLock"
          "context"
          "enableParallelBuilding"
          "srcOverrides"
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
            binDuneFile ? (src + "/bin/dune"),
            meta ? { },
            ...
          }:
          let
            project = sexp.parseFile duneProject;
            # _Technically_ bin/dune is just convention, and __technically__
            # you can have multiple "executable" stanzas.  So for "proper"
            # compliance you'd collect all the executable and executables
            # across all the dune files and decide which main program to
            # pick... this is a sensible default and we can address if needed.
            defaultMeta = lib.optionalAttrs (lib.pathExists binDuneFile) (
              let
                binDune = sexp.fromAlistN 2 (sexp.parseFile binDuneFile);
                mainProgram = lib.head (
                  binDune.executable.public_name or binDune.executables.public_names or [ null ]
                );
              in
              lib.optionalAttrs (mainProgram != null) { inherit mainProgram; }
            );
          in
          {
            name = sexp.scalar [ "package" "name" ] project;
            meta = defaultMeta // meta;
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
