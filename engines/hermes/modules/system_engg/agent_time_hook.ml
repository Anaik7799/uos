let render_pre_invocation result =
  let message =
    match result with
    | Ok message -> message
    | Error reason -> "Unavailable_observed: " ^ reason
  in
  `Assoc
    [ ( "injectSteps",
        `List [ `Assoc [ ("ephemeralMessage", `String message) ] ] ) ]
  |> Yojson.Safe.to_string

let read_all channel =
  let chunk = Bytes.create 4_096 in
  let buffer = Buffer.create 256 in
  let rec loop () =
    match input channel chunk 0 (Bytes.length chunk) with
    | 0 -> Buffer.contents buffer
    | count ->
        Buffer.add_subbytes buffer chunk 0 count;
        loop ()
  in
  loop ()

let status_reason program = function
  | Unix.WEXITED code -> Printf.sprintf "%s exited with exit %d" program code
  | Unix.WSIGNALED signal ->
      Printf.sprintf "%s was signalled with %d" program signal
  | Unix.WSTOPPED signal ->
      Printf.sprintf "%s was stopped with %d" program signal

let invoke ~program ~argv =
  let read_fd, write_fd = Unix.pipe ~cloexec:true () in
  match Unix.create_process program argv Unix.stdin write_fd Unix.stderr with
  | pid ->
      Unix.close write_fd;
      let channel = Unix.in_channel_of_descr read_fd in
      let output =
        match Fun.protect ~finally:(fun () -> close_in_noerr channel)
                (fun () -> Ok (read_all channel)) with
        | result -> result
        | exception exn -> Error (Printexc.to_string exn)
      in
      let _, status = Unix.waitpid [] pid in
      begin match output, status with
      | Ok output, Unix.WEXITED 0 when String.trim output <> "" -> Ok output
      | Ok _, Unix.WEXITED 0 -> Error (program ^ " produced empty stdout")
      | _, status -> Error (status_reason program status)
      end
  | exception exn ->
      Unix.close read_fd;
      Unix.close write_fd;
      Error (program ^ " could not start: " ^ Printexc.to_string exn)
