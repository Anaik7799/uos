import Std

/-
Independent Mirage receipt admission reference model, 2026-09-07.
This executable specification does not prove that the OCaml/Gleam implementation
refines it. Fingerprints and run identifiers are opaque positive natural numbers;
cryptographic authenticity, ELF parsing, host instrumentation and OS cleanup are
external facts. The invariant concerns receipt credit, never deployment authority.
-/
namespace UOS.MirageReceiptAdmission

inductive Target where | hvt | spt | virtio deriving DecidableEq, Repr
inductive Profile where | hello | expectedSspAbort deriving DecidableEq, Repr

structure Binding where
  candidate : Nat
  host : Nat
  boot : Nat
  run : Nat
  provenance : Nat
  guestDigest : Nat
  tenderDigest : Nat
deriving DecidableEq, Repr

structure Expected where
  candidate : Nat
  host : Nat
  boot : Nat
  run : Nat
  provenance : Nat
  specDigest : Nat
  guestDigest : Target → Nat
  tenderDigest : Target → Nat
  now : Nat
  maxAge : Nat
  maxDuration : Nat
  maxBytes : Nat

structure Receipt where
  binding : Binding
  target : Target
  profile : Profile
  started : Nat
  finished : Nat
  bytes : Nat
  outputDigest : Nat
  authenticObservation : Bool
  outputComplete : Bool
  processGroupReaped : Bool
  hostExit : Int
  guestExit : Option Nat
  successMarker : Bool
  abortMarker : Bool
deriving DecidableEq, Repr

def expectedBinding (e : Expected) (t : Target) : Binding :=
  ⟨e.candidate, e.host, e.boot, e.run, e.provenance, e.guestDigest t, e.tenderDigest t⟩

def nonzero (b : Binding) : Prop :=
  b.candidate > 0 ∧ b.host > 0 ∧ b.boot > 0 ∧ b.run > 0 ∧
  b.provenance > 0 ∧ b.guestDigest > 0 ∧ b.tenderDigest > 0

instance (b : Binding) : Decidable (nonzero b) := inferInstanceAs (Decidable (_ ∧ _))

def expectedHostExit (t : Target) (p : Profile) : Int :=
  match t, p with
  | .virtio, _ => 83
  | _, .hello => 0
  | _, .expectedSspAbort => 255

def outcome (t : Target) (p : Profile) (r : Receipt) : Bool :=
  r.hostExit == expectedHostExit t p &&
  match p with
  | .hello => r.guestExit == some 0 && r.successMarker && !r.abortMarker
  | .expectedSspAbort => r.abortMarker && !r.successMarker && r.guestExit != some 0

def valid (e : Expected) (t : Target) (p : Profile) (r : Receipt) : Bool :=
  decide (r.binding = expectedBinding e t ∧ nonzero r.binding ∧
    r.target = t ∧ r.profile = p ∧
    e.maxAge > 0 ∧ e.maxDuration > 0 ∧ e.maxBytes > 0 ∧
    r.started ≤ r.finished ∧ r.finished ≤ e.now ∧
    e.now - r.finished ≤ e.maxAge ∧ r.finished - r.started ≤ e.maxDuration ∧
    r.bytes > 0 ∧ r.bytes ≤ e.maxBytes ∧ r.outputDigest > 0 ∧
    r.authenticObservation = true ∧ r.outputComplete = true ∧
    r.processGroupReaped = true ∧ outcome t p r = true)

def receiptReady (e : Expected) (t : Target) (r : Option Receipt) : Bool :=
  match r with | none => false | some receipt => valid e t .hello receipt

structure FormalReceipt where
  candidate : Nat
  specDigest : Nat
  toolchainDigest : Nat
  proofDigest : Nat
  observedAt : Nat
  checked : Bool
deriving DecidableEq, Repr

def formalReady (e : Expected) (receipt : Option FormalReceipt) : Bool :=
  match receipt with
  | none => false
  | some f => decide (f.candidate = e.candidate ∧ f.specDigest = e.specDigest ∧
      f.specDigest > 0 ∧ f.toolchainDigest > 0 ∧ f.proofDigest > 0 ∧
      f.checked = true ∧ f.observedAt ≤ e.now ∧ e.now - f.observedAt ≤ e.maxAge)

structure State where
  expected : Expected
  receipts : Target → Option Receipt
  formal : Option FormalReceipt
  admitted : Bool

def ready (s : State) : Bool :=
  receiptReady s.expected .hvt (s.receipts .hvt) &&
  receiptReady s.expected .spt (s.receipts .spt) &&
  receiptReady s.expected .virtio (s.receipts .virtio) &&
  formalReady s.expected s.formal

def Inv (s : State) : Prop := s.admitted = true → ready s = true

instance (s : State) : Decidable (Inv s) := inferInstanceAs (Decidable (_ → _))

def admit (s : State) : State := { s with admitted := ready s }
def record (s : State) (t : Target) (r : Receipt) : State :=
  { s with receipts := fun target => if target = t then some r else s.receipts target,
           admitted := false }
def replaceContext (s : State) (e : Expected) : State :=
  { s with expected := e, admitted := false }
def tick (s : State) (now : Nat) : State :=
  replaceContext s { s.expected with now := now }
def recordFormal (s : State) (receipt : FormalReceipt) : State :=
  { s with formal := some receipt, admitted := false }

theorem admit_preserves (s : State) : Inv (admit s) := by
  intro h
  exact h

theorem record_preserves (s : State) (t : Target) (r : Receipt) :
    Inv (record s t r) := by simp [Inv, record]

theorem replace_context_preserves (s : State) (e : Expected) :
    Inv (replaceContext s e) := by simp [Inv, replaceContext]

theorem tick_preserves (s : State) (now : Nat) : Inv (tick s now) := by
  exact replace_context_preserves s _

theorem formal_record_preserves (s : State) (receipt : FormalReceipt) :
    Inv (recordFormal s receipt) := by simp [Inv, recordFormal]

inductive Event where
  | receipt : Target → Receipt → Event
  | context : Expected → Event
  | clock : Nat → Event
  | formal : FormalReceipt → Event
  | admit : Event

def applyEvent (s : State) : Event → State
  | .receipt t r => record s t r
  | .context e => replaceContext s e
  | .clock now => tick s now
  | .formal receipt => recordFormal s receipt
  | .admit => admit s

theorem event_preserves (s : State) (event : Event) : Inv (applyEvent s event) := by
  cases event with
  | receipt t r => exact record_preserves s t r
  | context e => exact replace_context_preserves s e
  | clock now => exact tick_preserves s now
  | formal receipt => exact formal_record_preserves s receipt
  | admit => exact admit_preserves s

def replay (s : State) : List Event → State
  | [] => s
  | event :: tail => replay (applyEvent s event) tail

theorem trace_preserves (events : List Event) (s : State) (h : Inv s) :
    Inv (replay s events) := by
  induction events generalizing s with
  | nil => exact h
  | cons event tail ih => exact ih (applyEvent s event) (event_preserves s event)

theorem valid_binds_candidate (e : Expected) (t : Target) (p : Profile) (r : Receipt)
    (h : valid e t p r = true) : r.binding.candidate = e.candidate := by
  simp only [valid, decide_eq_true_eq] at h
  exact congrArg Binding.candidate h.1

theorem wrong_candidate_rejected (e : Expected) (t : Target) (p : Profile) (r : Receipt)
    (wrong : r.binding.candidate ≠ e.candidate) : valid e t p r = false := by
  cases h : valid e t p r with
  | false => rfl
  | true => exact False.elim (wrong (valid_binds_candidate e t p r h))

theorem valid_binds_boot (e : Expected) (t : Target) (p : Profile) (r : Receipt)
    (h : valid e t p r = true) : r.binding.boot = e.boot := by
  simp only [valid, decide_eq_true_eq] at h
  exact congrArg Binding.boot h.1

theorem valid_is_fresh (e : Expected) (t : Target) (p : Profile) (r : Receipt)
    (h : valid e t p r = true) : r.finished ≤ e.now ∧ e.now - r.finished ≤ e.maxAge := by
  simp only [valid, decide_eq_true_eq] at h
  exact ⟨h.2.2.2.2.2.2.2.2.1, h.2.2.2.2.2.2.2.2.2.1⟩

theorem missing_virtio_rejected (s : State) (h : s.receipts .virtio = none) :
    ready s = false := by simp [ready, h, receiptReady]

theorem missing_formal_rejected (s : State) (h : s.formal = none) :
    ready s = false := by simp [ready, formalReady, h]

def sampleContext : Expected :=
  ⟨1, 1, 1, 1, 1, 1, fun _ => 1, fun _ => 1, 10, 2, 2, 4096⟩

def sample (t : Target) (p : Profile) : Receipt :=
  ⟨expectedBinding sampleContext t, t, p, 9, 10, 100, 1, true, true, true,
    expectedHostExit t p, if p == .hello then some 0 else none,
    p == .hello, p == .expectedSspAbort⟩

def completeState : State :=
  ⟨sampleContext, fun t => some (sample t .hello), some ⟨1, 1, 1, 1, 10, true⟩, false⟩

-- Successful witnesses and deliberately unsafe mutations distinguish a real
-- admission/freshness check from a model with no reachable accepted state.
example : ready completeState = true := by decide
example : valid sampleContext .virtio .hello (sample .virtio .hello) = true := by decide
example : valid sampleContext .virtio .expectedSspAbort (sample .virtio .expectedSspAbort) = true := by decide
example : valid sampleContext .virtio .hello (sample .virtio .expectedSspAbort) = false := by decide
example : valid sampleContext .hvt .hello { sample .hvt .hello with finished := 11 } = false := by decide
example : ready (tick (admit completeState) 13) = false := by decide
example : (admit (tick (admit completeState) 13)).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with boot := 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with run := 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with candidate := 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with host := 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with provenance := 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with guestDigest := fun _ => 2 })).admitted = false := by decide
example : (admit (replaceContext completeState { sampleContext with tenderDigest := fun _ => 2 })).admitted = false := by decide
example : valid sampleContext .hvt .hello { sample .hvt .hello with processGroupReaped := false } = false := by decide
example : valid sampleContext .hvt .hello { sample .hvt .hello with bytes := 4097 } = false := by decide
example : valid sampleContext .hvt .hello { sample .hvt .hello with outputDigest := 0 } = false := by decide
example : valid sampleContext .hvt .hello { sample .hvt .hello with started := 7 } = false := by decide
example : formalReady sampleContext (some ⟨2, 1, 1, 1, 10, true⟩) = false := by decide
example : formalReady sampleContext (some ⟨1, 2, 1, 1, 10, true⟩) = false := by decide
example : formalReady sampleContext (some ⟨1, 1, 0, 1, 10, true⟩) = false := by decide
example : formalReady sampleContext (some ⟨1, 1, 1, 1, 7, true⟩) = false := by decide
example : formalReady sampleContext (some ⟨1, 1, 1, 1, 10, false⟩) = false := by decide

def unsafeStickyTick (s : State) : State :=
  { s with expected := { s.expected with now := 13 } }
example : ¬ Inv (unsafeStickyTick (admit completeState)) := by decide

def unsafeOmitVirtio (s : State) : State :=
  { s with receipts := fun t => if t == .virtio then none else s.receipts t,
           admitted := true }
example : ¬ Inv (unsafeOmitVirtio completeState) := by decide

#print axioms admit_preserves
#print axioms wrong_candidate_rejected
#print axioms missing_virtio_rejected
#print axioms trace_preserves

end UOS.MirageReceiptAdmission

open UOS.MirageReceiptAdmission

-- A bounded truth table for an independent integer/deficit oracle. Each line
-- is target, profile, candidate, boot, finished, hostExit, guestExit(-1=none),
-- success, abort, authentic, complete, verdict. 31,104 cases, no OS execution.
def main : IO Unit := do
  for (t, ti) in [(Target.hvt, 0), (.spt, 1), (.virtio, 2)] do
    for (p, pi) in [(Profile.hello, 0), (.expectedSspAbort, 1)] do
      for c in [0, 1, 2] do
        for boot in [0, 1, 2] do
          for finished in [7, 8, 10, 11] do
            for hostExit in ([0, 83, 255] : List Int) do
              for guest in ([-1, 0, 1] : List Int) do
                for success in [false, true] do
                  for abort in [false, true] do
                    for authentic in [false, true] do
                      for complete in [false, true] do
                        let r := { sample t p with
                          binding := { (sample t p).binding with candidate := c, boot := boot }
                          started := finished - 1, finished := finished
                          hostExit := hostExit
                          guestExit := if guest < 0 then none else some guest.toNat
                          successMarker := success, abortMarker := abort
                          authenticObservation := authentic, outputComplete := complete }
                        IO.println s!"{ti},{pi},{c},{boot},{finished},{hostExit},{guest},{success},{abort},{authentic},{complete},{valid sampleContext t p r}"
