let ( let* ) result f = match result with Ok value -> f value | Error _ as error -> error

let read_file path =
  try
    if Sys.is_directory path then Error (path ^ " is a directory")
    else
      let channel = open_in_bin path in
      Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        Ok (In_channel.input_all channel))
  with
  | Sys_error message -> Error (path ^ ": " ^ message)
  | Unix.Unix_error (error, call, argument) ->
      Error (Printf.sprintf "%s: %s(%s): %s" path call argument
               (Unix.error_message error))

let rec ensure_directory path =
  if path = "." || path = "" then Ok ()
  else if Sys.file_exists path then
    if Sys.is_directory path then Ok () else Error (path ^ " exists and is not a directory")
  else
    let* () = ensure_directory (Filename.dirname path) in
    try Unix.mkdir path 0o755; Ok () with
    | Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> Ok ()
    | Unix.Unix_error (error, call, argument) ->
        Error (Printf.sprintf "%s(%s): %s" call argument (Unix.error_message error))

let write_atomic path content =
  let temporary = Printf.sprintf "%s.tmp.%d" path (Unix.getpid ()) in
  let cleanup () =
    if Sys.file_exists temporary then
      try Sys.remove temporary with Sys_error _ -> ()
  in
  try
    let channel = open_out_bin temporary in
    let write_result =
      Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () ->
        output_string channel content;
        flush channel;
        Ok ())
    in
    let* () = write_result in
    Sys.rename temporary path;
    Ok ()
  with
  | Sys_error message -> cleanup (); Error (path ^ ": " ^ message)
  | Unix.Unix_error (error, call, argument) ->
      cleanup ();
      Error (Printf.sprintf "%s: %s(%s): %s" path call argument
               (Unix.error_message error))

let validate_sources outputs =
  let gaps = Run_mbse.validate () in
  if gaps <> [] then Error ("projection validation failed: " ^ String.concat " | " gaps)
  else if Run_topology.authority.components = [] then Error "operations source authority is empty"
  else if String.length Run_topology.source_digest <> 64 then Error "source digest is invalid"
  else if outputs = [] then Error "projection output set is empty"
  else
    match List.find_opt
        (fun (path, content) -> String.trim path = "" || String.trim content = "") outputs with
    | Some (path, _) -> Error ("projection source is empty: " ^ path)
    | None -> Ok ()

let write outputs =
  let* () = validate_sources outputs in
  let directories = outputs |> List.map (fun (path, _) -> Filename.dirname path)
      |> List.sort_uniq String.compare in
  let rec create = function
    | [] -> Ok ()
    | directory :: rest -> let* () = ensure_directory directory in create rest
  in
  let* () = create directories in
  let rec emit = function
    | [] -> Ok ()
    | (path, content) :: rest -> let* () = write_atomic path content in emit rest
  in
  emit outputs

let check outputs =
  let* () = validate_sources outputs in
  let rec compare = function
    | [] -> Ok ()
    | (path, expected) :: rest ->
        let* observed = read_file path in
        if String.equal observed expected then compare rest
        else Error ("generated projection drift: " ^ path)
  in
  compare outputs

let fail code message = Printf.eprintf "gen_run_model: %s\n" message; exit code

let () =
  let outputs = Run_mbse.outputs () in
  match Array.to_list Sys.argv with
  | [ _; "--write" ] ->
      begin match write outputs with
      | Ok () -> Printf.printf "gen_run_model: wrote 4 digest-bound projections\n"
      | Error message -> fail 1 message
      end
  | [ _; "--check" ] ->
      begin match check outputs with
      | Ok () -> Printf.printf "gen_run_model: projections current\n"
      | Error message -> fail 1 message
      end
  | [ _ ] -> fail 2 "exactly one of --write or --check is required"
  | _ -> fail 2 "unknown arguments; accepted forms are --write and --check"
