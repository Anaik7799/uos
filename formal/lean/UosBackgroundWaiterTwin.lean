/-
  UosBackgroundWaiterTwin.lean — the digital twin of a background waiter:
  what makes one terminate, what makes one burn a core, and what makes one
  burn tokens.

  THE INCIDENT BEING FORMALISED
  -----------------------------
  On 2026-11-06, eight background shells of the shape

      while pgrep -f "dataplane.ml --subject" >/dev/null; do :; done; tail ...

  were started to wait for a mutation sweep. The sweep finished at 21:28.
  The waiters were still running at 04:28 the next morning, when they were
  stopped by hand. They could not have stopped on their own: `pgrep -f PAT`
  matches against the full command line of every process, and the waiter's
  OWN command line contains PAT -- it is the string it was given. So the
  guard the loop tests is a predicate that the loop itself satisfies. The
  observed set is never empty because the observer is in it.

  Measured, not assumed: the loop body forks one `pgrep` per iteration at
  56 iterations/second/waiter (tools-measured on this host, 2026-11-07),
  and `pgrep` walks all of /proc each time. Eight waiters times seven hours
  at that rate is 1.1e7 process creations, and the host's load average read
  9.64 (15-minute) against 24 cores at the moment they were killed.

  WHAT THIS FILE IS AND IS NOT
  ----------------------------
  It is a SPECIFICATION of the admissible waiter, with its termination,
  fork-rate and token-cost conditions proved over the model. It is NOT a
  claim that any script in the tree satisfies it: `background_waiter_oracle`
  measures that, and `tools/uos-wait` is the one implementation built to it.

  The theorems are stated so they CAN fail. THM_WAIT_01 proves the shape
  that actually ran does not terminate, and THM_WAIT_ADM_02 proves that same
  shape is inadmissible under this file's own rule -- if either were vacuous
  the incident would type-check as acceptable, which is the whole thing this
  file exists to forbid.

  No `sorry`, no `axiom`, no `IO`, no recorded observation.
  authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV minted.
-/

namespace UOS.BackgroundWaiter

/-- What the waiter asks the host about.

    `pid` is identity: the waiter holds a process id and asks whether THAT
    process is alive. `pattern` is a string test over every command line,
    and `selfMatches` records whether the waiter's own command line answers
    it -- which it does whenever the pattern is passed as an argument. -/
inductive Target where
  | pid (p : Nat)
  | pattern (selfMatches : Bool)
  deriving DecidableEq, Repr

structure Waiter where
  /-- what is being waited on -/
  target : Target
  /-- deadline in polls; `0` means no deadline -/
  budget : Nat
  /-- sleep between polls in ms; `0` means busy-wait -/
  intervalMs : Nat
  /-- output emitted per poll; `0` means emit only on exit -/
  emitPerPoll : Nat
  deriving Repr

/-- The guard the host answers at poll `k`, where the real work finishes at
    poll `finishes`. A self-matching pattern answers `true` forever, because
    the waiter is itself a process whose command line matches. -/
def guard (w : Waiter) (finishes k : Nat) : Bool :=
  match w.target with
  | .pid _ => decide (k < finishes)
  | .pattern selfMatches => selfMatches || decide (k < finishes)

/-- The poll at which the waiter stops, or `none` if it never does. -/
def stopsAt (w : Waiter) (finishes : Nat) : Option Nat :=
  if w.budget = 0 then
    match w.target with
    | .pid _ => some finishes
    | .pattern true => none
    | .pattern false => some finishes
  else
    some (min finishes w.budget)

/-- Polls actually performed, given a horizon `cap` on how long anyone
    waits. A non-terminating waiter performs `cap` polls: its cost is a
    function of the horizon, not of the work. -/
def pollsOf (w : Waiter) (finishes cap : Nat) : Nat :=
  match stopsAt w finishes with
  | some k => k
  | none => cap

/-- Lines of output, hence tokens carried back into a conversation. The
    trailing `+ 1` is the one line emitted on exit. -/
def tokens (w : Waiter) (finishes cap : Nat) : Nat :=
  w.emitPerPoll * pollsOf w finishes cap + 1

/-- Process creations per wall second. A busy-wait is bounded only by what
    the host can fork; an interval bounds it by arithmetic. -/
def forksPerSec (w : Waiter) (hostForkRate : Nat) : Nat :=
  if w.intervalMs = 0 then hostForkRate else 1000 / w.intervalMs

/-- The rule. A waiter is admissible only if it asks about identity rather
    than about a string that describes itself, carries a deadline, sleeps,
    and says nothing until it is done. -/
def admissible (w : Waiter) : Bool :=
  (match w.target with | .pid _ => true | .pattern s => !s)
    && !(w.budget == 0)
    && !(w.intervalMs == 0)
    && (w.emitPerPoll == 0)

/-- The shape that actually ran on 2026-11-06: a self-matching pattern, no
    deadline, no sleep. -/
def theIncident : Waiter :=
  { target := .pattern true, budget := 0, intervalMs := 0, emitPerPoll := 0 }

/-- What `tools/uos-wait` is built to be: a pid, a deadline, a one-second
    interval, silence until exit. -/
def theController (p finishes : Nat) : Waiter :=
  { target := .pid p, budget := finishes + 1, intervalMs := 1000,
    emitPerPoll := 0 }

/-! ## Termination -/

/-- THM_WAIT_01 — the incident shape never terminates, for ANY finishing
    time of the work it waits on. The work completing is irrelevant; the
    guard is satisfied by the waiter. -/
theorem THM_WAIT_01_self_matching_pattern_never_stops (f : Nat) :
    stopsAt theIncident f = none := by
  rfl

/-- THM_WAIT_02 — and the reason, stated at the guard: it is true at every
    poll, including polls after the work has finished. -/
theorem THM_WAIT_02_guard_true_after_work_finished (f k : Nat) :
    guard theIncident f k = true := by
  simp [guard, theIncident]

/-- THM_WAIT_03 — a deadline forces termination whatever the target is.
    This is the property that makes a waiter safe to start unattended. -/
theorem THM_WAIT_03_deadline_forces_termination (w : Waiter) (f : Nat)
    (h : w.budget ≠ 0) : (stopsAt w f).isSome = true := by
  simp [stopsAt, h]

/-- THM_WAIT_04 — a pid target terminates even with no deadline, because a
    process id cannot be the waiter's own. Identity is not self-matching. -/
theorem THM_WAIT_04_pid_target_terminates (p f : Nat) :
    stopsAt { target := .pid p, budget := 0, intervalMs := 0,
              emitPerPoll := 0 } f = some f := by
  rfl

/-- THM_WAIT_05 — and it stops when the work stops, not later. -/
theorem THM_WAIT_05_controller_stops_at_the_work (p f : Nat) :
    stopsAt (theController p f) f = some f := by
  simp [stopsAt, theController]

/-! ## Cost -/

/-- THM_WAIT_06 — a non-terminating waiter's poll count is the horizon, so
    its CPU cost grows without bound in the length of the session. -/
theorem THM_WAIT_06_nonterminating_cost_is_the_horizon (f cap : Nat) :
    pollsOf theIncident f cap = cap := by
  rfl

/-- THM_WAIT_07 — emitting nothing per poll makes token cost independent of
    duration: one line, whether the wait was a second or seven hours. This
    is the minimum-token-burn property. -/
theorem THM_WAIT_07_silent_waiter_costs_one_line
    (w : Waiter) (f cap : Nat) (h : w.emitPerPoll = 0) :
    tokens w f cap = 1 := by
  simp [tokens, h]

/-- THM_WAIT_08 — the converse, so THM_WAIT_07 is not vacuous: a waiter
    that speaks each poll and never stops costs strictly more the longer
    the session runs. -/
theorem THM_WAIT_08_chatty_nonterminating_waiter_grows (f cap : Nat) :
    tokens { target := .pattern true, budget := 0, intervalMs := 0,
             emitPerPoll := 1 } f (cap + 1)
    > tokens { target := .pattern true, budget := 0, intervalMs := 0,
               emitPerPoll := 1 } f cap := by
  simp [tokens, pollsOf, stopsAt]

/-- THM_WAIT_09 — an interval bounds the fork rate by arithmetic rather
    than by what the host happens to allow. At the measured host rate of 56
    forks/second, a one-second interval is a 56-fold reduction. -/
theorem THM_WAIT_09_interval_bounds_fork_rate :
    forksPerSec theIncident 56 = 56
    ∧ forksPerSec (theController 7 7) 56 = 1 := by
  constructor <;> rfl

/-! ## Shutdown -/

structure Shutdown where
  waiterStopped : Bool
  childrenLive : Nat
  deriving Repr

/-- Stopping the waiter is not the end of the obligation: the work it
    started must be gone too, or the core stays busy with the waiter's
    name off the list. -/
def cleanShutdown (s : Shutdown) : Bool :=
  s.waiterStopped && s.childrenLive == 0

/-- THM_WAIT_10 — a stopped waiter with a live child is NOT a clean
    shutdown. Falsifiable and routinely false in practice. -/
theorem THM_WAIT_10_orphan_is_not_clean (n : Nat) :
    cleanShutdown { waiterStopped := true, childrenLive := n + 1 } = false := by
  simp [cleanShutdown]

/-- THM_WAIT_11 — and the only clean state is both conditions together. -/
theorem THM_WAIT_11_clean_requires_both (s : Shutdown) :
    cleanShutdown s = true ↔ (s.waiterStopped = true ∧ s.childrenLive = 0) := by
  simp [cleanShutdown]

/-! ## The rule binds to the incident -/

/-- THM_WAIT_ADM_01 — the controller shape is admissible. -/
theorem THM_WAIT_ADM_01_controller_is_admissible (p f : Nat) :
    admissible (theController p f) = true := by
  simp [admissible, theController]

/-- THM_WAIT_ADM_02 — the shape that actually ran is NOT admissible. If
    this failed, the rule would permit the incident, and the file would be
    decoration. -/
theorem THM_WAIT_ADM_02_incident_is_inadmissible :
    admissible theIncident = false := by
  rfl

/-- THM_WAIT_ADM_03 — admissibility is sufficient for termination. The rule
    is not a style preference; it implies the property that matters. -/
theorem THM_WAIT_ADM_03_admissible_implies_terminates
    (w : Waiter) (f : Nat) (h : admissible w = true) :
    (stopsAt w f).isSome = true := by
  have hb : ¬ (w.budget = 0) := by
    simp [admissible] at h
    omega
  simp [stopsAt, hb]

/-- THM_WAIT_ADM_04 — and sufficient for one-line token cost. -/
theorem THM_WAIT_ADM_04_admissible_implies_minimum_tokens
    (w : Waiter) (f cap : Nat) (h : admissible w = true) :
    tokens w f cap = 1 := by
  have he : w.emitPerPoll = 0 := by
    simp [admissible] at h
    omega
  simp [tokens, he]

end UOS.BackgroundWaiter
