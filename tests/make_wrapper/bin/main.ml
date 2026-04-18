(* https://ocaml.org/docs/cli-arguments *)
let () =
  for i = 1 to Array.length Sys.argv - 1 do
    Printf.printf "[%i] %s\n" i Sys.argv.(i)
  done
