type session = Zlt_1 | Zlt_2 | Zlt_3 | Zlt_4 | Zlt_5 | Zlt_6
type install_method = Cargo_locked
type attachment = Manual

type t = {
  install_method : install_method;
  workspace_root : string;
  config_root : string;
  command_root : string;
  zellij_bin : string;
  shell : string;
  sessions : session list;
  attachment : attachment;
}

let all_sessions = [ Zlt_1; Zlt_2; Zlt_3; Zlt_4; Zlt_5; Zlt_6 ]

let session_name = function
  | Zlt_1 -> "zlt-1"
  | Zlt_2 -> "zlt-2"
  | Zlt_3 -> "zlt-3"
  | Zlt_4 -> "zlt-4"
  | Zlt_5 -> "zlt-5"
  | Zlt_6 -> "zlt-6"

let session_of_string = function
  | "zlt-1" -> Some Zlt_1
  | "zlt-2" -> Some Zlt_2
  | "zlt-3" -> Some Zlt_3
  | "zlt-4" -> Some Zlt_4
  | "zlt-5" -> Some Zlt_5
  | "zlt-6" -> Some Zlt_6
  | _ -> None

let rank = function
  | Zlt_1 -> 1
  | Zlt_2 -> 2
  | Zlt_3 -> 3
  | Zlt_4 -> 4
  | Zlt_5 -> 5
  | Zlt_6 -> 6

let compare_session left right = Int.compare (rank left) (rank right)
let absolute_nonempty value = String.length value > 1 && value.[0] = '/'

let duplicates sessions =
  let sorted = List.sort compare_session sessions in
  let rec loop acc = function
    | left :: (right :: _ as tail) when left = right -> loop (left :: acc) tail
    | _ :: tail -> loop acc tail
    | [] -> List.rev acc
  in
  loop [] sorted

let validate value =
  let errors = ref [] in
  let require condition message =
    if not condition then errors := message :: !errors
  in
  require
    (absolute_nonempty value.workspace_root)
    "workspace_root must be a nonempty absolute path";
  require
    (absolute_nonempty value.config_root)
    "config_root must be a nonempty absolute path";
  require
    (absolute_nonempty value.command_root)
    "command_root must be a nonempty absolute path";
  require
    (absolute_nonempty value.zellij_bin)
    "zellij_bin must be a nonempty absolute path";
  require
    (absolute_nonempty value.shell)
    "shell must be a nonempty absolute path";
  require (value.sessions <> []) "session carrier must not be empty";
  require (duplicates value.sessions = []) "session carrier contains duplicates";
  require
    (value.sessions = all_sessions)
    "session carrier must be exactly zlt-1 through zlt-6 in order";
  List.rev !errors

let make ~install_method ~workspace_root ~config_root ~command_root ~zellij_bin
    ~shell ~sessions ~attachment () =
  let value =
    {
      install_method;
      workspace_root;
      config_root;
      command_root;
      zellij_bin;
      shell;
      sessions;
      attachment;
    }
  in
  match validate value with [] -> Ok value | errors -> Error errors

let default () =
  make ~install_method:Cargo_locked
    ~workspace_root:"/home/an/dev/ver/harness-bionic"
    ~config_root:"/home/an/.config/zellij" ~command_root:"/home/an/.local/bin"
    ~zellij_bin:"/home/an/.cargo/bin/zellij" ~shell:"/usr/bin/zsh"
    ~sessions:all_sessions ~attachment:Manual ()

let workspace_root value = value.workspace_root
let config_root value = value.config_root
let command_root value = value.command_root
let zellij_bin value = value.zellij_bin
let shell value = value.shell
let sessions value = value.sessions

let json_string value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '"';
  String.iter
    (fun character ->
      match character with
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\b' -> Buffer.add_string buffer "\\b"
      | '\012' -> Buffer.add_string buffer "\\f"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\000' .. '\031' ->
          Buffer.add_string buffer
            (Printf.sprintf "\\u%04x" (Char.code character))
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.add_char buffer '"';
  Buffer.contents buffer

let canonical_json value =
  let sessions =
    value.sessions
    |> List.map (fun session -> json_string (session_name session))
    |> String.concat ","
  in
  Printf.sprintf
    "{\"install_method\":\"cargo-locked\",\"workspace_root\":%s,\"config_root\":%s,\"command_root\":%s,\"zellij_bin\":%s,\"shell\":%s,\"sessions\":[%s],\"attachment\":\"manual\"}"
    (json_string value.workspace_root)
    (json_string value.config_root)
    (json_string value.command_root)
    (json_string value.zellij_bin)
    (json_string value.shell) sessions

let digest value =
  Digestif.SHA256.(to_hex (digest_string (canonical_json value)))
