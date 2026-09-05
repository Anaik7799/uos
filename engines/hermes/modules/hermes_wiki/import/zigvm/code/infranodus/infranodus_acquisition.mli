(** Provider-neutral acquisition algebra. External systems are effects supplied
    by interpreters; the carrier always retains provenance and progress. *)

type source_kind =
  | Document | Spreadsheet | Batch | Web | Search | Youtube | Social
  | Knowledge_notes | Graph_network | Api

type provider_state =
  | Configured
  | Unavailable of string
  | Rate_limited of { retry_after_seconds : int }

type request = {
  id : string;
  kind : source_kind;
  locator : string option;
  content_type : string;
  content : string;
  metadata : (string * string) list;
}

type provider_payload = {
  body : string;
  content_type : string;
  metadata : (string * string) list;
  usage : int;
}

type progress = {
  completed : int;
  total : int;
  truncated : bool;
  retry_after_seconds : int option;
  usage : int;
}

type provenance = {
  request_id : string;
  source_kind : source_kind;
  locator : string option;
  content_type : string;
  metadata : (string * string) list;
}

type result = {
  statements : Graph_processing.statement list;
  processed : Graph_processing.result;
  provenance : provenance list;
  progress : progress;
}

type provider = request -> (provider_payload, provider_state) Stdlib.result

val source_kind_name : source_kind -> string
val request : id:string -> kind:source_kind -> ?locator:string -> ?metadata:(string * string) list -> content_type:string -> string -> request
val acquire : ?provider:provider -> ?profile:Graph_processing.profile -> request list -> (result, provider_state) Stdlib.result
val to_yojson : result -> Yojson.Safe.t
