let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin incr failed; Printf.eprintf "FAIL %s\n" name end

let get = function Ok value -> value | Error _ -> failwith "valid identifier refused"
let request_id value = get (Jj_id.Request.make value)

let unique values =
  List.sort_uniq String.compare values |> List.length = List.length values

let common_obligations =
  [ Dependability_process_protocol.Exact_source;
    Exact_configuration; Approval_required; Writer_lease_required;
    Resource_preflight_required; Bridge_admission_required;
    Apply_once_receipt_required; Readback_required ]

let candidate_obligations =
  [ Dependability_process_protocol.Exact_source;
    Exact_configuration; Approval_required; Resource_preflight_required;
    Bridge_admission_required; Apply_once_receipt_required; Readback_required ]

let formal_obligations = candidate_obligations

let () =
  let kinds = Dependability_process_protocol.all_kinds in
  let declarations =
    List.mapi
      (fun index kind ->
         Dependability_process_protocol.declare
           ~request_id:(request_id (Printf.sprintf "protocol-%02d" index)) kind)
      kinds
  in
  let projections =
    List.map Dependability_process_protocol.projection declarations in
  check "D1 exact 44-member closed denominator"
    (List.length kinds = 44);
  check "D2 denominator derives exactly from Jj_process_protocol"
    (kinds = Jj_process_protocol.all);
  check "D3 request-kind keys are unique"
    (unique (List.map Jj_process_protocol.key kinds));
  check "D4 every declaration retains its exact kind"
    (List.map (fun row -> row.Dependability_process_protocol.kind) projections
     = kinds);
  check "M1 process-role mapping is total"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind, row.process_role with
          | Jj_process_protocol.Jujutsu_operation _, Jujutsu_process
          | Candidate_verification _, Candidate_process
          | Formal_oracle _, Formal_process -> true
          | _ -> false)
       projections);
  check "M2 target mapping is total"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind, row.target with
          | Jj_process_protocol.Jujutsu_operation _, Jj_target_protocol.Jujutsu
          | Candidate_verification _, Candidate_verification
          | Formal_oracle _, Formal -> true
          | _ -> false)
       projections);
  check "B1 every declaration carries a valid bounded budget"
    (List.for_all
       (fun row -> Jj_budget.valid row.Dependability_process_protocol.budget)
       projections);
  check "B2 Jujutsu budgets are exactly operation-derived"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Jujutsu_operation operation ->
              row.budget = (Jj_operation.declaration operation).budget
          | Candidate_verification _ | Formal_oracle _ -> true)
       projections);
  check "B3 candidate and formal budgets are the bounded observation profile"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Jujutsu_operation _ -> true
          | Candidate_verification _ | Formal_oracle _ ->
              row.budget = Jj_budget.for_profile Observation)
       projections);
  check "I1 every declaration identity is canonical SHA-256"
    (List.for_all
       (fun row -> String.length row.Dependability_process_protocol.digest = 64)
       projections);
  let first_kind = List.hd kinds in
  let first =
    Dependability_process_protocol.declare ~request_id:(request_id "same-a")
      first_kind in
  let second_request =
    Dependability_process_protocol.declare ~request_id:(request_id "same-b")
      first_kind in
  let second_kind =
    Dependability_process_protocol.declare ~request_id:(request_id "same-a")
      (List.hd (List.tl kinds)) in
  check "I2 request identity changes declaration identity"
    (Dependability_process_protocol.digest first
     <> Dependability_process_protocol.digest second_request);
  check "I3 request kind changes declaration identity"
    (Dependability_process_protocol.digest first
     <> Dependability_process_protocol.digest second_kind);
  check "O1 every Jujutsu declaration carries the exact production obligations"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jujutsu_operation Jj_operation.Git_push ->
              row.obligations
              = common_obligations @ [ Remote_publication_cas_required ]
          | Jujutsu_operation _ -> row.obligations = common_obligations
          | Candidate_verification _ | Formal_oracle _ -> true)
       projections);
  check "O1b candidate verification excludes production writer authority"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Candidate_verification _ ->
              row.obligations = candidate_obligations
              && not
                   (List.mem
                      Dependability_process_protocol.Writer_lease_required
                      row.obligations)
          | Jujutsu_operation _ | Formal_oracle _ -> true)
       projections);
  check "O1c formal verification excludes production writer authority"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Formal_oracle _ ->
              row.obligations = formal_obligations
              && not
                   (List.mem
                      Dependability_process_protocol.Writer_lease_required
                      row.obligations)
          | Jujutsu_operation _ | Candidate_verification _ -> true)
       projections);
  let find operation =
    List.find
      (fun row ->
         row.Dependability_process_protocol.kind
         = Jj_process_protocol.Jujutsu_operation operation)
      projections in
  check "O2 Git push alone carries the additional CAS obligation"
    ((find Jj_operation.Git_push).obligations
     = common_obligations @ [ Remote_publication_cas_required ]
     && List.for_all
          (fun row ->
             row.Dependability_process_protocol.kind
               = Jj_process_protocol.Jujutsu_operation Jj_operation.Git_push
             || not
                  (List.mem
                     Dependability_process_protocol.Remote_publication_cas_required
                     row.obligations))
          projections);
  check "R1 operation recovery policy is preserved exactly"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Jujutsu_operation operation ->
              row.recovery = (Jj_operation.declaration operation).recovery
          | Candidate_verification _ | Formal_oracle _ ->
              row.recovery = Jj_operation.Recovery_none)
       projections);
  check "A1 every formal oracle remains unavailable"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Formal_oracle _ ->
              row.availability = Formal_oracle_unavailable
          | _ -> true)
       projections);
  check "A2 Git push remains unavailable without proved CAS"
    ((find Jj_operation.Git_push).availability
     = Dependability_process_protocol.Remote_publication_unavailable_without_cas);
  check "A3 all remaining declarations remain unavailable until bridge"
    (List.for_all
       (fun row ->
          match row.Dependability_process_protocol.kind with
          | Jj_process_protocol.Formal_oracle _ -> true
          | Jujutsu_operation Jj_operation.Git_push -> true
          | Jujutsu_operation _ | Candidate_verification _ ->
              row.availability = Bridge_unavailable)
       projections);
  check "R2 replay classification is stable, conflicting, and request-separated"
    (Dependability_process_protocol.reconcile first first = Stable_replay
     && Dependability_process_protocol.reconcile first second_kind
        = Identity_conflict
     && Dependability_process_protocol.reconcile first second_request
        = Different_request);
  check "S1 source identity is bounded and every structural mutant is killed"
    (String.length Dependability_process_protocol.source_digest = 64
     && List.for_all
          (fun mutation ->
             Dependability_process_protocol.source_digest
             <> Dependability_process_protocol.For_test.source_digest_with_mutation
                  mutation)
          [ Dependability_process_protocol.For_test.Drop_row;
            Duplicate_row; Swap_target; Widen_budget; Remove_recovery;
            Promote_availability; Drop_obligation;
            Add_candidate_writer_lease; Add_formal_writer_lease ]);
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_process_protocol"
      ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_dependability_process_protocol ]);
  exit (Suite_telemetry.exit_code self)
