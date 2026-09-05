type change =
  | Write_config
  | Install_launcher
  | Link_command of Zellij_intent.session
  | Ensure_session of Zellij_intent.session

type command = Plan | Check | Apply | Ensure | Status | Docs_audit

type receipt = {
  intent_digest : string;
  applied : change list;
  config_digest : string;
}

let ( let* ) result function_ =
  match result with Ok value -> function_ value | Error _ as e -> e

let launcher_session path =
  let basename = Filename.basename path in
  match Zellij_intent.session_of_string basename with
  | Some session -> Ok session
  | None -> Error ("launcher basename is not a declared session: " ^ basename)

let command_of_argv = function
  | [| _; "plan" |] -> Ok Plan
  | [| _; "check" |] -> Ok Check
  | [| _; "apply" |] -> Ok Apply
  | [| _; "ensure" |] -> Ok Ensure
  | [| _; "status" |] -> Ok Status
  | [| _; "docs-audit" |] -> Ok Docs_audit
  | [| _ |] ->
      Error "one command is required: plan|check|apply|ensure|status|docs-audit"
  | _ ->
      Error
        "unknown arguments; accepted commands are \
         plan|check|apply|ensure|status|docs-audit"

let render_change = function
  | Write_config -> "write-config"
  | Install_launcher -> "install-launcher"
  | Link_command session -> "link-command:" ^ Zellij_intent.session_name session
  | Ensure_session session ->
      "ensure-session:" ^ Zellij_intent.session_name session

let plan intent observation =
  let open Zellij_observe in
  let errors = ref [] in
  let changes = ref [] in
  let add_error error = errors := error :: !errors in
  let add change = changes := change :: !changes in
  (match nested_session observation with
  | Known false -> ()
  | Known true ->
      add_error "refusing mutation planning from inside a Zellij session"
  | Unknown reason -> add_error ("nested-session state unknown: " ^ reason));
  (match version observation with
  | Known value when String.trim value <> "" -> ()
  | Known _ -> add_error "zellij version output was empty"
  | Unknown reason -> add_error ("zellij version unknown: " ^ reason));
  (match tmux_sessions observation with
  | Known _ -> ()
  | Unknown reason -> add_error ("tmux baseline unknown: " ^ reason));
  let expected_config =
    Zellij_projection.render_config_kdl intent |> Zellij_projection.digest
  in
  (match config_digest observation with
  | Known (Some observed) when String.equal observed expected_config -> ()
  | Known _ -> add Write_config
  | Unknown reason -> add_error ("configuration state unknown: " ^ reason));
  (match launcher_present observation with
  | Known true -> ()
  | Known false -> add Install_launcher
  | Unknown reason -> add_error ("launcher state unknown: " ^ reason));
  let observed_links = command_links observation in
  List.iter
    (fun session ->
      match List.assoc_opt session observed_links with
      | Some Correct -> ()
      | Some Missing | Some (Wrong _) -> add (Link_command session)
      | None ->
          add_error
            ("command observation missing: "
            ^ Zellij_intent.session_name session))
    (Zellij_intent.sessions intent);
  (match sessions observation with
  | Known live ->
      List.iter
        (fun session ->
          if not (List.mem session live) then add (Ensure_session session))
        (Zellij_intent.sessions intent)
  | Unknown reason -> add_error ("session set unknown: " ^ reason));
  match List.rev !errors with
  | [] -> Ok (List.rev !changes)
  | errors -> Error errors

let preflight_resources intent =
  let open Resource_envelope in
  [
    Binary { name = "cargo"; env_var = None };
    Binary { name = "rustc"; env_var = None };
    Binary { name = "zellij"; env_var = None };
    Frozen_reference { root = Zellij_intent.workspace_root intent };
    Disk_space
      {
        path = Zellij_intent.workspace_root intent;
        bytes_needed = 32 * 1024 * 1024;
        margin = default_margin;
      };
    Temp_space { bytes_needed = 16 * 1024 * 1024; margin = default_margin };
    Writable (Zellij_intent.config_root intent);
    Writable (Zellij_intent.command_root intent);
  ]

let preflight intent =
  let checks = Resource_envelope.preflight (preflight_resources intent) in
  if Resource_envelope.satisfied checks then Ok ()
  else
    checks |> Resource_envelope.unmet_checks
    |> List.map Resource_envelope.render_check
    |> fun errors -> Error errors

let rec ensure_directory path =
  if path = "." || path = "" then Ok ()
  else if Sys.file_exists path then
    if Sys.is_directory path then Ok ()
    else Error (path ^ " exists and is not a directory")
  else
    let* () = ensure_directory (Filename.dirname path) in
    try
      Unix.mkdir path 0o755;
      Ok ()
    with
    | Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> Ok ()
    | exn -> Error (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let write_atomic_with ~emit path content =
  let temporary = Printf.sprintf "%s.tmp.%d" path (Unix.getpid ()) in
  let cleanup () =
    try if Sys.file_exists temporary then Sys.remove temporary with _ -> ()
  in
  try
    let channel = open_out_bin temporary in
    let result =
      Fun.protect
        ~finally:(fun () -> close_out_noerr channel)
        (fun () ->
          let* () = emit channel content in
          flush channel;
          Unix.fsync (Unix.descr_of_out_channel channel);
          Ok ())
    in
    let* () = result in
    Unix.rename temporary path;
    Ok ()
  with exn ->
    cleanup ();
    Error (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let write_atomic path content =
  write_atomic_with
    ~emit:(fun channel value ->
      output_string channel value;
      Ok ())
    path content

let read_file path =
  try Ok (In_channel.with_open_bin path In_channel.input_all)
  with exn -> Error (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let copy_atomic ~source target =
  let* bytes = read_file source in
  let* () = write_atomic target bytes in
  try
    Unix.chmod target 0o755;
    Ok ()
  with exn -> Error (Printf.sprintf "%s: %s" target (Printexc.to_string exn))

let link_atomic ~target path =
  let temporary = Printf.sprintf "%s.tmp.%d" path (Unix.getpid ()) in
  let cleanup () = try Unix.unlink temporary with _ -> () in
  try
    cleanup ();
    Unix.symlink target temporary;
    Unix.rename temporary path;
    Ok ()
  with exn ->
    cleanup ();
    Error (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let validate_kdl intent content =
  let temporary = Filename.temp_file "hermes-zellij-config-" ".kdl" in
  let cleanup () = try Sys.remove temporary with _ -> () in
  Fun.protect ~finally:cleanup (fun () ->
      let* () = write_atomic temporary content in
      let zellij = Zellij_intent.zellij_bin intent in
      let result =
        Zellij_observe.run ~program:zellij
          ~argv:[| zellij; "--config"; temporary; "setup"; "--check" |]
      in
      match result.status with
      | Unix.WEXITED 0 -> Ok ()
      | _ -> Error ("native KDL validation failed: " ^ String.trim result.stderr))

let backup_existing intent =
  let config_root = Zellij_intent.config_root intent in
  let sources =
    [
      Filename.concat config_root "config.kdl";
      Filename.concat config_root "layouts/harness-bionic.kdl";
      Filename.concat config_root "z_connect.sh";
    ]
    |> List.filter Sys.file_exists
  in
  if sources = [] then Ok ()
  else
    let time = Unix.localtime (Unix.time ()) in
    let stamp =
      Printf.sprintf "%04d%02d%02d-%02d%02d%02d" (time.tm_year + 1900)
        (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min time.tm_sec
    in
    let root =
      Filename.concat config_root ("backups/harness-bionic-" ^ stamp)
    in
    let* () = ensure_directory root in
    let rec copy = function
      | [] -> Ok ()
      | source :: rest ->
          let target = Filename.concat root (Filename.basename source) in
          let* () = copy_atomic ~source target in
          let* () =
            try
              Unix.chmod target 0o600;
              Ok ()
            with exn -> Error (Printexc.to_string exn)
          in
          copy rest
    in
    copy sources

let documentation_outputs intent =
  let root = Zellij_intent.workspace_root intent in
  [
    ( Filename.concat root "docs/hermes/zellij/ontology.md",
      Zellij_projection.render_ontology_markdown () );
    ( Filename.concat root "docs/hermes/zellij/fractal-functional-atlas.md",
      Zellij_projection.render_atlas_markdown () );
    ( Filename.concat root "docs/hermes/zellij/fractal-functional-algebra.md",
      Zellij_projection.render_algebra_markdown () );
    ( Filename.concat root "docs/hermes/zellij/README.md",
      Zellij_projection.render_guide_markdown intent );
    ( Filename.concat root
        "docs/hermes/zellij/official-documentation-authority.json",
      Zellij_projection.render_authority_json () );
    ( Filename.concat root "docs/hermes/zellij/model.json",
      Zellij_projection.render_model_json intent );
  ]

let write_documentation intent =
  let outputs = documentation_outputs intent in
  let rec write paths = function
    | [] -> Ok (List.rev paths)
    | (path, content) :: rest ->
        let* () = ensure_directory (Filename.dirname path) in
        let* () = write_atomic path content in
        write (path :: paths) rest
  in
  match write [] outputs with
  | Ok paths -> Ok paths
  | Error message -> Error [ message ]

let with_cwd directory function_ =
  let previous = Unix.getcwd () in
  try
    Unix.chdir directory;
    Fun.protect
      ~finally:(fun () -> try Unix.chdir previous with _ -> ())
      function_
  with exn -> Error (Printexc.to_string exn)

let ensure_session intent session =
  let zellij = Zellij_intent.zellij_bin intent in
  let name = Zellij_intent.session_name session in
  with_cwd (Zellij_intent.workspace_root intent) (fun () ->
      let result =
        Zellij_observe.run ~program:zellij
          ~argv:[| zellij; "attach"; "--create-background"; name |]
      in
      match result.status with
      | Unix.WEXITED 0 -> Ok ()
      | _ ->
          Error
            (Printf.sprintf "ensure %s failed: %s %s" name
               (String.trim result.stdout)
               (String.trim result.stderr)))

let apply ~launcher_source intent changes =
  match preflight intent with
  | Error errors -> Error errors
  | Ok () -> (
      let config_root = Zellij_intent.config_root intent in
      let command_root = Zellij_intent.command_root intent in
      let launcher_target =
        Filename.concat command_root "zellij-attach-harness-bionic"
      in
      let config = Zellij_projection.render_config_kdl intent in
      let perform = function
        | Write_config ->
            let* () = ensure_directory config_root in
            let* () = validate_kdl intent config in
            let* () = backup_existing intent in
            write_atomic (Filename.concat config_root "config.kdl") config
        | Install_launcher ->
            let* () = ensure_directory command_root in
            copy_atomic ~source:launcher_source launcher_target
        | Link_command session ->
            let path =
              Filename.concat command_root (Zellij_intent.session_name session)
            in
            link_atomic ~target:launcher_target path
        | Ensure_session session -> ensure_session intent session
      in
      let rec perform_all done_ = function
        | [] -> Ok (List.rev done_)
        | change :: rest ->
            let* () = perform change in
            perform_all (change :: done_) rest
      in
      match perform_all [] changes with
      | Error message -> Error [ message ]
      | Ok applied -> (
          match write_documentation intent with
          | Error errors -> Error errors
          | Ok _ ->
              Ok
                {
                  intent_digest = Zellij_intent.digest intent;
                  applied;
                  config_digest = Zellij_projection.digest config;
                }))
