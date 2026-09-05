(* See import_coverage.mli. One row per importable module; the suite
   fails if this table and the import tree disagree either way. *)

type disposition =
  | Ported of string list
  | Operational of string
  | Scheduled of string
  | Superseded of string

type entry = { module_ : string; family : string; disposition : disposition }

let e module_ family disposition = { module_; family; disposition }

let entries =
  [ (* ---- core: the engine's own lineage ---- *)
    e "docs_wiki" "core" (Ported [ "HW.1.1.1"; "HW.1.2.1"; "HW.4.1.1" ]);
    e "docs_wiki_laws" "core" (Ported [ "HW.8.2.3" ]);
    e "markdown_ast" "core" (Ported [ "HW.2.0.1" ]);
    e "markdown_ast_laws" "core" (Ported [ "HW.2.0.1" ]);
    e "typed_html" "core" (Ported [ "HW.6.1.2" ]);
    e "route_algebra" "core" (Ported [ "HW.6.1.1" ]);
    e "route_laws" "core" (Ported [ "HW.6.1.1" ]);
    e "gen_markdown_baseline" "core" (Ported [ "HW.8.2.3" ]);
    e "doc_lint" "core" (Ported [ "HW.2.0.3" ]);
    e "note_ref" "core" (Ported [ "HW.3.7.1" ]);
    e "json_embed" "core" (Ported [ "HW.10.3.1" ]);
    e "json_embed_laws" "core" (Ported [ "HW.10.3.1" ]);
    e "render_markdown_file" "core" (Operational "render_site renders the whole corpus");
    e "figma_design" "core"
      (Superseded "no external design service is in any build path (P3)");
    e "dump_figma_design" "core"
      (Superseded "no external design service is in any build path (P3)");
    (* ---- graph: the kernels ---- *)
    e "graph_analytics" "graph" (Ported [ "HW.4.2.1"; "HW.4.2.3" ]);
    e "graph_processing" "graph" (Ported [ "HW.4.2.2" ]);
    e "graph_store" "graph" (Operational "Hermes_wiki.model IS the store (derived, never persisted)");
    e "graph_ingest" "graph" (Operational "read_tracked: the corpus is what git tracks");
    e "graph_export" "graph" (Ported [ "HW.10.3.1" ]);
    e "graph_revision" "graph" (Operational "git is the revision substrate (HW.8.1.1)");
    e "graph_intelligence" "graph" (Ported [ "HW.4.2.4" ]);
    e "graph_intelligence_workspace" "graph" (Ported [ "HW.4.5.2" ]);
    e "graph_worker_core" "graph"
      (Superseded "the build is single-process and deterministic; workers would need HW.10.1.3 first");
    (* ---- zk: the enforcer/prover fleet ---- *)
    e "zk_block_anchor_uniqueness" "zk" (Ported [ "HW.3.3.1" ]);
    e "zk_frontmatter_schema_enforcer" "zk" (Ported [ "HW.1.3.16" ]);
    e "zk_page_rank_calculator" "zk" (Ported [ "HW.4.2.1" ]);
    e "zk_graph_betweenness_calculator" "zk" (Ported [ "HW.4.2.3" ]);
    e "zk_discourse_logic_checker" "zk" (Ported [ "HW.4.4.1" ]);
    e "zk_contradiction_prover" "zk" (Ported [ "HW.4.4.2" ]);
    e "zk_discourse_edge_inverter" "zk" (Ported [ "HW.4.1.1" ]);
    e "zk_typed_edge_extractor" "zk" (Ported [ "HW.4.1.2" ]);
    e "zk_markdown_to_html_compiler" "zk" (Ported [ "HW.2.0.1" ]);
    e "zk_moc_freeze_enforcer" "zk" (Ported [ "HW.4.6.1" ]);
    e "zk_query_live_executor" "zk" (Ported [ "HW.5.1.3"; "HW.5.1.5" ]);
    e "zk_query_ast_mutator" "zk" (Operational "test_wiki_query mutation legs");
    e "zk_query_dsl_fuzzer" "zk" (Operational "test_wiki_query totality leg over generated input");
    e "zk_law_to_test_traceability_matrix" "zk" (Operational "Formal_coverage anchors law to suite");
    e "zk_doc_to_code_coverage_runner" "zk" (Operational "Formal_coverage + the register's probes");
    e "zk_formal_spec_to_doc_prover" "zk" (Operational "Formal_specs + the catalogue coverage check");
    e "zk_transclusion_depth_limiter" "zk" (Ported [ "HW.3.5.3" ]);
    e "zk_transclusion_loop_injector" "zk" (Ported [ "HW.3.5.3" ]);
    e "zk_graph_isomorphism_checker" "zk"
      (Superseded
         "HW.4.5.1 landed by another route, and its premise is gone: the module
          diffs a zk_edge_history SQLite table, and the corpus is plain files");
    e "zk_query_performance_profiler" "zk" (Ported [ "HW.10.3.2" ]);
    e "zk_tag_laundering_preventer" "zk" (Ported [ "HW.4.1.7" ]);
    e "zk_api_contract_doc_verifier" "zk"
      (Superseded "HW.9.3.1 landed as Hermes_wiki.doctest_drift, probe-verified");
    e "zk_comptime_logic_documenter" "zk"
      (Superseded
         "its target row HW.9.1.1 is Excluded (0/0), and it audits **/*.zig files
          that do not exist in this workspace");
    e "zk_compliance_audit_trail_exporter" "zk"
      (Operational "the OTel stream + the append-only journal");
    e "zk_agent_write_quota_enforcer" "zk"
      (Superseded "no HTTP write path exists: the route ADT cannot express a write verb");
    e "zk_cryptographic_note_signer" "zk"
      (Superseded "provenance is git's signed history, not a per-note signature");
    e "zk_mcp_auth_token_validator" "zk"
      (Superseded "R15: the surface is read-only and Tailscale-gated; no token path exists");
    e "zk_sqlite_db_encryption_wrapper" "zk"
      (Superseded "the corpus is plain files in git; there is no database to encrypt");
    e "zk_gate_isolation_prover" "zk" (Operational "the self-containment law (test_hermes_wiki)");
    (* ---- wiki: the checker fleet ---- *)
    e "wiki_render_laws" "wiki" (Ported [ "HW.8.2.3" ]);
    e "wiki_sidebar_tree_generator" "wiki" (Ported [ "HW.6.8.1" ]);
    e "wiki_content_security_policy_generator" "wiki" (Ported [ "HW.6.1.4" ]);
    e "wiki_theme_token_injector" "wiki" (Ported [ "HW.7.1.1" ]);
    e "wiki_snippet_executor_validator" "wiki"
      (Superseded "HW.9.3.1 landed as doctest_drift; this one never compiles a snippet");
    e "wiki_cache_poisoning_detector" "wiki"
      (Superseded "the static export has no cache layer to poison");
    e "wiki_gate_coupling_prover" "wiki" (Operational "the ratchet + the differential gate");
    e "wiki_benchmark_dashboard" "wiki" (Ported [ "HW.10.3.2" ]);
    e "wiki_pipeline_scale" "wiki" (Ported [ "HW.10.3.2" ]);
    e "wiki_selfcheck_parallel" "wiki" (Ported [ "HW.10.1.3" ]);
    (* ---- journal: the KM pillar ---- *)
    e "journal_bundle" "journal" (Ported [ "HW.8.3.8" ]);
    e "journal_bundle_digest" "journal" (Ported [ "HW.8.3.8" ]);
    e "journal_bundle_io" "journal" (Operational "read_tracked + the tools' own IO shells");
    e "journal_bundle_telemetry" "journal" (Ported [ "HW.10.5.1" ]);
    e "journal_bundle_transaction" "journal"
      (Operational "the commit IS the transaction (git), reviewed as one unit");
    e "journal_markdown_html" "journal" (Ported [ "HW.2.0.1" ]);
    e "render_journal_html" "journal" (Operational "render_site renders journals with the corpus");
    e "journal_html_playwright" "journal" (Scheduled "HW.6.9.8");
    e "journal_bundle_dashboard_playwright" "journal" (Scheduled "HW.6.9.8");
    e "journal_playwright_contract" "journal" (Scheduled "HW.6.9.8");
    (* ---- playwright: the browser layer ---- *)
    e "playwright_controller" "playwright" (Scheduled "HW.6.9.8");
    e "playwright_authority" "playwright" (Scheduled "HW.6.9.8");
    e "playwright_ontology" "playwright" (Scheduled "HW.6.9.8");
    e "playwright_source_ontology" "playwright" (Scheduled "HW.6.9.8");
    (* ---- infranodus: graph intelligence ---- *)
    e "infranodus_feature" "infranodus" (Ported [ "HW.4.2.4" ]);
    e "infranodus_scenario" "infranodus" (Ported [ "HW.4.2.4" ]);
    e "infranodus_acquisition" "infranodus"
      (Superseded "P3: no network fetch occurs in any build path");
    e "infranodus_host_adapter" "infranodus"
      (Superseded "P3: no external service is called from the system");
    e "infranodus_artifacts" "infranodus"
      (Superseded "HW.4.5.1 landed by another route");
    e "infranodus_fractal_closure_plan" "infranodus" (Operational "the register IS the plan ledger");
    e "infranodus_full_ui_playwright" "infranodus" (Scheduled "HW.6.9.8");
    (* ---- km-profiles: comparator models ---- *)
    e "notion" "km-profiles" (Operational "the Notion fractal survey documents (corpus pages)");
    e "logseq_profile" "km-profiles"
      (Operational "the comparator set is Notion/Obsidian/Docusaurus/Sphinx/Yuque by decision");
    e "render_logseq_profile" "km-profiles"
      (Operational "the comparator set is closed; no Logseq surface is rendered") ]

let names () = List.map (fun x -> x.module_) entries

let unclassified ~observed =
  let declared = names () in
  List.filter (fun m -> not (List.mem m declared)) observed |> List.sort_uniq compare

let phantom ~observed =
  List.filter (fun m -> not (List.mem m observed)) (names ()) |> List.sort_uniq compare

type census = { ported : int; operational : int; scheduled : int; superseded : int }

let census () =
  List.fold_left
    (fun c x ->
      match x.disposition with
      | Ported _ -> { c with ported = c.ported + 1 }
      | Operational _ -> { c with operational = c.operational + 1 }
      | Scheduled _ -> { c with scheduled = c.scheduled + 1 }
      | Superseded _ -> { c with superseded = c.superseded + 1 })
    { ported = 0; operational = 0; scheduled = 0; superseded = 0 }
    entries

let next_mirrors () =
  List.filter_map
    (fun x -> match x.disposition with Scheduled r -> Some (x.module_, r) | _ -> None)
    entries
  |> List.sort compare
