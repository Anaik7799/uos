type surface = Ocaml_api | Cli | Mcp | Zenoh
type scope = Whole_system | Control_plane | Data_plane
type action =
  | Inventory
  | Plan
  | Decide
  | Act
  | Run
  | Check
  | Explain of string
  | Mbse_check
  | Fpp_check
  | Formal_check
  | Metrics_observe
  | History_observe
  | Orientation_observe
  | Debug of string
  | Invoke of string

type request = { request_id : string; action : action; scope : scope }
type verdict = Succeeded | Blocked
type receipt = {
  request_id : string;
  action : string;
  scope : string;
  verdict : verdict;
  output : string;
  digest : string;
}
type observation = { surface : surface; receipt : receipt }
type executor = request -> (string, string) result
type dispatcher = surface:surface -> request -> (observation, string) result

let action_name = function
  | Inventory -> "inventory" | Plan -> "plan" | Decide -> "decide"
  | Act -> "act" | Run -> "run" | Check -> "check"
  | Explain id -> "explain:" ^ id | Mbse_check -> "mbse-check"
  | Fpp_check -> "fpp-check" | Formal_check -> "formal-check"
  | Metrics_observe -> "metrics-observe"
  | History_observe -> "history-observe"
  | Orientation_observe -> "orientation-observe"
  | Debug id -> "debug:" ^ id
  | Invoke id -> "invoke:" ^ id

let scope_name = function
  | Whole_system -> "whole-system" | Control_plane -> "control-plane"
  | Data_plane -> "data-plane"

let verdict_name = function Succeeded -> "succeeded" | Blocked -> "blocked"

let supported_actions =
  [ "inventory"; "plan"; "decide"; "act"; "run"; "check"; "explain"; "mbse-check";
    "fpp-check"; "formal-check"; "metrics-observe"; "history-observe";
    "orientation-observe"; "debug"; "invoke" ]

let receipt_payload ~request_id ~action ~scope ~verdict ~output =
  `Assoc
    [ ("request_id", `String request_id); ("action", `String action);
      ("scope", `String scope); ("verdict", `String (verdict_name verdict));
      ("output", `String output) ]

let digest payload =
  payload |> Yojson.Safe.to_string |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let dispatch ~execute ~surface (request : request) =
  let action = action_name request.action in
  let scope = scope_name request.scope in
  let verdict, output =
    match execute request with Ok text -> (Succeeded, text) | Error text -> (Blocked, text)
  in
  let payload = receipt_payload ~request_id:request.request_id ~action ~scope ~verdict ~output in
  { surface;
    receipt =
      { request_id = request.request_id; action; scope; verdict; output;
        digest = digest payload } }

let receipt_json receipt =
  `Assoc
    [ ("request_id", `String receipt.request_id);
      ("action", `String receipt.action); ("scope", `String receipt.scope);
      ("verdict", `String (verdict_name receipt.verdict));
      ("output", `String receipt.output); ("digest", `String receipt.digest) ]
  |> Yojson.Safe.to_string

let scope_of_string = function
  | "whole-system" -> Ok Whole_system
  | "control-plane" -> Ok Control_plane
  | "data-plane" -> Ok Data_plane
  | value -> Error ("unknown scope: " ^ value)

let action_of_string ?target = function
  | "inventory" -> Ok Inventory | "plan" -> Ok Plan | "decide" -> Ok Decide
  | "act" -> Ok Act | "run" -> Ok Run
  | "check" -> Ok Check | "mbse-check" -> Ok Mbse_check
  | "fpp-check" -> Ok Fpp_check | "formal-check" -> Ok Formal_check
  | "metrics-observe" -> Ok Metrics_observe
  | "history-observe" -> Ok History_observe
  | "orientation-observe" -> Ok Orientation_observe
  | "debug" ->
      begin match target with
      | Some value when String.trim value <> "" -> Ok (Debug value)
      | _ -> Error "debug requires an intent id"
      end
  | "invoke" ->
      begin match target with
      | Some value when String.trim value <> "" -> Ok (Invoke value)
      | _ -> Error "invoke requires a declaration id"
      end
  | "explain" ->
      begin match target with
      | Some value when String.trim value <> "" -> Ok (Explain value)
      | _ -> Error "explain requires a declaration id"
      end
  | value -> Error ("unknown action: " ^ value)

let parse_options values =
  let rec loop scope request_id target = function
    | [] -> Ok (scope, request_id, target)
    | "--scope" :: value :: rest ->
        begin match scope_of_string value with
        | Error _ as error -> error
        | Ok parsed -> loop parsed request_id target rest
        end
    | "--request-id" :: value :: rest when String.trim value <> "" ->
        loop scope value target rest
    | value :: rest when target = None -> loop scope request_id (Some value) rest
    | value :: _ -> Error ("unexpected argument: " ^ value)
  in
  loop Whole_system "" None values

let dispatch_or_delegate ?dispatcher ~execute ~surface request =
  match dispatcher with
  | None -> Ok (dispatch ~execute ~surface request)
  | Some delegate -> delegate ~surface request

let dispatch_cli ?dispatcher ~execute = function
  | "completion" :: action_text :: options ->
      begin match parse_options options with
      | Error _ as error -> error
      | Ok (scope, request_id, target) ->
          if String.trim request_id = "" then Error "--request-id is required"
          else
            begin match action_of_string ?target action_text with
            | Error _ as error -> error
            | Ok action ->
                dispatch_or_delegate ?dispatcher ~execute ~surface:Cli
                  { request_id; action; scope }
            end
      end
  | _ -> Error "expected: completion ACTION --scope SCOPE --request-id ID"

let member_string key = function
  | `Assoc fields ->
      begin match List.assoc_opt key fields with
      | Some (`String value) when String.trim value <> "" -> Ok value
      | _ -> Error ("missing string field: " ^ key)
      end
  | _ -> Error "request must be a JSON object"

let optional_string key = function
  | `Assoc fields ->
      begin match List.assoc_opt key fields with
      | None -> None | Some (`String value) -> Some value | Some _ -> None
      end
  | _ -> None

let request_of_json json =
  match member_string "request_id" json, member_string "action" json,
        member_string "scope" json with
  | Ok request_id, Ok action_text, Ok scope_text ->
      begin match scope_of_string scope_text,
                  action_of_string ?target:(optional_string "target" json) action_text with
      | Ok scope, Ok action -> Ok { request_id; action; scope }
      | Error error, _ | _, Error error -> Error error
      end
  | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error

let dispatch_mcp ?dispatcher ~execute json =
  match request_of_json json with
  | Error _ as error -> error
  | Ok request -> dispatch_or_delegate ?dispatcher ~execute ~surface:Mcp request

let dispatch_zenoh ?dispatcher ~execute ~key ~payload () =
  match String.split_on_char '/' key with
  | [ "hermes"; plane; "completion"; action_text ]
    when plane = "control" || plane = "data" ->
      begin match Yojson.Safe.from_string payload with
      | exception Yojson.Json_error message -> Error ("malformed Zenoh payload: " ^ message)
      | json ->
          begin match member_string "request_id" json, member_string "scope" json with
          | Ok request_id, Ok scope_text ->
              begin match scope_of_string scope_text,
                          action_of_string ?target:(optional_string "target" json) action_text with
              | Ok scope, Ok action ->
                  let plane_matches =
                    match plane, scope with
                    | "control", (Whole_system | Control_plane) -> true
                    | "data", Data_plane -> true
                    | _ -> false
                  in
                  if not plane_matches then Error "Zenoh key plane disagrees with request scope"
                  else
                    dispatch_or_delegate ?dispatcher ~execute ~surface:Zenoh
                      { request_id; action; scope }
              | Error error, _ | _, Error error -> Error error
              end
          | Error error, _ | _, Error error -> Error error
          end
      end
  | _ -> Error "invalid Zenoh completion key"

let mcp_tool_schema =
  `Assoc
    [ ("name", `String "hermes_completion");
      ("description", `String "Dispatch the typed Hermes completion command algebra");
      ("inputSchema",
       `Assoc
         [ ("type", `String "object");
           ("properties",
            `Assoc
              [ ("request_id", `Assoc [ ("type", `String "string") ]);
                ("action",
                 `Assoc
                   [ ("type", `String "string");
                     ("enum", `List (List.map (fun value -> `String value) supported_actions)) ]);
                ("scope",
                 `Assoc
                   [ ("type", `String "string");
                     ("enum", `List [ `String "whole-system";
                                      `String "control-plane"; `String "data-plane" ]) ]);
                ("target", `Assoc [ ("type", `String "string") ]) ]);
           ("required", `List [ `String "request_id"; `String "action"; `String "scope" ]) ]) ]
