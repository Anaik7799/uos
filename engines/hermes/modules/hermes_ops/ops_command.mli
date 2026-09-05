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

val action_name : action -> string
val scope_name : scope -> string
val dispatch : execute:executor -> surface:surface -> request -> observation
val dispatch_cli : ?dispatcher:dispatcher -> execute:executor -> string list -> (observation, string) result
val dispatch_mcp : ?dispatcher:dispatcher -> execute:executor -> Yojson.Safe.t -> (observation, string) result
val dispatch_zenoh : ?dispatcher:dispatcher -> execute:executor -> key:string -> payload:string ->
  unit -> (observation, string) result
val receipt_json : receipt -> string
val supported_actions : string list
val mcp_tool_schema : Yojson.Safe.t
