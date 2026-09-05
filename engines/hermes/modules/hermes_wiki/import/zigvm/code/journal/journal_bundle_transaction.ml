type phase = Prepared | Committing of int | Committed
type target = { path : string; temporary : string; backup : string option }
type t = { version : int; journal_path : string; content_id : string; phase : phase; targets : target list }

let error message = Error (`Msg message)

let rec ensure_directory path =
  if Sys.file_exists path then
    if Sys.is_directory path then Ok () else error (path ^ " is not a directory")
  else
    let parent = Filename.dirname path in
    match (if parent = path then Ok () else ensure_directory parent) with
    | Error _ as failure -> failure
    | Ok () ->
        (try Unix.mkdir path 0o755; Ok ()
         with Unix.Unix_error (code, fn, arg) ->
           error (Printf.sprintf "%s(%s): %s" fn arg (Unix.error_message code)))

let fsync_path path =
  try
    let fd = Unix.openfile path [ Unix.O_RDONLY ] 0 in
    Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> Unix.fsync fd);
    Ok ()
  with Unix.Unix_error (code, fn, arg) ->
    error (Printf.sprintf "%s(%s): %s" fn arg (Unix.error_message code))

let write_file path content =
  match ensure_directory (Filename.dirname path) with
  | Error _ as failure -> failure
  | Ok () ->
      (try
         let channel = open_out_bin path in
         Fun.protect
           ~finally:(fun () -> close_out_noerr channel)
           (fun () -> output_string channel content; flush channel;
             Unix.fsync (Unix.descr_of_out_channel channel));
         Ok ()
       with Sys_error message -> error message)

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
      Ok (really_input_string channel (in_channel_length channel)))
  with Sys_error message -> error message

let phase_json = function
  | Prepared -> `Assoc [ "kind", `String "prepared" ]
  | Committing index -> `Assoc [ "kind", `String "committing"; "index", `Int index ]
  | Committed -> `Assoc [ "kind", `String "committed" ]

let target_json target =
  `Assoc
    [ "path", `String target.path; "temporary", `String target.temporary;
      "backup", (match target.backup with None -> `Null | Some path -> `String path) ]

let encode transaction =
  `Assoc
    [ "version", `Int transaction.version;
      "journal_path", `String transaction.journal_path;
      "content_id", `String transaction.content_id;
      "phase", phase_json transaction.phase;
      "targets", `List (List.map target_json transaction.targets) ]
  |> Yojson.Safe.pretty_to_string
  |> fun value -> value ^ "\n"

let assoc name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let decode path text =
  try
    let json = Yojson.Safe.from_string text in
    let string name json = match assoc name json with Some (`String value) -> value | _ -> raise Exit in
    let phase =
      match assoc "phase" json with
      | Some (`Assoc _ as value) ->
          (match string "kind" value with
           | "prepared" -> Prepared
           | "committing" ->
               (match assoc "index" value with Some (`Int value) -> Committing value | _ -> raise Exit)
           | "committed" -> Committed
           | _ -> raise Exit)
      | _ -> raise Exit
    in
    let targets =
      match assoc "targets" json with
      | Some (`List values) ->
          List.map
            (fun value ->
              { path = string "path" value; temporary = string "temporary" value;
                backup = match assoc "backup" value with
                  | Some (`String path) -> Some path | Some `Null -> None | _ -> raise Exit })
            values
      | _ -> raise Exit
    in
    let version = match assoc "version" json with Some (`Int value) -> value | _ -> raise Exit in
    if version <> 1 then error "unsupported transaction journal version"
    else Ok { version; journal_path = path; content_id = string "content_id" json; phase; targets }
  with Yojson.Json_error message -> error ("invalid transaction journal: " ^ message)
     | Exit -> error "invalid transaction journal schema"

let persist transaction = write_file transaction.journal_path (encode transaction)

let with_lock ~path operation =
  match ensure_directory (Filename.dirname path) with
  | Error _ as failure -> failure
  | Ok () ->
      (try
         let fd = Unix.openfile path [ Unix.O_CREAT; Unix.O_RDWR ] 0o600 in
         Fun.protect
           ~finally:(fun () ->
             (try Unix.lockf fd Unix.F_ULOCK 0 with _ -> ()); Unix.close fd)
           (fun () -> Unix.lockf fd Unix.F_LOCK 0; operation ())
       with Unix.Unix_error (code, fn, arg) ->
         error (Printf.sprintf "%s(%s): %s" fn arg (Unix.error_message code)))

let same_filesystem targets =
  try
    let devices =
      targets
      |> List.map (fun path ->
           match ensure_directory (Filename.dirname path) with
           | Error (`Msg message) -> failwith message
           | Ok () -> (Unix.stat (Filename.dirname path)).Unix.st_dev)
      |> List.sort_uniq compare
    in
    Ok (List.length devices <= 1)
  with Failure message -> error message
     | Unix.Unix_error (code, fn, arg) ->
         error (Printf.sprintf "%s(%s): %s" fn arg (Unix.error_message code))

let prepare ~journal_path ~content_id ~content ~targets =
  match same_filesystem targets with
  | Error _ as failure -> failure
  | Ok false -> error "cross-filesystem fanout cannot preserve rollback backups"
  | Ok true ->
      let suffix = Printf.sprintf ".%d.%s" (Unix.getpid ()) content_id in
      let rec build accumulated = function
        | [] -> Ok (List.rev accumulated)
        | path :: rest ->
            let temporary = path ^ suffix ^ ".tmp" in
            let backup = if Sys.file_exists path then Some (path ^ suffix ^ ".backup") else None in
            (match write_file temporary content with
             | Error _ as failure -> failure
             | Ok () ->
                 (match backup with
                  | None -> build ({ path; temporary; backup } :: accumulated) rest
                  | Some backup_path ->
                      (match read_file path with
                       | Error _ as failure -> failure
                       | Ok previous ->
                           match write_file backup_path previous with
                           | Error _ as failure -> failure
                           | Ok () -> build ({ path; temporary; backup } :: accumulated) rest)))
      in
      (match build [] targets with
       | Error _ as failure -> failure
       | Ok prepared ->
           let transaction = { version = 1; journal_path; content_id; phase = Prepared; targets = prepared } in
           match persist transaction with Error _ as failure -> failure | Ok () -> Ok transaction)

let remove_if_exists path = if Sys.file_exists path then Sys.remove path

let cleanup transaction =
  try
    List.iter
      (fun target -> remove_if_exists target.temporary; Option.iter remove_if_exists target.backup)
      transaction.targets;
    remove_if_exists transaction.journal_path;
    Ok ()
  with Sys_error message -> error message

let commit ?fail_after transaction =
  let rec loop index = function
    | [] ->
        if fail_after = Some index then
          error (Printf.sprintf "injected failure after %d rename(s)" index)
        else
          let committed = { transaction with phase = Committed } in
          (match persist committed with Error _ as failure -> failure | Ok () -> cleanup committed)
    | target :: rest ->
        if fail_after = Some index then error (Printf.sprintf "injected failure after %d rename(s)" index)
        else
          (try
             Sys.rename target.temporary target.path;
             ignore (fsync_path (Filename.dirname target.path));
             let progress = { transaction with phase = Committing (index + 1) } in
             match persist progress with Error _ as failure -> failure | Ok () -> loop (index + 1) rest
           with Sys_error message -> error message)
  in
  loop 0 transaction.targets

let recover ~journal_path =
  if not (Sys.file_exists journal_path) then Ok ()
  else
    match read_file journal_path with
    | Error _ as failure -> failure
    | Ok text ->
        (match decode journal_path text with
         | Error _ as failure -> failure
         | Ok transaction ->
             match transaction.phase with
             | Committed -> cleanup transaction
             | Prepared | Committing _ ->
                 (try
                    List.iter
                      (fun target ->
                        match target.backup with
                        | Some backup when Sys.file_exists backup -> Sys.rename backup target.path
                        | _ -> if Sys.file_exists target.path && not (Sys.file_exists target.temporary)
                               then Sys.remove target.path;
                        remove_if_exists target.temporary)
                      transaction.targets;
                    remove_if_exists transaction.journal_path;
                    Ok ()
                  with Sys_error message -> error message))
