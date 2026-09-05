(* The formal-coverage registry: the executable claim that EVERY fractal
   component, layer, use case, and system interaction has named formal
   backing — and that all four aspect dimensions (structural, static,
   behavioral, dynamic) are checked for each component.

   Modeled on two proven shapes (R14): fractal_ontology's total-function-
   with-fail-closed-coverage (silence is not permitted; "not applicable"
   must carry a reason) and the c3i doctrine grid (evidence cells graded,
   system grade = the weakest cell). The coverage FLOOR is declared as
   intent and reconciled against the computed actual — the RFC 9315
   pattern applied to formal evidence itself: declare, validate, observe,
   report drift. Citations are anchored: every entry names real files, and
   the test suite stats them.

   This registry GRANTS nothing. It observes which proofs and suites exist
   and where the gaps are; parity credit still flows only through L4-L6
   differential evidence (R10). *)

(* The four aspect dimensions of the directive. *)
type aspect = Structural | Static | Behavioral | Dynamic

val aspect_name : aspect -> string
val all_aspects : aspect list

(* Evidence strength, strongest first. Rank: Machine_checked 5,
   Solver_proved 4, Differentially_tested 3, Property_tested 2,
   Contracted 1, Declared 0 (an honest gap: the reason and what would
   close it). *)
type strength =
  | Machine_checked of string
  | Solver_proved of string
  | Differentially_tested of string
  | Property_tested of string
  | Contracted of string
  | Declared of string

val rank : strength -> int
val cite : strength -> string

type aspect_claim = Checked of string | Not_applicable of string

type entry = {
  component : string;                        (* Fractal_ontology id *)
  artifacts : strength list;                 (* >= 1, citations real *)
  files : string list;                       (* anchor paths; all must exist *)
  aspect_coverage : (aspect * aspect_claim) list;  (* all four, always *)
  interactions : string list;                (* topology labels governed *)
  scenarios : string list;                   (* BDD scenario names backed *)
}

val entries : entry list
val entry_for : string -> entry option

(* Best evidence rank of an entry; the system grade is the minimum over
   entries — the weakest link, exactly the c3i worst-of cell rule. *)
val grade : entry -> int
val system_grade : unit -> int

(* ------------------------------------------------------------- census *)

(* How many instances of each atlas element the system uses. Names are
   dotted paths ("topology.instances", "ontology.edges.governs",
   "machine.transitions", "dictionary.commands", ...). Deterministic. *)
val census : unit -> (string * int) list

(* Per-element usage: how often each port definition is instantiated, and
   how often each named type is referenced. An unused definition is dead
   weight the tests flag. *)
val port_def_usage : unit -> (string * int) list
val type_def_usage : unit -> (string * int) list

(* ---------------------------------------- differential completeness laws *)

(* Generic set-difference used by every law below; exposed so tests can
   prove each law CAN fail (meta-falsification). *)
val gaps_against : label:string -> known:string list -> claimed:string list -> string list

val component_gaps : unit -> string list   (* vs Fractal_ontology, both directions *)
val aspect_gaps : unit -> string list      (* entries missing one of the four *)
val scenario_gaps : unit -> string list    (* vs Fpp_usecases.all *)
val interaction_gaps : unit -> string list (* vs harness_topology direct + patterns *)
val missing_files : unit -> string list    (* cited anchors that do not exist *)

(* Per fractal level: (level name, components at it, entries at rank >=
   Property_tested). Every populated level must be fully covered. *)
val level_coverage : unit -> (string * int * int) list

(* --------------------------------------------------- declarative intent *)

type requirement = {
  subject : string;   (* "system-floor" or a component id *)
  minimum : int;      (* required rank *)
  reason : string;
}

val intent : requirement list

(* [] = the declared intent is satisfied by the computed actuals; each
   drift line names subject, wanted, actual. Unknown subjects are drift
   too (fail-closed validation). *)
val reconcile : unit -> string list

(* ------------------------------------------------------- zenoh seams *)

(* The mesh topics the harness publishes TODAY (compare / auto_converge /
   run_config, sweep + worst each). *)
val zenoh_live_topics : string list

(* Where zenoh can be used next, each with its rationale and its guard —
   bounded by the boundary-as-law: intra-process composition stays pure;
   the mesh carries observation/advice, never authority. The census counts
   the eligible populations from the live model. *)
val zenoh_seams : (string * string) list

(* ------------------------------------------------------------- rendering *)

val grid : unit -> string list
