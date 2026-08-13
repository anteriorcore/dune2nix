{ self, ... }: {
  flake.lib.dune2nix =
    {
      lib,
      newScope,
      dune,
      fetchurl,
      linkFarm,
      jq,
      stdenv,
      writableTmpDirAsHomeHook,
      writeText,
      zstd,
      overrideScope ? _: _: { },
    }:
    let
      # Like lib.attrsets.getAttrs but skip missing names
      getAttrsSafe = names: a: lib.getAttrs (builtins.filter (n: builtins.hasAttr n a) names) a;
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
            name,
            src,
            srcOverrides ? _: _: { },
            duneWorkspace ? src + "/dune-workspace",

            # Create a separate derivation with only the dependencies (target
            # ‘@pkg-install’).  Caches the built dependencies and only rebuilds
            # when there's a change in `dune-*` files.  Use with caution: all
            # dependencies, including ocamlc, must be relocatable.  The ocaml
            # compiler only became relocatable with 5.5.0.
            duneSeparateDeps ? true, # NOMERGE

            # Sanity check to ensure that no cached entries are considered stale
            # by dune.  In a Nix context, that almost certainly means something
            # is wrong, and the failure mode is painful as it silently rebuilds
            # the dependency, which can surreptitiously inflate build times.
            # Only makes sense when getting cache from a separate derivation in
            # the first place.  (I’ve seen this check fail on a derivation that
            # was built atomically, and at that point, dune my dear, it’s out of
            # my hands...)
            duneCheckNoCacheMiss ? duneSeparateDeps,

            # Dune (Opam) gives a lot of liberty to the package build step and
            # it is technically possible to produce different build outputs
            # depending on the number of concurrency. However, just like many
            # Nix packages on Nixpkgs, dune2nix by default assume that none of
            # the packages would do that. If you _really_ need to depend on such
            # behavior and/or package, this is the escape hatch: set this to the
            # minimum number of cores that you and your team use; obviously the
            # build will be slower.
            jobs ? "$NIX_BUILD_CORES",
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
                    { name, src, ... }@args:
                    stdenv.mkDerivation {
                      name = "${name}-src";
                      inherit src;
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
                        inherit (node) url;
                        match = builtins.match "^([a-zA-Z0-9+_-]+)://(.*)" url;
                        protocol = if match == null then "file" else builtins.head match;
                        rest = builtins.elemAt match 1;
                        copy =
                          if protocol == "file" then
                            src + "/${rest}"
                          else if protocol == "git+https" then
                            fetch {
                              inherit name;
                              lockFileSexp = a;
                              src =
                                let
                                  s = lib.splitString "#" rest;
                                in
                                builtins.fetchGit {
                                  url = "https://${builtins.head s}";
                                  rev = lib.last s;
                                };
                            }
                          else if protocol == "http" || protocol == "https" then
                            fetch {
                              inherit name;
                              lockFileSexp = a;
                              src = fetchurl {
                                inherit url;
                                hash = lib.replaceString "=" ":" node.checksum;
                              };
                            }
                          else
                            throw "Unknown protocol: ${protocol}";
                      in
                      {
                        inherit copy;
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
            jobsFlag = "-j ${toString jobs}";

            # Derivation with only the dependencies built, for reuse during
            # builds of the application. Ideally we'd want to build each package
            # as an individual derivation, but that's pretty difficult and this
            # is the compromise we make now, though it will us pretty far. -
            # shun 2026-03
            #
            #   - $out/_build is the _build directory
            #
            #   - $out/cache is the (“global”) cache
            #
            # We initially tried to use a separate output for the cache
            # (‘cache’) but it caused problems with circular store references on
            # certain rachitectures.  This is simpler and works just as well.
            duneDeps = stdenv.mkDerivation (
              {
                name = "${finalAttrs.name}-deps";

                patchPhase = ''
                  runHook prePatch

                  cp -rL ${finalAttrs.passthru.patchedLock} ${finalAttrs.passthru.lockDir}

                  runHook postPatch
                '';

                # Since we're only building the dependencies, we don't need the
                # source. _Technically_ we need to collect all the `dune-*`
                # files in the workspace, but it's quite tedious.  We don’t feel
                # feel like implementing that, so we're skipping on this for
                # now.
                src = lib.fileset.toSource {
                  root = finalAttrs.src;
                  fileset = lib.fileset.fileFilter (
                    file:
                    lib.elem file.name [
                      "dune-project"
                      "dune-workspace"
                    ]
                  ) finalAttrs.src;
                };

                target = "@pkg-install";

                buildPhase = ''
                  export DUNE_CACHE_ROOT="$out/cache"
                  dune build $duneBuildFlags ${jobsFlag} $target
                '';

                buildInputs = lib.unique (
                  finalAttrs.buildInputs or [ ]
                  ++ [
                    # Almost every package installs ocaml-compiler, and if you
                    # don’t provide zstd you get this message during the configure
                    # phase:
                    #
                    #   configure: WARNING: zstd library not found
                    #   configure: WARNING: compressed compilation artefacts not supported
                    #
                    # Might as well just provide it by default.
                    zstd
                  ]
                );

                installPhase = ''
                  runHook preInstall

                  mkdir -p $out/cache
                  cp -r _build $out/

                  runHook postInstall
                '';

                # The dependencies shouldn’t be tampered with: just build and
                # copy.  Fixing up is left to the final derivation.
                dontFixup = true;
              }
              // getAttrsSafe [
                "depsBuildBuild"
                "depsBuildBuildPropagated"
                "nativeBuildInputs"
                "propagatedNativeBuildInputs"
                "defaultNativeBuildInputs"
                "depsBuildTarget"
                "depsBuildTargetPropagated"
                "depsHostHost"
                "depsHostHostPropagated"
                "propagatedBuildInputs"
                "defaultBuildInputs"
                "depsTargetTarget"
                "depsTargetTargetPropagated"

                "DUNE_CACHE"
                "DUNE_CACHE_STORAGE_MODE"
                "DUNE_TRACE"
                "context"
                "duneBuildFlags"
                "strictDeps"
              ] finalAttrs
            );
          in
          {
            strictDeps = true;

            # The default is "hardlink" which is a bad choice for Nix: it’s
            # likely the build directory lives on a different drive from the nix
            # store.  Strongly recommended to leave this as-is.
            DUNE_CACHE_STORAGE_MODE = args.DUNE_CACHE_STORAGE_MODE or "copy";

            inherit duneSeparateDeps duneCheckNoCacheMiss;

            passthru = args.passthru or { } // {
              inherit
                patchedLock
                lockDir
                lockFiles
                duneDeps
                ;
            };

            # zstd is needed for ocaml, but of course not if that’s built in a
            # separate derivation.
            buildInputs = args.buildInputs or [ ] ++ lib.optionals (!finalAttrs.duneSeparateDeps) [ zstd ];

            nativeBuildInputs =
              (args.nativeBuildInputs or [ ])
              ++ [
                dune
                # Dune wants to write in ~/.cache
                writableTmpDirAsHomeHook
              ]
              ++ lib.optionals finalAttrs.duneCheckNoCacheMiss [ jq ];

            # Set up the cache in case the program wants to use it.
            duneConfigureCachePhase = ''
              runHook preDuneConfigureCache

            ''
            + (
              if finalAttrs.duneIncludeBuildOutputs then
                ''
                  export DUNE_CACHE_ROOT="$cache"
                ''
              else
                ''
                  export DUNE_CACHE_ROOT="$(mktemp -d)"
                ''
            )
            + ''
              mkdir -p "$DUNE_CACHE_ROOT"
              runHook postDuneConfigureCache
            '';

            prePhases = args.prePhases or [ ] ++ [ "duneConfigureCachePhase" ];

            duneLoadCache = ''
              runHook preDuneLoacCache

              rm -rf ${lockDir}
            ''
            + lib.optionalString (lib.pathExists duneLock && !finalAttrs.duneSeparateDeps) ''
              cp -rL ${patchedLock} ${lockDir}
            ''
            + ''

              runHook postDuneLoacCache
            '';

            # Load pre-build to avoid changing the cache at all during configure
            # phase, updateAutotools.. phase, etc.  This helps avoid cache
            # invalidation by dune.
            preBuildPhases = args.preBuildPhases or [ ] ++ [ "duneLoadCache" ];

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

            # The target to build. It defaults to "_build/${context}", but can
            # pass [aliases](https://dune.readthedocs.io/en/latest/reference/aliases.html)
            # like `@pkg-install`.
            #
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

            duneBuildFlags = [
              "--error-reporting=twice"
              "--always-show-command-line"
              "--action-stdout-on-success=print"
              "--action-stderr-on-success=print"
              "--display=verbose"
              "--stop-on-first-error"
              # Not 100% sure if this is necessary but the wording in the docs
              # makes it sound slike it’s an important flag for ensuring
              # determinism in cache handling.  That’s extremely relevant to
              # Nix, particularly when using separate dependency derivations, so
              # let’s enable it, to be safe.
              "--wait-for-filesystem-clock"
            ];

            buildPhase =
              args.buildPhase or ''
                runHook preBuild

                if [[ -n "''${duneCheckNoCacheMiss-}" ]]; then
                  # Semantics of DUNE_TRACE envvar are a bit complicated: either
                  # comma separated, XOR +/- alternating.
                  if [[ "''${DUNE_TRACE-}" == *,* ]]; then
                    export DUNE_TRACE="$DUNE_TRACE,cache"
                  else
                    export DUNE_TRACE="''${DUNE_TRACE-}+cache"
                  fi
                fi

                ${
                  if finalAttrs.duneSeparateDeps then
                    ''
                      # Tempdir to copy the cached dependencies because Dune
                      # wants write permission to the directory.
                      pkg_dir="$(mktemp -d)"

                      # Dune chokes on absolute path: https://github.com/ocaml/dune/issues/12230
                      pkg_dir="$(realpath --relative-to="$PWD" "$pkg_dir")"

                      cp -r ${finalAttrs.passthru.duneDeps}/_build/_private/default/.pkg/. "$pkg_dir"

                      # Assemble the envvars so the OCaml compilers (ocamlfind) can
                      # find them.

                      OCAMLPATH=""
                      for lib in "$pkg_dir"/*/target/lib; do
                        OCAMLPATH="''${OCAMLPATH:+$OCAMLPATH:}$lib"
                      done

                      CAML_LD_LIBRARY_PATH=""
                      for stub in "$pkg_dir"/*/target/lib/stublibs; do
                        CAML_LD_LIBRARY_PATH="''${CAML_LD_LIBRARY_PATH:+$CAML_LD_LIBRARY_PATH:}$stub"
                      done

                      for bin in "$pkg_dir"/*/target/bin; do
                        PATH="''${bin}:$PATH"
                      done

                      export OCAMLPATH CAML_LD_LIBRARY_PATH

                      # Explicitly disable package-management to prevent Dune
                      # from getting confused by `pkg` stanza in dune-workspace.
                      dune build $duneBuildFlags $target ${jobsFlag} --pkg disabled
                    ''
                  else
                    ''
                      dune build $duneBuildFlags $target ${jobsFlag}
                    ''
                }

                runHook postBuild
              '';

            # Set to true to include _build as build and the global cache as
            # cache outputs.  Useful for debugging, and they’re easily garbage
            # collected, but they can grow quite large which can slow down
            # builds.
            duneIncludeBuildOutputs = args.duneIncludeBuildOutputs or false;
            outputs = [
              "out"
            ]
            ++ lib.optionals finalAttrs.duneIncludeBuildOutputs [
              "build"
              "cache"
            ];

            checkPhase =
              args.checkPhase or ''
                runHook preCheck

                dune runtest $duneBuildFlags $target ${jobsFlag}

                runHook postCheck
              '';

            installPhase =
              args.installPhase or ''
                runHook preInstall

                # `dune install` is not supported with Dune package management
                # (https://github.com/ocaml/dune/issues/14449).
                # Apparently this is the way 🤷 - shun 2026-08
                mkdir -p $out
                cp -rL _build/install/$context/. $out/

                runHook postInstall
              '';

            duneCheckNoCacheMissPhase = ''
              if [[ -n "''${duneCheckNoCacheMiss-}" ]]; then
                outfile=dune-cache-misses.jsonl
                dune trace cat --trace-file _build/trace.csexp \
                  | jq -c 'select(.cat == "cache" and .name == "workspace_local_miss" and (.args.reason | startswith("rule or dependencies changed")))' \
                  > $outfile
                if [[ -s $outfile ]]; then
                  cat $outfile
                  >&2 cat <<'EOF'


              ERROR: Dune had cache misses during build.  This means dune2nix
              was not able to set up an environment where dune can reuse the
              cache it generated, itself.  The failure mode is that builds
              succeed, but become very slow, as every single derivation will
              require a rebuild of all dependencies.  If you know what you're
              doing, you can set duneCheckNoCacheMiss to 'false' on this
              derivation.

              EOF
                  exit 1
                fi
              fi
            '';

            # Also ensure there is at least some directory in the $cache output,
            # if specified.
            installBuildDirsPhase = ''
              runHook preInstallBuildDirs

              for target in $outputs; do
                if [[ "$target" == build && -d _build && ! -a $build ]]; then
                  cp -r _build $build
                fi
                if [[ "$target" == cache ]]; then
                  mkdir -p $cache
                fi
              done

              runHook postInstallBuildDir
            '';

            preFixupPhases = args.preFixupPhases or [ ] ++ [
              "installBuildDirsPhase"
              "duneCheckNoCacheMissPhase"
            ];
          };

        excludeDrvArgNames = [
          "duneProject"
          "duneWorkspace"
          "duneLock"
          "context"
          "enableParallelBuilding"
          "srcOverrides"
          "duneSeparateDeps"
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
