module F = Stdlib_upstream_compatible.Float_u

let () =
  let x : float# = F.of_float 1.0 in
  let y : float# = F.of_float 1.0 in
  Printf.printf "%f\n" (F.to_float (F.add x y))
