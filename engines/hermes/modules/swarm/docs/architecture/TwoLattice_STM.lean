/- TwoLattice_STM.lean — Lean 4 Formal Model of the UOS Two-Lattice Law
   and Software Transactional Memory (STM) Single-Writer Lease Protocol.

   Companion to specs/quint/uos_two_lattice_stm.qnt and
   harness-bionic/modules/hermes_harness/evidence_store.ml.

   Formalizes:
   1. The Two-Lattice Separation Law: Telemetry observation cannot mutate
      or invalidate authoritative evidence state (Non-Interference).
   2. STM Single-Writer Exclusivity: Mutual exclusion over SQLite writer leases.
   3. Monotonicity of Evidence: The authoritative evidence ledger never rolls back.
   4. Multi-Reader Snapshot Isolation: Readers observe an immutable prefix.

   Uses Lean 4 core `omega` (no external Mathlib dependencies).
   Verify: `lean proofs/lean/TwoLattice_STM.lean`
-/

namespace UOS

abbrev Epoch := Nat
abbrev Version := Nat
abbrev Clock := Nat
abbrev AgentId := Nat

/-- A single-writer lease issued to an agent with an epoch and expiration tick. -/
structure Lease where
  holder     : AgentId
  epoch      : Epoch
  expires_at : Clock
deriving Repr, DecidableEq

/-- The state of an STM writer transaction. -/
inductive WriterState where
  | Idle
  | Executing (l : Lease) (snap : Version)
  | Aborted
  | Committed (v : Version)
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
    simp [Lease.epoch]

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
      rcases h with ⟨hver, hrows, htele, _⟩
      refine ⟨by omega, by omega, ?_, trivial⟩
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
  unfold telemetryPublish
  split <;> simp

/-- THEOREM (The Two-Lattice Law): Network partitions on Zenoh NEVER modify
    authoritative evidence records, evidence version, or active writer leases. -/
theorem two_lattice_partition_non_interference (s : State) :
    let s' := toggleZenoh s
    s'.evidence_ver = s.evidence_ver ∧
    s'.evidence_rows = s.evidence_rows ∧
    s'.active_lease = s.active_lease := by
  intro s'
  unfold toggleZenoh; simp

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
  simp only
  have h_not_le : ¬ (s.clock ≤ l.expires_at) := by omega
  have h_and : ¬ (l.holder = a ∧ s.clock ≤ l.expires_at ∧ snap = s.evidence_ver) := by
    intro ⟨_, hle, _⟩; exact h_not_le hle
  simp [h_and]

end UOS
