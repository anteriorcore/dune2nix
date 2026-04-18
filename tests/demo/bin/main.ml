open Core

let () =
  let x = Some "NOMERGE-foobasdfasdfddsfoobarsdafads" in
  let y = Option.value x ~default:"🏜️" in
  print_endline y
