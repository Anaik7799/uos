#!/usr/bin/env -S opam exec -- ocaml
#use "product_catalog.ml";;
#require "str";;
(* @agent_intent: Derive one native product specification and its detailed
   SQLite import package from existing UOS requirements and the source review.
   @laws: preserve stable IDs and all acceptance cases; source is not proof;
   no external executable source, credentials, model weights or DB bytes. *)
let stamp = "20260907-1837"
let plan = "uos/agentic-product/" ^ stamp
let get_json p = Yojson.Basic.from_string (read_document p)
let strs xs = `List (List.map (fun s -> `String s) xs)
let source_spec = "docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json"
let review_path = "docs/reviews/" ^ stamp ^ "-zigvm-harness-product-feature-oracle-review.md"
let observations_path = "docs/reviews/" ^ stamp ^ "-product-management-source-observations.json"
let detail_path = "docs/design/" ^ stamp ^ "-agentic-product-detailed-specification.md"
let definitions_path = "governance/capability-inventory/" ^ stamp ^ "-product-management-definitions.json"
let source_path = "docs/design/" ^ stamp ^ "-operator-agentic-infrastructure-source.txt"
let mapping path =
  let baseline_path = path in
  let path = match path with
    | "apps/uos_tui/src/uos_tui/swarm.gleam" -> "apps/uos_swarm/src/uos_swarm/swarm.gleam"
    | "apps/uos_tui/src/uos_tui/board.gleam" -> "apps/uos_swarm/src/uos_swarm/board.gleam"
    | "apps/uos_tui/src/uos_tui/coord.gleam" -> "apps/uos_swarm/src/uos_swarm/coord.gleam"
    | path -> path in
  let present = Sys.file_exists path in
  `Assoc ["path",`String path;"status",`String (if present then "SOURCE_PRESENT" else "ABSENT");
    "baseline_path",`String baseline_path;
    "sha256",(if present then `String (sha (read path)) else `Null);
    "runtime_status",`String "UNRUN"]
let service_details = [
 "01",["go-spiffe";"spiffe"],"Per-agent short-lived identity, rotation and authenticated tenant binding remain unverified.";
 "02",["opa";"cedar"],"Typed policy runs on MCP dispatch; externalized policy and durable approvals are incomplete.";
 "03",["arcade-ai";"openbao"],"Generic delegated user scope and provider lifecycle need end-to-end verification.";
 "04",["openbao"],"Opaque credential leases and secure key custody at the actual tool boundary remain unverified.";
 "05",["nemo-guardrails"],"Output guardrails, injection evaluation and strict transport/schema boundaries need executed acceptance.";
 "06",["consul-reference"],"Health/lease/capability registration exists in pieces; Consul behavioral oracle is not pinned locally.";
 "07",["modelcontextprotocol"],"Protocol/policy components exist; tenant, schemas, framing and effect preflight need joint acceptance.";
 "08",["nats-server"],"Zenoh is the native backplane; durable outbox/inbox, tenant ACL and delivery parity need evidence.";
 "09",["dragonfly";"valkey"],"ETS/cache components exist; tenant/principal partitions, quotas and crash recovery are unverified.";
 "10",["qdrant"],"Native similarity/index code exists; real versioned embeddings and authorization before scoring remain gaps.";
 "11",["openCypher"],"Pure BEAM/Hermes graph reuse; provenance and ACL on derived paths need runtime checks.";
 "12",["letta"],"Compaction components exist; preserved policy, unresolved tool pairs and model tokenizer bounds need evidence.";
 "13",["E2B"],"Deterministic VFS is not a hostile-code sandbox; real isolation, egress and descendant reaping remain unverified.";
 "14",["temporal"],"Sa-plan durability/control replay exists; model/tool outcome replay and ambiguous-effect reconciliation need integration.";
 "15",["arcade-ai"],"Signed approval primitives exist; durable per-action approval consumption and reauthorization need integration.";
 "16",["langgraph"],"Prajna breakers exist; semantic repeated-state, no-progress and recursion limits need dispatch integration.";
 "17",["litellm"],"Provider/advisory routing exists; fallback spend reservations and actual MAX inference need evidence.";
 "18",["langfuse";"trace-context";"opentelemetry-specification"],"Trace emitters exist; propagation/schema parity, persisted trajectory and usage correlation need evidence.";
 "19",["litellm"],"Per-request caps exist; atomic simultaneous global/tenant/user/workflow budgets remain incomplete.";
 "20",["immudb"],"SQLite evidence and signed receipts exist; anchored tamper-evident history and restore proofs need integration.";
 "21",["promptfoo";"deepeval"],"Native contract/differential suites exist; versioned trajectory and prompt regression rollout gates remain unverified."
]
let infra_feature service =
  let id = text "id" service in
  let number = String.sub id (String.length id - 2) 2 in
  let _,oracles,gap = List.find (fun (n,_,_) -> n=number) service_details in
  `Assoc ["id",`String id;"name",member "name" service;"category",member "layer" service;
    "status",`String "MAPPED";"actor_intent",member "actor" service;
    "fractal_layer",member "fractal_layer" service;
    "use_case",`String ("Provide " ^ text "name" service ^ " within the initiating user's authorized UOS workflow.");
    "requirements",`List [`Assoc ["id",member "requirement_id" service;"shall",member "shall" service]];
    "acceptance",member "acceptance" service;"oracle_ids",strs oracles;
    "mappings",`List (items "reuse_paths" service |> List.map (fun p -> mapping (to_string p)));
    "gap",`String gap;
    "implementation",`String ("Reuse " ^ text "actor" service ^ " role in Gleam/OTP with the listed native UOS modules; preserve Hermes/SQLite, Zenoh and isolated MAX boundaries.");
    "evidence_basis",`String "Existing requirement and prior source review plus fresh listed-file digest; full runtime acceptance UNRUN.";
    "sa_plan_task",`Null;"catalog_task",`String "CATALOG";
    "oracle_comparison",`String "Drive each acceptance with the same normalized inputs against the pinned reference and UOS; retain mismatches/unavailable outcomes; pin comparator and normalizer.";
    "admission_status",`String "NOT_ADMITTED"]
let management_feature d =
  let id = text "id" d in
  let case suffix assertion = `Assoc ["id",`String (id^"-"^suffix);"assertion",`String assertion;"status",`String "UNRUN"] in
  `Assoc ["id",`String id;"name",member "name" d;"category",`String "Product, specification, feature and oracle management";
    "status",`String "REVIEWED";"use_case",member "use_case" d;
    "requirements",`List [`Assoc ["id",`String (id^"-R1");"shall",member "shall" d]];
    "acceptance",`List [case "T1" (text "shall" d);case "T2" (text "negative" d);
      case "T3" ("Repeat the " ^ text "name" d ^ " operation at a new candidate and prove stale evidence does not carry verification credit.")];
    "oracle_ids",strs ["zigvm-management";"harness-management"];
    "mappings",`List [mapping (text "canonical_path" d)];
    "gap",member "gap" d;"implementation",member "implementation" d;
    "sa_plan_task",`Null;"catalog_task",`String "CATALOG";"admission_status",`String "NOT_ADMITTED"]
let file_artifact ~id ~kind path =
  let body = read path in let digest = sha body in
  `Assoc ["id",`String id;"revision",`String digest;"kind",`String kind;
    "locator",`String path;"sha256",`String digest;"content",`String body]
let external_artifacts observations =
  items "sources" observations |> List.concat_map (fun root ->
    items "files" root |> List.filter_map (fun f ->
      if text "status" f = "ABSENT" then None else
      let id = (if text "root" root = "/home/an/dev/ver/zigvm" then "zigvm:" else "harness:") ^ text "relative_path" f in
      Some (`Assoc ["id",`String id;"revision",member "sha256" f;"kind",`String "external-source-reference";
        "locator",member "locator" f;"sha256",member "sha256" f;"content",`Null;
        "source_revision",member "head" root;"writers_quiesced",`Bool false;"admission",`String "NOT_INGESTED"])))
let findings review =
  String.split_on_char '\n' review |> List.filter_map (fun line ->
    if String.contains line '*' && String.contains line ':' then
      try
        let start = Str.search_forward (Str.regexp "PM-F[0-9][0-9]") line 0 in
        let id = String.sub line start 6 in
        let title_end = Str.search_forward (Str.regexp_string "** ") line (start+6) in
        let title_start = start + String.length (id ^ " — ") in
        let title = String.sub line title_start (title_end-title_start) in
        Some (`Assoc ["id",`String id;"severity",`String (if String.starts_with ~prefix:"High" title then "HIGH" else "MEDIUM");
          "title",`String title;"detail",`String line;"basis",`String "SOURCE_REVIEW_AND_READONLY_METADATA";"status",`String "OPEN_FOR_ADOPTION"])
      with Not_found | Invalid_argument _ -> None
    else None)
let () =
  let baseline = get_json source_spec and observations = get_json observations_path in
  let features = List.map infra_feature (items "services" baseline) @
    List.map management_feature (get_json definitions_path |> items "management_features") in
  let oracles = List.map (fun o -> `Assoc ["id",member "id" o;"status",member "pin_status" o;
    "reference",o;"execution_status",`String "UNRUN";"role",`String "READ_ONLY_BEHAVIOR_REFERENCE"])
    (items "oracles" observations) @
    (items "sources" observations |> List.map (fun o ->
      `Assoc ["id",`String (if text "root" o = "/home/an/dev/ver/zigvm" then "zigvm-management" else "harness-management");
        "status",`String "DIRTY_SOURCE_OBSERVED";"source_revision",member "head" o;"locator",member "root" o;
        "writers_quiesced",`Bool false;"execution_status",`String "UNRUN";"role",`String "READ_ONLY_MANAGEMENT_REFERENCE"])) @
    [`Assoc ["id",`String "consul-reference";"status",`String "NOT_PINNED";
       "locator",`String "https://github.com/hashicorp/consul";"execution_status",`String "UNRUN";
       "role",`String "REQUESTED_SERVICE_DISCOVERY_REFERENCE"]] in
  let spec = `Assoc ["id",`String "uos-agentic-infrastructure-and-product-management";"revision",`String stamp;
    "title",`String "Production agentic infrastructure and full product/specification/feature/oracle management";
    "created_at",member "observed_at" observations;"sa_plan_plan",`String plan;
    "admission_status",`String "NOT_ADMITTED";"purpose",`String "Realize the supplied architecture with existing UOS elements and keep product requirements, source/oracle mappings, artifacts and evidence queryable.";
    "outcome_hypothesis",`String "Traceable complete requirements reduce omitted security controls and false completion claims; benefit is not yet measured.";
    "measured_outcome",`Null;"execution_authority",`String "Sa-plan only";
    "native_baseline",baseline;
    "readiness_criteria",strs ["workload identity";"sandbox egress";"durable replay";"simultaneous budgets";"cycle detection";"policy separation"]] in
  let b = Buffer.create 32000 in
  Printf.bprintf b "# %s — Detailed product specification and feature list\n\n#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda\n\n" stamp;
  Buffer.add_string b ("[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Review](http://nas-1.tail55d152.ts.net:4100/files/"^review_path^") · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/"^detail_path^")\n\n");
  Printf.bprintf b "Status: requirements and source mapping; production NOT_ADMITTED. %d features: 21 infrastructure services and 25 management capabilities. All %d acceptance definitions remain UNRUN until their own evidence is collected. Catalog software test receipts are separate.\n\n"
    (List.length features) (List.fold_left (fun n f -> n + List.length (items "acceptance" f)) 0 features);
  Buffer.add_string b "## Feature index\n\n| ID | Feature | State | Reference oracle |\n|---|---|---|---|\n";
  List.iter (fun f -> Printf.bprintf b "| %s | %s | %s | %s |\n" (text "id" f) (text "name" f) (text "status" f)
    (items "oracle_ids" f |> List.map to_string |> String.concat ", ")) features;
  List.iter (fun f ->
    Printf.bprintf b "\n## %s — %s\n\n**Use case:** %s\n\n**Native implementation:** %s\n\n**Remaining gap:** %s\n\n"
      (text "id" f) (text "name" f) (text "use_case" f) (text "implementation" f) (text "gap" f);
    List.iter (fun r -> Printf.bprintf b "**%s:** %s\n\n" (text "id" r) (text "shall" r)) (items "requirements" f);
    List.iter (fun m -> Printf.bprintf b "- [%s](http://nas-1.tail55d152.ts.net:4100/files/%s) — %s; runtime UNRUN.\n"
      (text "path" m) (text "path" m) (text "status" m)) (items "mappings" f);
    Buffer.add_string b "\n**Acceptance:**\n\n";
    List.iter (fun a -> Printf.bprintf b "- [ ] %s — %s\n" (text "id" a) (text "assertion" a)) (items "acceptance" f)) features;
  let review = read review_path in
  let pos = Str.search_forward (Str.regexp_string "## Comprehensive verification checklist") review 0 in
  let footer = Str.search_forward (Str.regexp_string "**Previous:**") review pos in
  Buffer.add_string b ("\n" ^ String.sub review pos (footer-pos));
  Printf.bprintf b "**Previous:** [Management review](http://nas-1.tail55d152.ts.net:4100/files/%s) · **Next:** [Completion journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/%s-agentic-product-management-review-journal.md)\n\n**UOS footer:** versioned product and artifact catalog; Sa-plan owns execution; acceptance definitions remain UNRUN.\n" review_path stamp;
  (match Bos.OS.File.write (Fpath.v detail_path) (Buffer.contents b) with Ok () -> () | Error (`Msg e) -> fail e);
  let artifacts = [file_artifact ~id:"operator-architecture" ~kind:"user-source" source_path;
    file_artifact ~id:"management-review" ~kind:"review" review_path;
    file_artifact ~id:"source-observations" ~kind:"observations" observations_path;
    file_artifact ~id:"detailed-product-specification" ~kind:"specification" detail_path;
    file_artifact ~id:"native-baseline-specification" ~kind:"specification" source_spec;
    file_artifact ~id:"management-definitions" ~kind:"definition" definitions_path] @ external_artifacts observations in
  let links = List.map (fun a -> `Assoc ["artifact_id",member "id" a;"artifact_revision",member "revision" a;"role",member "kind" a]) artifacts in
  let manifest = `Assoc ["schema",`String "uos.product-catalog/v1";"specification",spec;
    "features",`List features;"oracles",`List oracles;"artifacts",`List artifacts;
    "artifact_links",`List links;"findings",`List (findings review)] in
  validate manifest;
  let path = "governance/capability-inventory/" ^ stamp ^ "-agentic-product-manifest.json" in
  match Bos.OS.File.write (Fpath.v path) (Yojson.Basic.pretty_to_string manifest ^ "\n") with
  | Ok () -> Printf.printf "manifest=%s features=%d artifacts=%d\n" path (List.length features) (List.length artifacts)
  | Error (`Msg e) -> fail e
