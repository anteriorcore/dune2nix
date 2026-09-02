(* Sample program taken from https://dune.readthedocs.io/en/stable/tutorials/dune-package-management/oxcaml.html *)

let () =
  (* The `local_` keyword requires OxCaml *)
  let local_ i = 42 in
  let j = i + 1 in
  Printf.printf "%d\n" j
