(* STPA and FMEA for the vision system.

   -------------------------------------------------------------------
   DERIVED, NOT AUTHORED

   An FMEA maintained as a table beside the code is wrong within a week
   and nobody notices, because nothing checks it. Every element of every
   ontology in this module already declares a HAZARD — the way it reports
   success while delivering nothing — and a hazard is a failure mode with
   its effect already written. So the FMEA rows are PROJECTED from the
   ontologies rather than typed out, and a stage or element added without
   a hazard shows up here as a missing row rather than as silence.

   -------------------------------------------------------------------
   STPA IS ABOUT CONTROL, WHICH IS WHY IT IS SEPARATE

   FMEA asks how a component fails. STPA asks how a CONTROL ACTION,
   correctly executed by working components, produces an unsafe state.
   Those find different defects, and the second is the one that matters
   for a control plane that can restart a live service: nothing in this
   system has to break for a restart issued at the wrong moment to take
   the stream down.

   The four STPA guide phrases are used as given, because narrowing them
   is how an analysis stops finding what it was designed to find. *)

(* ------------------------------------------------------------- FMEA *)

type severity = Negligible | Degraded | Stream_lost | Evidence_false

(* [Evidence_false] outranks [Stream_lost] deliberately. A dropped stream
   is visible and someone fixes it; a run that reports success it did not
   measure corrupts every decision taken downstream, and nobody looks. *)
val severity_rank : severity -> int
val severity_name : severity -> string

type detection =
  | Probed of string      (* a probe exists and is named *)
  | Undetected            (* nothing in the system would notice *)

val detection_name : detection -> string

type mode = {
  component : string;
  failure : string;        (* the hazard, verbatim from the ontology *)
  impact : severity;
  detected_by : detection;
  origin : Fractal_diagnostic.origin;
}

(* Every hazard in every ontology, as FMEA rows. Derived. *)
val modes : unit -> mode list

(* Rows nothing would detect. This is the FMEA's only real product: a
   list of failures that would happen silently. An empty list is the
   goal and a long one is the work. *)
val undetected : unit -> mode list

(* Risk priority: severity weighted by whether anything would catch it.
   Undetected failures rank above detected ones of equal severity,
   because detection is the cheapest mitigation there is. *)
val priority : mode -> int
val ranked : unit -> mode list

(* -------------------------------------------------------------- STPA *)

(* The four guide phrases, unnarrowed. *)
type uca_kind =
  | Not_provided        (* the action was needed and did not happen *)
  | Provided_unsafe     (* the action happened when it was unsafe *)
  | Wrong_timing        (* right action, too early or too late *)
  | Stopped_too_soon    (* applied too briefly, or held too long *)

val uca_kinds : uca_kind list
val uca_kind_name : uca_kind -> string

type uca = {
  action : string;       (* the control action *)
  kind : uca_kind;
  context : string;      (* the state in which it becomes unsafe *)
  consequence : string;
  constraint_ : string;  (* the safety constraint that must hold *)
  enforced_by : string;  (* what enforces it TODAY, or "" if nothing does *)
}

(* Every control action this system offers, analysed against all four
   guide phrases. *)
val ucas : uca list

(* Constraints nothing currently enforces. Like [undetected], this is the
   product: a named list of ways the control plane can be driven into an
   unsafe state, with nothing standing in the way. *)
val unenforced : unit -> uca list

(* Every control action must be analysed against ALL FOUR guide phrases.
   Returns the actions that are not, so an analysis cannot silently skip
   the phrase that would have found the defect. *)
val incomplete_analysis : unit -> (string * uca_kind) list

val render : unit -> string
