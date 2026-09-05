(* The FPP (F Prime Prime) metamodel, mapped construct-for-construct into
   OCaml. Source of truth: the FPP language specification and the F Prime
   JSON dictionary specification (imported 2026-08-08 —
   docs/hermes/references/fprime-digest.md). The mapping table lives in
   docs/hermes/fprime-alignment.md.

   Scope note (honest): telemetry packet sets are carried as an empty
   dictionary key, and init specifiers / include / location specifiers are
   translation-unit concerns with no runtime semantics here; the alignment
   doc records both. Everything else in the spec's definition and specifier
   inventory is representable below.

   The validator enforces the spec's semantic checks and returns fractal
   diagnostics (level L3/contract, origin Specification): a model defect is
   the specification saying the wrong thing, and it never touches parity
   (R10). Emitters are fail-closed: an invalid model refuses to emit. *)

(* ------------------------------------------------------------------ types *)

type prim = U8 | U16 | U32 | U64 | I8 | I16 | I32 | I64 | F32 | F64 | Bool
          | String of int option

type ty = Prim of prim | Named of string

type type_def =
  | Abstract of { name : string }
  | Alias of { name : string; target : ty }
  | Array_t of { name : string; size : int; element : ty; format : string option }
  | Enum_t of { name : string; repr : prim; constants : (string * int) list }
  | Struct_t of { name : string; members : (string * ty) list }

(* ------------------------------------------------------------------ ports *)

type port_def = {
  port_name : string;
  params : (string * ty) list;
  return_type : ty option;
}

type queue_full = Assert | Block | Drop

type direction =
  | Sync_input
  | Guarded_input
  | Async_input of { priority : int option; queue_full : queue_full }
  | Output

type special_port =
  | Command_recv | Command_reg | Command_resp
  | Event_p | Text_event_p | Telemetry_p | Time_get
  | Param_get_p | Param_set_p
  | Product_get_p | Product_request_p | Product_recv_p | Product_send_p

type port_instance =
  | General of { name : string; port : string; direction : direction; count : int }
  | Special of special_port

(* ------------------------------------------------------- C&DH dictionaries *)

type command_kind =
  | Sync_cmd
  | Guarded_cmd
  | Async_cmd of { priority : int option; queue_full : queue_full }

type command = {
  cmd_name : string;
  opcode : int;
  cmd_kind : command_kind;
  cmd_params : (string * ty) list;
}

type severity =
  | Activity_hi | Activity_lo | Command_sev | Diagnostic | Fatal
  | Warning_hi | Warning_lo

type event = {
  event_name : string;
  event_id : int;
  severity : severity;
  format : string;
  throttle : int option;
}

type update = Always | On_change

type threshold = { yellow : float option; orange : float option; red : float option }

type channel = {
  chan_name : string;
  chan_id : int;
  chan_type : ty;
  update : update;
  chan_format : string option;
  low : threshold option;
  high : threshold option;
}

type parameter = {
  param_name : string;
  param_id : int;
  param_type : ty;
  default : string option;
  set_opcode : int;
  save_opcode : int;
  external_ : bool;
}

type record_spec = {
  record_name : string;
  record_id : int;
  record_type : ty;
  record_is_array : bool;
}

type container_spec = {
  container_name : string;
  container_id : int;
  default_priority : int option;
}

type internal_port = {
  internal_name : string;
  internal_params : (string * ty) list;
  internal_priority : int option;
  internal_queue_full : queue_full;
}

(* --------------------------------------------------------- state machines *)

type target = To_state of string | To_choice of string

type transition = {
  on_signal : string;
  guard : string option;
  do_actions : string list;
  target : target;
}

type state = {
  state_name : string;
  entry : string list;
  exit_ : string list;
  transitions : transition list;
}

type signal_def = { signal_name : string; signal_type : ty option }

type choice = {
  choice_name : string;
  choice_guard : string;
  if_true : string list * target;
  if_false : string list * target;
}

type state_machine =
  | External_machine of { machine_name : string }
  | Internal_machine of {
      machine_name : string;
      signals : signal_def list;
      guards : string list;
      actions : string list;
      states : state list;
      choices : choice list;
      initial : string list * string;
    }

(* -------------------------------------------------------------- components *)

type component_kind = Passive | Queued | Active

type component = {
  comp_name : string;
  kind : component_kind;
  ports : port_instance list;
  commands : command list;
  events : event list;
  channels : channel list;
  parameters : parameter list;
  records : record_spec list;
  containers : container_spec list;
  internal_ports : internal_port list;
  machines : (string * string) list;  (* instance name, machine name *)
  matched : (string * string) list;   (* port matching: (port, port) *)
}

(* -------------------------------------------------- instances and topology *)

type instance = {
  inst_name : string;
  of_component : string;
  base_id : int;
  queue_size : int option;
  stack_size : int option;
  inst_priority : int option;
  cpu : int option;
}

type endpoint = { ep_instance : string; ep_port : string; ep_index : int option }

type connection = { from_ : endpoint; to_ : endpoint }

type pattern_kind =
  | P_command | P_event | P_telemetry | P_text_event | P_time | P_health | P_param

type graph =
  | Direct of { graph_name : string; connections : connection list }
  | Pattern of { pattern : pattern_kind; source : string; targets : string list }

type topology = {
  topo_name : string;
  members : string list;
  graphs : graph list;
}

type model = {
  model_name : string;
  type_defs : type_def list;
  port_defs : port_def list;
  constants : (string * int) list;
  components : component list;
  machines : state_machine list;
  instances : instance list;
  topologies : topology list;
}

(* ---------------------------------------------------------------- analysis *)

(* The width of a component's relative-identifier window: 1 + the largest
   relative id used by any command opcode, event/channel/parameter/record/
   container id, or parameter set/save opcode; at least 1. Instance base-id
   ranges [base, base + span) must be pairwise disjoint (FPP-INST-02). *)
val id_span : component -> int

(* Every semantic check the FPP spec mandates, as fractal diagnostics.
   [] means well-formed. Check ids: FPP-NAME-01, FPP-TYPE-01/02,
   FPP-CMP-01..10, FPP-SM-01..03, FPP-INST-01..03, FPP-TOPO-01..06. *)
val validate : model -> Fractal_diagnostic.t list

(* Direct connections plus pattern expansion. Pattern semantics (documented
   subset): each pattern connects the consuming port on each target to the
   canonical serving port on the source; targets lacking the consuming port
   are skipped, exactly as F Prime patterns skip non-participating
   instances. Errors only on structural impossibility (unknown topology
   member), not on skipped targets. *)
val connections : model -> topology -> (connection list, string) result

(* ---------------------------------------------------------------- emitters *)

(* FPP-syntax rendering of the whole model (deterministic). *)
val to_fpp : model -> string

(* The F Prime JSON dictionary for one topology, per the JSON dictionary
   specification: metadata, typeDefinitions, constants, commands, events,
   telemetryChannels, parameters, records, containers, telemetryPacketSets.
   Entry names are instance-qualified; opcodes/ids are base-id offset.
   Fail-closed: an invalid model or unknown topology refuses. *)
val to_dictionary :
  ?framework_version:string ->
  ?project_version:string ->
  model ->
  topology:string ->
  (Yojson.Safe.t, string) result
