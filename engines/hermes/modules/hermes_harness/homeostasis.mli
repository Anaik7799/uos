(** Homeostasis controls for the convergence loop — pure control algorithms
    imported from the c3i controller family (stop_hook_lyapunov's graduated
    P0/P1/P2/green alerting, hysteresis/flap detection, circuit breaking) and
    zigvm's cross-run monotone-frontier discipline (R14).

    Controllers OBSERVE, REFUSE, ADVISE, and stop the line. They never grant or
    deny parity credit (R10): every alert is advisory telemetry about the LOOP,
    and the only actuation they justify is refusing to proceed (exit teeth) or
    naming a quarantine/runbook candidate. Absence of telemetry is never a
    violation (the c3i rule): an empty window is Green, not an alarm. *)

type alert =
  | Green        (** in control *)
  | P2 of string (** note — worth a look, no action forced *)
  | P1 of string (** sustained/instability — runbook item *)
  | P0 of string (** regression/boundary — stop the line *)

val severity : alert -> int
(** Green 0 < P2 1 < P1 2 < P0 3. *)

val worst : alert list -> alert
(** Keep-worst join — the control plane composes like the evidence plane
    (same shape as the parity combine). [worst [] = Green]. *)

val describe : alert -> string
(** Render for the loop's report: "green" or "P0 -- <detail>". *)

val lyapunov : total:int -> satisfied:int -> int
(** The frontier's Lyapunov measure V = max 0 (total - satisfied): distance
    from the declared goal. Non-negative; 0 exactly at full convergence. *)

val frontier_alert : satisfied_counts:int list -> total:int -> alert
(** The cross-run descent gate over the recorded frontier trajectory
    (chronological satisfied-intent counts, oldest first).

    - ANY strict shrink between consecutive observations is [P0]: a previously
      satisfied intent regressed between runs — the cross-run twin of
      [Converge]'s in-run monotone guard, measured on real history.
      Shrink-detection (not raw V-rise) so legitimately GROWING the blueprint
      never false-alarms.
    - A window of >= 3 observations all equal while V > 0 is [P2] (stalled —
      the frontier is not advancing toward the declared goal).
    - Empty window is [Green] (absence of telemetry is not a violation).
    - Otherwise [Green]. *)

val transitions : bool list -> int
(** State changes in a chronological pass/fail window. Constant windows
    (including empty and singleton) have 0. *)

val flap_alert : scenario:string -> window:bool list -> alert
(** Hysteresis sensor over one scenario's receipt history:
    >= 2 transitions in the window is [P1] (flapping — quarantine candidate);
    exactly 1 is [P2] (a single state change: a fix or a regression — the
    PRIMARY divergence sensor is the differential compare, not this; this
    only measures stability). Constant windows are [Green]. *)

val regressed : window:bool list -> bool
(** True iff the chronological window ends failing after passing earlier.
    A never-passed window is a first measurement, not a regression; a window
    ending in a pass is a recovery. Empty is false. *)

val regression_alert : scenario:string -> window:bool list -> alert
(** [P0] naming the scenario when {!regressed}; [Green] otherwise. The
    cross-run twin of the compare's own divergence finding: the compare says
    WHAT differs, this says the difference is NEW. *)

type breaker
(** Circuit breaker for repeated oracle invocations (capture interpreter,
    gospel, z3, quint): consecutive failures open the circuit so the loop
    refuses fast with one diagnostic instead of hammering a dead oracle. *)

val breaker : threshold:int -> breaker
(** A closed breaker tripping after [threshold] consecutive failures
    (clamped to >= 1). *)

val observe : breaker -> ok:bool -> breaker
(** Feed one invocation outcome. A success while closed resets the count.
    An OPEN breaker never half-opens on its own: re-closing is a deliberate
    human act (an unattended retry of a possibly-destructive oracle is how
    L-09 class incidents happen). *)

val admits : breaker -> bool
(** Whether the next invocation may proceed. *)

val failures : breaker -> int
(** Consecutive failures observed (diagnostic surface). *)
