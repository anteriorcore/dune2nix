# Simple and limited S-expression parser. Project agnostic.

{ lib, self, ... }:
{
  flake = {
    lib.sexp =
      let
        hasKey = key: n: lib.isList n && lib.head n == key;
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
            tokens = lib.concatLists (
              lib.filter lib.isList (
                lib.split
                  # Capture either parens or a seq of chars that are neither
                  # parens nor whitespace.
                  "([()]|[^()[:space:]]+)"
                  text
              )
            );
          in
          parseAll tokens;

        # Inspired by lib.getAttrFromPath
        get =
          path: nodes:
          if (path == [ ]) then
            null
          else
            let
              step =
                key: next:
                let
                  found = lib.findFirst (hasKey key) null next;
                in
                if found == null then null else lib.tail found;
            in
            lib.foldl' (acc: key: if acc == null then null else step key acc) nodes path;

        # Get first scalar element at path
        scalar =
          path: nodes:
          let
            result = get path nodes;
          in
          if result == null || result == [ ] then null else lib.head result;

        # Transform children of node at path
        update =
          path: fn: nodes:
          if path == [ ] then
            fn nodes
          else
            let
              key = lib.head path;
              rest = lib.tail path;
            in
            map (n: if hasKey key n then [ key ] ++ update rest fn (lib.tail n) else n) nodes;

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
          scalar
          get
          update
          toString
          ;
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
        get = {
          "test: basic" = {
            expr = get [ "name" ] (parse ''
              (name foo)
            '');
            expected = [ "foo" ];
          };
          "test: non-empty path on empty object" = {
            expr = get [ "name" ] (parse "");
            expected = null;
          };
          "test: empty path on empty object" = {
            expr = get [ ] (parse "");
            expected = null;
          };
          "test: non-empty path on non-empty object" = {
            expr = get [ ] (parse ''
              (name foo)
            '');
            expected = null;
          };
          "test: nested" = {
            expr = get [ "depends" "all_platforms" ] (parse ''
              (depends
                (all_platforms foo bar))
            '');
            expected = [
              "foo"
              "bar"
            ];
          };
          "test: missing key" = {
            expr = get [ "missing" ] (parse ''
              (name foo)
            '');
            expected = null;
          };
          "test: partially missing path" = {
            expr = get [ "depends" "missing" ] (parse ''
              (depends foo bar)
            '');
            expected = null;
          };
        };
        scalar = {
          "test: basic" = {
            expr = scalar [ "name" ] (parse ''
              (name foo)
            '');
            expected = "foo";
          };
          "test: missing" = {
            expr = scalar [ "missing" ] (parse ''
              (name foo)
            '');
            expected = null;
          };
          "test: empty path" = {
            expr = scalar [ ] (parse ''
              (name foo)
            '');
            expected = null;
          };
          "test: key exists but has no value" = {
            expr = scalar [ "name" ] (parse "(name)");
            expected = null;
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
