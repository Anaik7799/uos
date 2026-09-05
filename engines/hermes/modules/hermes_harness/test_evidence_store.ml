let () =
  let path = Filename.temp_file "hermes-harness" ".sqlite3" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      match Evidence_store.open_db ~path with
      | Error message -> failwith message
      | Ok db ->
          assert
            (Evidence_store.record_snapshot db ~digest:(String.make 64 'a') ~entry_count:2 = Ok ());
          assert
            (Evidence_store.record_check db ~name:"dune" ~status:(Core.Failed "missing") = Ok ());
          assert (Evidence_store.record_check db ~name:"dune" ~status:Core.Passed = Ok ());
          assert (Evidence_store.latest_readiness db = Ok Core.Passed);
          let snapshot_digest = String.make 64 'a' in
          let cell : Inventory.domain_summary =
            { domain = "agent"; file_count = 1; digest = String.make 64 'b' }
          in
          assert (Evidence_store.record_cells db ~snapshot_digest [ cell ] = Ok ());
          assert
            (Evidence_store.cells db ~snapshot_digest
            = Ok [ ("agent", 1, String.make 64 'b', "unmapped") ]);
          let replacement : Inventory.domain_summary =
            { domain = "providers"; file_count = 2; digest = String.make 64 'c' }
          in
          assert
            (match Evidence_store.record_cells db ~snapshot_digest [ replacement ] with
            | Error _ -> true
            | Ok () -> false);
          let scenario : Evidence_store.scenario =
            { snapshot_digest; id = "agent.turn.basic"; feature_id = "agent_loop";
              contract_id = "turn_contract"; fixture_digest = String.make 64 'd';
              reference_digest = String.make 64 'e' }
          in
          assert (Evidence_store.record_scenario db scenario = Ok ());
          let trace : Evidence_store.paired_trace =
            { snapshot_digest; scenario_id = scenario.id; trace_id = "turn-basic";
              reference_trace = String.make 64 'f'; candidate_trace = String.make 64 'g';
              normalization_version = "v1" }
          in
          assert (Evidence_store.record_paired_trace db trace = Ok ());
          let verification : Evidence_store.verification =
            { snapshot_digest; scenario_id = scenario.id; trace_id = trace.trace_id;
              verifier = "parity-v1"; harness_revision = "abc123"; check = "trace-equal";
              passed = true; evidence_digest = String.make 64 'h' }
          in
          assert (Evidence_store.record_verification db verification = Ok ());
          assert (Evidence_store.verified_scenarios db ~snapshot_digest ~harness_revision:"abc123"
                  = Ok [ scenario.id ]);
          let feature : Evidence_store.feature =
            { snapshot_digest; id = "agent_loop"; label = "Agent conversation and tool loop";
              source_domains = [ "agent" ] }
          in
          assert (Evidence_store.record_features db [ feature ] = Ok ());
          assert (Evidence_store.features db ~snapshot_digest
                  = Ok [ (feature.id, feature.label, feature.source_domains) ]);
          let history : Evidence_store.feature_history =
            { snapshot_digest; feature_id = feature.id; git_revision = "abc123";
              phase = "cataloged"; status = "unmapped";
              implementation_anchor = "feature_catalog.ml";
              evidence_digest = String.make 64 'i' }
          in
          assert (Evidence_store.record_feature_history db history = Ok ());
          assert (Evidence_store.feature_history db ~snapshot_digest ~feature_id:feature.id
                  = Ok [ history ]);
          let node : Evidence_store.fractal_node =
            { snapshot_digest; id = "hermes.agent_loop"; level = 1;
              parent_id = Some "hermes"; semantic_key = "agent_loop";
              label = "Agent conversation and tool loop"; required = true;
              status_policy = "all-children" }
          in
          assert (Evidence_store.record_fractal_nodes db
                    [ { node with id = "hermes"; level = 0; parent_id = None;
                                  semantic_key = "hermes"; label = "Hermes" };
                      node ] = Ok ());
          let artifact : Evidence_store.artifact =
            { snapshot_digest; id = "docs.agent-loop"; kind = "documentation";
              path = "website/docs/developer-guide/agent-loop.md";
              title = "Agent loop"; content_digest = String.make 64 'j';
              git_revision = "abc123" }
          in
          assert (Evidence_store.record_artifacts db [ artifact ] = Ok ());
          assert (Evidence_store.link_node_artifact db ~snapshot_digest
                    ~node_id:node.id ~artifact_id:artifact.id ~role:"specification" = Ok ());
          assert (Evidence_store.node_artifacts db ~snapshot_digest ~node_id:node.id
                  = Ok [ (artifact, "specification") ]);
          let knowledge : Evidence_store.knowledge_link =
            { snapshot_digest; artifact_id = artifact.id; system = "zk";
              locator = "zk-hermes-agent-loop"; relation = "indexes";
              content_digest = artifact.content_digest }
          in
          assert (Evidence_store.record_knowledge_links db [ knowledge ] = Ok ());
          assert (Evidence_store.artifact_knowledge_links db ~snapshot_digest
                    ~artifact_id:artifact.id = Ok [ knowledge ]);
          let commit : Evidence_store.git_commit =
            { revision = "abc123"; tree_digest = String.make 64 'k';
              parent_revisions = []; subject = "catalog Hermes" }
          in
          assert (Evidence_store.record_git_commits db [ commit ] = Ok ());
          let revision : Evidence_store.node_revision =
            { snapshot_digest; node_id = node.id; git_revision = commit.revision;
              phase = "cataloged"; strict_status = "unmapped";
              implementation_anchor = "feature_catalog.ml";
              evidence_digest = String.make 64 'l' }
          in
          assert (Evidence_store.record_node_revisions db [ revision ] = Ok ());
          assert (Evidence_store.node_revisions db ~snapshot_digest ~node_id:node.id
                  = Ok [ revision ]);
          assert
            (match Evidence_store.record_fractal_nodes db [ { node with label = "conflict" } ] with
            | Error _ -> true | Ok () -> false);
          assert
            (match Evidence_store.record_git_commits db [ { commit with subject = "conflict" } ] with
            | Error _ -> true | Ok () -> false);
          let rejects = function Error _ -> true | Ok () -> false in
          (* Identical replay of an immutable row stays accepted. *)
          assert (Evidence_store.record_feature_history db history = Ok ());
          assert (Evidence_store.record_artifacts db [ artifact ] = Ok ());
          assert (Evidence_store.record_knowledge_links db [ knowledge ] = Ok ());
          assert (Evidence_store.record_node_revisions db [ revision ] = Ok ());
          assert (Evidence_store.record_scenario db scenario = Ok ());
          assert (Evidence_store.record_paired_trace db trace = Ok ());
          assert (Evidence_store.record_verification db verification = Ok ());
          assert (Evidence_store.link_node_artifact db ~snapshot_digest
                    ~node_id:node.id ~artifact_id:artifact.id ~role:"specification" = Ok ());
          (* Divergent replay under an existing key is rejected, never silently dropped. *)
          assert (rejects (Evidence_store.record_feature_history db
                             { history with status = "verified" }));
          assert (rejects (Evidence_store.record_artifacts db
                             [ { artifact with title = "conflict" } ]));
          assert (rejects (Evidence_store.record_artifacts db
                             [ { artifact with content_digest = String.make 64 'z' } ]));
          assert (rejects (Evidence_store.record_knowledge_links db
                             [ { knowledge with content_digest = String.make 64 'z' } ]));
          assert (rejects (Evidence_store.record_node_revisions db
                             [ { revision with strict_status = "verified" } ]));
          assert (rejects (Evidence_store.record_scenario db
                             { scenario with fixture_digest = String.make 64 'z' }));
          assert (rejects (Evidence_store.record_paired_trace db
                             { trace with candidate_trace = String.make 64 'z' }));
          assert (rejects (Evidence_store.record_verification db
                             { verification with passed = false }));
          (* Rejection leaves the stored evidence untouched. *)
          assert (Evidence_store.feature_history db ~snapshot_digest ~feature_id:feature.id
                  = Ok [ history ]);
          assert (Evidence_store.node_revisions db ~snapshot_digest ~node_id:node.id
                  = Ok [ revision ]);
          assert (Evidence_store.node_artifacts db ~snapshot_digest ~node_id:node.id
                  = Ok [ (artifact, "specification") ]);
          assert (Evidence_store.artifact_knowledge_links db ~snapshot_digest
                    ~artifact_id:artifact.id = Ok [ knowledge ]);
          assert (Evidence_store.verified_scenarios db ~snapshot_digest ~harness_revision:"abc123"
                  = Ok [ scenario.id ]);
          Evidence_store.close db)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_evidence_store" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)
