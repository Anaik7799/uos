/- TwoLattice_STM.lean — Lean 4 Formal Model of the UOS Two-Lattice Architecture
   and Software Transactional Memory (STM) Single-Writer Lease Protocol.

   Companion to specs/quint/uos_two_lattice_stm.qnt and
   harness-bionic/modules/hermes_harness/evidence_store.ml.

   Formalizes:
   1. The Two-Lattice Separation Law: Telemetry observation cannot mutate
      or invalidate authoritative evidence state (Non-Interference).
   2. Single-Writer Exclusive Lease Protocol with Fencing Tokens.
   3. Lockless Snapshot Isolation for Readers.
   4. Totality & Expiration Invariants on Leases.
-/

namespace UOS

/- ── 0. FOUNDATIONAL TYPES & DOMAINS ────────────────────────────────────── -/

abbrev AgentId  := Nat
abbrev Version  := Nat
abbrev Epoch    := Nat
abbrev Clock    := Nat

/-- A single-writer exclusive lease granted to an agent. -/
structure Lease where
  holder     : AgentId
  epoch      : Epoch
  expires_at : Clock
deriving Repr, DecidableEq

/-- The state of a lockless snapshot reader. -/
inductive ReaderState where
  | Idle
  | Reading (snap : Version)
deriving Repr, DecidableEq

/-- Global state of the Unified Operational System Two-Lattice fabric. -/
structure State where
  clock           : Clock
  evidence_ver    : Version
  evidence_rows   : Nat
  active_lease    : Option Lease
  epoch_counter   : Epoch
  tele_ring_len   : Nat
  tele_cap        : Nat
  zenoh_online    : Bool
deriving Repr

/-- Well-formedness invariants on the global state. -/
def State.wf (s : State) : Prop :=
  s.evidence_ver ≥ 1 ∧
  s.evidence_rows ≥ 1 ∧
  s.tele_ring_len ≤ s.tele_cap ∧
  (match s.active_lease with
   | some l => l.epoch ≤ s.epoch_counter ∧ l.holder > 0
   | none   => True)

/- ── 1. STM LEASE EXCLUSIVITY & GRANTING ────────────────────────────────── -/

/-- Request an exclusive writer lease. Fails if a lease is currently active. -/
def acquireLease (s : State) (a : AgentId) (duration : Nat) : Option State :=
  match s.active_lease with
  | some _ => none -- Contention: reject fail-closed
  | none   =>
    let new_epoch := s.epoch_counter + 1
    let lease : Lease := { holder := a, epoch := new_epoch, expires_at := s.clock + duration }
    some { s with
      active_lease  := some lease,
      epoch_counter := new_epoch
    }

/-- Theorem: Lease acquisition preserves state well-formedness. -/
theorem acquireLease_wf (s : State) (a : AgentId) (d : Nat) (ha : a > 0)
    (h : s.wf) (s' : State) (heq : acquireLease s a d = some s') : s'.wf := by
  unfold acquireLease at heq
  split at heq
  · contradiction
  · injection heq with h_inj
    rw [← h_inj]
    unfold State.wf at *
    rcases h with ⟨hver, hrows, htele, _⟩
    refine ⟨hver, hrows, htele, ?_⟩
    simp
    exact ha

/-- Theorem: Mutex Exclusivity — Acquire fails if a lease is already held. -/
theorem lease_mutex (s : State) (l : Lease) (h_lease : s.active_lease = some l)
    (a : AgentId) (d : Nat) : acquireLease s a d = none := by
  unfold acquireLease
  rw [h_lease]

/- ── 2. STM COMMIT & EVIDENCE MONOTONICITY ─────────────────────────────── -/

/-- Commit an STM transaction. Requires valid, unexpired lease and matching snapshot. -/
def commitTx (s : State) (a : AgentId) (snap : Version) : Option State :=
  match s.active_lease with
  | none   => none -- No lease: reject fail-closed
  | some l =>
    if l.holder = a ∧ s.clock ≤ l.expires_at ∧ snap = s.evidence_ver then
      let new_ver := s.evidence_ver + 1
      let new_rows := s.evidence_rows + 1
      let new_ring := if s.tele_ring_len < s.tele_cap then s.tele_ring_len + 1 else s.tele_ring_len
      some { s with
        evidence_ver  := new_ver,
        evidence_rows := new_rows,
        active_lease  := none,
        tele_ring_len := new_ring
      }
    else
      none

/-- Theorem: Commit strictly advances authoritative evidence version. -/
theorem commit_strictly_monotonic (s : State) (a : AgentId) (snap : Version)
    (s' : State) (heq : commitTx s a snap = some s') :
    s'.evidence_ver = s.evidence_ver + 1 := by
  unfold commitTx at heq
  split at heq
  · contradiction
  · split at heq
    · injection heq with h_inj; rw [← h_inj]
    · contradiction

/-- Theorem: Commit preserves state well-formedness. -/
theorem commitTx_wf (s : State) (a : AgentId) (snap : Version)
    (h : s.wf) (s' : State) (heq : commitTx s a snap = some s') : s'.wf := by
  unfold commitTx at heq
  split at heq
  · contradiction
  · split at heq
    · injection heq with h_inj
      rw [← h_inj]
      unfold State.wf at *
      rcases h with ⟨_, _, htele, _⟩
      dsimp
      refine ⟨Nat.succ_le_succ (Nat.zero_le _), Nat.succ_le_succ (Nat.zero_le _), ?_, trivial⟩
      split
      · omega
      · exact htele
    · contradiction

/- ── 3. TWO-LATTICE NON-INTERFERENCE THEOREM ────────────────────────────── -/

/-- Telemetry frame emission or network drop action on the Zenoh plane. -/
def telemetryPublish (s : State) : State :=
  if s.zenoh_online ∧ s.tele_ring_len > 0 then
    { s with tele_ring_len := s.tele_ring_len - 1 }
  else
    s

/-- Telemetry network partition toggle. -/
def toggleZenoh (s : State) : State :=
  { s with zenoh_online := ¬ s.zenoh_online }

/-- THEOREM (The Two-Lattice Law): Telemetry publication NEVER modifies
    authoritative evidence records, evidence version, or active writer leases. -/
theorem two_lattice_telemetry_non_interference (s : State) :
    let s' := telemetryPublish s
    s'.evidence_ver = s.evidence_ver ∧
    s'.evidence_rows = s.evidence_rows ∧
    s'.active_lease = s.active_lease := by
  intro s'
  dsimp [s', telemetryPublish]
  split
  · simp
  · simp

/-- THEOREM (The Two-Lattice Law): Network partitions on Zenoh NEVER modify
    authoritative evidence records, evidence version, or active writer leases. -/
theorem two_lattice_partition_non_interference (s : State) :
    let s' := toggleZenoh s
    s'.evidence_ver = s.evidence_ver ∧
    s'.evidence_rows = s.evidence_rows ∧
    s'.active_lease = s.active_lease := by
  intro s'
  dsimp [s', toggleZenoh]
  simp

/- ── 4. MULTI-READER SNAPSHOT ISOLATION ─────────────────────────────────── -/

/-- Reader takes a lockless snapshot of the authoritative evidence store. -/
def startReader (s : State) : ReaderState :=
  ReaderState.Reading s.evidence_ver

/-- THEOREM: Reader snapshot is always bounded by the current evidence version. -/
theorem reader_snapshot_valid (s : State) (h : s.wf) :
    match startReader s with
    | ReaderState.Reading v => v = s.evidence_ver ∧ v ≥ 1
    | ReaderState.Idle      => False := by
  unfold startReader
  unfold State.wf at h
  exact ⟨rfl, h.1⟩

/- ── 5. TOTALITY & FAIL-CLOSED EXPIRATION ───────────────────────────────── -/

/-- Revoke an expired lease. -/
def revokeExpiredLease (s : State) : State :=
  match s.active_lease with
  | some l =>
    if s.clock > l.expires_at then
      { s with active_lease := none }
    else
      s
  | none => s

/-- THEOREM: If clock has exceeded expiration, commit is impossible. -/
theorem expired_lease_cannot_commit (s : State) (a : AgentId) (snap : Version)
    (l : Lease) (h_lease : s.active_lease = some l) (h_exp : s.clock > l.expires_at) :
    commitTx s a snap = none := by
  unfold commitTx
  rw [h_lease]
  dsimp
  have h_not_le : ¬ (s.clock ≤ l.expires_at) := Nat.not_le_of_gt h_exp
  have h_cond : ¬ (l.holder = a ∧ s.clock ≤ l.expires_at ∧ snap = s.evidence_ver) := by
    intro ⟨_, hle, _⟩
    exact h_not_le hle
  rw [if_neg h_cond]

end UOS
