open Num

let () = print_endline ("After 1 comes " ^ (1 |> num_of_int |> succ_num |> string_of_num))
