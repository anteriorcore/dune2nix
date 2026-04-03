open Core

let () =
  let x = Some "NOMERGE-foobasdfa" in
  let y = Option.value x ~default:"🏜️" in
  print_endline y
