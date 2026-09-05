type stratum = Production | Generated | Verification | Tooling
type effect_posture = Pure | Read_only | Guarded_write | External_effect
type fpp_mapping =
  | Fpp_components of (Fpp_window_authority.owner * string list) list
  | Fpp_not_applicable of string
type mediation =
  | Direct_read
  | Run_swarm_bridge of string list
  | Unavailable_until_bridge_activity of string
type t = {
  stable_id : string; owner_directory : string; purpose : string;
  stratum : stratum; libraries : Stanza.t list; plane : Ops_capability.plane;
  coordinate : Ops_capability.coordinate; effect_posture : effect_posture;
  configuration_ids : string list; capability_ids : string list;
  surfaces : (Ops_capability.surface * Ops_capability.applicability) list;
  fpp : fpp_mapping; mediation : mediation;
}

let string_of_stratum = function Production -> "production" | Generated -> "generated" | Verification -> "verification" | Tooling -> "tooling"
let string_of_effect_posture = function Pure -> "pure" | Read_only -> "read-only" | Guarded_write -> "guarded-write" | External_effect -> "external-effect"

let all_surfaces =
  [ Ops_capability.Ocaml_api; Ops_capability.Cli;
    Ops_capability.Mcp; Ops_capability.Zenoh ]

let internal_surfaces =
  [ (Ops_capability.Ocaml_api, Ops_capability.Applicable);
    (Ops_capability.Cli,
     Ops_capability.Not_applicable "internal module area has no independent CLI command");
    (Ops_capability.Mcp,
     Ops_capability.Not_applicable "internal module area is projected through typed Ops commands");
    (Ops_capability.Zenoh,
     Ops_capability.Not_applicable "internal module area is projected through typed Ops commands") ]

let command_surfaces =
  List.map (fun surface -> (surface, Ops_capability.Applicable)) all_surfaces

let c level phase = Ops_capability.{ level; phase }
let na reason = Fpp_not_applicable reason
let fpp owner components = Fpp_components [ (owner, components) ]

type specification = {
  directory : string; purpose : string; stratum : stratum;
  plane : Ops_capability.plane; coordinate : Ops_capability.coordinate;
  effect_posture : effect_posture; configuration_ids : string list;
  capability_ids : string list; surfaces : (Ops_capability.surface * Ops_capability.applicability) list;
  fpp : fpp_mapping; mediation : mediation;
}

let harness_components =
  [ "inventory"; "capability_catalog"; "gospel_contracts";
    "reference_capture"; "parity_normalizer"; "evidence_store";
    "parity_compare"; "parity_algebra"; "resource_envelope"; "blueprint";
    "harness_config"; "control_plane"; "homeostasis"; "hermes_zenoh";
    "irmin"; "eio"; "fractal_diagnostic"; "agents"; "sop"; "planning";
    "job_manager"; "temporal"; "skills"; "superpowers"; "rules" ]

let operations_components =
  [ "runSupervisor"; "reteUlGate"; "ravenGate"; "stpaFmeaGate";
    "ruliadAnalyzer"; "stanReliability"; "z3FormalGate";
    "swarmExecutionBridge"; "suiteWorker"; "runEventStore";
    "resourceSampler"; "zenohRunBridge"; "dreamGateway";
    "bonsaiDashboard"; "uiIntentCompiler"; "uiEffectInterpreter";
    "webglRenderer"; "assuranceGate"; "completionGate" ]

let spec ?(stratum = Production) ?(plane = Ops_capability.Control_plane)
    ?(coordinate = c Ops_capability.L2 Ops_capability.Observe)
    ?(effect_posture = Pure) ?(configuration_ids = [])
    ?(capability_ids = []) ?(surfaces = internal_surfaces)
    ?(mediation = Direct_read) directory purpose fpp =
  { directory; purpose; stratum; plane; coordinate; effect_posture;
    configuration_ids; capability_ids; surfaces; fpp; mediation }

let specifications =
  [ spec ~stratum:Tooling "modules/fetch_cowboy"
      "Bounded source acquisition executable"
      (na "build-time acquisition tool is not a resident FPP component");
    spec "modules/hermes_agent_loop"
      "Typed agent conversation, context, tool, memory, and lifecycle kernel"
      (fpp Fpp_window_authority.Harness
         [ "agents"; "planning"; "job_manager"; "skills"; "superpowers"; "rules" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Run_swarm_bridge [ "activity.verify-sqlite-dependability" ])
      "modules/hermes_dependability"
      "Dependability algebra, SQLite lifecycle, solver, process, and topology"
      (Fpp_components
         [ (Fpp_window_authority.Operations, [ "runEventStore" ]);
           (Fpp_window_authority.Harness, [ "resource_envelope" ]) ]);
    spec ~stratum:Tooling "modules/hermes_dune_graph"
      "Fail-closed Dune graph and generated dependency witnesses"
      (na "build graph authority is modeled as compilation structure, not runtime FPP");
    spec "modules/hermes_fpp_authority"
      "Normative five-owner FPP identity and allocation-window authority"
      (na "FPP allocation authority governs models and is not itself a modeled component");
    spec ~effect_posture:Guarded_write
      ~configuration_ids:
        [ "OPENROUTER_API_KEY"; "QCHECK_SEED"; "HERMES_Z3";
          "HERMES_GOSPEL"; "HERMES_COQC"; "HERMES_REFERENCE_PYTHON";
          "HERMES_ZENOH"; "HERMES_ZENOH_ENDPOINT"; "PYTHONPATH" ]
      ~mediation:(Run_swarm_bridge [ "activity.verify-repository" ])
      "modules/hermes_harness"
      "Hermes parity harness, evidence, formal, safety, and observation capabilities"
      (fpp Fpp_window_authority.Harness harness_components);
    spec ~stratum:Generated "modules/hermes_harness/generated_rocq"
      "Extracted Rocq parity-lattice implementation"
      (na "generated proof extraction is represented by its owning harness component");
    spec ~stratum:Tooling "modules/hermes_harness_stubber"
      "Parallel OCaml harness source generator"
      (na "source generator is a build tool and has no resident runtime instance");
    spec ~effect_posture:External_effect
      ~mediation:(Unavailable_until_bridge_activity
        "Nix and Devenv operations remain unavailable until a closed typed activity is admitted by Run_swarm_bridge")
      "modules/hermes_nix"
      "Typed Nix, Determinate Systems, and Devenv ecosystem algebra and intent controller"
      (na "nix adapter is governed by Ops but has no FPP runtime instance");
    spec ~effect_posture:Guarded_write ~surfaces:command_surfaces
      ~capability_ids:[ "capability.fpp-check"; "capability.verify-full" ]
      ~mediation:(Run_swarm_bridge [ "activity.verify-repository" ])
      "modules/hermes_ops"
      "Four-surface declarative command, governance, configuration, and completion plane"
      (Fpp_components
         [ (Fpp_window_authority.Ops_monitor, [ "opsVerifier" ]);
           (Fpp_window_authority.Completion,
            [ "commandGateway"; "completionHistory"; "mbseProjector"; "formalOracle" ]) ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Run_swarm_bridge
        [ "activity.verify-sqlite-dependability"; "activity.verify-repository" ])
      "modules/hermes_ops_dashboard"
      "Operations authority, assurance, FPP/MBSE projections, dashboard, and Swarm bridge"
      (fpp Fpp_window_authority.Operations operations_components);
    spec ~effect_posture:External_effect
      ~configuration_ids:
        [ "HERMES_VISION_VM1"; "HERMES_VISION_UI_PORT";
          "HERMES_DATARHEI_WEBRTC"; "HERMES_OVENPLAYER_STATIC" ]
      ~mediation:(Unavailable_until_bridge_activity
        "server lifecycle has no admitted declarative Run_topology activity")
      "modules/hermes_server" "Dream server process boundary"
      (fpp Fpp_window_authority.Operations [ "dreamGateway" ]);
    spec "modules/hermes_stanza"
      "Generated unforgeable Dune-library identity and reverse-cone witnesses"
      (na "compile-time library witness has no resident FPP component");
    spec "modules/hermes_sysml"
      "SysML algebra and typed system-model projections"
      (fpp Fpp_window_authority.Operations [ "z3FormalGate" ]);
    spec ~stratum:Tooling "modules/hermes_toolchain"
      "Derived OCaml switch and dependency conformance gate"
      (na "toolchain verifier is a build gate rather than a resident FPP component");
    spec ~effect_posture:External_effect
      ~configuration_ids:
        [ "JUJUTSU_RELEASE_ID"; "JUJUTSU_CONFIG_ID";
          "JUJUTSU_OPERATOR_PUBLIC_KEY_ID";
          "JUJUTSU_RESOURCE_BUDGET_PROFILE";
          "JUJUTSU_SOURCE_CARRIER_POLICY"; "JUJUTSU_APPROVAL_POLICY";
          "JUJUTSU_WRITER_LEASE_POLICY"; "JUJUTSU_CREDENTIAL_POLICY";
          "JUJUTSU_COMPLETION_RECONCILE_ATTEMPT_LIMIT" ]
      ~mediation:(Unavailable_until_bridge_activity
        "Jujutsu operations remain unavailable until a closed typed activity is admitted by Run_swarm_bridge")
      "modules/hermes_vcs"
      "Typed Jujutsu repository-state and operation algebra"
      (na "version-control adapter is governed by Ops but has no FPP runtime instance");
    spec ~effect_posture:External_effect
      ~mediation:(Unavailable_until_bridge_activity
        "vision lifecycle requires a dedicated admitted bridge activity")
      "modules/hermes_vision"
      "Typed capture, render, browser, and media evidence pipeline"
      (fpp Fpp_window_authority.Harness [ "reference_capture" ]);
    spec "modules/hermes_wiki/src/build" "Wiki build and static artifact assembly"
      (fpp Fpp_window_authority.Wiki [ "renderer" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Unavailable_until_bridge_activity
        "wiki control mutations require a dedicated admitted bridge activity")
      "modules/hermes_wiki/src/control" "Wiki audit-loop and ratchet control"
      (fpp Fpp_window_authority.Wiki [ "auditLoop"; "ratchetController" ]);
    spec "modules/hermes_wiki/src/core" "Wiki core types and corpus contracts"
      (fpp Fpp_window_authority.Wiki [ "corpusStore" ]);
    spec "modules/hermes_wiki/src/engine" "Wiki parsing, transclusion, and execution engine"
      (fpp Fpp_window_authority.Wiki [ "corpusStore"; "renderer"; "queryEngine" ]);
    spec "modules/hermes_wiki/src/fpp" "FPP metamodel, interpreter, and wiki topology"
      (fpp Fpp_window_authority.Wiki [ "modelGate" ]);
    spec ~configuration_ids:[ "HERMES_VISION_KPI_WS" ]
      "modules/hermes_wiki/src/frontend" "Wiki browser frontend projection"
      (fpp Fpp_window_authority.Wiki [ "browserProbe" ]);
    spec "modules/hermes_wiki/src/graph" "Wiki graph analysis and link integrity"
      (fpp Fpp_window_authority.Wiki [ "graphAnalyzer"; "linkAuditor" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Unavailable_until_bridge_activity
        "knowledge writes require a dedicated admitted bridge activity")
      "modules/hermes_wiki/src/km" "Knowledge-management and journal authority"
      (fpp Fpp_window_authority.Wiki [ "journalKeeper" ]);
    spec "modules/hermes_wiki/src/mbse" "Wiki SysML, OML, and OpenMBEE projections"
      (fpp Fpp_window_authority.Wiki [ "modelGate" ]);
    spec "modules/hermes_wiki/src/present" "Wiki presentation and navigation model"
      (fpp Fpp_window_authority.Wiki [ "renderer" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Unavailable_until_bridge_activity
        "reconciliation writes require a dedicated admitted bridge activity")
      "modules/hermes_wiki/src/reconcile" "Corpus reconciliation and backfill"
      (fpp Fpp_window_authority.Wiki [ "reconciler"; "backfiller" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Unavailable_until_bridge_activity
        "register writes require a dedicated admitted bridge activity")
      "modules/hermes_wiki/src/register" "Typed feature and vocabulary register"
      (fpp Fpp_window_authority.Wiki [ "schemaAuditor" ]);
    spec "modules/hermes_wiki/src/render" "Markdown and static-site rendering"
      (fpp Fpp_window_authority.Wiki [ "renderer" ]);
    spec "modules/hermes_wiki/src/search" "Wiki lexical and graph recall"
      (fpp Fpp_window_authority.Wiki [ "queryEngine" ]);
    spec ~effect_posture:External_effect
      ~mediation:(Unavailable_until_bridge_activity
        "wiki server lifecycle has no admitted declarative activity")
      "modules/hermes_wiki/src/server" "Wiki HTTP serving boundary"
      (fpp Fpp_window_authority.Wiki [ "browserProbe" ]);
    spec "modules/hermes_wiki/src/source" "Corpus source ingestion and normalization"
      (fpp Fpp_window_authority.Wiki [ "corpusStore" ]);
    spec "modules/hermes_wiki/src/surface" "Wiki static and browser surface contracts"
      (fpp Fpp_window_authority.Wiki [ "browserProbe" ]);
    spec ~stratum:Tooling ~configuration_ids:[ "WIKI_AUDIT_DEBUG" ]
      "modules/hermes_wiki/src/tools"
      "Wiki audit, recall, render, and maintenance executables"
      (fpp Fpp_window_authority.Wiki [ "auditLoop" ]);
    spec ~stratum:Verification "modules/hermes_wiki/test"
      "Wiki differential, property, mutation, and conformance suites"
      (na "verification executables observe the wiki topology and are not resident components");
    spec ~effect_posture:External_effect
      ~mediation:(Unavailable_until_bridge_activity
        "Zellij process attachment has no admitted declarative bridge activity")
      "modules/hermes_zellij"
      "Typed declarative Zellij workspace model, projection, observation, and attachment boundary"
      (fpp Fpp_window_authority.Operations [ "runSupervisor" ]);
    spec ~effect_posture:Guarded_write
      ~mediation:(Unavailable_until_bridge_activity
        "plan-store mutation requires a dedicated admitted bridge activity")
      "modules/sa_plan" "Durable SQLite plan, task, job, and workflow store"
      (fpp Fpp_window_authority.Harness [ "planning"; "job_manager" ]);
    spec ~effect_posture:External_effect
      ~configuration_ids:[ "DREAM_PORT"; "HERMES_TAILSCALE_FQDN" ]
      ~mediation:(Run_swarm_bridge
        [ "activity.verify-sqlite-dependability"; "activity.verify-repository" ])
      "modules/swarm" "OCaml 5 Domain-wave execution and effect-target algebra"
      (fpp Fpp_window_authority.Operations [ "swarmExecutionBridge"; "suiteWorker" ]);
    spec ~stratum:Tooling "modules/system_engg"
      "Agent-surface synchronization, source authority, and programme gates"
      (fpp Fpp_window_authority.Operations [ "assuranceGate"; "completionGate" ]) ]

let stable_id directory =
  "module."
  ^ String.map
      (function '/' | '_' -> '-' | character -> character)
      (String.sub directory (String.length "modules/")
         (String.length directory - String.length "modules/"))

let libraries_of directory =
  List.filter (fun library -> Stanza.owner_directory library = directory) Stanza.all

let all =
  List.map
    (fun item ->
      { stable_id = stable_id item.directory;
        owner_directory = item.directory; purpose = item.purpose;
        stratum = item.stratum; libraries = libraries_of item.directory;
        plane = item.plane; coordinate = item.coordinate;
        effect_posture = item.effect_posture;
        configuration_ids = item.configuration_ids;
        capability_ids = item.capability_ids; surfaces = item.surfaces;
        fpp = item.fpp; mediation = item.mediation })
    specifications

let find stable_id = List.find_opt (fun item -> item.stable_id = stable_id) all

let read_dir path =
  try Sys.readdir path |> Array.to_list |> List.sort String.compare with _ -> []

let rec dune_directories directory =
  read_dir directory
  |> List.concat_map (fun entry ->
         let path = Filename.concat directory entry in
         if entry = "dune" then [ directory ]
         else if try Sys.is_directory path with _ -> false then dune_directories path
         else [])

let observed_dune_directories ~root =
  dune_directories (Filename.concat root "modules")
  |> List.map (fun path ->
         if String.starts_with ~prefix:"./" path then
           String.sub path 2 (String.length path - 2)
         else path)
  |> List.sort_uniq String.compare

let sorted_stanzas values = List.sort Stanza.compare values
let unique_strings values = List.length values = List.length (List.sort_uniq String.compare values)

let validate_interfaces ~root (interfaces : t list) =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  let expected_directories = observed_dune_directories ~root in
  let actual_directories = List.map (fun (item : t) -> item.owner_directory) interfaces in
  if actual_directories <> expected_directories then add "module interface directory denominator differs from live Dune files";
  let ids = List.map (fun (item : t) -> item.stable_id) interfaces in
  let known_capability_ids =
    List.map (fun (item : Ops_capability.declaration) -> item.id)
      Ops_capability.all
  in
  if not (unique_strings ids) then add "module interface stable ids are not unique";
  let owned = List.concat_map (fun (item : t) -> item.libraries) interfaces in
  if sorted_stanzas owned <> sorted_stanzas Stanza.all then add "module interface library partition differs from Stanza.all";
  if List.length owned <> List.length (List.sort_uniq Stanza.compare owned) then add "a Dune library has more than one semantic owner";
  List.iter
    (fun (item : t) ->
      if String.trim item.purpose = "" then add (item.stable_id ^ " has an empty purpose");
      if List.exists (fun library -> Stanza.owner_directory library <> item.owner_directory) item.libraries then
        add (item.stable_id ^ " owns a library from another Dune directory");
      if List.map fst item.surfaces |> List.sort_uniq compare <> List.sort_uniq compare all_surfaces then
        add (item.stable_id ^ " does not declare exactly four surfaces");
      if not (unique_strings item.capability_ids) then
        add (item.stable_id ^ " has duplicate capability references");
      List.iter
        (fun id ->
          if not (List.mem id known_capability_ids) then
            add (item.stable_id ^ " references unknown capability " ^ id))
        item.capability_ids;
      List.iter
        (function
          | _, Ops_capability.Applicable -> ()
          | _, Ops_capability.Not_applicable reason ->
              if String.length (String.trim reason) < 20 then add (item.stable_id ^ " has a vacuous surface exclusion"))
        item.surfaces;
      begin match item.fpp with
      | Fpp_components mappings ->
          if mappings = [] || List.exists (fun (_, components) -> components = []) mappings then
            add (item.stable_id ^ " has an empty FPP mapping")
      | Fpp_not_applicable reason ->
          if String.length (String.trim reason) < 20 then add (item.stable_id ^ " has a vacuous FPP exclusion")
      end;
      begin match item.effect_posture, item.mediation with
      | (Guarded_write | External_effect), Direct_read ->
          add (item.stable_id ^ " allows an effect through direct-read mediation")
      | (Guarded_write | External_effect), Run_swarm_bridge [] ->
          add (item.stable_id ^ " names the bridge without an admitted activity")
      | _ -> ()
      end)
    interfaces;
  if not (List.exists (fun (item : t) -> match item.fpp with Fpp_components _ -> true | _ -> false) interfaces) then
    add "all module interfaces declare FPP inapplicable";
  List.rev !gaps

let validate ~root = validate_interfaces ~root all

let validate_configuration_references ~known_ids (interfaces : t list) =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  List.iter
    (fun (item : t) ->
      if not (unique_strings item.configuration_ids) then
        add (item.stable_id ^ " has duplicate configuration references");
      List.iter
        (fun id ->
          if not (List.mem id known_ids) then
            add (item.stable_id ^ " references unknown configuration " ^ id))
        item.configuration_ids)
    interfaces;
  List.rev !gaps

let canonical (item : t) =
  let libraries = List.map Stanza.name item.libraries |> String.concat "," in
  let surfaces =
    item.surfaces
    |> List.map (fun (surface, applicability) ->
           Ops_capability.string_of_surface surface ^ ":"
           ^ match applicability with
             | Ops_capability.Applicable -> "applicable"
             | Ops_capability.Not_applicable reason -> "na:" ^ reason)
    |> String.concat ";"
  in
  let fpp_text = match item.fpp with
    | Fpp_not_applicable reason -> "na:" ^ reason
    | Fpp_components mappings ->
        mappings |> List.map (fun (owner, components) ->
          Fpp_window_authority.owner_name owner ^ ":" ^ String.concat "," components)
        |> String.concat ";"
  in
  let mediation = match item.mediation with
    | Direct_read -> "direct-read"
    | Run_swarm_bridge activities ->
        "run-swarm-bridge:" ^ String.concat "," activities
    | Unavailable_until_bridge_activity reason -> "unavailable:" ^ reason
  in
  String.concat "|"
    [ item.stable_id; item.owner_directory; item.purpose; libraries;
      string_of_stratum item.stratum;
      Ops_capability.string_of_plane item.plane;
      Ops_capability.string_of_level item.coordinate.level;
      Ops_capability.string_of_phase item.coordinate.phase;
      string_of_effect_posture item.effect_posture;
      String.concat "," item.configuration_ids;
      String.concat "," item.capability_ids;
      surfaces; fpp_text; mediation ]

let source_digest =
  let payload = String.concat "\n" (List.map canonical all) in
  Digest.to_hex (Digest.string ("module-intent-0|" ^ payload))
  ^ Digest.to_hex (Digest.string ("module-intent-1|" ^ payload))

module For_test = struct
  type mutation =
    | Drop_first
    | Duplicate_first_library
    | Erase_first_purpose
    | Force_direct_external_effect
    | Make_all_fpp_inapplicable
    | Add_unknown_configuration
    | Add_unknown_capability
  let replace_first (update : t -> t) (items : t list) =
    match items with [] -> [] | first :: rest -> update first :: rest
  let mutate = function
    | Drop_first -> (match all with [] -> [] | _ :: rest -> rest)
    | Duplicate_first_library ->
        let rec loop (items : t list) : t list = match items with
          | [] -> []
          | item :: rest ->
              begin match item.libraries with
              | [] -> item :: loop rest
              | first :: _ -> { item with libraries = first :: item.libraries } :: rest
              end
        in loop all
    | Erase_first_purpose -> replace_first (fun item -> { item with purpose = "" }) all
    | Force_direct_external_effect ->
        let rec loop (items : t list) : t list = match items with
          | [] -> []
          | item :: rest when item.effect_posture = Guarded_write || item.effect_posture = External_effect ->
              { item with mediation = Direct_read } :: rest
          | item :: rest -> item :: loop rest
        in loop all
    | Make_all_fpp_inapplicable ->
        List.map (fun (item : t) -> { item with fpp = Fpp_not_applicable "mutation removes every concrete FPP mapping" }) all
    | Add_unknown_configuration ->
        replace_first
          (fun item ->
            { item with configuration_ids = "HERMES_UNKNOWN_CONFIG" :: item.configuration_ids })
          all
    | Add_unknown_capability ->
        replace_first
          (fun item ->
            { item with capability_ids = "capability.unknown" :: item.capability_ids })
          all
  let validate_interfaces = validate_interfaces
  let validate_configuration_references = validate_configuration_references
end
