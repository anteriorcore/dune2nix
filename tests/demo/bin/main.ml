open Core

let () =
  let x = Some "NOMERGE-foo" in
  let y = Option.value x ~default:"🏜️" in
  print_endline y
