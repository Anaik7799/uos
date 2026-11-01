/-
  DEVELOPMENT PROTOTYPE; UNSAFE FOR UNTRUSTED MODULES.

  An imported module initializer can exit successfully before this helper runs,
  and an imported command elaborator can suppress a `run_elab` invocation.
  A normal Lean exit or output marker therefore cannot establish that this
  function executed. Do not use this prototype as a proof-admission gate.

  A trusted test caller may import the target module and this helper, then supply
  the exact target module and theorem names. This is not an MCP tool, a process
  sandbox, an import-closure verifier, a check of intended theorem statements,
  or a proof of source/runtime refinement. A trusted wrapper must separately
  typecheck each requested theorem against its intended statement.
  No caller-controlled allowlist is accepted. Lean's foundational axioms are
  the only permitted transitive axioms. Custom axioms and incomplete
  declarations in the target module are rejected even when no requested
  theorem depends on them. Unused axioms in other imported modules are not
  covered by this prototype.
-/

import Lean.Elab.BuiltinEvalCommand
import Lean.Util.CollectAxioms

open Lean Elab Command

namespace UOS.HarnessAxiomAudit

private def allowedAxiom (name : Name) : Bool :=
  [`propext, `Classical.choice, `Quot.sound].contains name

/- `Lean.collectAxioms` treats an unknown constant as contributing no axioms.
   Walk the kernel environment first and refuse any missing reachable name.
   This is a bounded structural check, not a kernel replay of imported data. -/
private partial def resolvedClosure (env : Environment) (pending : List Name)
    (seen : NameSet) (remaining : Nat) : Except String Unit := do
  match pending with
  | [] => pure ()
  | name :: rest =>
      if seen.contains name then
        resolvedClosure env rest seen remaining
      else if remaining == 0 then
        throw "declaration dependency limit exceeded"
      else
        let some info := env.toKernelEnv.find? name
          | throw s!"unresolved declaration dependency: {name}"
        let mut dependencies := info.getUsedConstantsAsSet
        match info with
        | .inductInfo value =>
            for sibling in value.all do
              dependencies := dependencies.insert sibling
        | .ctorInfo value =>
            dependencies := dependencies.insert value.induct
        | .recInfo value =>
            for rule in value.rules do
              dependencies := dependencies.insert rule.ctor
              dependencies := dependencies ++ rule.rhs.getUsedConstantsAsSet
        | _ => pure ()
        resolvedClosure env (dependencies.toArray.toList ++ rest)
          (seen.insert name) (remaining - 1)

def check [Monad m] [MonadEnv m] [MonadError m]
    (targetModule : Name) (theorems : Array Name) : m Unit := do
  if theorems.isEmpty then
    throwError "audit requires at least one theorem"
  if theorems.toList.eraseDups.length != theorems.size then
    throwError "audit theorem list contains duplicates"
  let env ← getEnv
  let some targetIndex := env.getModuleIdx? targetModule
    | throwError "audit target module is not imported: {targetModule}"
  let targetNames := env.constants.toList.filterMap fun (name, _) =>
    if env.getModuleIdxFor? name == some targetIndex then some name else none
  match resolvedClosure env targetNames {} 500000 with
  | .ok () => pure ()
  | .error reason => throwError "{reason}"
  for (name, info) in env.constants.toList do
    if env.getModuleIdxFor? name == some targetIndex then
      match info with
      | .axiomInfo _ =>
          unless allowedAxiom name do
            throwError "target module declares forbidden axiom: {name}"
      | _ => pure ()
  for (name, _) in env.constants.toList do
    if env.getModuleIdxFor? name == some targetIndex then
      let axioms ← collectAxioms name
      for axiomName in axioms do
        unless allowedAxiom axiomName do
          throwError "target declaration {name} depends on forbidden axiom: {axiomName}"
  for theoremName in theorems do
    let some info := env.find? theoremName
      | throwError "audit theorem is missing: {theoremName}"
    match info with
    | .thmInfo _ => pure ()
    | _ => throwError "audit target is not a theorem: {theoremName}"
    unless env.getModuleIdxFor? theoremName == some targetIndex do
      throwError "audit theorem is not defined in target module: {theoremName}"
    let axioms ← collectAxioms theoremName
    for axiomName in axioms do
      unless allowedAxiom axiomName do
        throwError "theorem {theoremName} depends on forbidden axiom: {axiomName}"

end UOS.HarnessAxiomAudit
