let error message =
  prerr_endline ("mirage-metrics-bridge: " ^ message);
  exit 2

let read_timeout_ns = 2_000_000_000L

let read_frame descriptor =
  let capacity = Mirage_metrics.max_console_bytes + 1 in
  let bytes = Bytes.create capacity in
  let deadline = Int64.add (Mtime_clock.elapsed_ns ()) read_timeout_ns in
  let rec loop offset =
    if offset = capacity then offset
    else
      let remaining_ns = Int64.sub deadline (Mtime_clock.elapsed_ns ()) in
      if Int64.compare remaining_ns 0L <= 0 then raise Exit
      else
        let timeout = Int64.to_float remaining_ns /. 1_000_000_000. in
        match Unix.select [descriptor] [] [] timeout with
        | [], _, _ -> raise Exit
        | _, _, _ ->
            (match Unix.read descriptor bytes offset (capacity - offset) with
             | 0 -> offset
             | count -> loop (offset + count)
             | exception Unix.Unix_error (Unix.EINTR, _, _) -> loop offset)
  in
  match loop 0 with
  | exception Exit -> Error "console input timed out"
  | count ->
      if count > Mirage_metrics.max_console_bytes then Error "console input exceeds bound"
      else
        let count =
          if count > 0 && Bytes.get bytes (count - 1) = '\n' then
            if count > 1 && Bytes.get bytes (count - 2) = '\r' then count - 2 else count - 1
          else count
        in
        Ok (Bytes.sub_string bytes 0 count)

let () =
  match Array.to_list Sys.argv with
  | [_] ->
      (match read_frame Unix.stdin with
       | Error message -> error message
       | Ok frame ->
           match Mirage_metrics.decode_and_render frame with
           | Error message -> error message
           | Ok output -> print_string output)
  | _ -> error "usage: mirage_metrics_bridge < guest-console-frame"
