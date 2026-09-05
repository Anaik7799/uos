(* The wiki/ZK feature register as tracked DATA — the executable form of
   docs/hermes/features-audit-implementation-plan.md.

   The plan document argues; this module decides. Where a live predicate
   can tell whether a feature is actually present, it does, and [status]
   prefers the predicate over the declaration. [stale_declarations]
   reports every disagreement, so the register cannot drift from the
   system it describes — the same discipline as Gap_plan, applied to the
   276-feature register.

   Sources: the features_audit.md rows (Notion, Obsidian), Docusaurus,
   Sphinx, and our own architecture. Laws are the short form of the
   plan's §8.0 catalogue; the long form stays in the document. *)

type area =
  | Corpus     (* HW.1  what a document is *)
  | Dialect    (* HW.2  what markdown means *)
  | Address    (* HW.3  how things are pointed at *)
  | Graph      (* HW.4  the corpus as a structure *)
  | Query      (* HW.5  notes as data *)
  | Surface    (* HW.6  how it is reached *)
  | Present    (* HW.7  how it looks *)
  | Lifecycle  (* HW.8  how it is governed *)
  | Source     (* HW.9  binding to code *)
  | Build      (* HW.10 how the corpus is processed *)

type source = Notion | Obsidian | Docusaurus | Sphinx | Own

type readiness =
  | Built                 (* present and test-backed *)
  | Ready                 (* no blocker; can start now *)
  | Blocked of string     (* waiting on the named feature id *)
  | Forked of int         (* needs the numbered policy decision *)
  | Excluded              (* N/A by design; the law is an exclusion invariant *)

type feature = {
  id : string;                    (* HW.<area>.<group>.<feature> *)
  area : area;
  name : string;
  sources : source list;
  audit_rows : int list;          (* rows in features_audit.md; some features cover two *)
  law : string;                   (* acceptance criterion, short form of §8.0 *)
  utility : int;                  (* 1..5 — value delivered on its own *)
  criticality : int;              (* 1..5 — cost of its absence; silent wrongness scores high *)
  gates : string list;            (* feature ids this one unblocks *)
  declared : readiness;
  derived : (unit -> bool) option;  (* live probe: is it ACTUALLY present? *)
}

val features : feature list

(* Derived where a probe exists, declared otherwise. A feature whose probe
   says present is [Built] regardless of what the table claims. *)
val status : feature -> readiness

(* Actionable now: [Ready] (or a [Blocked] whose blocker is satisfied),
   and not already present. *)
val actionable : feature -> bool

(* 3*criticality + 2*utility + |gates| — criticality weighted highest
   because a feature whose absence is silently wrong costs more than one
   that is merely missing. Excluded and Built features score 0. *)
val priority : feature -> int

(* Every actionable feature, highest priority first, ties by id. *)
val prioritized : unit -> feature list

(* The single next thing to build. *)
val next : unit -> feature option

type summary = { built : int; ready : int; blocked : int; forked : int; excluded : int }

val summary : unit -> summary
val by_area : unit -> (area * feature list) list
val area_name : area -> string
val readiness_name : readiness -> string

(* Ids named as a blocker or a gate that no feature declares — the
   register's referential integrity, checked rather than assumed. *)
val dangling_references : unit -> string list

(* Features whose live probe disagrees with the declared readiness. *)
val stale_declarations : unit -> string list
