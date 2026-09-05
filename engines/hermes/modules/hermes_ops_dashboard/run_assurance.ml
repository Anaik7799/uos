type decision = Admit | Block of string list

let required_gates = Run_safety.Assurance_evaluator.required_gates

let evaluate_inputs context receipts =
  match Run_safety.Assurance_evaluator.evaluate context receipts with
  | Error errors -> Error errors
  | Ok evaluation ->
      let decision =
        if evaluation.admitted then Admit else Block evaluation.reasons
      in
      Ok (decision, evaluation.receipt)

type gate_input =
  | Safety_input of Run_safety.model * Run_safety.receipt
  | Rete_input of
      Run_intelligence.Rete_ul.network *
      Run_intelligence.Rete_ul.fact list *
      Run_intelligence.Rete_ul.dispatch_receipt
  | Raven_input of
      Run_intelligence.Raven_matrix.matrix *
      Run_intelligence.Raven_matrix.receipt
  | Ruliad_input of
      Run_analysis.Ruliad.system * Run_analysis.Ruliad.bounds *
      Run_analysis.Ruliad.receipt
  | Stan_input of Run_analysis.Stan_model.input * Run_analysis.Stan_model.receipt
  | Z3_input of
      Run_analysis.Z3.campaign_envelope *
      Run_analysis.Z3.cli_configuration * Run_analysis.Z3.receipt
  | Z3_unavailable_input of Run_safety.receipt

type receipt = {
  context_digest : string;
  current_head_digest : string;
  current_at_ns : int64;
  safety_receipt_digest : string;
  rete_receipt_digest : string;
  raven_receipt_digest : string;
  ruliad_receipt_digest : string;
  stan_receipt_digest : string;
  z3_receipt_digest : string;
  load_bearing_digest : string;
  completeness_digest : string;
  receipt_digest : string;
}

type inputs = {
  ordered_inputs : gate_input list;
  receipt : receipt;
}

type admitted_bundle = {
  authority : Run_safety.authority;
  context_digest : string;
  current_head_digest : string;
  current_at_ns : int64;
  inputs : inputs;
  receipt : receipt;
  bundle_digest : string;
}

let unavailable context message =
  Error
    [ Run_safety.make_gate_error context ~code:Run_safety.Invalid_receipt
        ~message ~rca_origin:Ops_capability.Control
        ~hazard_id:"HZ-T6-ASSURANCE-01" ]

let error context message =
  Run_safety.make_gate_error context ~code:Run_safety.Invalid_receipt
    ~message ~rca_origin:Ops_capability.Evidence
    ~hazard_id:"HZ-T6-ASSURANCE-01"

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = Printf.sprintf "%d:%s" (String.length value) value

let digest_fields fields =
  fields |> List.map frame |> String.concat "" |> sha256

let validate_safety context model receipt =
  match Run_safety.validate_receipt ~context receipt with
  | Error _ as failure -> failure
  | Ok () ->
      begin match Run_safety.evaluate context model with
      | Error _ as failure -> failure
      | Ok (Run_safety.Admit, expected)
        when receipt.gate = Run_safety.Stpa_fmea
             && receipt.authority = Run_safety.Load_bearing_dispatch_gate
             && receipt.outcome = Run_safety.Satisfied
             && expected = receipt ->
          Ok ()
      | Ok (Run_safety.Admit, _) | Ok (Run_safety.Block _, _) ->
          Error
            (error context
               "STPA/FMEA receipt does not exactly match a satisfied source model")
      end

let validate_unavailable_z3 context receipt =
  match Run_safety.validate_receipt ~context receipt with
  | Error _ as failure -> failure
  | Ok () ->
      if receipt.gate = Run_safety.Z3
         && receipt.authority = Run_safety.Load_bearing_dispatch_gate
         && match receipt.outcome with
            | Run_safety.Unavailable_observed _ -> true
            | Run_safety.Satisfied | Run_safety.Rejected _ -> false
      then Ok ()
      else
        Error
          (error context
             "deferred Z3 evidence must be an exact unavailable Z3 receipt")

let result_error = function Ok () -> None | Error issue -> Some issue

let make_receipt (context : Run_safety.gate_context) ~safety_receipt_digest ~rete_receipt_digest
    ~raven_receipt_digest ~ruliad_receipt_digest ~stan_receipt_digest
    ~z3_receipt_digest =
  let load_bearing_digest =
    digest_fields
      [ "run-assurance-load-bearing-v1"; safety_receipt_digest;
        rete_receipt_digest; raven_receipt_digest; z3_receipt_digest ]
  in
  let completeness_digest =
    digest_fields
      [ "run-assurance-completeness-v1"; load_bearing_digest;
        ruliad_receipt_digest; stan_receipt_digest ]
  in
  let provisional =
    { context_digest = context.Run_safety.context_digest;
      current_head_digest = context.current_head_digest;
      current_at_ns = context.current_at_ns; safety_receipt_digest;
      rete_receipt_digest; raven_receipt_digest; ruliad_receipt_digest;
      stan_receipt_digest; z3_receipt_digest; load_bearing_digest;
      completeness_digest; receipt_digest = "" }
  in
  let receipt_digest =
    digest_fields
      [ "run-assurance-input-receipt-v1"; provisional.context_digest;
        provisional.current_head_digest;
        Int64.to_string provisional.current_at_ns;
        provisional.safety_receipt_digest; provisional.rete_receipt_digest;
        provisional.raven_receipt_digest; provisional.ruliad_receipt_digest;
        provisional.stan_receipt_digest; provisional.z3_receipt_digest;
        provisional.load_bearing_digest; provisional.completeness_digest ]
  in
  { provisional with receipt_digest }

let make_inputs ~context ordered_inputs =
  match ordered_inputs with
  | [ Safety_input (safety_model, safety);
      Rete_input (rete_network, rete_facts, rete);
      Raven_input (raven_matrix, raven);
      Ruliad_input (ruliad_system, ruliad_bounds, ruliad);
      Stan_input (stan_input, stan);
      (Z3_input (z3_campaign, z3_configuration, z3) as z3_input) ] ->
      let errors =
        [ validate_safety context safety_model safety;
          Run_intelligence.Rete_ul.validate_dispatch ~context
            ~network:rete_network ~facts:rete_facts rete;
          Run_intelligence.Raven_matrix.validate_receipt ~context
            ~matrix:raven_matrix raven;
          Run_analysis.Ruliad.validate_exact ~context ~system:ruliad_system
            ~bounds:ruliad_bounds ruliad;
          Run_analysis.Stan_model.validate_exact ~context ~input:stan_input stan;
          Run_analysis.Z3.validate_receipt ~context ~campaign:z3_campaign
            z3_configuration z3 ]
        |> List.filter_map result_error
      in
      if errors <> [] then Error errors
      else
        let receipt =
          make_receipt context ~safety_receipt_digest:safety.receipt_digest
            ~rete_receipt_digest:rete.receipt_digest
            ~raven_receipt_digest:raven.receipt_digest
            ~ruliad_receipt_digest:ruliad.receipt_digest
            ~stan_receipt_digest:stan.receipt_digest
            ~z3_receipt_digest:z3.receipt_digest
        in
        Ok
          { ordered_inputs =
              [ Safety_input (safety_model, safety);
                Rete_input (rete_network, rete_facts, rete);
                Raven_input (raven_matrix, raven);
                Ruliad_input (ruliad_system, ruliad_bounds, ruliad);
                Stan_input (stan_input, stan); z3_input ];
            receipt }
  | [ Safety_input (safety_model, safety);
      Rete_input (rete_network, rete_facts, rete);
      Raven_input (raven_matrix, raven);
      Ruliad_input (ruliad_system, ruliad_bounds, ruliad);
      Stan_input (stan_input, stan);
      (Z3_unavailable_input z3 as z3_input) ] ->
      let errors =
        [ validate_safety context safety_model safety;
          Run_intelligence.Rete_ul.validate_dispatch ~context
            ~network:rete_network ~facts:rete_facts rete;
          Run_intelligence.Raven_matrix.validate_receipt ~context
            ~matrix:raven_matrix raven;
          Run_analysis.Ruliad.validate_exact ~context ~system:ruliad_system
            ~bounds:ruliad_bounds ruliad;
          Run_analysis.Stan_model.validate_exact ~context ~input:stan_input stan;
          validate_unavailable_z3 context z3 ]
        |> List.filter_map result_error
      in
      if errors <> [] then Error errors
      else
        let receipt =
          make_receipt context ~safety_receipt_digest:safety.receipt_digest
            ~rete_receipt_digest:rete.receipt_digest
            ~raven_receipt_digest:raven.receipt_digest
            ~ruliad_receipt_digest:ruliad.receipt_digest
            ~stan_receipt_digest:stan.receipt_digest
            ~z3_receipt_digest:z3.receipt_digest
        in
        Ok
          { ordered_inputs =
              [ Safety_input (safety_model, safety);
                Rete_input (rete_network, rete_facts, rete);
                Raven_input (raven_matrix, raven);
                Ruliad_input (ruliad_system, ruliad_bounds, ruliad);
                Stan_input (stan_input, stan); z3_input ];
            receipt }
  | _ ->
      unavailable context
        "assurance inputs must contain exactly STPA, Rete, Raven, Ruliad, Stan, and Z3 in canonical order"

let receipt (inputs : inputs) = inputs.receipt

let invalid context message = Error [ error context message ]

let revalidate_admitting_inputs (context : Run_safety.gate_context)
    (inputs : inputs) =
  match inputs.ordered_inputs with
  | [ Safety_input (safety_model, safety);
      Rete_input (rete_network, rete_facts, rete);
      Raven_input (raven_matrix, raven);
      Ruliad_input (ruliad_system, ruliad_bounds, ruliad);
      Stan_input (stan_input, stan);
      Z3_input (z3_campaign, z3_configuration, z3) ] ->
      let errors =
        [ validate_safety context safety_model safety;
          Run_intelligence.Rete_ul.validate_dispatch ~context
            ~network:rete_network ~facts:rete_facts rete;
          Run_intelligence.Raven_matrix.validate_receipt ~context
            ~matrix:raven_matrix raven;
          Run_analysis.Ruliad.validate_exact ~context ~system:ruliad_system
            ~bounds:ruliad_bounds ruliad;
          Run_analysis.Stan_model.validate_exact ~context ~input:stan_input stan;
          Run_analysis.Z3.validate_receipt ~context ~campaign:z3_campaign
            z3_configuration z3 ]
        |> List.filter_map result_error
      in
      if errors <> [] then Error errors
      else if
        z3.authority <> Run_safety.Load_bearing_dispatch_gate
        || z3.admission <> Run_analysis.Z3.Admitted
        || z3.row_policy <> Run_analysis.Z3.Full_denominator
        || List.length z3.in_process <> List.length Run_formal.obligations
        || List.length z3.cli <> List.length Run_formal.obligations
        || not z3.controls_complete || not z3.laws_complete
        || not z3.cross_backend_agreement
        || not z3.memory_evidence.hard_isolated
        || not z3.memory_evidence.within_envelope
        || z3.diagnostics <> []
      then
        invalid context
          "Z3 evidence is not an admitted full-denominator hard-isolated campaign"
      else
        let expected =
          make_receipt context ~safety_receipt_digest:safety.receipt_digest
            ~rete_receipt_digest:rete.receipt_digest
            ~raven_receipt_digest:raven.receipt_digest
            ~ruliad_receipt_digest:ruliad.receipt_digest
            ~stan_receipt_digest:stan.receipt_digest
            ~z3_receipt_digest:z3.receipt_digest
        in
        if inputs.receipt <> expected then
          invalid context
            "assurance input receipt differs from exact source recomputation"
        else Ok expected
  | _ ->
      unavailable context
        "an admitted assurance bundle requires exact ordered STPA, Rete, Raven, Ruliad, Stan, and admitted Z3 inputs"

let bundle_digest_of authority (context : Run_safety.gate_context)
    (receipt : receipt) =
  digest_fields
    [ "run-assurance-admitted-bundle-v1";
      Run_safety.string_of_authority authority;
      context.context_digest; context.current_head_digest;
      Int64.to_string context.current_at_ns; receipt.receipt_digest;
      receipt.load_bearing_digest; receipt.completeness_digest ]

let admit ~context inputs =
  match revalidate_admitting_inputs context inputs with
  | Error _ as failure -> failure
  | Ok receipt ->
      let authority = Run_safety.Load_bearing_dispatch_gate in
      Ok
        { authority; context_digest = context.Run_safety.context_digest;
          current_head_digest = context.current_head_digest;
          current_at_ns = context.current_at_ns; inputs; receipt;
          bundle_digest = bundle_digest_of authority context receipt }

let validate_bundle ~(context : Run_safety.gate_context)
    (bundle : admitted_bundle) =
  match revalidate_admitting_inputs context bundle.inputs with
  | Error _ as failure -> failure
  | Ok expected_receipt ->
      let expected_bundle_digest =
        bundle_digest_of Run_safety.Load_bearing_dispatch_gate context
          expected_receipt
      in
      if bundle.authority <> Run_safety.Load_bearing_dispatch_gate
         || not (String.equal bundle.context_digest context.context_digest)
         || not
              (String.equal bundle.current_head_digest
                 context.current_head_digest)
         || not (Int64.equal bundle.current_at_ns context.current_at_ns)
         || bundle.receipt <> expected_receipt
         || not (String.equal bundle.bundle_digest expected_bundle_digest)
      then
        invalid context
          "admitted assurance bundle identity differs from exact recomputation"
      else Ok ()

module For_test = struct
  type bundle_mutation =
    | Context_digest
    | Current_head_digest
    | Current_at_ns
    | Authority
    | Receipt_digest
    | Load_bearing_digest
    | Completeness_digest
    | Bundle_digest

  let mutated_digest value = sha256 (value ^ ":mutant")

  let mutate_bundle mutation (bundle : admitted_bundle) =
    match mutation with
    | Context_digest ->
        { bundle with context_digest = mutated_digest bundle.context_digest }
    | Current_head_digest ->
        { bundle with
          current_head_digest = mutated_digest bundle.current_head_digest }
    | Current_at_ns ->
        { bundle with current_at_ns = Int64.succ bundle.current_at_ns }
    | Authority ->
        { bundle with authority = Run_safety.Analysis_only }
    | Receipt_digest ->
        { bundle with
          receipt =
            { bundle.receipt with
              receipt_digest = mutated_digest bundle.receipt.receipt_digest } }
    | Load_bearing_digest ->
        { bundle with
          receipt =
            { bundle.receipt with
              load_bearing_digest =
                mutated_digest bundle.receipt.load_bearing_digest } }
    | Completeness_digest ->
        { bundle with
          receipt =
            { bundle.receipt with
              completeness_digest =
                mutated_digest bundle.receipt.completeness_digest } }
    | Bundle_digest ->
        { bundle with bundle_digest = mutated_digest bundle.bundle_digest }
end
