/-
# ServiceDiff — oracle for the deployed merge classifier

Second arm of the model-to-source differential oracle. `Ruliad.Service.classify`
claims to model `inference_api.evaluate_ruliad_branch`. This executable runs the
Lean model over a shared corpus; `diff/service_diff.erl` runs the deployed Gleam
function over the same corpus and prints the same format.

**Decisions, not raw floats.** The deployed record carries `Float` fields
(`1.25`, `0.85`); the model carries `ℚ` (`5/4`, `17/20`). Those are the same
values in different representations, so comparing their printed forms would
report a representation artefact as a divergence. What is compared instead is
everything the theorems in `Ruliad.Service` actually assert: which branch of the
table fired, the merge verdict (`conflict < 1/2`), whether the entropy constant
clears the 2.50-bit gate, the record id, and the collapse path.

No square brackets appear in the output, so the classifier cannot excuse an
ordering difference in the collapse path as `ORDER_ONLY` — path order is
load-bearing here and any difference is a divergence.
-/
import Ruliad.Service

open Ruliad.Service

def splitField (s : String) : List String :=
  if s.isEmpty then [] else s.splitOn "|"

def renderReport (r : BranchReport) : String :=
  "status=" ++ r.convergenceStatus ++
  " mergeable=" ++ toString (decide (mergeable r)) ++
  " entropy_lt_gate=" ++ toString (decide (r.branchialEntropy < 5 / 2)) ++
  " id=" ++ r.id ++
  " path=" ++ String.intercalate "/" r.optimalCollapsePath ++
  " agents=" ++ String.intercalate "/" r.participatingAgents

def runCase (line : String) : String :=
  match line.splitOn "\t" with
  | [src, tgt, changes, agents] =>
    let r := classify src tgt (splitField changes) (splitField agents)
    src ++ "\t" ++ tgt ++ "\t" ++ changes ++ "\t" ++ agents ++ "\t" ++ renderReport r
  | _ => "BADLINE " ++ line

def isBlankLine (s : String) : Bool :=
  s.toList.all fun c => c == ' ' || c == '\r' || c == '\n' || c == '\t'

def main (args : List String) : IO Unit := do
  let path := args.headD "diff/service_corpus.tsv"
  let text ← IO.FS.readFile path
  for line in text.splitOn "\n" do
    if !isBlankLine line then
      IO.println (runCase line)
