open Core

let () =
  let x = Some "🐫" in
  let y = Option.value x ~default:"🏜️" in
  printf "%d\n" y
