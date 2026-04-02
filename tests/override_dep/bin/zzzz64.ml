let () =
  In_channel.stdin |> In_channel.input_all |> Base64.encode_exn |> Out_channel.output_string Out_channel.stdout
