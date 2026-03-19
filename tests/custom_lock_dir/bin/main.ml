open Core

let () =
  let x = Some 3 in
  let y = Option.value x ~default:0 in
  printf "%d\n" y
