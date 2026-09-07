type level = Product | Feature | Requirement | Acceptance
type node = { id : string; parent : string option; level : level; required : bool }
let rank_level = function Product -> 0 | Feature -> 1 | Requirement -> 2 | Acceptance -> 3
let validate_nodes nodes =
  let ids = List.map (fun n -> n.id) nodes in
  if nodes = [] || List.length nodes > 10000 then Error "empty or oversized hierarchy"
  else if List.exists (fun id -> String.trim id = "") ids then Error "blank node id"
  else if List.length ids <> List.length (List.sort_uniq String.compare ids) then Error "duplicate node id"
  else if List.length (List.filter (fun n -> n.level = Product) nodes) <> 1 then Error "exactly one product root required"
  else if List.exists (fun n -> match n.parent with
    | None -> n.level <> Product
    | Some p -> match List.find_opt (fun x -> x.id = p) nodes with
      | None -> true | Some parent -> rank_level parent.level + 1 <> rank_level n.level) nodes
    then Error "missing parent, cycle or invalid level"
  else if List.exists (fun n -> n.required && n.level <> Acceptance &&
    not (List.exists (fun child -> child.parent = Some n.id && child.required) nodes)) nodes
    then Error "required node has no required children"
  else Ok ()

type binding = {
  candidate : string; specification : string; oracle : string;
  executable : string; normalizer : string; checker : string;
}
type kind = Runtime | Formal
type receipt = {
  case_id : string; kind : kind; binding : binding; sequence : int;
  observed : float; expires : float; passed : bool;
  artifact_valid : bool; invocation_valid : bool;
}
type state = Unrun | Stale | Blocked | Failed | Passed
type verdict = { state : state; reasons : string list }
let state_name = function Unrun -> "UNRUN" | Stale -> "STALE" | Blocked -> "BLOCKED" | Failed -> "FAILED" | Passed -> "PASSED"
let severity = function Passed -> 0 | Unrun -> 1 | Stale -> 2 | Blocked -> 3 | Failed -> 4
let roll_up verdicts = match verdicts with
  | [] -> { state = Unrun; reasons = ["No required evidence; empty sets cannot pass."] }
  | x :: xs ->
    { state = List.fold_left (fun acc v -> if severity v.state > severity acc then v.state else acc) x.state xs;
      reasons = List.concat_map (fun v -> v.reasons) verdicts |> List.sort_uniq String.compare }
let eligible_bits bits = List.length bits = 9 && not (List.mem false bits)
let evaluate_case ~now ~source_current ~expected ~case_id receipts =
  let verdict state reason = { state; reasons = [reason] } in
  if not source_current then verdict Stale "Candidate source manifest has changed."
  else if List.exists (fun s -> String.trim s = "") [expected.candidate;expected.specification;expected.oracle;expected.executable;expected.normalizer;expected.checker]
    then verdict Blocked "Expected evidence identity is incomplete."
  else
    let one kind =
      let matching = List.filter (fun r -> r.case_id = case_id && r.kind = kind) receipts
        |> List.sort (fun a b -> Int.compare b.sequence a.sequence) in
      match matching with
      | [] -> verdict Unrun (if kind = Runtime then "Runtime receipt missing." else "Formal receipt missing.")
      | r :: rest ->
        let admissible = eligible_bits [r.binding = expected;
          not (List.exists (fun x -> x.sequence = r.sequence) rest);
          Float.is_finite now && Float.is_finite r.observed && Float.is_finite r.expires && r.observed <= now && r.expires > r.observed;
          r.expires > now; r.artifact_valid; r.invocation_valid; r.sequence > 0; r.passed; source_current] in
        if List.exists (fun x -> x.sequence = r.sequence) rest then verdict Blocked "Ambiguous receipt sequence."
        else if r.binding <> expected then verdict Stale "Candidate, specification, oracle, executable, normalizer or checker mismatch."
        else if not (Float.is_finite now && Float.is_finite r.observed && Float.is_finite r.expires)
          || r.observed > now || r.expires <= r.observed || r.sequence <= 0
          then verdict Blocked "Invalid receipt time or sequence."
        else if r.expires <= now then verdict Stale "Receipt expired."
        else if not (r.artifact_valid && r.invocation_valid) then verdict Blocked "Artifact or invocation integrity failed."
        else if not r.passed then verdict Failed "Latest matching execution failed."
        else if admissible then { state = Passed; reasons = [] }
        else verdict Blocked "Eligibility predicate withheld evidence."
    in roll_up [one Runtime;one Formal]
