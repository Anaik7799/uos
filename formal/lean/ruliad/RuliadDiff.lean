/-
# RuliadDiff — the Lean side of the model-to-source differential oracle

`Ruliad.Multiway` claims to model `apps/cepaf_gleam/src/cepaf_gleam/ecology/multiway.gleam`.
The journal graded that claim **C3** — hand transcription, nothing mechanically
checked — and named this oracle as the way to raise it. This executable runs the
Lean model over a shared corpus and prints a canonical line per case; the
Erlang harness in `diff/` runs the deployed Gleam engine over the same corpus
and prints the same format. A disagreement is a real divergence, in one
direction or the other.
-/
import Ruliad.Multiway

open Ruliad.Multiway

/-- Canonical rendering: order-sensitive, so a same-set/different-order
divergence is visible rather than hidden by sorting. -/
def renderWord (w : Word) : String := String.ofList w

def renderGraph (g : Graph) : String :=
  let states := String.intercalate "," (g.states.map renderWord)
  let edges := String.intercalate ","
    (g.edges.map fun e =>
      renderWord e.source ++ ">" ++ renderWord e.target ++ "@" ++
      toString e.rule ++ ":" ++ toString e.offset)
  let frontier := String.intercalate "," (g.frontier.map renderWord)
  "OK states=[" ++ states ++ "] edges=[" ++ edges ++ "] frontier=[" ++ frontier ++
    "] steps=" ++ toString g.steps

def parseRules (s : String) : List Rule :=
  if s.isEmpty then []
  else
    (s.splitOn ",").map fun spec =>
      match spec.splitOn ">" with
      | [a, b] => { lhs := a.toList, rhs := b.toList }
      | _ => { lhs := spec.toList, rhs := [] }

/-- `String.trim` is not in this core; digits are extracted explicitly. -/
def digitsOf (s : String) : String := String.ofList (s.toList.filter Char.isDigit)

def isBlank (s : String) : Bool :=
  s.toList.all fun c => c == ' ' || c == '\r' || c == '\n' || c == '\t'

def runCase (line : String) : String :=
  match line.splitOn "\t" with
  | [seed, rulespec, stepsStr] =>
    let stepsClean := digitsOf stepsStr
    let steps := stepsClean.toNat!
    let rules := parseRules rulespec
    let verdict :=
      match explore seed.toList rules steps with
      | .ok g => renderGraph g
      | .error e => "ERR " ++ e
    seed ++ "\t" ++ rulespec ++ "\t" ++ stepsClean ++ "\t" ++ verdict
  | _ => "BADLINE " ++ line

def main (args : List String) : IO Unit := do
  let path := args.headD "diff/corpus.tsv"
  let text ← IO.FS.readFile path
  for line in text.splitOn "\n" do
    if !isBlank line then
      IO.println (runCase line)
