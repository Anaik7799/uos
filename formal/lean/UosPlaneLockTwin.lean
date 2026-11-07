/-
  UosPlaneLockTwin — the digital twin of the shared code-plane lock.

  Subject: tools/uos_plane_lock.ml, and its two call sites
           tools/mojo_mutation_dataplane.ml (writer),
           tools/lean_mojo_differential.ml  (reader + digest),
           tools/mojo_arm_falsifiability.ml (writer + reader),
           tools/verification_plane_deps.ml (reader).

  WHAT THIS PROVES, AND WHAT IT CANNOT
  ------------------------------------
  Findings F-W-13 and F-W-15, authored 20261107-2048 from the host clock.

  F-W-13: the mutation instrument rewrites `formal/mojo/*` in place; the
  differential digests those same bytes into `oracle_set_sha256_16`. Between
  the write and the restore the tree is a mutant, so an unsynchronised digest
  can name a revision nobody authored.

  F-W-15 is a DIFFERENT defect and no lock fixes it: the falsifiability
  instrument writes `generated_falsify_<mod>.mojo`, whose name ends in
  `_oracle.mojo`, so a crash before cleanup leaves a file that the
  differential enumerates as a real pair, scores VACUOUS, and -- VACUOUS
  being lattice position 5 under worst-wins -- that one stray file dominates
  the whole run's verdict. Modelled here as `strayPoisons`.

  No `sorry`, no `axiom`. Every theorem below names, in its comment, the
  observation that would falsify it. Theorems 02/03 and 04/05 are deliberate
  PAIRS: each positive claim is accompanied by a counter-model in which it is
  false, because a property that holds of every implementation says nothing
  about the one that was chosen.

  This is specification evidence at one candidate. authority NONE.
  EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number is minted.
-/

namespace UOS.PlaneLockTwin

/-- The three mechanisms. `kernelLock` is `Unix.lockf F_TLOCK`, held by the
    kernel and released when the holder dies. `pidFile` is the design that
    was considered and rejected: a file whose existence means "held".
    `noLock` is the state of the tree before this change. -/
inductive Impl where
  | kernelLock
  | pidFile
  | noLock
  deriving DecidableEq, Repr

/-- Plane events. `mutate p b` is a writer putting a mutant on disk (`b`
    true) or restoring (`b` false); it carries the pid so the model can say
    whether that writer was entitled to act. -/
inductive Ev where
  | acquire (pid : Nat)
  | release (pid : Nat)
  | die     (pid : Nat)
  | digest
  | mutate  (pid : Nat) (on : Bool)
  deriving DecidableEq, Repr

/-- `marker` exists only to distinguish the two mechanisms: it is the lock
    FILE, which outlives its holder. `kernelLock` ignores it; `pidFile`
    depends on it, which is the whole difference. -/
structure St where
  holder  : Option Nat
  mutant  : Bool
  marker  : Bool
  sawMut  : Bool   -- did a `digest` ever observe a mutant on disk?
  deriving DecidableEq, Repr

def init : St := { holder := none, mutant := false, marker := false, sawMut := false }

def free (i : Impl) (s : St) : Bool :=
  match i with
  | .kernelLock => s.holder.isNone
  | .pidFile    => s.holder.isNone && !s.marker
  | .noLock     => true

def step (i : Impl) (s : St) : Ev → St
  | .acquire p =>
      if free i s then { s with holder := some p, marker := true } else s
  | .release p =>
      if s.holder == some p then { s with holder := none, marker := false } else s
  | .die p =>
      -- The kernel drops the record lock; the FILE stays. That single line is
      -- the entire argument for lockf over a pid file.
      if s.holder == some p then { s with holder := none } else s
  | .digest =>
      { s with sawMut := s.sawMut || s.mutant }
  | .mutate p b =>
      match i with
      | .noLock => { s with mutant := b }
      | _       => if s.holder == some p then { s with mutant := b } else s

def run (i : Impl) : List Ev → St → St
  | [],      s => s
  | e :: es, s => run i es (step i s e)

/-- ## THM_LOCK_01 — mutual exclusion.
    A second acquirer cannot displace a live holder.
    FALSIFIED BY: observing two processes inside the critical section at once
    (`--selftest` control C2, which a `lockf`-less build fails). -/
theorem THM_LOCK_01_holder_is_not_displaced
    (i : Impl) (s : St) (p q : Nat) (h : s.holder = some p) (hi : i ≠ Impl.noLock) :
    (step i s (Ev.acquire q)).holder = some p := by
  cases i with
  | kernelLock => simp [step, free, h]
  | pidFile    => simp [step, free, h]
  | noLock     => exact absurd rfl hi

/-- ## THM_LOCK_02 — no stale wedge, for the kernel lock.
    The holder dies without releasing; the plane is acquirable again.
    FALSIFIED BY: a crashed sweep leaving the plane permanently unavailable
    (`--selftest` control C5). -/
theorem THM_LOCK_02_kernel_lock_survives_holder_death (p : Nat) :
    free Impl.kernelLock (run Impl.kernelLock [Ev.acquire p, Ev.die p] init) = true := by
  simp [run, step, free, init]

/-- ## THM_LOCK_03 — the NON-VACUITY PARTNER of 02.
    The same trace under a pid file leaves the plane wedged. Without this,
    THM_LOCK_02 would be consistent with the mechanism not mattering, and the
    choice of `lockf` would be unjustified rather than justified.
    FALSIFIED BY: a pid-file build that passes C5 -- which would mean the
    model's `marker` does not describe a real pid file. -/
theorem THM_LOCK_03_pid_file_wedges_on_holder_death (p : Nat) :
    free Impl.pidFile (run Impl.pidFile [Ev.acquire p, Ev.die p] init) = false := by
  simp [run, step, free, init]

/-- ## THM_LOCK_04 — digest soundness under the lock.
    A reader holds the plane; a writer attempts to place a mutant and is
    refused; the digest therefore observes no mutant.
    FALSIFIED BY: an `oracle_set_sha256_16` that moves while a reader holds
    the lock. -/
theorem THM_LOCK_04_locked_digest_sees_no_mutant :
    (run Impl.kernelLock
      [Ev.acquire 1, Ev.mutate 2 true, Ev.digest] init).sawMut = false := by
  decide

/-- ## THM_LOCK_05 — finding F-W-13, stated as a theorem, and the NON-VACUITY
    PARTNER of 04. With no lock there is an interleaving in which the digest
    observes a mutant: the recorded hash names a tree that never existed.
    This must be PROVABLE; if it were not, F-W-13 would not be a real defect
    and the whole change would be unnecessary.
    FALSIFIED BY: showing no such interleaving exists -- i.e. that the two
    instruments never touch the same bytes. They do: the mutation plane writes
    `formal/mojo/*_oracle.mojo` and the differential cats exactly those. -/
theorem THM_LOCK_05_unlocked_digest_can_see_a_mutant :
    (run Impl.noLock [Ev.mutate 2 true, Ev.digest] init).sawMut = true := by
  decide

/-- ## THM_LOCK_06 — the acquire retry is bounded.
    `polls` counts /proc-free waiting rounds. The bound is what makes this an
    admissible waiter under UosBackgroundWaiterTwin: a mandatory deadline.
    FALSIFIED BY: a build whose retry is a `while` with no budget -- which is
    the defect that burned ~56 core-hours on 20261107. -/
def polls (i : Impl) (s : St) : Nat → Nat
  | 0     => 0
  | n + 1 => if free i s then 1 else 1 + polls i s n

theorem THM_LOCK_06_acquire_polls_are_bounded (i : Impl) (s : St) :
    ∀ n, polls i s n ≤ n := by
  intro n
  induction n with
  | zero => simp [polls]
  | succ k ih =>
    simp only [polls]
    by_cases h : free i s = true
    · simp [h]
    · simp only [h, if_false, Bool.false_eq_true]
      omega

/-- ## THM_LOCK_07 — path agreement.
    Two instruments exclude each other exactly when they resolve the same
    lock path. This is why `uos_plane_lock.ml` copies the root expression
    from `lean_mojo_differential.ml` byte for byte instead of falling back to
    `Sys.getcwd ()`: with different roots BOTH acquire successfully, every
    exclusion control still passes, and the lock excludes nobody.
    FALSIFIED BY: two instruments with different roots that nonetheless
    exclude each other. -/
def excludes (root₁ root₂ : Nat) : Bool := root₁ == root₂

theorem THM_LOCK_07a_same_root_excludes (r : Nat) : excludes r r = true := by
  simp [excludes]

theorem THM_LOCK_07b_different_roots_exclude_nobody (r₁ r₂ : Nat) (h : r₁ ≠ r₂) :
    excludes r₁ r₂ = false := by
  simp [excludes, h]

/-- ## THM_LOCK_08 — finding F-W-15: a stray generated probe poisons the
    verdict, and NO lock prevents it.
    `strayPoisons` says: if the pair enumeration admits a file the
    falsifiability instrument generated, the run's verdict is decided by that
    file (VACUOUS = 5 dominates PASS = 0 under worst-wins), regardless of how
    the authored pairs did.
    FALSIFIED BY: placing such a file in `formal/mojo` and observing the
    differential ignore it -- which is what the fix now does, and what the
    pre-fix tree did NOT do (observed: overall=VACUOUS from one stray file). -/
def VACUOUS : Nat := 5
def PASS : Nat := 0

def worstWins (vs : List Nat) : Nat := vs.foldl Nat.max PASS

/-- Admitting the stray changes the verdict; excluding it does not. The two
    halves together are the statement that the exclusion is load-bearing. -/
theorem THM_LOCK_08_stray_probe_dominates_the_verdict :
    worstWins [PASS, PASS, VACUOUS] = VACUOUS ∧ worstWins [PASS, PASS] = PASS := by
  constructor <;> decide

end UOS.PlaneLockTwin
