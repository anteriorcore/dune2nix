Normal base64:

  $ echo Hello, friend | base64
  SGVsbG8sIGZyaWVuZAo=

But we patched ocaml's base64 to only output z's:

  $ echo Hello, friend | zzzz64
  zzzzzzzzzzzzzzzzzzz=


