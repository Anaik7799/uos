module P = Zigvm_harness_support.Graph_processing

let require condition message = if not condition then failwith message

let () =
  let profile =
    P.
      {
        default_profile with
        language = "EN";
        stop_words = [ "noise" ];
        protected_words = [ "API" ];
        synonyms = [ ("graphs", "graph") ];
      }
  in
  let statements =
    [
      P.statement ~id:"s1" ~source_id:"src" ~ordinal:0
        ~metadata:[ ("sentiment", "positive"); ("segment", "alpha") ]
        "API graphs remove noise [[Knowledge Graph]] @analyst #research";
      P.statement ~id:"s2" ~source_id:"src" ~ordinal:1
        "Entity:InfraNodus connects graph evidence";
    ]
  in
  let result = P.process profile statements in
  require (P.has_node result "api") "protected terms survive normalization";
  require (P.has_node result "graph") "synonyms normalize before graph construction";
  require (not (P.has_node result "graphs")) "aliases do not leak as duplicate nodes";
  require (not (P.has_node result "noise")) "stop words are excluded";
  require
    (P.statement_ids_for_node result "graph" = [ "s1"; "s2" ])
    "node provenance is stable and complete";
  require (List.mem ("graphs", "graph") result.aliases) "aliases remain inspectable";
  List.iter
    (fun kind ->
      require
        (List.exists (fun (node : P.typed_node) -> node.kind = kind) result.typed_nodes)
        (kind ^ " forms a typed token family"))
    [ "wiki-link"; "mention"; "tag"; "entity" ];
  require (result.effective_language = "en") "language is explicit and normalized";
  require
    (List.exists
       (fun (tag : P.metadata_tag) -> tag.key = "sentiment" && tag.value = "positive")
       result.tags)
    "metadata and sentiment provenance is retained";
  require (P.process profile statements = result) "processing is deterministic";
  let entities = P.process P.{ profile with graph_mode = Entities_only } statements in
  require
    (List.for_all (fun (node : P.typed_node) -> node.kind <> "word") entities.typed_nodes)
    "entity-only mode excludes word nodes";
  require
    (P.process P.{ profile with window = 0 } statements
     = P.process P.{ profile with window = 1 } statements)
    "co-occurrence window is clamped at the lower bound";
  print_endline "graph processing laws: pass (seed=5031, deterministic)"
