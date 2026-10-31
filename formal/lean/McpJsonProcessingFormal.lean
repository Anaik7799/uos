import Std

/- Source-bound abstract formal model, 2026-10-31, J1..J8.
   Source anchors (read-only): apps/cepaf_gleam/src/mcp_stdio_ffi.erl
   (read_line/0 and json:decode), and formal/lean/McpSymbiosis101FormalImpact.lean.
   The model specifies desired JSON / JSON-RPC / MCP wire invariants. It is not
   an extraction of the running parser, a proof of its refinement, or a system
   admission claim. Chunk concatenation is a byte-list law, not a decoder proof;
   canonical lookup equality is not a cryptographic collision-resistance claim.
   Duplicate rejection and Unicode checks are abstract guards; structural
   depth induction and sorting invariance are proved over the explicit models.
   JSON-RPC batch transport status 202 is an external interpretation of silence.
   Provenance boundary: admitted_ev_ceiling = 93; system admission is false.
-/
namespace UOS.McpJsonProcessingFormal

def admitted_ev_ceiling : Nat := 93
def systemAdmission : Bool := false
theorem provenance_ceiling : admitted_ev_ceiling = 93 := rfl
theorem zero_system_admission_claim : systemAdmission = false := rfl

-- J1: recoverable line errors do not terminate the stdio automaton.
inductive StdioEvent where
  | ValidFrame | OversizedLineDrained | InvalidUtf8Line | MalformedJsonLine | EndOfFile
  deriving DecidableEq, Repr
inductive LoopState where
  | Running | Halted
  deriving DecidableEq, Repr

def stepStdio : LoopState → StdioEvent → LoopState
  | .Halted, _ => .Halted
  | .Running, .EndOfFile => .Halted
  | .Running, _ => .Running

theorem stdio_never_terminates_before_eof :
    ∀ ev, ev ≠ .EndOfFile → stepStdio .Running ev = .Running := by
  intro ev h
  cases ev <;> simp_all [stepStdio]

theorem stdio_eof_halts : stepStdio .Running .EndOfFile = .Halted := rfl

theorem chunk_concat_associative (c1 c2 c3 : List UInt8) :
    (c1 ++ c2) ++ c3 = c1 ++ (c2 ++ c3) := List.append_assoc c1 c2 c3

-- J2: validity is applied to decoded scalar values, including escapes.
def validJsonScalar (u : Nat) : Bool :=
  (u ≥ 1 && u ≤ 0xD7FF) || (u ≥ 0xE000 && u ≤ 0x10FFFF)

theorem nul_excluded : validJsonScalar 0 = false := by decide

theorem lone_surrogates_excluded :
    ∀ u, 0xD800 ≤ u → u ≤ 0xDFFF → validJsonScalar u = false := by
  intro u lo hi
  have h1 : ¬ u ≤ 0xD7FF := by omega
  have h2 : ¬ u ≥ 0xE000 := by omega
  simp [validJsonScalar, h1, h2]

theorem above_unicode_max_excluded :
    ∀ u, u > 0x10FFFF → validJsonScalar u = false := by
  intro u h
  have h1 : ¬ u ≤ 0xD7FF := by omega
  have h2 : ¬ u ≤ 0x10FFFF := by omega
  simp [validJsonScalar, h1, h2]

-- J3: a guarded push preserves the depth bound, including maxD = 32.
def pushDepth (maxD d : Nat) : Option Nat :=
  if d < maxD then some (d + 1) else none

theorem pushDepth_bounded : ∀ maxD d d', d ≤ maxD →
    pushDepth maxD d = some d' → d' ≤ maxD := by
  intro maxD d d' _ h
  unfold pushDepth at h
  split at h
  · simp only [Option.some.injEq] at h
    omega
  · contradiction

theorem pushDepth_32_bounded (d d' : Nat) (h : d ≤ 32)
    (accepted : pushDepth 32 d = some d') : d' ≤ 32 :=
  pushDepth_bounded 32 d d' h accepted

theorem pushDepth_rejects_overflow : pushDepth 32 32 = none := by decide

-- J4: first-key (list.find) versus last-key (maps:from_list) semantics.
abbrev Obj := List (String × String)

def lookupFirst {α : Type} (k : String) : List (String × α) → Option α
  | [] => none
  | (key, value) :: rest => if k = key then some value else lookupFirst k rest

def lookupLast {α : Type} (k : String) (obj : List (String × α)) : Option α :=
  lookupFirst k obj.reverse

def UniqueKeys {α : Type} (obj : List (String × α)) : Prop :=
  (obj.map Prod.fst).Nodup

def attackObj : Obj := [("method", "ping"), ("method", "tools/call")]

theorem duplicate_key_smuggling_witness :
    lookupFirst "method" attackObj = some "ping" ∧
    lookupLast "method" attackObj = some "tools/call" ∧
    lookupFirst "method" attackObj ≠ lookupLast "method" attackObj := by decide

theorem lookupFirst_append {α : Type} (k : String) (xs ys : List (String × α)) :
    lookupFirst k (xs ++ ys) =
      match lookupFirst k xs with
      | some v => some v
      | none => lookupFirst k ys := by
  induction xs with
  | nil => rfl
  | cons pair xs ih =>
    rcases pair with ⟨key, value⟩
    simp only [List.cons_append, lookupFirst]
    split <;> simp_all

theorem lookupFirst_none_of_absent {α : Type} (obj : List (String × α))
    (k : String) (h : k ∉ obj.map Prod.fst) : lookupFirst k obj = none := by
  induction obj with
  | nil => rfl
  | cons pair xs ih =>
    rcases pair with ⟨key, value⟩
    simp only [List.map_cons, List.mem_cons, not_or] at h
    simp [lookupFirst, h.1, ih h.2]

theorem unique_keys_eliminates_parser_differential {α : Type} :
    ∀ (obj : List (String × α)) (k : String),
      UniqueKeys obj → lookupFirst k obj = lookupLast k obj := by
  intro obj
  induction obj with
  | nil => intro k _; rfl
  | cons pair xs ih =>
    rcases pair with ⟨key, value⟩
    intro k unique
    have nodup : key ∉ xs.map Prod.fst ∧ (xs.map Prod.fst).Nodup := by
      simpa [UniqueKeys] using unique
    have tailUnique : UniqueKeys xs := nodup.2
    have tailEq := ih k tailUnique
    unfold lookupLast
    rw [List.reverse_cons, lookupFirst_append]
    by_cases hk : k = key
    · subst k
      have absent := lookupFirst_none_of_absent xs key nodup.1
      have revAbsent : lookupFirst key xs.reverse = none := by
        exact (ih key tailUnique).symm.trans absent
      simp [lookupFirst, revAbsent]
    · have revEq : lookupFirst k xs.reverse = lookupFirst k xs := tailEq.symm
      rw [revEq]
      cases found : lookupFirst k xs <;> simp [lookupFirst, hk, found]

-- J5: integer conservation in the closed I-JSON interoperable interval.
def ijsonMax : Int := 9007199254740991
def isSafeIJsonInt (n : Int) : Bool := (-ijsonMax ≤ n) && (n ≤ ijsonMax)

theorem ijson_upper_boundary : isSafeIJsonInt ijsonMax = true := by decide
theorem ijson_lower_boundary : isSafeIJsonInt (-ijsonMax) = true := by decide
theorem ijson_upper_overflow : isSafeIJsonInt (ijsonMax + 1) = false := by decide
theorem ijson_lower_overflow : isSafeIJsonInt (-ijsonMax - 1) = false := by decide

theorem ijson_negation_symmetry (n : Int) :
    isSafeIJsonInt n = isSafeIJsonInt (-n) := by
  have lower : (-ijsonMax ≤ n) ↔ (-n ≤ ijsonMax) := by omega
  have upper : (n ≤ ijsonMax) ↔ (-ijsonMax ≤ -n) := by omega
  simp only [isSafeIJsonInt, lower, upper]
  exact Bool.and_comm _ _

-- J6: syntactic envelope partition, then seven execution outcomes.
inductive IdField where
  | Absent | ExplicitNull | IntId (n : Int) | StrId (s : String) | InvalidIdType
  deriving DecidableEq, Repr
inductive EnvelopeClass where
  | ParseErr32700 | InvalidReq32600 | NotificationSilent | SingleRequest | BatchRequest
  deriving DecidableEq, Repr

structure RpcObject where
  version : String
  methodIsString : Bool
  idField : IdField
  knownMethod : Bool
  paramsValid : Bool
  handlerOk : Bool
  deriving DecidableEq, Repr

def validObject (obj : RpcObject) : Bool :=
  (obj.version == "2.0") && obj.methodIsString && (obj.idField != .InvalidIdType)

inductive WireEnvelope where
  | MalformedJson | NonObject | Object (obj : RpcObject) | Array (items : List RpcObject)
  deriving DecidableEq, Repr

def notificationShape (obj : RpcObject) : Bool :=
  obj.methodIsString && (obj.idField == .Absent)

def classifyEnvelope : WireEnvelope → EnvelopeClass
  | .MalformedJson => .ParseErr32700
  | .NonObject => .InvalidReq32600
  | .Array [] => .InvalidReq32600
  | .Array (_ :: _) => .BatchRequest
  | .Object obj =>
    if notificationShape obj then .NotificationSilent
    else if validObject obj then .SingleRequest else .InvalidReq32600

theorem envelope_classification_total (e : WireEnvelope) :
    classifyEnvelope e = .ParseErr32700 ∨ classifyEnvelope e = .InvalidReq32600 ∨
    classifyEnvelope e = .NotificationSilent ∨ classifyEnvelope e = .SingleRequest ∨
    classifyEnvelope e = .BatchRequest := by
  cases classifyEnvelope e <;> simp

theorem envelope_classification_pairwise_disjoint (e : WireEnvelope)
    (a b : EnvelopeClass) (different : a ≠ b) :
    ¬ (classifyEnvelope e = a ∧ classifyEnvelope e = b) := by
  intro h
  exact different (h.1.symm.trans h.2)

inductive RpcReply where
  | Error (code : Int) | Result (value : String) | Batch (replies : List RpcReply)
  deriving Repr

def dispatchReply (obj : RpcObject) : RpcReply :=
  if !obj.knownMethod then .Error (-32601)
  else if !obj.paramsValid then .Error (-32602)
  else if !obj.handlerOk then .Error (-32603)
  else .Result "ok"

def evalItem (obj : RpcObject) : Option RpcReply :=
  if notificationShape obj then none
  else if validObject obj then some (dispatchReply obj)
  else some (.Error (-32600))

def evalBatch (xs : List RpcObject) : Option RpcReply :=
  match xs with
  | [] => some (.Error (-32600))
  | _ :: _ =>
    match xs.filterMap evalItem with
    | [] => none
    | replies => some (.Batch replies)

def envelopeReply : WireEnvelope → Option RpcReply
  | .MalformedJson => some (.Error (-32700))
  | .NonObject => some (.Error (-32600))
  | .Object obj => evalItem obj
  | .Array items => evalBatch items

theorem notification_always_silent (obj : RpcObject)
    (noId : obj.idField = .Absent) (_version : obj.version = "2.0")
    (method : obj.methodIsString = true) :
    envelopeReply (.Object obj) = none := by
  simp [envelopeReply, evalItem, notificationShape, noId, method]

theorem explicit_null_id_not_silent (obj : RpcObject)
    (nullId : obj.idField = .ExplicitNull) :
    ∃ reply, envelopeReply (.Object obj) = some reply := by
  unfold envelopeReply evalItem
  by_cases valid : validObject obj = true <;> simp [valid, nullId, notificationShape]

theorem empty_batch_invalid_request : evalBatch [] = some (.Error (-32600)) := rfl

theorem all_notification_batch_silent : ∀ xs, xs ≠ [] →
    (∀ x ∈ xs, evalItem x = none) → evalBatch xs = none := by
  intro xs nonempty silent
  have filtered : xs.filterMap evalItem = [] := by
    clear nonempty
    induction xs with
    | nil => rfl
    | cons x rest ih =>
      have hx : evalItem x = none := silent x (by simp)
      have hr : ∀ y ∈ rest, evalItem y = none := by
        intro y hy
        exact silent y (by simp [hy])
      simp [hx, ih hr]
  cases xs with
  | nil => contradiction
  | cons x xs => simpa [evalBatch] using congrArg (fun ys =>
      match ys with
      | [] => (none : Option RpcReply)
      | replies => some (.Batch replies)) filtered

inductive Outcome where
  | ParseError | InvalidRequest | Silent | MethodNotFound | InvalidParams | InternalError | Success
  deriving DecidableEq, Repr

def itemOutcome (obj : RpcObject) : Outcome :=
  if notificationShape obj then .Silent
  else if !validObject obj then .InvalidRequest
  else if !obj.knownMethod then .MethodNotFound
  else if !obj.paramsValid then .InvalidParams
  else if !obj.handlerOk then .InternalError
  else .Success

def singleOutcome : WireEnvelope → Outcome
  | .MalformedJson => .ParseError
  | .Object obj => itemOutcome obj
  | _ => .InvalidRequest

theorem seven_outcomes_total (e : WireEnvelope) :
    singleOutcome e = .ParseError ∨ singleOutcome e = .InvalidRequest ∨
    singleOutcome e = .Silent ∨ singleOutcome e = .MethodNotFound ∨
    singleOutcome e = .InvalidParams ∨ singleOutcome e = .InternalError ∨
    singleOutcome e = .Success := by
  cases singleOutcome e <;> simp

theorem seven_outcomes_disjoint (e : WireEnvelope) (a b : Outcome) (h : a ≠ b) :
    ¬ (singleOutcome e = a ∧ singleOutcome e = b) := by
  intro both
  exact h (both.1.symm.trans both.2)

-- J7: finite-key lookup equivalence is the canonical projection used here.
-- No hash function, key serializer or sorting algorithm is assumed verified.
def canonicalLookupProjection {α : Type} (obj : List (String × α)) : String → Option α :=
  fun k => lookupLast k obj

theorem canonical_key_order_invariance {α : Type}
    (o1 o2 : List (String × α)) (u1 : UniqueKeys o1) (u2 : UniqueKeys o2)
    (same : ∀ k, lookupFirst k o1 = lookupFirst k o2) :
    (∀ k, lookupLast k o1 = lookupLast k o2) ∧
      canonicalLookupProjection o1 = canonicalLookupProjection o2 := by
  have lastSame : ∀ k, lookupLast k o1 = lookupLast k o2 := by
    intro k
    rw [← unique_keys_eliminates_parser_differential o1 k u1,
        ← unique_keys_eliminates_parser_differential o2 k u2]
    exact same k
  exact ⟨lastSame, funext lastSame⟩

-- J8: outbound envelopes are constructed, never arbitrary raw member lists.
inductive OutboundEnvelope where
  | Success (id result : String)
  | Failure (id : String) (code : Int) (message : String)
  deriving DecidableEq, Repr

def mkSuccess (id res : String) : OutboundEnvelope := .Success id res
def mkError (id : String) (code : Int) (msg : String) : OutboundEnvelope :=
  .Failure id code msg

def version (_ : OutboundEnvelope) : String := "2.0"
def hasResult : OutboundEnvelope → Bool | .Success _ _ => true | .Failure _ _ _ => false
def hasError : OutboundEnvelope → Bool | .Success _ _ => false | .Failure _ _ _ => true

inductive OutboundValue where
  | Text (s : String) | ErrorObject (code : Int) (message : String)
  deriving DecidableEq, Repr

def toFields : OutboundEnvelope → List (String × OutboundValue)
  | .Success id res => [("jsonrpc", .Text "2.0"), ("id", .Text id), ("result", .Text res)]
  | .Failure id code msg =>
    [("jsonrpc", .Text "2.0"), ("id", .Text id), ("error", .ErrorObject code msg)]

theorem outbound_xor_and_unique_keys (env : OutboundEnvelope) :
    version env = "2.0" ∧ (hasResult env != hasError env) = true ∧ UniqueKeys (toFields env) := by
  cases env <;> simp [version, hasResult, hasError, UniqueKeys, toFields]

end UOS.McpJsonProcessingFormal

namespace UOS.McpJsonProcessingFormal

-- J2: two lexical spellings share the same post-unescape scalar check.
inductive ScalarSpelling where
  | raw (u : Nat) | escaped (u : Nat)

def decodedScalar : ScalarSpelling → Nat | .raw u => u | .escaped u => u

theorem raw_and_escaped_nul_both_rejected :
    validJsonScalar (decodedScalar (.raw 0)) = false ∧
    validJsonScalar (decodedScalar (.escaped 0)) = false := by decide

-- J3: a JSON AST/forest representation counts only containers, not siblings.
-- Object and array containers have the same pushdown-depth semantics.
inductive JsonForest where
  | scalar | object (children : JsonForest) | array (children : JsonForest)
  | siblings (left right : JsonForest)
  deriving DecidableEq, Repr

def forestDepth : JsonForest → Nat
  | .scalar => 0
  | .object children | .array children => 1 + forestDepth children
  | .siblings left right => max (forestDepth left) (forestDepth right)

def guardForest (maxD current : Nat) : JsonForest → Bool
  | .scalar => decide (current ≤ maxD)
  | .object children | .array children =>
      (current < maxD) && guardForest maxD (current + 1) children
  | .siblings left right => guardForest maxD current left && guardForest maxD current right

theorem accepted_ast_has_bounded_stack (maxD current : Nat) (ast : JsonForest)
    (accepted : guardForest maxD current ast = true) :
    current + forestDepth ast ≤ maxD := by
  induction ast generalizing current with
  | scalar => simpa [guardForest, forestDepth] using accepted
  | object children ih | array children ih =>
      simp only [guardForest, Bool.and_eq_true, decide_eq_true_eq] at accepted
      have childBound := ih (current + 1) accepted.2
      simp only [forestDepth]
      omega
  | siblings left right ihL ihR =>
      simp only [guardForest, Bool.and_eq_true] at accepted
      have leftBound := ihL current accepted.1
      have rightBound := ihR current accepted.2
      simp only [forestDepth]
      omega

theorem j3_accepted_json_depth_at_most_32 (ast : JsonForest)
    (accepted : guardForest 32 0 ast = true) : forestDepth ast ≤ 32 := by
  simpa using accepted_ast_has_bounded_stack 32 0 ast accepted

-- J4: the concrete witness uses an administrative second method.
theorem administrative_duplicate_smuggling_exists :
    ∃ obj : Obj, lookupFirst "method" obj ≠ lookupLast "method" obj := by
  exact ⟨[("method", "ping"), ("method", "admin")], by decide⟩

-- J5: exact integral members of mathematical binary64, with exponent zero.
-- An IEEE binary64 significand has 53 bits including its implicit leading bit;
-- every admitted integral value has a representative with exponent zero.
-- This is a mathematical representability model, not a primitive Float implementation proof.
abbrev SafeIJsonInteger := { n : Int // -ijsonMax ≤ n ∧ n ≤ ijsonMax }
structure ExactBinary64Integer where
  significand : Int
  bounded : -ijsonMax ≤ significand ∧ significand ≤ ijsonMax

def toExactBinary64 (n : SafeIJsonInteger) : ExactBinary64Integer :=
  ⟨n.val, n.property⟩
def fromExactBinary64 (n : ExactBinary64Integer) : SafeIJsonInteger :=
  ⟨n.significand, n.bounded⟩

theorem exact_binary64_integer_roundtrip (n : SafeIJsonInteger) :
    fromExactBinary64 (toExactBinary64 n) = n := by cases n; rfl

theorem exact_binary64_representative_roundtrip (n : ExactBinary64Integer) :
    toExactBinary64 (fromExactBinary64 n) = n := by cases n; rfl

theorem exact_binary64_safe_integer_bijection :
    (∀ a b, toExactBinary64 a = toExactBinary64 b → a = b) ∧
    (∀ b, ∃ a, toExactBinary64 a = b) := by
  constructor
  · intro a b same
    have := congrArg fromExactBinary64 same
    simpa [exact_binary64_integer_roundtrip] using this
  · intro b
    exact ⟨fromExactBinary64 b, exact_binary64_representative_roundtrip b⟩

-- J7: key-preserving permutation, rather than an assumed lookup equality.
theorem lookup_first_some_iff_mem {α : Type} (obj : List (String × α))
    (unique : UniqueKeys obj) (k : String) (v : α) :
    lookupFirst k obj = some v ↔ (k,v) ∈ obj := by
  induction obj with
  | nil => simp [lookupFirst]
  | cons pair rest ih =>
      rcases pair with ⟨key, val⟩
      have uniqueTail : UniqueKeys rest := (List.nodup_cons.mp unique).2
      have absent : key ∉ rest.map Prod.fst := (List.nodup_cons.mp unique).1
      by_cases same : k = key
      · subst k
        have pairAbsent : (key,v) ∉ rest := by
          intro h
          exact absent (List.mem_map.mpr ⟨(key,v), h, rfl⟩)
        simp [lookupFirst, pairAbsent, Prod.mk.injEq, eq_comm]
      · simp [lookupFirst, same, ih uniqueTail, Prod.mk.injEq]

theorem lookup_first_permutation {α : Type} (obj1 obj2 : List (String × α))
    (perm : obj1.Perm obj2) (unique : UniqueKeys obj1) (k : String) :
    lookupFirst k obj1 = lookupFirst k obj2 := by
  have unique2 : UniqueKeys obj2 := (perm.map Prod.fst).nodup_iff.mp unique
  cases h1 : lookupFirst k obj1 with
  | some v =>
      have member := (lookup_first_some_iff_mem obj1 unique k v).mp h1
      exact ((lookup_first_some_iff_mem obj2 unique2 k v).mpr (perm.mem_iff.mp member)).symm
  | none =>
      cases h2 : lookupFirst k obj2 with
      | none => rfl
      | some v =>
          have member := (lookup_first_some_iff_mem obj2 unique2 k v).mp h2
          have contra := (lookup_first_some_iff_mem obj1 unique k v).mpr (perm.mem_iff.mpr member)
          rw [h1] at contra
          contradiction

theorem canonical_projection_permutation_invariant {α : Type}
    (obj1 obj2 : List (String × α)) (perm : obj1.Perm obj2)
    (unique : UniqueKeys obj1) :
    canonicalLookupProjection obj1 = canonicalLookupProjection obj2 := by
  exact (canonical_key_order_invariance obj1 obj2 unique
    ((perm.map Prod.fst).nodup_iff.mp unique)
    (lookup_first_permutation obj1 obj2 perm unique)).2

end UOS.McpJsonProcessingFormal

namespace UOS.McpJsonProcessingFormal

-- A concrete sorted-key canonical representation; no sorting oracle assumed.
def sortedObjectKeys {α : Type} (obj : List (String × α)) : List String :=
  (obj.map Prod.fst).mergeSort (fun a b => decide (a ≤ b))

theorem sorted_object_keys_permutation_invariant {α : Type}
    (obj1 obj2 : List (String × α)) (perm : obj1.Perm obj2) :
    sortedObjectKeys obj1 = sortedObjectKeys obj2 := by
  have trans : ∀ (a b c : String), decide (a ≤ b) = true →
      decide (b ≤ c) = true → decide (a ≤ c) = true := by
    intro a b c hab hbc
    simp only [decide_eq_true_eq] at *
    exact String.le_trans hab hbc
  have total : ∀ (a b : String), (decide (a ≤ b) || decide (b ≤ a)) = true := by
    intro a b
    simpa using String.le_total a b
  apply List.Perm.eq_of_pairwise
    (le := fun a b : String => decide (a ≤ b) = true)
  · intro a b _ _ hab hba
    simp only [decide_eq_true_eq] at hab hba
    exact String.le_antisymm hab hba
  · exact List.pairwise_mergeSort trans total (obj1.map Prod.fst)
  · exact List.pairwise_mergeSort trans total (obj2.map Prod.fst)
  · exact ((List.mergeSort_perm _ _).trans (perm.map Prod.fst)).trans
      (List.mergeSort_perm _ _).symm

def canonicalize {α : Type} (obj : List (String × α)) : List (String × Option α) :=
  (sortedObjectKeys obj).map (fun k => (k,lookupFirst k obj))

theorem sorted_key_canonicalization_permutation_invariant {α : Type}
    (obj1 obj2 : List (String × α)) (perm : obj1.Perm obj2)
    (unique : UniqueKeys obj1) : canonicalize obj1 = canonicalize obj2 := by
  have keys := sorted_object_keys_permutation_invariant obj1 obj2 perm
  have values : (fun k => (k,lookupFirst k obj1)) =
      (fun k => (k,lookupFirst k obj2)) := by
    funext k
    rw [lookup_first_permutation obj1 obj2 perm unique k]
  simp only [canonicalize, keys, values]

-- Congruence transports the proven canonical identity through any deterministic
-- digest. This states no injectivity or cryptographic-strength property.
theorem canonical_digest_key_order_invariance {α β : Type}
    (digest : List (String × Option α) → β)
    (obj1 obj2 : List (String × α)) (perm : obj1.Perm obj2)
    (unique : UniqueKeys obj1) : digest (canonicalize obj1) = digest (canonicalize obj2) :=
  congrArg digest (sorted_key_canonicalization_permutation_invariant obj1 obj2 perm unique)

end UOS.McpJsonProcessingFormal

namespace UOS.McpJsonProcessingFormal
-- Silence is imposed before method/envelope validation, including unknown
-- methods, invalid version and non-object parameters, as required by ingress.
theorem notification_silent_even_when_validation_fails (obj : RpcObject)
    (noId : obj.idField = .Absent) (method : obj.methodIsString = true) :
    evalItem obj = none := by
  simp [evalItem, notificationShape, noId, method]
end UOS.McpJsonProcessingFormal
