(* The BDD use-case catalog for the FPP layer.

   Two families:
   - [generic]: the common F Prime use cases every project meets (define a
     sensor, wire an async port, the three queue-full policies, a state
     machine lifecycle, base-id windowing, invalid wiring rejected) on
     small purpose-built models.
   - [workflows]: EVERY harness workflow mapped into FPP terms and executed
     against the real `Harness_topology.model` — pipeline dispatch, the
     OODA converge walk, R13 refusal, anomaly stop-the-line, divergence-as-
     measurement, the read-only laws (no CAPTURE/REPORT opcodes), health/
     time/telemetry patterns, the two-lattice boundary, frontier sensor,
     reconcile, parameters.

   Scenarios are data; `test_fpp_bdd` is the runner (Given/When/Then). *)

type step =
  | When_signal of string * (string * bool) list
      (* dispatch a signal to the scenario's machine under a guard valuation *)
  | Then_state of string                (* machine sits in this state *)
  | Then_log_includes of string         (* an action that must have run *)
  | When_command of string * int        (* instance, RELATIVE opcode *)
  | Then_dispatch of
      [ `Executed | `Enqueued | `Assert_failed | `Blocked | `Dropped | `Rejected ]
      (* verdict on the most recent When_command *)
  | Then_event_severity of string * string * string
      (* instance, event name, dictionary severity (e.g. "FATAL") *)
  | Then_channel of string * string * string
      (* instance, channel name, telemetryUpdate ("always" / "on change") *)
  | Then_no_command_named of string
      (* no dictionary command name contains this substring: read-only law *)
  | Then_connection of string * string
      (* some expanded connection runs from-instance -> to-instance *)
  | Then_no_connection of string list * string list
      (* no DIRECT connection from any of the first set into the second *)
  | Then_law of string * (unit -> bool) (* named property *)

type scenario = {
  name : string;
  given : string;                       (* the Given line, prose *)
  model : Fpp_model.model;
  topology_name : string;
  machine : Fpp_model.state_machine option;
  queue_capacity : int;                 (* the async queue the runner carries *)
  steps : step list;
}

val generic : scenario list
val workflows : scenario list

(* Code-generation scenarios: every generator the system carries (FPP
   source, the ground dictionary, the Rocq extraction/transcription pair,
   the quint machine spec, the committed atlas pages), each exercised or
   anchored, all fail-closed. *)
val codegen : scenario list

val all : scenario list
