(** Pure verification graph and exact-cache frontier.

    This mirrors ZigVM Vgraph/Vcache P2-P3 while strengthening identities to
    SHA-256 and rejecting ambiguous graphs or cache maps. *)

type attempt_phase = Sequential_oracle | Bounded_parallel of { lane : int }

type attempt = { attempt_id : int; phase : attempt_phase }

type unit_kind =
  | Identity_admission
  | Formal_model
  | Formal_smt
  | Native_focused
  | Permit_capacity of int
  | Process_attempt of attempt
  | Process_reliability
  | Crash_window
  | Fpp_mbse
  | Full_gate

type cache_policy = Reusable | Always_run

type input_kind = Source_input | Configuration_input | Tool_input | Executable_input

type input_state =
  | Present of string
  | Missing
  | Unreadable of string

type input_requirement = {
  key : string;
  kind : input_kind;
  expected_digest : string option;
}

type input_fact = { key : string; kind : input_kind; state : input_state }

type node = {
  id : string;
  kind : unit_kind;
  dependencies : string list;
  inputs : input_fact list;
  criticality : int;
  cache_policy : cache_policy;
}

type verdict =
  | Passed
  | Failed of string
  | Unavailable of string
  | Skipped
  | Corrupt of string

type authority_binding = {
  target_digest : string;
  policy_digest : string;
  criteria_digest : string;
  source_digest : string;
  configuration_digest : string;
  toolchain_digest : string;
  executable_digest : string;
  topology_digest : string;
  receipt_digest : string;
}

type cache_entry = {
  fingerprint : string;
  authority : authority_binding;
  verdict : verdict;
}

val required_inputs : Dependability_intent.t -> input_requirement list

val build :
  inputs:input_fact list ->
  Dependability_intent.t ->
  (node list, string list) result
(*@ graph = build ~inputs intent
    pure *)

val validate : node list -> string list
(*@ errors = validate graph
    pure *)

val topo_order : node list -> node list
(*@ ordered = topo_order graph
    pure *)

val fingerprint : node -> parents:(string * string) list -> string
(*@ hash = fingerprint node ~parents
    pure
    ensures String.length hash = 64 *)

val fingerprints : node list -> (string * string) list
(*@ hashes = fingerprints graph
    pure *)

val dirty_frontier :
  fingerprints:(string * string) list ->
  authorities:(string * authority_binding) list ->
  cache:(string * cache_entry) list ->
  node list ->
  string list
(*@ dirty = dirty_frontier ~fingerprints ~authorities ~cache graph
    pure *)
