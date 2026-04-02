# Simple and limited S-expression parser. Project agnostic.

{ lib, self, ... }:
{
  flake = {
    lib.sexp =
      let
        hasKey = key: n: lib.isList n && lib.head n == key;
        mapAttrsN =
          fn: n: attrs:
          if n <= 0 then attrs else builtins.mapAttrs (_: mapAttrsN fn (n - 1)) (fn attrs);
        cons = a: b: [ a ] ++ b;
      in
      rec {
        parse =
          text:
          let
            go =
              token:
              if lib.head token == "(" then
                let
                  loop =
                    tl:
                    if tl == [ ] || lib.head tl == ")" then
                      {
                        val = [ ];
                        rest = lib.tail tl;
                      }
                    else
                      let
                        inherit (go tl) rest val;
                        next = loop rest;
                      in
                      {
                        inherit (next) rest;
                        val = [ val ] ++ next.val;
                      };
                in
                loop (lib.tail token)
              else
                {
                  val = lib.head token;
                  rest = lib.tail token;
                };

            parseAll =
              tokens:
              if tokens == [ ] then
                [ ]
              else
                let
                  inherit (go tokens) val rest;
                in
                [ val ] ++ parseAll rest;

            # Poor man's s-expression tokenizer
            tokenize =
              text:
              lib.pipe text [
                # Capture parens or chars that are neither parens nor space
                (lib.split "([()]|[^()[:space:]]+)")
                (lib.filter lib.isList)
                lib.concatLists
              ];
          in
          lib.pipe text [
            tokenize
            parseAll
          ];

        # Check if path exists. Inspired by lib.hasAttrByPath.
        has =
          path: nodes:
          if path == [ ] then
            true
          else
            let
              key = lib.head path;
              rest = lib.tail path;
              found = lib.findFirst (hasKey key) null nodes;
            in
            if found == null then false else has rest (lib.tail found);

        # Get children at path. Throws if not found. Inspired by lib.getAttrFromPath.
        get =
          path: nodes:
          if path == [ ] then
            nodes
          else
            let
              key = lib.head path;
              rest = lib.tail path;
              found = lib.findFirst (hasKey key) null nodes;
            in
            assert lib.assertMsg (found != null) "sexp.get: key '${key}' not found";
            get rest (lib.tail found);

        # Convert s-expression encoded attribute list to an attrset
        fromAlist = lib.foldl' (acc: x: acc // { "${lib.head x}" = lib.tail x; }) { };

        # Like fromAlist, but with customizable depth
        fromAlistN = mapAttrsN fromAlist;

        # Convert an attrset to an attribute list
        toAlist = lib.mapAttrsToList cons;

        # Get first scalar element at path. Throws if not found.
        scalar =
          path: nodes:
          let
            result = get path nodes;
          in
          assert lib.assertMsg (result != [ ]) "sexp.scalar: no value at path";
          lib.head result;

        # Transform children of node at path. Inspired by lib.updateManyAttrsByPath.
        update =
          path: f: nodes:
          if path == [ ] then
            f nodes
          else
            let
              key = lib.head path;
              rest = lib.tail path;
            in
            map (n: if hasKey key n then [ key ] ++ update rest f (lib.tail n) else n) nodes;

        # Convert S-exp back to string. Slightly opinionated with separators.
        toString = nodes: toStringSep nodes " " "\n";

        toStringSep =
          nodes: elementSep: lineSep:
          let
            go = node: if lib.isList node then "(${lib.concatMapStringsSep elementSep go node})" else node;
          in
          lib.concatMapStringsSep lineSep go nodes;

        parseFile = path: parse (lib.readFile path);

      };

    tests =
      let
        inherit (self.lib.sexp)
          parse
          has
          get
          fromAlist
          fromAlistN
          toAlist
          scalar
          update
          toString
          ;
        alistAttrsetFixture = {
          a = [
            "b"
            [
              "c"
              1
            ]
          ];
          e = [ 2 ];
          x = [
            { y = 3; }
            { z = 4; }
          ];
        };
      in
      {
        parse = {
          "test: parse basic" = {
            expr = parse ''
              (name foo)
            '';
            expected = [
              [
                "name"
                "foo"
              ]
            ];
          };
          "test: parse empty" = {
            expr = parse "";
            expected = [ ];
          };
          "test: parse multiple entries" = {
            expr = parse ''
              (depends foo bar)
            '';
            expected = [
              [
                "depends"
                "foo"
                "bar"
              ]
            ];
          };
          "test: parse multiple toplevels" = {
            expr = parse ''
              (name foo)

              (depends foo bar)
            '';
            expected = [
              [
                "name"
                "foo"
              ]
              [
                "depends"
                "foo"
                "bar"
              ]
            ];
          };
          "test: parse nested" = {
            expr = parse ''
              (depends
                (all_platforms
                  (foo bar baz)))
            '';
            expected = [
              [
                "depends"
                [
                  "all_platforms"
                  [
                    "foo"
                    "bar"
                    "baz"
                  ]
                ]
              ]
            ];
          };
          "test: parse nested multiple toplevels" = {
            expr = parse ''
              (depends
                (all_platforms
                  (foo bar baz)))

              (build
                (all_platforms
                  (action
                    (run foo bar))))
            '';
            expected = [
              [
                "depends"
                [
                  "all_platforms"
                  [
                    "foo"
                    "bar"
                    "baz"
                  ]
                ]
              ]
              [
                "build"
                [
                  "all_platforms"
                  [
                    "action"
                    [
                      "run"
                      "foo"
                      "bar"
                    ]
                  ]
                ]
              ]
            ];
          };
        };
        has = {
          "test: exists" = {
            expr = has [ "a" ] (parse "(a b)");
            expected = true;
          };
          "test: missing" = {
            expr = has [ "x" ] (parse "(a b)");
            expected = false;
          };
          "test: empty path" = {
            expr = has [ ] (parse "(a b)");
            expected = true;
          };
          "test: nested exists" = {
            expr = has [ "a" "b" ] (parse "(a (b c))");
            expected = true;
          };
          "test: nested missing" = {
            expr = has [ "a" "x" ] (parse "(a (b c))");
            expected = false;
          };
        };
        get = {
          "test: basic" = {
            expr = get [ "a" ] (parse "(a b c)");
            expected = [
              "b"
              "c"
            ];
          };
          "test: empty path returns root" = {
            expr = get [ ] (parse "(a b)");
            expected = [
              [
                "a"
                "b"
              ]
            ];
          };
          "test: nested" = {
            expr = get [ "a" "b" ] (parse "(a (b c d))");
            expected = [
              "c"
              "d"
            ];
          };
          "test: throws on missing key" = {
            expr = get [ "missing" ] (parse "(a b)");
            expectedError.type = "ThrownError";
          };
          "test: throws on missing nested key" = {
            expr = get [ "a" "missing" ] (parse "(a (b c))");
            expectedError.type = "ThrownError";
          };
        };
        fromAlist.test = {
          expr = fromAlist ([
            [
              "a"
              "b"
              "c"
            ]
            [
              "x"
              "y"
              "z"
            ]
            [
              "aa"
              "bb"
              [
                "cc"
                "dd"
              ]
            ]
          ]);
          expected = {
            a = [
              "b"
              "c"
            ];
            aa = [
              "bb"
              [
                "cc"
                "dd"
              ]
            ];
            x = [
              "y"
              "z"
            ];
          };
        };
        fromAlistN = {
          test = {
            expr = fromAlistN 2 ([
              [
                "a"
                [
                  "b"
                  "c"
                ]
                [
                  "e"
                  "f"
                ]
              ]
              [
                "u"
                [
                  "v"
                  [
                    "w"
                    [
                      "x"
                      [
                        "y"
                        [ "z" ]
                      ]
                    ]
                  ]
                ]
              ]
              [
                "aa"
                [
                  "cc"
                  "dd"
                ]
              ]
            ]);
            expected = {
              a.b = [ "c" ];
              a.e = [ "f" ];
              u.v = [
                [
                  "w"
                  [
                    "x"
                    [
                      "y"
                      [ "z" ]
                    ]
                  ]
                ]
              ];
              aa.cc = [ "dd" ];
            };
          };
        };
        toAlist = {
          test = {
            expr = toAlist alistAttrsetFixture;
            expected = [
              [
                "a"
                "b"
                [
                  "c"
                  1
                ]
              ]
              [
                "e"
                2
              ]
              [
                "x"
                { y = 3; }
                { z = 4; }
              ]
            ];
          };
          "test: toAlist ∘ fromAlist" = {
            expr = toAlist (fromAlist [
              [
                "a"
                "b"
              ]
              [
                "x"
                "z"
              ]
              [
                "b"
                "d"
              ]
            ]);
            expected = [
              [
                "a"
                "b"
              ]
              [
                "b"
                "d"
              ]
              [
                "x"
                "z"
              ]
            ];
          };
          "test: fromAlist ∘ toAlist" = {
            expected = alistAttrsetFixture;
            expr = fromAlist (toAlist alistAttrsetFixture);
          };
        };
        scalar = {
          "test: basic" = {
            expr = scalar [ "a" ] (parse "(a b)");
            expected = "b";
          };
          "test: nested" = {
            expr = scalar [ "a" "b" ] (parse "(a (b c))");
            expected = "c";
          };
          "test: throws on empty value" = {
            expr = scalar [ "a" ] (parse "(a)");
            expectedError.type = "ThrownError";
          };
        };
        update = {
          "test: transform root" = {
            expr = update [ ] (map (
              n:
              if lib.head n == "a" then
                [
                  "a"
                  "new"
                ]
              else
                n
            )) (parse "(a old)");
            expected = [
              [
                "a"
                "new"
              ]
            ];
          };
          "test: transform children" = {
            expr = update [ "a" ] (_: [
              [
                "x"
                "y"
              ]
            ]) (parse "(a (b c))");
            expected = [
              [
                "a"
                [
                  "x"
                  "y"
                ]
              ]
            ];
          };
          "test: missing key unchanged" = {
            expr = update [ "missing" ] (_: [ ]) (parse "(a b)");
            expected = [
              [
                "a"
                "b"
              ]
            ];
          };
          "test: preserves siblings" = {
            expr = update [ "b" ] (_: [ "new" ]) (parse ''
              (a 1)
              (b old)
              (c 2)
            '');
            expected = [
              [
                "a"
                "1"
              ]
              [
                "b"
                "new"
              ]
              [
                "c"
                "2"
              ]
            ];
          };
          "test: nested update" = {
            expr = update [ "a" "b" ] (_: [ "new" ]) (parse "(a (b old) (c kept))");
            expected = [
              [
                "a"
                [
                  "b"
                  "new"
                ]
                [
                  "c"
                  "kept"
                ]
              ]
            ];
          };
        };
        toString = {
          "test: basic" = {
            expr = toString (parse "(name foo)");
            expected = "(name foo)";
          };
          "test: empty" = {
            expr = toString (parse "");
            expected = "";
          };
          "test: multiple entries" = {
            expr = toString (parse "(depends foo bar)");
            expected = "(depends foo bar)";
          };
          "test: multiple toplevels" = {
            expr = toString (parse ''
              (name foo)
              (version bar)
              (depends baz)
            '');
            expected = "(name foo)\n(version bar)\n(depends baz)";
          };
          "test: nested" = {
            expr = toString (parse ''
              (depends
                (all_platforms
                  (foo bar baz)))
            '');
            expected = "(depends (all_platforms (foo bar baz)))";
          };
        };
      };
  };
}
