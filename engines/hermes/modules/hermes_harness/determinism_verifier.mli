(** Determinacy gate (R14 / the zigvm GATE-DETERMINACY concern): replay a producer
    twice and byte-compare the normalized renders. Any variance is a
    Control-origin defect — a non-reproducible apparatus proves nothing about
    parity, and a flaky pass can grant credit for a candidate that is not
    consistently equivalent (HZ-DET-01). Fixed constructively, never hidden by
    re-running.

    Reuses {!Reference_capture.sha256} and {!Parity_normalizer} rather than
    reinventing them. *)

type verdict = Stable of string | Unstable of { first : string; second : string }

val check : normalizer:Parity_normalizer.t -> (unit -> Yojson.Safe.t) -> verdict
(** Run the producer twice; [Stable digest] iff the two normalized renders are
    byte-identical, else [Unstable] with both digests. *)

val to_diagnostic :
  scenario_id:string -> node:string -> verdict -> Fractal_diagnostic.t option
(** [None] for [Stable]; an HZ-DET-01 Control / Blocks_credit diagnostic for
    [Unstable]. *)
