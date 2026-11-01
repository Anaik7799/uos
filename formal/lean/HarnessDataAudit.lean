/-
  Development-only data-import audit driver. It does not create MCP receipts,
  bind source/import hashes, replay the Lean kernel, or isolate its own process.

  Unlike a wrapper parsed after importing the target, this trusted driver calls
  Lean's module API with extensions disabled and no plugins. The caller must
  supply an independently trusted source/olean snapshot and expected-statement
  module. Before admission, separately kernel-check the complete artifact
  closure and verify driver, toolchain, inputs, output and containment.
-/

import HarnessAxiomAudit
import Lean.CoreM
import Lean.Util.Path

open Lean

private def reservedRoots : List String := ["Init", "Lean", "Std", "Lake"]

private def reservedEntry (name : String) : Bool :=
  reservedRoots.any fun root => name == root || name.startsWith (root ++ ".")

unsafe def main (args : List String) : IO UInt32 := do
  let [sysrootText, artifactDirText, moduleText, theoremText, specModuleText, specText] := args
    | throw <| IO.userError "expected sysroot, artifact directory, module, theorem, spec module and spec declaration"
  let moduleName := moduleText.toName
  let theoremName := theoremText.toName
  let specModule := specModuleText.toName
  let specName := specText.toName
  if moduleName.isAnonymous || theoremName.isAnonymous || specModule.isAnonymous || specName.isAnonymous then
    throw <| IO.userError "anonymous audit identity"
  if moduleName == specModule then
    throw <| IO.userError "expected-statement module must be separate"
  if reservedRoots.contains moduleName.getRoot.toString ||
      reservedRoots.contains specModule.getRoot.toString then
    throw <| IO.userError "reserved target or expected-statement module"
  let artifactDir : System.FilePath := ⟨artifactDirText⟩
  let entries ← artifactDir.readDir
  if entries.size > 4096 then
    throw <| IO.userError "artifact directory entry limit exceeded"
  if entries.any (fun entry => reservedEntry entry.fileName) then
    throw <| IO.userError "reserved module shadow in artifact directory"
  let builtin ← getBuiltinSearchPath ⟨sysrootText⟩
  searchPathRef.set (builtin ++ [artifactDir])
  let env ← importModules (loadExts := false) (plugins := #[])
    #[{ module := moduleName }, { module := specModule }] {} 0
  let some targetIndex := env.getModuleIdx? moduleName
    | throw <| IO.userError "target module missing"
  let some specIndex := env.getModuleIdx? specModule
    | throw <| IO.userError "expected-statement module missing"
  let some (.thmInfo theoremInfo) := env.find? theoremName
    | throw <| IO.userError "target is not a theorem"
  unless env.getModuleIdxFor? theoremName == some targetIndex do
    throw <| IO.userError "theorem module mismatch"
  let some (.axiomInfo specInfo) := env.find? specName
    | throw <| IO.userError "expected statement is not a spec declaration"
  unless env.getModuleIdxFor? specName == some specIndex do
    throw <| IO.userError "expected-statement module mismatch"
  if theoremInfo.levelParams.length != specInfo.levelParams.length then
    throw <| IO.userError "theorem universe arity mismatch"
  if theoremInfo.levelParams.eraseDups.length != theoremInfo.levelParams.length ||
      specInfo.levelParams.eraseDups.length != specInfo.levelParams.length then
    throw <| IO.userError "duplicate universe parameters"
  let renamedSpec := specInfo.type.instantiateLevelParams specInfo.levelParams
    (theoremInfo.levelParams.map Level.param)
  unless theoremInfo.type == renamedSpec do
    throw <| IO.userError "theorem statement mismatch"
  let _ ← (UOS.HarnessAxiomAudit.check moduleName #[theoremName] : CoreM Unit).toIO
    { fileName := "<harness-data-audit>", fileMap := default } { env := env }
  IO.println s!"AXIOM_METADATA_CHECKED_NO_KERNEL_REPLAY module={moduleName} theorem={theoremName}"
  return 0
