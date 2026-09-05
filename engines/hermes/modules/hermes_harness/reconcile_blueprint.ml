(* The harness's own parity goal, expressed as a declarative, intent-based
   blueprint, reconciled against the measured state -- a Terraform-style plan:
   what we intend, where reality drifts, and by how much. Report-only.

   Each directive's OCaml comment is the textual intent (the WHY); the record is
   the executable desired state (the HOW), targeting a fractal ontology/atlas node
   and a Parity_algebra verdict (the fractal algebra). *)

let parity_intent : Blueprint.t =
  Blueprint.
    [ (* Proven: the OpenRouter provider transport reproduces the frozen
         reference's request shaping and response decoding. *)
      { id = "provider_transports";
        target = "hermes.model_routing.provider_transports";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen provider-transport request shaping and response decoding";
        requires = [] };
      (* Proven bar one deliberate, documented divergence: the candidate
         Turn_budget matches the frozen IterationBudget. *)
      { id = "interrupt_control";
        target = "hermes.agent_loop.interrupt_control";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen IterationBudget consume/refund/remaining semantics";
        requires = [] };
      (* Proven: the path-safety traversal predicate. *)
      { id = "path_safety";
        target = "hermes.tool_execution.path_and_url_safety";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen has_traversal_component path predicate";
        requires = [] };
      (* Intended, not yet evidenced: the Retry-After parser (candidate exists,
         differential machinery pending). *)
      { id = "rate_and_retry";
        target = "hermes.model_routing.rate_and_retry";
        desired = Parity_algebra.Verified;
        intent = "reproduce the frozen Retry-After parsing deterministic branches";
        requires = [ "provider_transports" ] } ]

(* The measured state -- the per-slice evidence roll-up. interrupt_control rolls
   up to Divergent because budget.negative is a proved (deliberate) divergence. *)
let actual = function
  | "hermes.model_routing.provider_transports" -> Parity_algebra.Verified
  | "hermes.agent_loop.interrupt_control" -> Parity_algebra.Divergent
  | "hermes.tool_execution.path_and_url_safety" -> Parity_algebra.Verified
  | _ -> Parity_algebra.Unmapped

let () =
  match Blueprint.validate parity_intent with
  | Error errors ->
      List.iter (fun e -> prerr_endline (Blueprint.describe_error e)) errors;
      exit 1
  | Ok () ->
      let plan = Blueprint.reconcile parity_intent ~actual in
      Printf.printf "parity blueprint -- desired-state reconciliation (report-only)\n\n";
      List.iter
        (fun (r : Blueprint.reconciled) ->
          match r.outcome with
          | Blueprint.Satisfied -> Printf.printf "  %-20s SATISFIED\n" r.directive.Blueprint.id
          | Blueprint.Drift _ ->
              Printf.printf "  %-20s DRIFT\n%s\n" r.directive.Blueprint.id
                (match r.diagnostic with
                | Some d -> Fractal_diagnostic.render d
                | None -> ""))
        plan;
      Printf.printf "\n%s%s\n" (Blueprint.summary plan)
        (if Blueprint.converged plan then " (converged)" else " (drift remains)")
