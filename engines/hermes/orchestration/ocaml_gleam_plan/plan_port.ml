let max_frame = 8 * 1024 * 1024

let read_frame () =
  let header = really_input_string stdin 4 in
  let size = ref 0 in
  String.iter (fun c -> size := (!size lsl 8) lor Char.code c) header;
  if !size < 1 || !size > max_frame then failwith "frame outside 1..8MiB";
  really_input_string stdin !size |> Yojson.Basic.from_string

let write_frame json =
  let payload = Yojson.Basic.to_string json in
  let n = String.length payload in
  if n > max_frame then failwith "reply exceeds 8MiB";
  List.iter (fun shift -> output_byte stdout ((n lsr shift) land 255)) [24;16;8;0];
  output_string stdout payload;
  flush stdout

let member name = function
  | `Assoc fields -> (match List.assoc_opt name fields with Some v -> v | None -> `Null)
  | _ -> `Null

let allowed_path path =
  let production_prefixes =
    [ "/home/an/NAS-setup/.uos-workspaces/ocaml-gleam-tests/state/ocaml_gleam_tests/";
      "/home/an/NAS-setup/uos/state/ocaml_gleam_tests/" ] in
  let prefixes = match Sys.getenv_opt "UOS_PLAN_TEST_ROOT" with
    | Some root when String.starts_with ~prefix:"/tmp/uos-sa-plan-tests." root ->
        (root ^ "/") :: production_prefixes
    | _ -> production_prefixes in
  String.ends_with ~suffix:"/sa_plan.sqlite3" path
  && List.exists (fun prefix -> String.starts_with ~prefix path) prefixes
  && not (String.contains path '\000' || String.contains path '\\')
  && (match String.split_on_char '/' path with
      | "" :: parts -> List.for_all (fun p -> p <> "" && p <> "." && p <> "..") parts
      | _ -> false)

let rec ensure_directory ~create path =
  if path = "/" then ()
  else begin
    ensure_directory ~create (Filename.dirname path);
    match Unix.lstat path with
    | st when st.Unix.st_kind = Unix.S_DIR -> ()
    | _ -> failwith "non-directory or symlink in state path"
    | exception Unix.Unix_error (Unix.ENOENT, _, _) when create -> Unix.mkdir path 0o700
  end

let with_store path ~create f =
  if not (allowed_path path) then Error "state path outside declared task scope"
  else
    try
      ensure_directory ~create (Filename.dirname path);
      (match Unix.lstat path with
       | st when st.Unix.st_kind = Unix.S_REG -> ()
       | _ -> failwith "state file is not a regular file"
       | exception Unix.Unix_error (Unix.ENOENT, _, _) when create -> ());
      (* Directory permissions and lstat checks are local hygiene, not a
         descriptor-relative guarantee against hostile concurrent renames. *)
      let prior_umask = Unix.umask 0o077 in
      let opened = Fun.protect ~finally:(fun () -> ignore (Unix.umask prior_umask))
          (fun () -> Sa_plan.Store.open_db path) in
      match opened with
      | Error _ as error -> error
      | Ok store -> Fun.protect ~finally:(fun () -> Sa_plan.Store.close store)
                      (fun () -> f store)
    with exn -> Error (Printexc.to_string exn)

let handle path request =
  let id = member "id" request and operation = member "operation" request in
  let result =
    if member "version" request <> `Int 1 then Error "unsupported protocol version"
    else match id, operation with
    | `String id, `String op when id <> "" && String.length id <= 128 ->
        (match op with
         | "spec" -> Ok Migration_plan.specification
         | "register" ->
             with_store path ~create:true (fun store ->
               Migration_plan.materialize store
                 ~now_ns:(Int64.of_float (Unix.gettimeofday () *. 1e9)))
         | "status" -> with_store path ~create:false Migration_plan.observe
         | _ -> Error "unsupported operation; only spec, register, status")
    | _ -> Error "id and operation must be bounded nonempty strings"
  in
  let body = match result with
    | Ok value -> "result", value
    | Error message -> "error", `Assoc ["code", `String "sa_plan_refused"; "message", `String message] in
  `Assoc ["version", `Int 1; "id", id; "operation", operation; body]

let () =
  match Array.to_list Sys.argv with
  | [_; "--spec"] -> Yojson.Basic.pretty_to_channel stdout Migration_plan.specification; print_newline ()
  | [_; "--db"; path] ->
      (try let request = read_frame () in write_frame (handle path request)
       with _ -> prerr_endline "invalid or incomplete SA-Plan request"; exit 2)
  | _ -> prerr_endline "usage: plan_port.exe --spec | --db ABSOLUTE_TASK_STATE_PATH (framed stdin)"; exit 2
