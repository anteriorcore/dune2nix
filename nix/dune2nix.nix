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

      mkDuneProject = lib.extendMkDerivation {
        constructDrv = stdenv.mkDerivation;

        extendDrvArgs =
          finalAttrs:
          {
            src,
            duneProject ? src + "/dune-project",

            # Any directory containing a dune-project file implicitly acts as a
            # workspace root.
            duneWorkspace ? src + "/dune-workspace",

            # The build context. Dune supports "default" and Opam switch context,
            # but I'm not convinced that we should support Opam switch context:
            # if you're using Opam switch (not managing package via Dune), you
            # probably don't want to use this library anyways.
            #
            # One situation where this might not be true is if someone wants to
            # manage Dune via Opam, and rest of the packages via Dune. But that's
            # also unlikely because the user of this library would use Nix (via
            # devshell) to manage Dune -- so I will leave the door open but will
            # not spend my complexity budget here.
            #
            # https://dune.readthedocs.io/en/stable/reference/dune-workspace/context.html
            context ? "default",

            enableParallelBuilding ? true,
            ...
          }@args:
          let
            # Default is "dune.lock", and can be customized via dune-workspace's
            # context.${name}.lock_dir stanza.
            lockDir =
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
              parsed:
              lib.pipe parsed [
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

            project = sexp.parseFile duneProject;

            jobsFlag = lib.optionalString enableParallelBuilding "-j $NIX_BUILD_CORES";

            # For some reason, `dune build` and `dune runtest` don't accept the
            # `--context` flag, instead, you specify the build target directory
            # (`_build/${context}`) - I _hope_ this works, but I wouldn't be
            # surprised at all even if this breaks someday. As I mentioned above
            # context support is best-effort: it's very possible that I rip this
            # out for a very minor issue.
            #
            # build:
            # https://github.com/ocaml/dune/issues/9672
            #
            # runtest:
            # https://github.com/ocaml/dune/blob/33b6ab730ce2bf0a78aaac116d7e95db6c71c45c/bin/runtest.ml#L29
            target = "_build/${context}";

            # Small utility for writing phases
            mkPhase =
              phase: body:
              let
                capitalized = lib.toSentenceCase phase;
              in
              ''
                runHook pre${capitalized}
                ${body}
                runHook post${capitalized}
              '';
          in
          # Heavily inspired by:
          # https://github.com/NixOS/nixpkgs/blob/27894d0586cf031cd5b3b345b6f9676c99ca6bac/pkgs/build-support/ocaml/dune.nix
          {
            name = sexp.scalar [ "package" "name" ] project;

            strictDeps = true;

            nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
              dune
              # Dune wants to write in ~/.cache
              writableTmpDirAsHomeHook
            ];

            patchPhase = mkPhase "patch" (
              lib.optionalString (lib.pathExists duneLock) ''
                rm -rf ${lockDir}
                cp -rL ${patchedLock} ${lockDir}
              ''
            );

            buildPhase = mkPhase "build" ''
              dune build ${target} ${jobsFlag}
            '';

            installPhase = mkPhase "install" ''
              dune install --context ${context} --prefix $out
            '';

            checkPhase = mkPhase "check" ''
              dune runtest ${target} ${jobsFlag}
            '';
          }
          // lib.optionalAttrs (sexp.has [ "version" ] project) {
            version = sexp.scalar [ "version" ] project;
          };

        # Hate this hardcoded list but it's a very standard practice in nixpkgs.
        excludeDrvArgNames = [
          "duneProject"
          "duneWorkspace"
          "duneLock"
          "context"
          "enableParallelBuilding"
        ];
      };

      scope = lib.makeScope newScope (_: {
        inherit mkDuneProject;
      });
    in
    scope.overrideScope overrideScope;
}
