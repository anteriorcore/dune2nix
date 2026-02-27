# Simple and limited S-expression parser. Project agnostic.

{ lib, self, ... }:
{
  flake = {
    lib.sexp = rec {
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
                found = lib.findFirst (n: lib.isList n && lib.head n == key) null next;
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

      # Delete element at path
      delete =
        path: nodes:
        if path == [ ] then
          nodes
        else
          let
            key = lib.head path;
            rest = lib.tail path;
          in
          if rest == [ ] then
            lib.filter (n: !(lib.isList n && lib.head n == key)) nodes
          else
            map (n: if lib.isList n && lib.head n == key then [ key ] ++ delete rest (lib.tail n) else n) nodes;

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
          delete
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
        delete = {
          "test: basic" = {
            expr = delete [ "name" ] (parse ''
              (name foo)
            '');
            expected = [ ];
          };
          "test: empty path" = {
            expr = delete [ ] (parse ''
              (name foo)
            '');
            expected = [
              [
                "name"
                "foo"
              ]
            ];
          };
          "test: missing key" = {
            expr = delete [ "missing" ] (parse ''
              (name foo)
            '');
            expected = [
              [
                "name"
                "foo"
              ]
            ];
          };
          "test: multiple entries" = {
            expr = delete [ "name" ] (parse ''
              (name foo)
              (depends bar)
            '');
            expected = [
              [
                "depends"
                "bar"
              ]
            ];
          };
          "test: nested" = {
            expr = delete [ "depends" "all_platforms" ] (parse ''
              (depends
                (all_platforms foo bar))
            '');
            expected = [ [ "depends" ] ];
          };
          "test: nested preserves siblings" = {
            expr = delete [ "depends" "all_platforms" ] (parse ''
              (depends
                (all_platforms foo)
                (linux bar))
            '');
            expected = [
              [
                "depends"
                [
                  "linux"
                  "bar"
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
