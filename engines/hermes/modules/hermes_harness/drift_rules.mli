(** Drift diagnosis: production rules over the reconciliation output.

    Projects {!Blueprint.reconciled} results (plus the hazard analysis and the
    countermeasure table) into {!Hermes_rete} working memory and fires the drift
    rule set -- the zigvm rete_rules projection discipline (R14) applied to
    intent drift. Two kinds of rule:

    - the GATE (fail-closed): a reconciled entry whose actual equals its desired
      verdict but is marked as drift is a corrupted reconciliation -- the run is
      rejected, zero-trust style;
    - DIAGNOSIS: each drift inserts an [advice] fact -- fix the candidate for a
      proved divergence, capture-and-compare for an unmapped intent, apply (or
      manually perform) the hazard's countermeasure for a blocked one.

    The embedded Rust engine ({!Rust_rules}) is cross-checked against the same
    conclusions differentially in its test; THIS module is the authoritative
    fail-closed path (the Rust GRL parser is lenient -- a measured finding). *)

type advice = {
  target : string;
  action : string;   (** fix-candidate | capture-and-compare | apply-countermeasure | manual-countermeasure *)
  detail : string;
}

val diagnose : Blueprint.reconciled list -> (advice list, string) result
(** Project, fire, collect. [Error] is the gate rejecting a corrupted
    reconciliation; advice comes back sorted by target then action. *)
