open Core

let () =
  let x = Some "NOMERGE-foobasdfasdfdd" in
  let y = Option.value x ~default:"🏜️" in
  print_endline y
