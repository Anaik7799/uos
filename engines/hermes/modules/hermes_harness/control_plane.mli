(** The full-fractal controller sweep: one control leg per fractal level, each
    fed by a REAL signal, composed per entry point. The dashboard composes the
    store-only subset; the run commands compose the full set. A level whose
    sensor is not available to a surface is listed as UNSENSED with its reason
    -- never silently omitted (the no-silent-caps rule).

    Alerts are {!Homeostasis.alert}s: they observe, refuse, and advise. No leg
    reads or writes a parity verdict; the two lattices stay orthogonal, and the
    only sanctioned couplings are read-only observation of receipt history and
    process exit codes (R10). *)

type leg = { level : string; alert : Homeostasis.alert }

type sweep = {
  legs : leg list;
  unsensed : (string * string) list;  (** (level, reason) — no silent caps *)
}

(** {1 Leg constructors — pure, one per fractal level} *)

val l0_frontier : counts:int list -> total:int -> leg
(** L0 product: {!Homeostasis.frontier_alert} over the recorded satisfied-count
    trajectory (cross-run descent gate). *)

val l1_regressions : history:(string * string * bool) list -> leg
(** L1 family: scenarios that regressed (passed earlier, latest fails),
    grouped by family (first dotted component of the contract id). Any
    regression is [P0] naming family and scenarios. [history] rows are
    (contract_id, scenario_id, passed), chronological. *)

val l2_flaps : history:(string * string * bool) list -> leg
(** L2 capability: flapping scenarios (>= 2 transitions in their chronological
    window) are [P1] quarantine candidates, named; single-transition windows
    ending in a pass are a [P2] note (recoveries); else [Green]. *)

val l3_contract_oracle : available:bool -> leg
(** L3 contract: the gospel oracle's presence. Absent is [P1] with the
    provisioning runbook — obligations unverifiable, never silently skipped. *)

val l4_receipt_currency : receipts_revision:string option -> current:string -> leg
(** L4 fixture/receipt currency: latest receipt's harness revision vs HEAD.
    [None] (no receipts yet) is [Green] here — coverage is L6's finding.
    A mismatch is [P2]: staleness lead-time — re-verify before trusting. *)

val l6_observation_coverage : recorded:int -> corpus:int -> leg
(** L6 receipt: distinct scenarios with receipts vs the corpus the surface
    iterates. Fewer is [P2] (named gap drives capture); MORE is [P1] — the
    corpus registry this surface used is stale (the drifting-surfaces
    sensor). Equal is [Green]. *)

val lx_envelope : satisfied:bool -> leg
(** LX control: the R13 resource envelope's outcome for this run. *)

(** {1 Composition} *)

val worst : sweep -> Homeostasis.alert
(** Keep-worst over the sweep's legs ([Green] when no legs). *)

val render : sweep -> string list
(** One aligned line per leg, then one per unsensed level. *)
