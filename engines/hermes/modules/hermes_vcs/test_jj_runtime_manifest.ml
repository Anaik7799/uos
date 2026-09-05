let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let () =
  let open Jj_runtime_manifest in
  let manifest = production
    ~target_jj ~target_external_resource ~target_repository_source
    ~target_approval ~target_writer_lease ~target_transition
    ~target_mutation_frontier ~target_network_scope ~target_credential_lease
    ~target_filesystem_materialization ~target_candidate_verification
    ~target_release ~target_completion_receipt
    ~target_formal:target_formal_unavailable
    ~process_jujutsu ~process_candidate
    ~process_formal:process_formal_unavailable
    ~runtime_core ~runtime_operator ~runtime_recovery_port_vault
    ~activation_production ~activation_candidate ~activation_release
    ~activation_formal:activation_formal_unavailable
    ~store_authority ~store_dispatch ~store_recovery_vault ~store_effect_event
    ~store_completion_receipt
  in
  check "M1 exact production slot denominator is 29" (slot_count = 29);
  check "M2 typed production assembly is constructible and digest-bound"
    (match manifest with Ok value -> String.length (production_digest value) = 64
     | Error _ -> false);
  check "M3 public declarations are slot-local and formal absence is reasoned"
    (declaration_key target_jj = "target.jj"
     && declaration_key
          target_formal_unavailable
        = "target.formal");
  check "M4 slot declarations are nominally distinct and canonically named"
    (slot_key Target_jj = "target.jj"
     && slot_key Store_completion_receipt = "store.completion-receipt");
  check "M5 manifest authority digest is nonempty"
    (String.length source_digest = 64);
  check "M6 production schema projection pins every slot in exact order"
    (production_slot_keys
     = [ "target.jj"; "target.external-resource";
         "target.repository-source"; "target.approval";
         "target.writer-lease"; "target.transition";
         "target.mutation-frontier"; "target.network-scope";
         "target.credential-lease"; "target.filesystem-materialization";
         "target.candidate-verification"; "target.release";
         "target.completion-receipt"; "target.formal";
         "process.jujutsu"; "process.candidate"; "process.formal";
         "runtime.core"; "runtime.operator";
         "runtime.recovery-transition-port-vault";
         "activation.production"; "activation.candidate";
         "activation.release"; "activation.formal";
         "store.authority"; "store.dispatch"; "store.recovery-vault";
         "store.effect-event"; "store.completion-receipt" ]);
  let support = test_support
      ~activation_disposable:test_activation_disposable
      ~fixture_materialization:test_fixture_materialization
      ~isolation:test_isolation in
  check "M7 test support is a distinct exact three-slot opaque product"
    (test_slot_count = 3
     && test_support_slot_keys
        = [ "test.activation.disposable";
            "test.fixture-materialization"; "test.isolation" ]
     && String.length (test_support_digest support) = 64
     && (match manifest with
         | Ok production ->
             not (String.equal (production_digest production)
                    (test_support_digest support))
         | Error _ -> false));
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 7 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_runtime_manifest"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
