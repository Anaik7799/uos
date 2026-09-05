(* A pure interpreter for the executable parts of the FPP metamodel: state
   machine dispatch (the spec's semantics: run the behavior for the signal
   in the current state; exit -> transition do -> entry action order;
   unhandled signals are dropped; choices resolve through guarded arcs) and
   command dispatch with the async queue-full behaviors (assert/block/
   drop).

   This is a SIMULATOR for testing models — BDD scenarios drive the real
   ConvergeLoop machine and the real dictionary through it. It actuates
   nothing (R10: descriptions and simulations never touch parity). *)

type machine_state = {
  current : string;       (* the current state's name *)
  log : string list;      (* every action executed, in order *)
}

(* Enter the initial state, running the initial transition's actions.
   External machines have no behavior here and are refused. *)
val init : Fpp_model.state_machine -> (machine_state, string) result

(* Dispatch one signal. [guards] is the valuation (absent = false).
   Unhandled signal in the current state: dropped, state unchanged (spec
   semantics). Unknown signal name or tampered state: Error — a caller
   defect, never a silent drop. Defensive: a choice cycle (impossible in a
   validated machine) errors rather than looping. *)
val dispatch :
  machine:Fpp_model.state_machine ->
  guards:(string * bool) list ->
  machine_state ->
  string ->
  (machine_state, string) result

(* ------------------------------------------------------- command queues *)

type queue = { capacity : int; depth : int; dropped : int }

val empty_queue : capacity:int -> queue

type dispatch_result =
  | Executed          (* sync/guarded (and param set/save) ran immediately *)
  | Enqueued of queue (* async accepted; new queue state *)
  | Dropped of queue  (* async on a full queue with drop *)
  | Blocked           (* async on a full queue with block *)
  | Assert_failed     (* async on a full queue with assert: a defect *)

(* Send an ABSOLUTE opcode (base id + relative) to an instance, resolving
   through the instance's component dictionary exactly as CmdDispatcher
   would. Async commands need [queue]; passing None is a caller error. *)
val send_command :
  Fpp_model.model ->
  instance:string ->
  opcode:int ->
  queue:queue option ->
  (dispatch_result, string) result
