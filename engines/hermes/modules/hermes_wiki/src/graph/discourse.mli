(* HW.4.4.1 / HW.4.4.2 — grounded semantics over the typed-edge
   argumentation frame. Att = @opposes ONLY; @supports is defence by
   STRUCTURE, never an attack (passing it as one is unrepresentable: the
   frame is built from the opposes relation alone). The grounded
   extension is the least fixed point of the characteristic function,
   computed by Kleene ascent from the empty set — monotone, so
   Knaster-Tarski guarantees uniqueness; the ascent is bounded by the
   node count. Anomalies are REPORT-ONLY (R5: they can never deny
   credit); deterministic, sorted. *)

(* grounded ~attacks ~nodes: the grounded extension, sorted. *)
val grounded : attacks:(string * string) list -> nodes:string list -> string list

(* claims (ntype = claim) outside the grounded extension of the corpus's
   @opposes frame, sorted — the grounded_anomalies gauge. *)
val anomalies : Hermes_wiki.model -> string list
