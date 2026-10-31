/- INV-FRESH-4100-01 / INV-MCP-KM-BRAIN-01.
   Executable specification of stateless projection; implementation conformance
   is established separately by hermetic HTTP/MCP falsifiers.
   #fractal-l0 #fractal-l5 #fractal-l8 #zk-adr #zero-muda -/
namespace UOS.KmTriadAlwaysFreshMemory
abbrev Bytes := List UInt8
abbrev Disk := String → Option Bytes
structure PathPolicy where
  allowlisted : Bool
  isSymlink : Bool
  nlinks : Nat
  deriving DecidableEq
inductive Reply where
  | ok (bytes : Bytes) (digest : Bytes)
  | notFound404
  | forbidden403
  | unavailable503
  deriving DecidableEq

def project (hash : Bytes → Bytes) (disk : Disk) (path : String)
    (policy : PathPolicy) : Reply :=
  if !policy.allowlisted || policy.isSymlink || policy.nlinks > 1 then
    .forbidden403
  else match disk path with
    | none => .notFound404
    | some bytes => .ok bytes (hash bytes)

def write (disk : Disk) (path : String) (bytes : Bytes) : Disk :=
  fun key => if key = path then some bytes else disk key

def delete (disk : Disk) (path : String) : Disk :=
  fun key => if key = path then none else disk key

def regular : PathPolicy := ⟨true, false, 1⟩

theorem zero_staleness_read_after_write (hash : Bytes → Bytes)
    (disk : Disk) (path : String) (bytes : Bytes) :
    project hash (write disk path bytes) path regular = .ok bytes (hash bytes) := by
  simp [project, write, regular]

theorem zero_staleness_delete_not_found (hash : Bytes → Bytes)
    (disk : Disk) (path : String) :
    project hash (delete disk path) path regular = .notFound404 := by
  simp [project, delete, regular]

theorem allowlist_and_link_non_interference (hash : Bytes → Bytes)
    (disk : Disk) (path : String) (policy : PathPolicy)
    (hazard : policy.allowlisted = false ∨ policy.isSymlink = true ∨ policy.nlinks > 1) :
    project hash disk path policy = .forbidden403 := by
  rcases hazard with h | h | h
  · simp [project, h]
  · simp [project, h]
  · simp [project, h]

structure Probe where
  status : Nat
  soft404 : Bool
  noStore : Bool
  sha256Matches : Bool

def accepts (p : Probe) : Prop :=
  p.status = 200 ∧ p.soft404 = false ∧ p.noStore = true ∧ p.sha256Matches = true

theorem verifier_no_soft404_false_green (p : Probe) :
    accepts p ↔ p.status = 200 ∧ p.soft404 = false ∧ p.noStore = true ∧ p.sha256Matches = true := by
  rfl

inductive Stage where
  | predict | observe | orient | decide | act | verify | reflect
  deriving DecidableEq
inductive Worker where
  | running | restarting
  deriving DecidableEq

def evaluate (hash : Bytes → Bytes) (disk : Disk) (path : String)
    (policy : PathPolicy) (canonicalIntact : Bool) : Stage → Worker → Reply
  | _, _ => if canonicalIntact then project hash disk path policy else .unavailable503

theorem mcp_brain_memory_total_availability (hash : Bytes → Bytes)
    (disk : Disk) (path : String) (policy : PathPolicy) (intact : Bool)
    (stage : Stage) (worker : Worker) :
    ∃ reply, evaluate hash disk path policy intact stage worker = reply ∧
      (intact = false → reply = .unavailable503) := by
  refine ⟨evaluate hash disk path policy intact stage worker, rfl, ?_⟩
  intro h
  simp [evaluate, h]
end UOS.KmTriadAlwaysFreshMemory
