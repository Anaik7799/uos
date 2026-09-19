/- Full_Feature_Testing_Invariants.lean — Lean 4 Formal Model of Full Feature Surface Testing Invariants
   Formalizes:
   1. Theorem: Monotonicity of Risk Priority Number (RPN) in FMEA
   2. Theorem: Quorum 2oo3 Consensus Monotonicity
   3. Theorem: Hardware Drive Serial Lockout Non-Reachability
   4. Theorem: Metamorphic Trace Roundtrip Identity
   5. Theorem: Lyapunov Dissipative Energy Convergence
-/

namespace UOS.TestingInvariants

/-- 1. FMEA Risk Priority Number Monotonicity -/
def rpn (s o d : Nat) : Nat := s * o * d

theorem rpn_monotonic (s1 s2 o1 o2 d1 d2 : Nat)
  (hs : s1 ≤ s2) (ho : o1 ≤ o2) (hd : d1 ≤ d2) :
  rpn s1 o1 d1 ≤ rpn s2 o2 d2 := by
  dsimp [rpn]
  have h1 : s1 * o1 ≤ s2 * o2 := Nat.mul_le_mul hs ho
  exact Nat.mul_le_mul h1 hd

/-- 2. Quorum Consensus (2oo3) Floor Monotonicity -/
def quorum_satisfied (approvals _total threshold : Nat) : Bool :=
  decide (approvals ≥ threshold)

theorem quorum_monotonic (k1 k2 threshold : Nat)
  (hk : k1 ≤ k2) (h_sat : quorum_satisfied k1 3 threshold = true) :
  quorum_satisfied k2 3 threshold = true := by
  dsimp [quorum_satisfied] at *
  have h1 : threshold ≤ k1 := of_decide_eq_true h_sat
  have h2 : threshold ≤ k2 := Nat.le_trans h1 hk
  exact decide_eq_true h2

/-- 3. Hardware Storage Inviolability: Denied Serial Write Block -/
def is_denied_serial (s : String) : Bool :=
  s == "25503L801736"

inductive WriteAccessVerdict where
  | SafeAdmitted
  | FailClosedLocked
deriving Repr, DecidableEq

def evaluate_device_access (dev_serial : String) : WriteAccessVerdict :=
  if is_denied_serial dev_serial then
    WriteAccessVerdict.FailClosedLocked
  else
    WriteAccessVerdict.SafeAdmitted

theorem root_os_drive_permanently_locked :
  evaluate_device_access "25503L801736" = WriteAccessVerdict.FailClosedLocked := by
  rfl

/-- 4. Trace ID Roundtrip Preservation -/
structure TraceId where
  hi : Nat
  lo : Nat
deriving Repr, DecidableEq

def encode_trace (t : TraceId) : Nat × Nat :=
  (t.hi, t.lo)

def decode_trace (p : Nat × Nat) : TraceId :=
  ⟨p.1, p.2⟩

theorem trace_roundtrip_identity (t : TraceId) :
  decode_trace (encode_trace t) = t := by
  cases t
  rfl

/-- 5. Lyapunov Energy Stability Convergence -/
def is_dissipative (v_prev v_curr : Nat) : Bool :=
  decide (v_curr ≤ v_prev)

theorem dissipative_step_bounds_energy (v0 v1 : Nat) (h : is_dissipative v0 v1 = true) :
  v1 ≤ v0 := by
  dsimp [is_dissipative] at h
  exact of_decide_eq_true h

/-- 6. MAUT 5-Attribute Utility Monotonicity -/
def maut_utility (c s d f i : Nat) (wc ws wd wf wi : Nat) : Int :=
  ((wc * c + ws * s + wd * d : Nat) : Int) - ((wf * f + wi * i : Nat) : Int)

theorem maut_utility_monotonic (c1 c2 s d f i wc ws wd wf wi : Nat)
  (hc : c1 ≤ c2) :
  maut_utility c1 s d f i wc ws wd wf wi ≤ maut_utility c2 s d f i wc ws wd wf wi := by
  dsimp [maut_utility]
  have h_mul : wc * c1 ≤ wc * c2 := Nat.mul_le_mul_left wc hc
  have h_add : wc * c1 + ws * s + wd * d ≤ wc * c2 + ws * s + wd * d := by
    apply Nat.add_le_add_right
    apply Nat.add_le_add_right
    exact h_mul
  have h_cast : ((wc * c1 + ws * s + wd * d : Nat) : Int) ≤ ((wc * c2 + ws * s + wd * d : Nat) : Int) := by
    exact Int.ofNat_le.mpr h_add
  exact Int.sub_le_sub_right h_cast ((wf * f + wi * i : Nat) : Int)

/-- 7. Monotonic Fencing Token Ordering -/
def is_valid_fence (current_highest candidate : Nat) : Bool :=
  decide (candidate > current_highest)

theorem fencing_token_monotone (curr cand : Nat) (h : is_valid_fence curr cand = true) :
  curr < cand := by
  dsimp [is_valid_fence] at h
  exact of_decide_eq_true h

/-- 8. VFS Descriptor Sandbox Isolation -/
structure VfsFileRef where
  descriptor_id : Nat
  relative_path : String
deriving Repr, DecidableEq

def files_alias (f1 f2 : VfsFileRef) : Bool :=
  f1.descriptor_id == f2.descriptor_id && f1.relative_path == f2.relative_path

theorem vfs_descriptor_isolation (f1 f2 : VfsFileRef) (h_desc : f1.descriptor_id ≠ f2.descriptor_id) :
  files_alias f1 f2 = false := by
  dsimp [files_alias]
  have h_ne : (f1.descriptor_id == f2.descriptor_id) = false := by
    exact beq_false_of_ne h_desc
  simp [h_ne]

/-- 9. Bounded 64MB Arena Envelope Invariant -/
def ARENA_MAX_BYTES : Nat := 67108864 -- 64 * 1024 * 1024

structure ArenaState where
  allocated : Nat
  alloc_count : Nat

def can_alloc (st : ArenaState) (req : Nat) : Bool :=
  decide (st.allocated + req ≤ ARENA_MAX_BYTES)

def step_alloc (st : ArenaState) (req : Nat) : Option ArenaState :=
  if can_alloc st req then
    some ⟨st.allocated + req, st.alloc_count + 1⟩
  else
    none

theorem arena_envelope_preserved (st : ArenaState) (req : Nat) (st' : ArenaState)
  (h_step : step_alloc st req = some st') :
  st'.allocated ≤ ARENA_MAX_BYTES := by
  dsimp [step_alloc] at h_step
  split at h_step
  · cases h_step
    rename_i h_can
    dsimp [can_alloc] at h_can
    exact of_decide_eq_true h_can
  · contradiction

end UOS.TestingInvariants

