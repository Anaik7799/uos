module Processing = Zigvm_harness_support.Graph_processing
module Revision = Zigvm_harness_support.Graph_revision
module Analytics = Zigvm_harness_support.Graph_analytics
module Intelligence = Zigvm_harness_support.Graph_intelligence_workspace

let require condition message = if not condition then failwith message

let () =
  let statements =
    [ Processing.statement ~id:"s1" ~source_id:"source" "Graph evidence connects systems and design";
      Processing.statement ~id:"s2" ~source_id:"source" "Design evidence reveals a knowledge gap";
      Processing.statement ~id:"s3" ~source_id:"source" "Systems propagate graph influence" ]
  in
  let processed = Processing.process Processing.default_profile statements in
  let revision = Revision.of_graph ~statement_ids:[ "s1"; "s2"; "s3" ] ~project_id:"p" ~revision:7 processed.graph in
  let report = Analytics.analyze ~filter_digest:processed.digest revision statements in
  require (String.length (Intelligence.topic_overview report) > 0) "topic overview must be observable";
  require (String.length (Intelligence.focused_summary ~node_ids:[ "evidence" ] report) > 0) "focused summary must retain excerpts";
  ignore (Intelligence.gap_ideation report);
  let packet = Intelligence.retrieve ~query:"graph evidence" report in
  require (packet.revision = 7 && packet.evidence <> []) "retrieval must retain revision and evidence";
  require (String.length (Intelligence.augment_prompt ~prompt:"Explain" packet) > 20) "augmentation must carry graph evidence";
  (match Intelligence.chat packet with
  | Ok answer -> require (answer.citations <> [] && answer.provider = None) "local chat must cite sources and disclose provider absence"
  | Error _ -> failwith "local graph-aware chat must not require a provider");
  let ontology = Intelligence.classify report in
  require (ontology.rules <> [] && ontology.relations <> []) "ontology review must expose rules and relations";
  let note = Intelligence.generate_note ~mode:Intelligence.Append ~existing:"Prior" ~label:"Orientation" report in
  require (note.revision = 7 && String.length note.body > 5) "generated notes must be revision scoped";
  (match Intelligence.select_provider [ Intelligence.Unavailable "offline"; Intelligence.Configured "local" ] with
  | Ok "local" -> () | _ -> failwith "configured provider selection must be deterministic");
  (match Intelligence.select_provider [ Intelligence.Rate_limited { provider = "remote"; retry_after_seconds = 60 } ] with
  | Error (Intelligence.Rate_limited { retry_after_seconds = 60; _ }) -> ()
  | _ -> failwith "provider rate limits must remain observable");
  print_endline "graph intelligence workspace laws: pass"
