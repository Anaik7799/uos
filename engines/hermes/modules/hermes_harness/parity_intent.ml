(* The harness's comprehensive parity intent -- the canonical Blueprint shared by
   run_config (reconcile) and ruliad_frontier (multiway exploration). Each
   directive's comment is its textual intent (the declarative-mode contract). *)

let blueprint : Blueprint.t =
  Blueprint.
    [ (* L0: the product itself. Honest expectation: Unmapped today (strict
         parity is 0%), so this DRIFTS until families verify end to end. *)
      { id = "product"; target = "hermes";
        desired = Parity_algebra.Verified;
        intent = "the whole product reaches differential parity with the frozen reference";
        requires = [ "routing_family" ] };
      (* L1: the first family being driven to completion. *)
      { id = "routing_family"; target = "hermes.model_routing";
        desired = Parity_algebra.Verified;
        intent = "every model_routing capability slice carries differential evidence";
        requires = [ "transports"; "retry"; "route"; "anthropic" ] };
      (* L2: the covered slices, each with its own rationale. *)
      { id = "transports"; target = "hermes.model_routing.provider_transports";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen provider-transport request shaping and response decoding";
        requires = [] };
      { id = "budget"; target = "hermes.agent_loop.interrupt_control";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen IterationBudget consume/refund/remaining semantics";
        requires = [] };
      { id = "paths"; target = "hermes.tool_execution.path_and_url_safety";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen path-traversal and url-safety predicates";
        requires = [] };
      { id = "retry"; target = "hermes.model_routing.rate_and_retry";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen Retry-After parsing deterministic branches";
        requires = [ "transports" ] };
      { id = "route"; target = "hermes.model_routing.route_resolution";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen fallback-chain resolver (coerce/normalize/dedup)";
        requires = [ "transports" ] };
      { id = "anthropic"; target = "hermes.model_routing.anthropic_adapter";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen Anthropic tool/model shaping and schema sanitizer";
        requires = [ "transports" ] } ]

(* The family catalog: each family with all its capability node ids -- the shape
   Evidence_rollup.family_verdicts rolls up over (an uncovered slice counts
   Unmapped, so a family verifies only when whole). *)
let family_catalog =
  List.fold_left
    (fun acc (c : Capability_catalog.capability) ->
      let family = c.Capability_catalog.family_id in
      let node = Capability_catalog.node_id c in
      match List.assoc_opt family acc with
      | Some nodes -> (family, node :: nodes) :: List.remove_assoc family acc
      | None -> (family, [ node ]) :: acc)
    [] Capability_catalog.all
  |> List.map (fun (family, nodes) -> (family, List.rev nodes))
  |> List.rev

(* Targets must resolve in the real fractal: capability nodes from the catalog,
   family nodes above them, and the product root. *)
let resolver =
  let nodes =
    List.concat_map
      (fun (c : Capability_catalog.capability) ->
        [ Capability_catalog.node_id c; Capability_catalog.parent_node_id c ])
      Capability_catalog.all
  in
  let known = List.sort_uniq compare ("hermes" :: nodes) in
  fun target -> List.mem target known
