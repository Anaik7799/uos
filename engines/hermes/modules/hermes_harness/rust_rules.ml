(* The embedded Rust rule engine (rust-rule-engine, GRL), integrated via FFI.

   One external call, JSON in and JSON out -- the oracle discipline: the reply is
   parsed and validated here, every failure (unreadable input, rejected GRL,
   execution error, engine-reported crash) is an Error value, and the call never
   raises. The Rust side (rust/drift_engine) never panics across the boundary;
   the OCaml Hermes_rete mirror stays the differential reference this engine is
   checked against in test_rust_rules. *)

external hde_eval : string -> string = "caml_hde_eval"

type result = { rules_fired : int; cycle_count : int; facts : Yojson.Safe.t }

let available () = true

(* The crate's Value serde-serializes with enum tags --
   {"Object": {"Advice": {"String": "x"}}} -- so replies are unwrapped back to
   plain JSON here. Normalization is the OCaml side's judgement, keeping the
   Rust wrapper dumb. Unknown or malformed tags are left as-is rather than
   guessed at: a comparison would then fail loudly instead of silently passing. *)
let rec untag (value : Yojson.Safe.t) : Yojson.Safe.t =
  match value with
  | `Assoc [ ("String", `String s) ] -> `String s
  | `Assoc [ ("Integer", `Int i) ] -> `Int i
  | `Assoc [ ("Number", (`Float _ as f)) ] -> f
  | `Assoc [ ("Number", `Int i) ] -> `Float (float_of_int i)
  | `Assoc [ ("Boolean", `Bool b) ] -> `Bool b
  | `Assoc [ ("Null", `Null) ] | `Assoc [ ("Null", `List []) ] -> `Null
  | `Assoc [ ("Array", `List items) ] -> `List (List.map untag items)
  | `Assoc [ ("Object", `Assoc fields) ] ->
      `Assoc (List.map (fun (k, v) -> (k, untag v)) fields)
  | `String "Null" -> `Null
  | `Assoc fields -> `Assoc (List.map (fun (k, v) -> (k, untag v)) fields)
  | `List items -> `List (List.map untag items)
  | other -> other

let eval ~grl ~facts =
  let request = `Assoc [ ("grl", `String grl); ("facts", facts) ] in
  match Yojson.Safe.from_string (hde_eval (Yojson.Safe.to_string request)) with
  | exception Yojson.Json_error message -> Error ("unreadable engine reply: " ^ message)
  | `Assoc fields -> (
      match List.assoc_opt "error" fields with
      | Some (`String reason) -> Error reason
      | Some other -> Error (Yojson.Safe.to_string other)
      | None -> (
          match
            ( List.assoc_opt "rules_fired" fields,
              List.assoc_opt "cycle_count" fields,
              List.assoc_opt "facts" fields )
          with
          | Some (`Int rules_fired), Some (`Int cycle_count), Some facts ->
              Ok { rules_fired; cycle_count; facts = untag facts }
          | _ -> Error "engine reply is missing required fields"))
  | _ -> Error "engine reply was not an object"
