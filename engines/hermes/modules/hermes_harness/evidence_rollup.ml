(* The live actual for the declarative-intent layer: per-node verdicts rolled up
   from the store's latest parity results. Pure over (contract_id, passed) rows;
   the node is the contract's first two dotted components under the hermes root;
   scenario verdicts (Verified/Divergent) roll up per node with the parity
   algebra, and absence is Unmapped -- never a silent pass. *)

let node_of_contract contract =
  match String.split_on_char '.' contract with
  | family :: capability :: _ -> "hermes." ^ family ^ "." ^ capability
  | _ -> "hermes." ^ contract

let per_node rows =
  let nodes =
    List.sort_uniq compare (List.map (fun (contract, _) -> node_of_contract contract) rows)
  in
  List.map
    (fun node ->
      let verdicts =
        rows
        |> List.filter (fun (contract, _) -> node_of_contract contract = node)
        |> List.map (fun (_, passed) ->
               if passed then Parity_algebra.Verified else Parity_algebra.Divergent)
      in
      (node, Parity_algebra.roll_up ~required:true verdicts))
    nodes

let actual_of nodes node =
  match List.assoc_opt node nodes with Some verdict -> verdict | None -> Parity_algebra.Unmapped

(* Family-level evidence: a family node rolls up over ALL its capability nodes,
   an uncovered capability counting as Unmapped -- Verified only when every
   slice is (the vacuous-truth guard at family scale). The product root rolls
   over the family verdicts the same way. *)
let family_verdicts ~catalog ~nodes =
  let node_verdict node = actual_of nodes node in
  let families =
    List.map
      (fun (family, capability_nodes) ->
        ( "hermes." ^ family,
          Parity_algebra.roll_up ~required:true (List.map node_verdict capability_nodes) ))
      catalog
  in
  let product =
    Parity_algebra.roll_up ~required:true (List.map snd families)
  in
  families @ [ ("hermes", product) ]

let actual_with_families ~catalog ~nodes target =
  match List.assoc_opt target nodes with
  | Some verdict -> verdict
  | None -> (
      match List.assoc_opt target (family_verdicts ~catalog ~nodes) with
      | Some verdict -> verdict
      | None -> Parity_algebra.Unmapped)

let live store ~snapshot_digest =
  match Evidence_store.parity_results store ~snapshot_digest with
  | Error message -> Error message
  | Ok rows -> Ok (actual_of (per_node rows))
