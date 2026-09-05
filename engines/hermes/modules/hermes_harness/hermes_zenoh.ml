(* Zenoh publisher -- the c3i `scripts/common/zenoh` discipline mirrored into
   OCaml (R14): typed wrapper, one publish path, fail-open at call sites.
   The wire work happens in one C stub over the vendored zenoh-c; everything
   that can be validated stays pure OCaml on this side of the FFI. *)

external hz_publish : string -> string -> string -> string = "caml_hz_publish"
external hz_serve_queryable : string -> string -> string = "caml_hz_serve_queryable"
external hz_query : string -> string -> string -> string = "caml_hz_query"

let default_endpoint = "tcp/127.0.0.1:7447"

let endpoint () =
  match Sys.getenv_opt "HERMES_ZENOH_ENDPOINT" with
  | Some value when String.trim value <> "" -> String.trim value
  | _ -> default_endpoint

let enabled () =
  match Sys.getenv_opt "HERMES_ZENOH" with Some "0" -> false | _ -> true

(* A publisher's key must be concrete and well-formed; wildcards belong to
   subscribers. Rejected here, before the wire, so a bad key never even opens
   a session. *)
let valid_key key =
  let length = String.length key in
  length > 0
  && key.[0] <> '/'
  && key.[length - 1] <> '/'
  && not
       (String.exists
          (fun c ->
            c = ' ' || c = '\t' || c = '\n' || c = '*' || c = '$' || c = '?' || c = '#')
          key)

let publish ~key ~payload =
  if not (enabled ()) then Error "disabled by HERMES_ZENOH=0 -- telemetry stays local"
  else if not (valid_key key) then Error ("invalid key expression: " ^ key)
  else
    match hz_publish (endpoint ()) key payload with
    | "ok" -> Ok ()
    | detail -> Error detail
    | exception _ -> Error "zenoh stub raised unexpectedly"

let valid_keyexpr keyexpr =
  let length = String.length keyexpr in
  length > 0 && keyexpr.[0] <> '/' && keyexpr.[length - 1] <> '/'
  && not (String.exists (fun c -> c = ' ' || c = '\t' || c = '\n' || c = '$' || c = '?' || c = '#') keyexpr)

let serve_queryable ~keyexpr ~callback =
  if not (enabled ()) then Error "disabled by HERMES_ZENOH=0 -- command ingress is unavailable"
  else if not (valid_keyexpr keyexpr) then Error ("invalid queryable key expression: " ^ keyexpr)
  else begin
    Callback.register "hermes_zenoh_command" callback;
    match hz_serve_queryable (endpoint ()) keyexpr with
    | "ok" -> Ok ()
    | detail -> Error detail
    | exception _ -> Error "zenoh queryable stub raised unexpectedly"
  end

let query ~key ~payload =
  if not (enabled ()) then Error "disabled by HERMES_ZENOH=0 -- command query is unavailable"
  else if not (valid_key key) then Error ("invalid command query key: " ^ key)
  else
    match hz_query (endpoint ()) key payload with
    | detail when String.length detail >= 7 && String.sub detail 0 7 = "error: " -> Error detail
    | reply -> Ok reply
    | exception _ -> Error "zenoh query stub raised unexpectedly"
