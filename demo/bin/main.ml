open Core

let () =
  let x = Some "🐫" in
  let y = Option.value x ~default:"🏜️" in
  print_endline y
