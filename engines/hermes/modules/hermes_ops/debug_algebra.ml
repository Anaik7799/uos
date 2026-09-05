type verdict = Unavailable | Stale | Contradicted | Open | Established | Corrected | Verified | Closed
type failure_effect = Blocks_credit | Denies_credit
let evidence_union left right =
  left @ right
  |> List.sort_uniq (fun left right ->
         String.compare
           (Debug_ontology.canonical_observation left)
           (Debug_ontology.canonical_observation right))

let eliminate hypotheses eliminated =
  List.filter
    (fun (item : Debug_ontology.hypothesis) ->
      not (List.mem item.hypothesis_id eliminated))
    hypotheses

let verdict_rank = function
  | Unavailable -> 0 | Contradicted -> 1 | Stale -> 2 | Open -> 3
  | Established -> 4 | Corrected -> 5 | Verified -> 6 | Closed -> 7

let join_verdict left right =
  if verdict_rank left <= verdict_rank right then left else right

let failure_effect = function
  | Ops_capability.Implementation -> Denies_credit
  | Specification | Environment | Evidence | Control -> Blocks_credit
