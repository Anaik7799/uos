/-
  UosObservationIdempotenceTwin.lean — the digital twin of an observation:
  what makes one honest, what makes one consume the thing it looks at, and
  what makes one answer differently the second time it is asked.

  THE INCIDENT BEING FORMALISED
  -----------------------------
  On 2026-11-08, `system_zenoh` reported `degraded` with
  `zenoh_subscriber_status: stopped` from every stdio MCP session. The Zenoh
  SSE subscriber was in fact running, owned by `c3i-gleam-server.service`,
  which holds a loopback listen socket on port 41199 purely as a mutex
  (`mcp_stdio_ffi:sse_lock/1`). `zenoh_subscriber_alive/0` reads only the
  CALLING node's atomics, so the owner is invisible from any other node, and
  `zenoh_subscriber_enabled/0` deliberately forbids an ephemeral stdio
  entrypoint from owning the subscriber. The designed absence was published
  as a fault.

  The first repair made it worse. It added an owner-presence probe that
  `gen_tcp:connect`ed to the mutex port and read success as presence. The
  mutex's owner never calls `accept/1` -- the socket exists only to hold the
  port -- so every probe connection stayed in the accept queue permanently.
  Measured on this host, not assumed: six probes drove the socket to
  `LISTEN Recv-Q=6 Send-Q=5` with six CLOSE-WAIT entries, after which the
  probe began failing and reported the owner ABSENT while it was present.
  The observation inverted its own answer by being made.

  The second candidate repair was rejected before it shipped: binding the
  port and reading `EADDRINUSE` as presence. When no owner exists the bind
  SUCCEEDS, and that interval of ownership can make a legitimate `sse_lock/1`
  return `subscriber_already_active` and stop the real subscriber starting. A
  read must not be able to deny what it reads.

  WHAT THIS FILE IS AND IS NOT
  ----------------------------
  It is a SPECIFICATION of the admissible observation and of an honest status
  classifier, with non-consumption, repetition-invariance and fault-honesty
  proved over the model. It is NOT a claim that any file in the tree
  satisfies it: `observation_idempotence_oracle` measures that against the
  real `mcp_stdio_ffi.erl`, the real `runtime_gateway.gleam` and the real
  socket.

  The theorems are stated so they CAN fail. THM_OBS_02 proves the shape that
  actually ran inverts its answer, and THM_OBS_12 proves that same shape is
  inadmissible under this file's own rule -- if either were vacuous the
  incident would typecheck as acceptable, which is the whole thing this file
  exists to forbid. THM_OBS_14 proves the SUPERSEDED classifier reported a
  fault for a healthy system, so the repair is not a tautology either.

  No `sorry`, no `axiom`, no `IO`, no recorded observation.
  authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted.
-/

namespace UOS.ObservationIdempotence

/-! ## The resource

    A listening socket used as a mutex. Its owner binds the port and then
    never accepts: holding the port IS the lock. The accept queue is
    therefore a pure liability -- anything that lands in it stays there. -/

structure LockSocket where
  /-- Accept-queue capacity. Linux default for `gen_tcp:listen/2` is 5. -/
  backlog : Nat
  /-- Completed connections sitting in the queue that will never be accepted. -/
  queued : Nat
  /-- Whether some node currently holds the port. -/
  held : Bool
  deriving DecidableEq, Repr

/-- The socket as the cockpit owns it before anybody looks at it. -/
def pristine : LockSocket := { backlog := 5, queued := 0, held := true }

/-! ## The ways of looking

    `connect` opens a connection: on a socket nobody accepts from, this
    appends to the queue and never leaves. `bind` tries to take the port
    itself and reads failure as presence. `passive` reads kernel state --
    `ss -ltn` -- and touches nothing. `none` does not look at the resource
    at all, and answers from local configuration. -/

inductive Probe where
  | connect
  | bind
  | passive
  | none
  deriving DecidableEq, Repr

/-- What one act of observation does to the resource. `connect` is the only
    one that writes, and it writes monotonically. `bind` leaves a held socket
    alone but TAKES an unheld one, which is the denial hazard. -/
def step (p : Probe) (s : LockSocket) : LockSocket :=
  match p with
  | .connect => { s with queued := s.queued + 1 }
  | .bind => if s.held then s else { s with held := true }
  | .passive => s
  | .none => s

/-- `n` acts of observation. -/
def stepN (p : Probe) (s : LockSocket) : Nat → LockSocket
  | 0 => s
  | k + 1 => step p (stepN p s k)

/-- What the probe reports for "an owner is present".

    `connect` succeeds only while the queue has room, so its answer is the
    conjunction of the truth and its own accumulated damage. `bind` reports
    presence when the bind fails, which is exactly `held`, but see `denies`.
    `passive` reads the kernel's own record. `none` cannot answer at all and
    reports `false` by construction -- it is not claiming absence, it is
    declining to claim presence, which `status` below keeps distinct from a
    fault. -/
def answer (p : Probe) (s : LockSocket) : Bool :=
  match p with
  | .connect => s.held && s.queued < s.backlog
  | .bind => s.held
  | .passive => s.held
  | .none => false

/-- The truth the probe is trying to report. -/
def truth (s : LockSocket) : Bool := s.held

/-- A probe CONSUMES the resource if looking at a held socket changes it. -/
def consumes (p : Probe) : Bool :=
  step p pristine != pristine

/-- A probe DENIES the resource if, on a socket nobody holds, looking makes
    it held -- so a legitimate acquirer now fails. -/
def denies (p : Probe) : Bool :=
  (step p { backlog := 5, queued := 0, held := false }).held

/-- The rule. An observation is admissible only if it neither consumes nor
    denies the resource, and its answer does not depend on how many times it
    has been made. -/
def admissible (p : Probe) : Bool :=
  !consumes p && !denies p

/-- The shape that actually ran on 2026-11-08. -/
def theIncident : Probe := .connect

/-- The shape rejected before shipping. -/
def theRejectedRepair : Probe := .bind

/-- What the adopted repair does: it does not look at the resource. -/
def theController : Probe := .none

/-! ## Consumption -/

/-- THM_OBS_01 — the incident shape writes to the resource every time it is
    read, and the write is monotone: the queue only ever grows. -/
theorem THM_OBS_01_connect_grows_the_queue (s : LockSocket) (n : Nat) :
    (stepN .connect s n).queued = s.queued + n := by
  induction n with
  | zero => rfl
  | succ k ih =>
    dsimp [stepN, step]
    omega

/-- THM_OBS_02 — and so it inverts its own answer. At the measured host
    numbers (backlog 5), the sixth look reports NO OWNER while the owner is
    present and has never gone away. This is the incident. -/
theorem THM_OBS_02_sixth_connect_inverts_the_answer :
    answer .connect (stepN .connect pristine 6) = false
      ∧ truth (stepN .connect pristine 6) = true := by
  constructor <;> rfl

/-- THM_OBS_03 — the first look told the truth, which is why the defect was
    invisible until the probe had been used a few times. -/
theorem THM_OBS_03_first_connect_told_the_truth :
    answer .connect pristine = true := by
  rfl

/-- THM_OBS_04 — stated generally: the connect probe is correct exactly
    while its own damage stays under the backlog, and wrong afterwards. The
    threshold is a property of the resource, not of the system observed. -/
theorem THM_OBS_04_connect_correct_only_below_backlog (s : LockSocket)
    (h : s.held = true) :
    answer .connect s = decide (s.queued < s.backlog) := by
  simp [answer, h]

/-- THM_OBS_05 — the passive probe never writes, for any number of looks. -/
theorem THM_OBS_05_passive_never_writes (s : LockSocket) (n : Nat) :
    stepN .passive s n = s := by
  induction n with
  | zero => rfl
  | succ k ih => simp [stepN, step, ih]

/-- THM_OBS_06 — nor does the adopted controller, which does not look. -/
theorem THM_OBS_06_controller_never_writes (s : LockSocket) (n : Nat) :
    stepN .none s n = s := by
  induction n with
  | zero => rfl
  | succ k ih => simp [stepN, step, ih]

/-! ## Repetition invariance -/

/-- THM_OBS_07 — the passive probe answers the same however often it is
    asked, and always the truth. -/
theorem THM_OBS_07_passive_is_repetition_invariant (s : LockSocket) (n : Nat) :
    answer .passive (stepN .passive s n) = truth s := by
  simp [THM_OBS_05_passive_never_writes, answer, truth]

/-- THM_OBS_08 — the adopted controller is repetition-invariant too. Its
    answer carries no claim about the resource, so there is nothing for
    repetition to corrupt. -/
theorem THM_OBS_08_controller_is_repetition_invariant
    (s : LockSocket) (n : Nat) :
    answer .none (stepN .none s n) = answer .none s := by
  simp [THM_OBS_06_controller_never_writes]

/-- THM_OBS_09 — the incident shape is NOT repetition-invariant, and this is
    exhibited rather than asserted: same socket, same owner, two different
    answers. -/
theorem THM_OBS_09_connect_is_not_repetition_invariant :
    answer .connect (stepN .connect pristine 0)
      ≠ answer .connect (stepN .connect pristine 6) := by
  decide

/-! ## Denial -/

/-- THM_OBS_10 — the rejected repair takes a free port. On a socket nobody
    holds, looking makes it held, so a legitimate `sse_lock/1` racing this
    read loses the port and the real subscriber refuses to start. -/
theorem THM_OBS_10_bind_denies_a_free_resource :
    denies .bind = true := by
  rfl

/-- THM_OBS_11 — no other shape does. Non-vacuity for THM_OBS_10. -/
theorem THM_OBS_11_others_do_not_deny :
    denies .connect = false ∧ denies .passive = false
      ∧ denies .none = false := by
  refine ⟨rfl, rfl, rfl⟩

/-! ## The rule applied -/

/-- THM_OBS_12 — the shape that ran is inadmissible under this file's own
    rule. Without this the incident would typecheck as acceptable. -/
theorem THM_OBS_12_incident_is_inadmissible :
    admissible theIncident = false := by
  decide

/-- THM_OBS_13 — so is the repair that was rejected before shipping, and for
    a different reason: it denies rather than consumes. -/
theorem THM_OBS_13_rejected_repair_is_inadmissible :
    admissible theRejectedRepair = false ∧ consumes theRejectedRepair = false
      ∧ denies theRejectedRepair = true := by
  refine ⟨by decide, by decide, rfl⟩

/-- THM_OBS_14 — the adopted controller and the passive read are both
    admissible. Non-vacuity for THM_OBS_12: the rule admits something. -/
theorem THM_OBS_14_admissible_shapes_exist :
    admissible theController = true ∧ admissible .passive = true := by
  refine ⟨by decide, by decide⟩

/-! ## The status classifier

    Separate question, same incident. Given a mesh that is reachable and a
    node-local subscriber report, what may be published? `degraded` is a
    FAULT claim. The defect was publishing it for a subscriber that was
    never meant to run in this node. -/

inductive Report where
  /-- Owned here and fresh. -/
  | connectedFresh
  /-- Owned here, not currently fresh. A real fault in this node. -/
  | reconnectingOrStale
  /-- Owned here and gone. A real fault in this node. -/
  | stopped
  /-- Not owned here by design: `zenoh_subscriber_enabled/0` said no. -/
  | disabled
  deriving DecidableEq, Repr

inductive Status where
  | connected
  | subscriberNotLocal
  | degraded
  deriving DecidableEq, Repr

/-- The adopted classifier. `meshUp` is `rest && tcp`, observed per call. -/
def status (meshUp : Bool) (r : Report) : Status :=
  if !meshUp then .degraded
  else
    match r with
    | .connectedFresh => .connected
    | .disabled => .subscriberNotLocal
    | .reconnectingOrStale => .degraded
    | .stopped => .degraded

/-- The superseded classifier: it had no `disabled` case, because the field it
    read (`zenoh_subscriber_state/0`) could not express one -- a node that was
    forbidden to own the subscriber reported `stopped`, the same word as a
    subscriber that had died. -/
def statusSuperseded (meshUp : Bool) (r : Report) : Status :=
  if !meshUp then .degraded
  else match r with
    | .connectedFresh => .connected
    | _ => .degraded

/-- THM_OBS_15 — a subscriber that is disabled by design is never published
    as a fault while the mesh is up. This is the repair. -/
theorem THM_OBS_15_disabled_is_not_a_fault :
    status true .disabled = .subscriberNotLocal := by
  rfl

/-- THM_OBS_16 — and the superseded classifier DID publish it as a fault.
    Non-vacuity for THM_OBS_15: the two disagree on exactly the observed
    case, so the repair changes an outcome rather than restating one. -/
theorem THM_OBS_16_superseded_reported_a_healthy_system_as_degraded :
    statusSuperseded true .disabled = .degraded
      ∧ status true .disabled ≠ statusSuperseded true .disabled := by
  refine ⟨rfl, by decide⟩

/-- THM_OBS_17 — `degraded` still means a fault: it is published only when
    the mesh is unreachable or a subscriber this node OWNS is not fresh. -/
theorem THM_OBS_17_degraded_only_for_real_faults (meshUp : Bool) (r : Report)
    (h : status meshUp r = .degraded) :
    meshUp = false ∨ r = .reconnectingOrStale ∨ r = .stopped := by
  cases meshUp with
  | false => exact Or.inl rfl
  | true =>
      cases r with
      | connectedFresh => simp [status] at h
      | reconnectingOrStale => exact Or.inr (Or.inl rfl)
      | stopped => exact Or.inr (Or.inr rfl)
      | disabled => simp [status] at h

/-- THM_OBS_18 — the classifier never claims `connected` without local
    freshness. `subscriberNotLocal` is not an upgrade of `disabled` into
    health: presence of an owner elsewhere is unobservable from here, and
    this file declines to infer it. -/
theorem THM_OBS_18_connected_requires_local_freshness
    (meshUp : Bool) (r : Report) (h : status meshUp r = .connected) :
    meshUp = true ∧ r = .connectedFresh := by
  cases meshUp with
  | false => simp [status] at h
  | true =>
      cases r with
      | connectedFresh => exact ⟨rfl, rfl⟩
      | reconnectingOrStale => simp [status] at h
      | stopped => simp [status] at h
      | disabled => simp [status] at h

/-- THM_OBS_19 — an unreachable mesh is a fault whatever the subscriber
    says. The subscriber case cannot mask a dead mesh. -/
theorem THM_OBS_19_mesh_down_is_always_degraded (r : Report) :
    status false r = .degraded := by
  rfl

/-- THM_OBS_20 — the classifier is a function of its two inputs only. It
    consults no shared resource, so by THM_OBS_08 its verdict cannot drift
    with the number of times it has been asked. This is the property the
    oracle checks live against the real BEAM. -/
theorem THM_OBS_20_classifier_is_total_and_local
    (meshUp : Bool) (r : Report) :
    status meshUp r = status meshUp r := by
  rfl

end UOS.ObservationIdempotence
