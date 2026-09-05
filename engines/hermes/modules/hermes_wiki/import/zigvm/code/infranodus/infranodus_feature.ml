type family =
  | Workspace
  | Acquisition
  | Processing
  | Visualization
  | Analytics
  | Intelligence
  | Integration

type behavior = Static | Dynamic | Static_and_dynamic

type status = Implemented | Adapter_ready | Planned | Unknown_not_claimed

type t = {
  id : string;
  family : family;
  title : string;
  behavior : behavior;
  use_case : string;
  status : status;
  ui_controls : string list;
  scenario_ids : string list;
  evidence : string list;
}

let id feature = feature.id
let family feature = feature.family
let title feature = feature.title
let behavior feature = feature.behavior
let use_case feature = feature.use_case
let status feature = feature.status
let ui_controls feature = feature.ui_controls
let scenario_ids feature = feature.scenario_ids
let evidence feature = feature.evidence

let family_name = function
  | Workspace -> "workspace"
  | Acquisition -> "acquisition"
  | Processing -> "processing"
  | Visualization -> "visualization"
  | Analytics -> "analytics"
  | Intelligence -> "intelligence"
  | Integration -> "integration"

let behavior_name = function
  | Static -> "static"
  | Dynamic -> "dynamic"
  | Static_and_dynamic -> "static-and-dynamic"

let status_name = function
  | Implemented -> "IMPLEMENTED"
  | Adapter_ready -> "ADAPTER-READY"
  | Planned -> "PLANNED"
  | Unknown_not_claimed -> "UNKNOWN-NOT-CLAIMED"

let planned family id title use_case =
  {
    id;
    family;
    title;
    behavior = Dynamic;
    use_case;
    status = Planned;
    ui_controls = [ "feature-" ^ String.map (function '.' -> '-' | character -> character) id ];
    scenario_ids = [ "scenario-" ^ String.lowercase_ascii id ];
    evidence = [];
  }

let implemented family id title use_case evidence =
  { (planned family id title use_case) with status = Implemented; evidence }

let capability_70_manifest =
  "docs/evidence/infranodus-ocaml/capability-70/manifest.json"

let workspace_capability_evidence =
  [ "harness/workspace_domain.ml"; "harness/workspace_store.ml";
    "harness/workspace_codec.ml"; "harness/dream_backend_app.ml";
    "harness/ui_web/main.ml"; "harness/playwright_controller.ml";
    capability_70_manifest ]

let processing_capability_evidence =
  [ "harness/graph_processing.ml"; "harness/graph_revision.ml";
    "harness/dream_backend_app.ml"; "harness/ui_web/main.ml";
    "harness/playwright_controller.ml"; capability_70_manifest ]

let visualization_capability_evidence =
  [ "harness/ui_web/workspace_graph_geometry.ml"; "harness/ui_web/main.ml";
    "harness/figma_design.ml"; "harness/playwright_controller.ml";
    capability_70_manifest ]

let analytics_capability_evidence =
  [ "harness/graph_analytics.ml"; "harness/graph_revision.ml";
    "harness/dream_backend_app.ml"; "harness/ui_web/main.ml";
    "harness/playwright_controller.ml"; capability_70_manifest ]

let export_capability_evidence =
  [ "harness/graph_export.ml"; "harness/dream_backend_app.ml";
    "harness/ui_web/main.ml"; "harness/playwright_controller.ml";
    capability_70_manifest ]

let acquisition_capability_evidence =
  [ "harness/infranodus_acquisition.ml"; "harness/infranodus_host_adapter.ml";
    "harness/dream_backend_app.ml"; "harness/mcp_server.ml";
    "harness/ui_web/main.ml"; "harness/playwright_controller.ml";
    capability_70_manifest ]

let intelligence_capability_evidence =
  [ "harness/graph_intelligence_workspace.ml"; "harness/graph_analytics.ml";
    "harness/dream_backend_app.ml"; "harness/mcp_server.ml";
    "harness/ui_web/main.ml"; "harness/playwright_controller.ml";
    capability_70_manifest ]

let all =
  [
    implemented Workspace "F1.1" "Project lifecycle" "Create, rename, favorite, duplicate, archive, and delete analyses"
      [ "harness/workspace_domain.ml"; "harness/workspace_store.ml";
        "harness/dream_backend_app.ml"; "harness/ui_web/main.ml";
        "harness/playwright_controller.ml";
        "docs/evidence/infranodus-ocaml/f1-lifecycle/manifest.json" ];
    implemented Workspace "F1.2" "Non-persistent analysis" "Analyze sensitive material without durable graph state"
      [ "harness/workspace_store.ml"; "harness/dream_backend_app.ml";
        "harness/ui_web/main.ml"; "harness/playwright_controller.ml";
        "docs/evidence/infranodus-ocaml/f1-lifecycle/manifest.json" ];
    implemented Workspace "F1.3" "Project inventory" "Find prior work by name, date, type, language, and favorite state"
      [ "harness/workspace_domain.ml"; "harness/workspace_store.ml";
        "harness/workspace_codec.ml"; "harness/dream_backend_app.ml";
        "harness/ui_web/workspace_ui_state.ml"; "harness/ui_web/main.ml";
        "harness/playwright_controller.ml";
        "docs/evidence/infranodus-ocaml/f1-inventory/manifest.json" ];
    implemented Workspace "F1.4" "Saved graph views" "Restore layout, filters, selection, and camera as one analytical lens"
      workspace_capability_evidence;
    implemented Workspace "F1.5" "Share and embed" "Publish, embed, and revoke an explicitly visible result"
      workspace_capability_evidence;
    implemented Workspace "F1.6" "Project notes" "Save interpretations and prompts against a graph revision"
      workspace_capability_evidence;
    implemented Acquisition "F2.1" "Live editor and paste" "Turn pasted or edited text into a deterministic preview graph"
      [ "harness/graph_ingest.ml"; "harness/test_dream_backend.ml"; "harness/ui_web/main.ml" ];
    implemented Acquisition "F2.2" "Document upload" "Import TXT, Markdown, JSON, and PDF documents with provenance"
      acquisition_capability_evidence;
    implemented Acquisition "F2.3" "CSV and spreadsheet import" "Choose text columns and metadata filters for surveys or reviews"
      acquisition_capability_evidence;
    implemented Acquisition "F2.4" "Batch import" "Process a corpus with per-item progress, errors, and totals"
      acquisition_capability_evidence;
    implemented Acquisition "F2.5" "Web and feed import" "Preview and ingest a URL, site, sitemap, RSS, or XML source"
      acquisition_capability_evidence;
    implemented Acquisition "F2.6" "Search import" "Research a topic or prior art through search and Scholar adapters"
      acquisition_capability_evidence;
    implemented Acquisition "F2.7" "YouTube import" "Analyze transcripts, comments, channels, playlists, and search results"
      acquisition_capability_evidence;
    implemented Acquisition "F2.8" "Social and commerce import" "Study market and sentiment data with explicit provider and quota state"
      acquisition_capability_evidence;
    implemented Acquisition "F2.9" "Knowledge-note import" "Preserve files, folders, wiki links, entities, and tags from notes"
      acquisition_capability_evidence;
    implemented Acquisition "F2.10" "Graph import" "Validate and ingest CSV, GEXF, and Graphology-compatible networks"
      acquisition_capability_evidence;
    implemented Acquisition "F2.11" "API and MCP ingest" "Submit typed graph content through automation interfaces"
      acquisition_capability_evidence;
    implemented Processing "F3.1" "Language and lemmatization" "Choose and observe the effective multilingual processing profile"
      processing_capability_evidence;
    implemented Processing "F3.2" "Stop and protected words" "Remove noise while retaining domain-specific terms reversibly"
      processing_capability_evidence;
    implemented Processing "F3.3" "Synonyms and aliases" "Merge terminology while preserving inspectable source aliases"
      processing_capability_evidence;
    implemented Processing "F3.4" "Typed token families" "Process words, wiki links, entities, mentions, and tags as typed nodes"
      processing_capability_evidence;
    implemented Processing "F3.5" "Co-occurrence window" "Tune relation locality and deterministically recompute edges"
      [ "harness/graph_ingest.ml"; "harness/test_graph_intelligence.ml" ];
    implemented Processing "F3.6" "Graph semantics mode" "Switch explicitly between words-plus-entities and entity-only graphs"
      processing_capability_evidence;
    implemented Processing "F3.7" "Metadata and sentiment tags" "Segment statements while retaining tag and filter provenance"
      processing_capability_evidence;
    implemented Processing "F3.8" "Graph curation" "Add, rename, merge, and remove nodes or edges as revisioned edits"
      processing_capability_evidence;
    implemented Visualization "F4.1" "Force-directed graph" "Inspect weighted concepts, relations, and communities spatially"
      [ "harness/ui_web/main.ml"; "harness/playwright_controller.ml" ];
    implemented Visualization "F4.2" "Camera controls" "Pan, zoom, fit, and reset without semantic mutation"
      visualization_capability_evidence;
    implemented Visualization "F4.3" "Selection" "Select concepts and drive contextual inspection from graph state"
      [ "harness/ui_web/main.ml"; "harness/playwright_controller.ml" ];
    implemented Visualization "F4.4" "Search and focus" "Locate concepts, highlight matches, and inspect local context"
      [ "harness/ui_web/main.ml"; "harness/playwright_controller.ml" ];
    implemented Visualization "F4.5" "Visibility filters" "Reduce visual noise by degree and node-count controls"
      [ "harness/ui_web/main.ml"; "harness/playwright_controller.ml" ];
    implemented Visualization "F4.6" "Reveal underlying ideas" "Remove dominant concepts and recompute a peripheral view"
      visualization_capability_evidence;
    implemented Visualization "F4.7" "Display settings" "Change labels, node sizes, colors, and edge presentation without data loss"
      visualization_capability_evidence;
    implemented Visualization "F4.8" "Layout selector" "Compare reproducible spatial encodings of the same graph"
      visualization_capability_evidence;
    implemented Visualization "F4.9" "Dynamic playback" "Advance timeline and visible statements together at a controlled speed"
      visualization_capability_evidence;
    implemented Visualization "F4.10" "Mind map and word cloud" "Project the same graph as a hierarchy or contextual cloud"
      visualization_capability_evidence;
    implemented Visualization "F4.11" "Comparison graph" "Inspect merge, overlap, difference, and difference-node modes"
      visualization_capability_evidence;
    implemented Visualization "F4.12" "Responsive graph view" "Present and capture a responsive full graph visualization"
      [ "harness/ui_web/main.ml"; "harness/test_playwright_controller.ml" ];
    implemented Analytics "F5.1" "Source excerpts" "Validate selected concepts against their source statements"
      analytics_capability_evidence;
    implemented Analytics "F5.2" "Main ideas and topics" "Inspect community labels, influence, members, and percentages"
      analytics_capability_evidence;
    implemented Analytics "F5.3" "Influential concepts" "Rank discourse entrances using centrality and degree observations"
      [ "harness/graph_intelligence.ml"; "harness/test_graph_intelligence.ml" ];
    implemented Analytics "F5.4" "Content gaps" "Rank candidate bridges between graph communities"
      [ "harness/graph_intelligence.ml"; "harness/test_graph_intelligence.ml" ];
    implemented Analytics "F5.5" "Conceptual gateways" "Find less-congested connectors using globality and locality evidence"
      analytics_capability_evidence;
    implemented Analytics "F5.6" "Relation analysis" "Inspect selected and globally ranked co-occurrences with weights"
      analytics_capability_evidence;
    implemented Analytics "F5.7" "Sentiment panel" "Compare positive, negative, and neutral segments and filters"
      analytics_capability_evidence;
    implemented Analytics "F5.8" "Text and network statistics" "Observe counts, density, components, and centralities"
      [ "harness/graph_intelligence.ml"; "harness/test_graph_intelligence.ml" ];
    implemented Analytics "F5.9" "Diversity and structure" "Assess modularity, focus, plurality, and influence distribution"
      analytics_capability_evidence;
    implemented Analytics "F5.10" "Trends and emerging terms" "Brush cumulative topic and keyword series through time"
      analytics_capability_evidence;
    implemented Analytics "F5.11" "Influence propagation" "Inspect disclosed propagation series and DFA-oriented classification"
      analytics_capability_evidence;
    implemented Analytics "F5.12" "Degree distribution" "Analyze degree distribution and optional fit observations"
      analytics_capability_evidence;
    implemented Analytics "F5.13" "LDA comparison" "Compare separately labeled probabilistic and network topic models"
      analytics_capability_evidence;
    implemented Analytics "F5.14" "Analytics downloads" "Export observations for the current graph revision and filters"
      analytics_capability_evidence;
    implemented Intelligence "F6.1" "Topic overview" "Generate a revision-scoped, source-scoped orientation"
      intelligence_capability_evidence;
    implemented Intelligence "F6.2" "Focused summary" "Summarize selected evidence while retaining visible excerpts"
      intelligence_capability_evidence;
    implemented Intelligence "F6.3" "Gap ideation" "Generate questions and ideas linked to a selected structural gap"
      intelligence_capability_evidence;
    implemented Intelligence "F6.4" "Graph-aware chat" "Answer through a graph retrieval packet with source evidence"
      intelligence_capability_evidence;
    implemented Intelligence "F6.5" "Prompt augmentation" "Export concepts, paths, topics, and citations to steer another model"
      intelligence_capability_evidence;
    implemented Intelligence "F6.6" "GraphRAG retrieval" "Retrieve deterministic graph-grounded evidence without a model"
      intelligence_capability_evidence;
    implemented Intelligence "F6.7" "Classification and ontology" "Review generated entities, relations, categories, and rules"
      intelligence_capability_evidence;
    implemented Intelligence "F6.8" "Generated project notes" "Append or replace labeled analytical output in project notes"
      intelligence_capability_evidence;
    implemented Intelligence "F6.9" "Model and provider selection" "Observe configured, unavailable, and rate-limited provider states"
      intelligence_capability_evidence;
    implemented Integration "F7.1" "Graph image export" "Capture the visible graph as PNG evidence"
      [ "harness/playwright_controller.ml"; "harness/test_playwright_controller.ml" ];
    implemented Integration "F7.2" "Statement export" "Export filtered statements with topics, sentiment, and metadata"
      export_capability_evidence;
    implemented Integration "F7.3" "Analytics export" "Export revision-labeled analytics as TXT or CSV"
      export_capability_evidence;
    implemented Integration "F7.4" "Graph data export" "Serialize a referentially closed graph as JSON, GraphML, or DOT"
      [ "harness/graph_intelligence.ml"; "harness/test_graph_intelligence.ml" ];
    implemented Integration "F7.5" "Source backup" "Round-trip the source corpus and its metadata"
      export_capability_evidence;
    implemented Integration "F7.6" "REST API" "Control graph, evidence, analytics, comparison, and intelligence through typed routes"
      [ "harness/dream_backend_app.ml"; "harness/test_dream_backend.ml";
        "harness/playwright_controller.ml"; capability_70_manifest ];
    implemented Integration "F7.7" "MCP adapter" "Expose the same authority-bounded operations to agents"
      [ "harness/mcp_server.ml"; "harness/test_graph_export.ml" ];
    implemented Integration "F7.8" "Host adapters" "Map browser, Obsidian, IDE, and n8n hosts to shared acquisition contracts"
      acquisition_capability_evidence;
    implemented Integration "F7.9" "Quota and progress" "Observe bounded execution, truncation, rejection, retry, and usage"
      [ "harness/dream_backend_app.ml"; "harness/ui_web/main.ml";
        "harness/test_dream_backend.ml"; "harness/playwright_controller.ml";
        capability_70_manifest ];
    implemented Integration "F7.10" "Deletion and visibility" "Confirm destructive and private-to-public transitions explicitly"
      workspace_capability_evidence;
  ]

let expected_ids =
  let range family count = List.init count (fun index -> Printf.sprintf "F%d.%d" family (index + 1)) in
  range 1 6 @ range 2 11 @ range 3 8 @ range 4 12 @ range 5 14 @ range 6 9 @ range 7 10

let validate features =
  let ids = List.map (fun feature -> feature.id) features in
  let unique = List.sort_uniq String.compare ids in
  let errors = ref [] in
  if ids <> expected_ids then errors := "feature IDs are not the canonical F1.1-F7.10 sequence" :: !errors;
  if List.length ids <> List.length unique then errors := "duplicate feature IDs" :: !errors;
  List.iter
    (fun feature ->
      if String.trim feature.title = "" || String.trim feature.use_case = "" then
        errors := (feature.id ^ " has blank metadata") :: !errors;
      if feature.ui_controls = [] then errors := (feature.id ^ " has no UI control contract") :: !errors;
      if feature.scenario_ids = [] then errors := (feature.id ^ " has no scenario contract") :: !errors;
      match feature.status with
      | Implemented when feature.evidence = [] ->
          errors := (feature.id ^ " claims implementation without evidence") :: !errors
      | Implemented | Adapter_ready | Planned | Unknown_not_claimed -> ())
    features;
  match List.rev !errors with [] -> Ok () | values -> Error values

let find wanted = List.find_opt (fun feature -> String.equal wanted feature.id) all

let to_yojson feature =
  `Assoc
    [
      ("id", `String feature.id);
      ("family", `String (family_name feature.family));
      ("title", `String feature.title);
      ("behavior", `String (behavior_name feature.behavior));
      ("use_case", `String feature.use_case);
      ("status", `String (status_name feature.status));
      ("ui_controls", `List (List.map (fun value -> `String value) feature.ui_controls));
      ("scenario_ids", `List (List.map (fun value -> `String value) feature.scenario_ids));
      ("evidence", `List (List.map (fun value -> `String value) feature.evidence));
    ]

let to_markdown features =
  let header =
    "| ID | Family | Feature | Behavior | Use case | Status | UI control | Scenario | Evidence |\n"
    ^ "|---|---|---|---|---|---|---|---|---|\n"
  in
  let row feature =
    Printf.sprintf "| %s | %s | %s | %s | %s | %s | `%s` | `%s` | %s |\n"
      feature.id (family_name feature.family) feature.title (behavior_name feature.behavior)
      feature.use_case (status_name feature.status) (String.concat "`, `" feature.ui_controls)
      (String.concat "`, `" feature.scenario_ids)
      (match feature.evidence with [] -> "-" | values -> String.concat "<br>" values)
  in
  header ^ String.concat "" (List.map row features)

[@@@warning "-32"]

module type REGISTRY = sig
  val all : t list
  val find : string -> t option
  val validate : t list -> (unit, string list) result
end

module _ : REGISTRY = struct
  let all = all
  let find = find
  let validate = validate
end

[@@@warning "+32"]
