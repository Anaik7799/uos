type 'a fact = Known of 'a | Unknown of string

type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

type runner = program:string -> argv:string array -> process_result
type link_state = Correct | Missing | Wrong of string

type observation = {
  version : string fact;
  sessions : Zellij_intent.session list fact;
  config_digest : string option fact;
  launcher_present : bool fact;
  command_links : (Zellij_intent.session * link_state) list;
  tmux_sessions : string fact;
  nested_session : bool fact;
}

let make ~version ~sessions ~config_digest ~launcher_present ~command_links
    ~tmux_sessions ~nested_session =
  {
    version;
    sessions;
    config_digest;
    launcher_present;
    command_links;
    tmux_sessions;
    nested_session;
  }

let version value = value.version
let sessions value = value.sessions
let config_digest value = value.config_digest
let launcher_present value = value.launcher_present
let command_links value = value.command_links
let tmux_sessions value = value.tmux_sessions
let nested_session value = value.nested_session

let run ~program ~argv =
  try
    let input, output, error =
      Unix.open_process_args_full program argv (Unix.environment ())
    in
    close_out_noerr output;
    let stdout = In_channel.input_all input in
    let stderr = In_channel.input_all error in
    let status = Unix.close_process_full (input, output, error) in
    { status; stdout; stderr }
  with exn ->
    { status = Unix.WEXITED 127; stdout = ""; stderr = Printexc.to_string exn }

let trim_lines value =
  value |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun line -> line <> "")

let parse_sessions result =
  match result.status with
  | Unix.WEXITED 0 ->
      let names = trim_lines result.stdout in
      let rec parse acc = function
        | [] ->
            let sessions = List.rev acc in
            if
              List.sort_uniq Zellij_intent.compare_session sessions = sessions
              || List.length
                   (List.sort_uniq Zellij_intent.compare_session sessions)
                 = List.length sessions
            then Known sessions
            else Unknown "duplicate session identity"
        | name :: rest -> (
            match Zellij_intent.session_of_string name with
            | Some session -> parse (session :: acc) rest
            | None -> Unknown ("unrecognized session output: " ^ name))
      in
      parse [] names
  | Unix.WEXITED 1
    when String.equal
           (String.trim result.stderr)
           "No active zellij sessions found." ->
      Known []
  | Unix.WEXITED code ->
      Unknown
        (Printf.sprintf "zellij list-sessions exited %d: %s" code
           (String.trim result.stderr))
  | Unix.WSIGNALED signal ->
      Unknown (Printf.sprintf "zellij list-sessions signalled %d" signal)
  | Unix.WSTOPPED signal ->
      Unknown (Printf.sprintf "zellij list-sessions stopped %d" signal)

let read_file path =
  try
    if not (Sys.file_exists path) then Known None
    else if Sys.is_directory path then Unknown (path ^ " is a directory")
    else
      In_channel.with_open_bin path (fun channel ->
          Known (Some (Zellij_projection.digest (In_channel.input_all channel))))
  with exn -> Unknown (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let executable_present path =
  try
    let stats = Unix.stat path in
    Known
      (stats.Unix.st_kind = Unix.S_REG
      &&
      match Unix.access path [ Unix.X_OK ] with
      | () -> true
      | exception _ -> false)
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Known false
  | exn -> Unknown (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let observe_link ~target path =
  try
    match (Unix.lstat path).Unix.st_kind with
    | Unix.S_LNK ->
        let observed = Unix.readlink path in
        if String.equal observed target then Correct else Wrong observed
    | _ -> Wrong "not-a-symbolic-link"
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Missing
  | exn -> Wrong (Printexc.to_string exn)

let process_fact label result =
  match result.status with
  | Unix.WEXITED 0 -> Known (String.trim result.stdout)
  | Unix.WEXITED code ->
      Unknown
        (Printf.sprintf "%s exited %d: %s" label code
           (String.trim result.stderr))
  | Unix.WSIGNALED signal ->
      Unknown (Printf.sprintf "%s signalled %d" label signal)
  | Unix.WSTOPPED signal ->
      Unknown (Printf.sprintf "%s stopped %d" label signal)

let observe_with ~runner intent =
  try
    let zellij = Zellij_intent.zellij_bin intent in
    let version =
      runner ~program:zellij ~argv:[| zellij; "--version" |]
      |> process_fact "zellij --version"
    in
    let sessions =
      runner ~program:zellij
        ~argv:[| zellij; "list-sessions"; "--short"; "--no-formatting" |]
      |> parse_sessions
    in
    let config_path =
      Filename.concat (Zellij_intent.config_root intent) "config.kdl"
    in
    let launcher =
      Filename.concat
        (Zellij_intent.command_root intent)
        "zellij-attach-harness-bionic"
    in
    let command_links =
      Zellij_projection.command_links intent
      |> List.filter_map (fun (name, target) ->
          Option.map
            (fun session ->
              ( session,
                observe_link ~target
                  (Filename.concat (Zellij_intent.command_root intent) name) ))
            (Zellij_intent.session_of_string name))
    in
    let tmux =
      runner ~program:"tmux"
        ~argv:[| "tmux"; "list-sessions"; "-F"; "#{session_name}" |]
    in
    let tmux_sessions =
      match tmux.status with
      | Unix.WEXITED 1
        when String.starts_with ~prefix:"no server running on"
               (String.trim tmux.stderr) ->
          Known ""
      | _ -> process_fact "tmux list-sessions" tmux
    in
    {
      version;
      sessions;
      config_digest = read_file config_path;
      launcher_present = executable_present launcher;
      command_links;
      tmux_sessions;
      nested_session =
        Known (Option.is_some (Sys.getenv_opt "ZELLIJ_SESSION_NAME"));
    }
  with exn ->
    let reason = "observation failed: " ^ Printexc.to_string exn in
    {
      version = Unknown reason;
      sessions = Unknown reason;
      config_digest = Unknown reason;
      launcher_present = Unknown reason;
      command_links = [];
      tmux_sessions = Unknown reason;
      nested_session = Unknown reason;
    }

let observe intent = observe_with ~runner:run intent
