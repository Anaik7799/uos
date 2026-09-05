type kind = Rule | Skill | Superpower | Agent | Capability | Sop | Activity
type plane = Control_plane | Data_plane
type surface = Ocaml_api | Cli | Mcp | Zenoh
type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX
type ooda_phase = Observe | Orient | Decide | Act
type lifecycle = Declared | Implemented | Executed | Current
type rca_origin = Specification | Implementation | Environment | Evidence | Control
type evidence = Structural | Functional | Differential | Formal | Mutation | Resource | Publication
type implementation = Judgment_only of string | Command of string
type applicability = Applicable | Not_applicable of string
type coordinate = { level : level; phase : ooda_phase }

type declaration = {
  id : string;
  kind : kind;
  purpose : string;
  authority : string;
  owner : string;
  dependencies : string list;
  path : coordinate list;
  implementation : implementation;
  evidence : evidence list;
  plane : plane;
  surfaces : (surface * applicability) list;
  projections : string list;
}

let string_of_kind = function
  | Rule -> "rule" | Skill -> "skill" | Superpower -> "superpower"
  | Agent -> "agent" | Capability -> "capability" | Sop -> "sop"
  | Activity -> "activity"

let string_of_plane = function Control_plane -> "control" | Data_plane -> "data"

let string_of_surface = function
  | Ocaml_api -> "ocaml-api" | Cli -> "cli" | Mcp -> "mcp" | Zenoh -> "zenoh"

let string_of_level = function
  | L0 -> "L0" | L1 -> "L1" | L2 -> "L2" | L3 -> "L3"
  | L4 -> "L4" | L5 -> "L5" | L6 -> "L6" | LX -> "LX"

let string_of_phase = function
  | Observe -> "observe" | Orient -> "orient" | Decide -> "decide" | Act -> "act"

let string_of_lifecycle = function
  | Declared -> "declared" | Implemented -> "implemented"
  | Executed -> "executed" | Current -> "current"

let string_of_rca_origin = function
  | Specification -> "Specification" | Implementation -> "Implementation"
  | Environment -> "Environment" | Evidence -> "Evidence" | Control -> "Control"

let judgment = Judgment_only "Irreducible human guidance; grants no executable completion credit"

let all_surfaces ?(mcp = true) ?(zenoh = true) () =
  let pending surface =
    Not_applicable
      (surface ^ " adapter is not implemented; completion remains blocked until it is projected")
  in
  [ (Ocaml_api, Applicable); (Cli, Applicable);
    (Mcp, if mcp then Applicable else pending "MCP");
    (Zenoh, if zenoh then Applicable else pending "Zenoh") ]

let rule_titles =
  [ ("R1", "All tooling is OCaml");
    ("R2", "External tools are oracles, never authors");
    ("R3", "Nothing may be recorded that was not verified");
    ("R4", "All logging is fractally contextual and OTel compliant");
    ("R5", "Only Implementation origin may deny parity credit");
    ("R6", "Every failure mode is analysed");
    ("R7", "Features are battle-tested before they are trusted");
    ("R8", "Specifications are linted before they are committed");
    ("R9", "Two fractals, never conflated");
    ("R10", "Only L4-L6 differential evidence grants parity");
    ("R11", "Fable in max mode specifies, designs and test-plans");
    ("R12", "Every component declares its ontology entry");
    ("R13", "Resources are checked before they are used");
    ("R14", "Study the zigvm harness first; maximize overlap");
    ("R15",
     "Web surfaces are Tailscale-reachable; the operations application is a constrained same-origin scripted profile");
    ("R16", "Journal and Zettelkasten notes carry a dated, stable identity");
    ("R17", "The workspace structure is law; changing it is governance");
    ("R18", "Recall before, record after");
    ("R19", "An operator tool fails closed, writes atomically, and tells the truth with its exit code");
    ("R20", "The toolchain is declared, derived and verified before it is used");
    ("R21", "The model comes first; surfaces derive from it");
    ("R22", "Offload to the swarm; an agent context is a scarce resource");
    ("R23", "All configuration is declarative intent, at every fractal layer");
    ("R24", "Executable OCaml authority is maximized and prose is a projection");
    ("R25", "Fractal and Fast OODA coverage follows authored semantic paths");
    ("R26", "Completion requires current-run declarative receipts");
    ("R27", "One command algebra projects through four native surfaces");
    ("R28", "Ontology, atlas, algebra, formal checks, logs, and metrics are total");
    ("R29", "Every task has a typed prompt and acceptance envelope");
    ("R30", "Evidence is oriented before it is read: measure, condense, validate, decide");
    ("R31", "All SQLite and external-system access crosses the controlled typed OCaml API layer") ]

let rule_declaration (id, purpose) =
  { id = "rule." ^ id; kind = Rule; purpose;
    authority = "Ops_capability.rule_titles"; owner = "system_engg";
    dependencies = []; path = []; implementation = judgment;
    evidence = [ Structural ]; plane = Control_plane; surfaces = [];
    projections = [ "docs/hermes/mandatory-rules.md" ] }

let skill_names =
  [ "agentic-expect-testing"; "controlled-external-access"; "feature-landing"; "fractal-evidence-orientation";
    "full-symbiosis";
    "hermes-formal-verification";
    "hermes-functional-envelope"; "hermes-parallel-generation";
    "hermes-wiki-zk"; "jujutsu-vcs"; "operations-ui-system";
    "swarm-offload"; "swarm-usage"; "systematic-debugging";
    "whole-system-completion"; "wiki-site-design"; "wiki-zk-operations";
    "workspace-structure" ]

let skill_declaration name =
  { id = "skill." ^ name; kind = Skill;
    purpose = "Native agent guidance projection for " ^ name;
    authority = "Ops_capability.skill_names"; owner = "system_engg";
    dependencies = []; path = []; implementation = judgment;
    evidence = [ Structural ]; plane = Control_plane; surfaces = [];
    projections = [ ".claude/skills/" ^ name ^ "/SKILL.md";
                    ".agents/skills/" ^ name ^ "/SKILL.md" ] }

let superpower_names =
  [ "systematic-debugging"; "test-driven-development";
    "verification-before-completion"; "writing-plans"; "writing-skills" ]

let superpower_declaration name =
  { id = "superpower." ^ name; kind = Superpower;
    purpose = "Runtime reasoning protocol retained as explicit judgment guidance: " ^ name;
    authority = "Ops_capability.superpower_names"; owner = "agent-runtime";
    dependencies = []; path = []; implementation = judgment;
    evidence = [ Structural ]; plane = Control_plane; surfaces = [];
    projections = [] }

let agent_names =
  [ "full-symbiosis-supervisor"; "hermes-completion-supervisor";
    "hermes-debugging-supervisor"; "hermes-external-access-auditor";
    "wiki-auditor" ]

let agent_declaration name =
  { id = "agent." ^ name; kind = Agent;
    purpose = "Native selector declaration for " ^ name;
    authority = "Ops_capability.agent_names"; owner = "system_engg";
    dependencies = []; path = []; implementation = judgment;
    evidence = [ Structural ]; plane = Control_plane; surfaces = [];
    projections = [ ".claude/agents/" ^ name ^ ".md";
                    ".codex/agents/" ^ name ^ ".toml";
                    ".agents/agents/" ^ name ^ "/agent.md" ] }

let command ~id ~kind ~purpose ~command ~path ~dependencies ~evidence ~plane =
  { id; kind; purpose; authority = "Ops_capability.all"; owner = "hermes_ops";
    dependencies; path; implementation = Command command; evidence; plane;
    surfaces = all_surfaces (); projections = [] }

let executable_declarations =
  [ command ~id:"capability.verify-fast" ~kind:Capability
      ~purpose:"Run the bounded fast feedback verification profile"
      ~command:"ops verify --fast --require-complete"
      ~path:[ { level = LX; phase = Observe } ] ~dependencies:[]
      ~evidence:[ Functional; Publication ] ~plane:Control_plane;
    command ~id:"capability.verify-full" ~kind:Capability
      ~purpose:"Run the complete production-module verification profile"
      ~command:"ops verify --full --require-complete"
      ~path:[ { level = L0; phase = Observe }; { level = L1; phase = Orient } ]
      ~dependencies:[ "capability.verify-fast" ]
      ~evidence:[ Functional; Publication ] ~plane:Control_plane;
    command ~id:"capability.formal-check" ~kind:Capability
      ~purpose:"Run staged formal-service checks without promoting unavailable evidence"
      ~command:"ops formal"
      ~path:[ { level = L3; phase = Observe }; { level = L3; phase = Orient } ]
      ~dependencies:[] ~evidence:[ Formal; Publication ] ~plane:Control_plane;
    { (command ~id:"capability.agent-surface-sync" ~kind:Capability
         ~purpose:"Check native agent and skill projections for drift"
         ~command:"verify_agent_surface_sync"
         ~path:[ { level = LX; phase = Observe } ] ~dependencies:[]
         ~evidence:[ Structural ] ~plane:Control_plane) with
      projections =
        [ "AGENTS.md"; "CLAUDE.md"; "CODEX.md"; "GEMINI.md";
          ".agents/hooks.json"; ".codex/hooks.json";
          ".gemini/settings.json"; "docs/hermes/cross-agent-surface.md";
          "modules/system_engg/run_agent_time_hook.ml" ] };
    command ~id:"capability.governance-check" ~kind:Capability
      ~purpose:"Evaluate one typed whole-system governance obligation"
      ~command:"ops governance check --obligation ID"
      ~path:[ { level = L0; phase = Observe }; { level = L1; phase = Orient } ]
      ~dependencies:[] ~evidence:[ Structural; Formal; Publication ] ~plane:Control_plane;
    command ~id:"capability.mbse-sysml" ~kind:Capability
      ~purpose:"Validate the textual SysML v2 projection from the model of record"
      ~command:"ops completion mbse-check --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Observe } ] ~dependencies:[]
      ~evidence:[ Structural; Formal ] ~plane:Data_plane;
    command ~id:"capability.mbse-oml" ~kind:Capability
      ~purpose:"Validate the OML/OWL projection and subsumption laws"
      ~command:"ops completion mbse-check --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Observe } ]
      ~dependencies:[ "capability.mbse-sysml" ]
      ~evidence:[ Structural; Formal ] ~plane:Data_plane;
    command ~id:"capability.mbse-openmbee" ~kind:Capability
      ~purpose:"Validate the OpenMBEE MMS projection without claiming a live push"
      ~command:"ops completion mbse-check --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Observe } ]
      ~dependencies:[ "capability.mbse-sysml"; "capability.mbse-oml" ]
      ~evidence:[ Structural; Publication ] ~plane:Data_plane;
    command ~id:"capability.fpp-check" ~kind:Capability
      ~purpose:"Validate FPP models, topologies, dictionaries, actors, and metrics"
      ~command:"ops completion fpp-check --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Observe }; { level = L3; phase = Orient } ]
      ~dependencies:[] ~evidence:[ Structural; Formal; Mutation ] ~plane:Control_plane;
    command ~id:"capability.metrics-observe" ~kind:Capability
      ~purpose:"Emit typed run-scoped governance metrics and observability attributes"
      ~command:"ops completion metrics-observe --scope data-plane --request-id RUN_ID"
      ~path:[ { level = LX; phase = Observe } ] ~dependencies:[]
      ~evidence:[ Functional; Publication ] ~plane:Data_plane;
    command ~id:"capability.history-observe" ~kind:Capability
      ~purpose:"Query the append-only command, receipt, surface, prompt, and agent history"
      ~command:"ops completion history-observe --scope data-plane --request-id RUN_ID"
      ~path:[ { level = L0; phase = Observe }; { level = L6; phase = Observe } ]
      ~dependencies:[ "capability.metrics-observe" ]
      ~evidence:[ Functional; Publication ] ~plane:Data_plane;
    command ~id:"capability.orientation-observe" ~kind:Capability
      ~purpose:"Query the durable orientation memory: pass history and key state (R30)"
      ~command:"ops command orientation-observe --scope whole-system"
      ~path:[ { level = L0; phase = Observe }; { level = LX; phase = Orient } ]
      ~dependencies:[ "capability.history-observe" ]
      ~evidence:[ Functional; Publication ] ~plane:Control_plane;
    command ~id:"capability.debug-observe" ~kind:Capability
      ~purpose:"Query one typed debugging intent and its dependable next measurement"
      ~command:"ops completion debug INTENT_ID --scope control-plane --request-id RUN_ID"
      ~path:[ { level = L0; phase = Observe }; { level = L1; phase = Orient } ]
      ~dependencies:[ "capability.orientation-observe" ]
      ~evidence:[ Structural; Functional; Mutation; Publication ]
      ~plane:Control_plane;
    command ~id:"sop.systematic-debugging" ~kind:Sop
      ~purpose:"Observe orient discriminate correct verify and observe again without guessing a cause"
      ~command:"ops completion debug INTENT_ID --scope control-plane --request-id RUN_ID"
      ~path:[ { level = L0; phase = Observe }; { level = L1; phase = Orient };
              { level = L2; phase = Decide }; { level = L3; phase = Act };
              { level = L0; phase = Observe } ]
      ~dependencies:[ "capability.debug-observe"; "capability.verify-fast" ]
      ~evidence:[ Functional; Differential; Formal; Mutation; Resource; Publication ]
      ~plane:Control_plane;
    command ~id:"activity.debug-correction" ~kind:Activity
      ~purpose:"Unavailable corrective-effect boundary reserved for a future exact admitted Run_swarm_bridge activity"
      ~command:"ops completion debug debug.bridge-admission --scope control-plane --request-id RUN_ID"
      ~path:[ { level = L3; phase = Act } ]
      ~dependencies:[ "sop.systematic-debugging" ]
      ~evidence:[ Structural; Mutation ] ~plane:Control_plane;
    command ~id:"sop.fast-ooda-completion" ~kind:Sop
      ~purpose:"Causal Fast OODA completion loop with a closing observation"
      ~command:"ops completion act --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L0; phase = Observe }; { level = L1; phase = Orient };
              { level = L2; phase = Decide }; { level = L3; phase = Act };
              { level = L0; phase = Observe } ]
      ~dependencies:[ "capability.verify-fast"; "capability.verify-full" ]
      ~evidence:[ Functional; Differential; Formal; Publication ] ~plane:Control_plane;
    command ~id:"activity.observe-inventory" ~kind:Activity
      ~purpose:"Inventory exact-head live declarations and receipts"
      ~command:"ops completion inventory --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L0; phase = Observe } ] ~dependencies:[]
      ~evidence:[ Structural; Publication ] ~plane:Data_plane;
    command ~id:"activity.orient-gaps" ~kind:Activity
      ~purpose:"Classify typed gaps with a canonical RCA origin"
      ~command:"ops completion plan --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L1; phase = Orient } ]
      ~dependencies:[ "activity.observe-inventory" ]
      ~evidence:[ Structural; Formal ] ~plane:Control_plane;
    command ~id:"activity.decide-intent" ~kind:Activity
      ~purpose:"Compile gaps into one declarative intent request"
      ~command:"ops completion decide --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L2; phase = Decide } ]
      ~dependencies:[ "activity.orient-gaps" ]
      ~evidence:[ Structural; Formal ] ~plane:Control_plane;
    command ~id:"activity.act-sop" ~kind:Activity
      ~purpose:"Legacy operator-path migration residual; unavailable as authority for new execution callers"
      ~command:"ops completion act --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Act } ]
      ~dependencies:[ "activity.decide-intent" ]
      ~evidence:[ Functional; Resource ] ~plane:Control_plane;
    command ~id:"activity.verify-sqlite-dependability" ~kind:Activity
      ~purpose:"Verify SQLite finalization and close lifecycle dependability exclusively through the admitted Run_swarm_bridge"
      ~command:"ops completion verify-sqlite-dependability --scope whole-system --request-id RUN_ID"
      ~path:[ { level = L3; phase = Act } ]
      ~dependencies:[ "activity.decide-intent" ]
      ~evidence:[ Functional; Formal; Resource ] ~plane:Control_plane ]

let all =
  List.map rule_declaration rule_titles
  @ List.map skill_declaration skill_names
  @ List.map superpower_declaration superpower_names
  @ List.map agent_declaration agent_names
  @ executable_declarations

let numeric_rule id =
  try int_of_string (String.sub id 1 (String.length id - 1)) with _ -> max_int

let rule_ids () =
  rule_titles |> List.map fst
  |> List.sort (fun left right -> compare (numeric_rule left) (numeric_rule right))

let frame value = Printf.sprintf "%d:%s" (String.length value) value

let encode_list encode values =
  values |> List.map (fun value -> frame (encode value)) |> String.concat ""
  |> frame

let string_of_evidence = function
  | Structural -> "structural"
  | Functional -> "functional"
  | Differential -> "differential"
  | Formal -> "formal"
  | Mutation -> "mutation"
  | Resource -> "resource"
  | Publication -> "publication"

let string_of_implementation = function
  | Judgment_only reason -> frame "judgment-only" ^ frame reason
  | Command command -> frame "command" ^ frame command

let string_of_applicability = function
  | Applicable -> frame "applicable"
  | Not_applicable reason -> frame "not-applicable" ^ frame reason

let canonical_declaration declaration =
  let coordinate value =
    frame (string_of_level value.level) ^ frame (string_of_phase value.phase)
  in
  let surface (name, applicability) =
    frame (string_of_surface name) ^ frame (string_of_applicability applicability)
  in
  [ frame declaration.id; frame (string_of_kind declaration.kind);
    frame declaration.purpose; frame declaration.authority;
    frame declaration.owner; encode_list Fun.id declaration.dependencies;
    encode_list coordinate declaration.path;
    frame (string_of_implementation declaration.implementation);
    encode_list string_of_evidence declaration.evidence;
    frame (string_of_plane declaration.plane); encode_list surface declaration.surfaces;
    encode_list Fun.id declaration.projections ]
  |> String.concat "" |> frame

let declaration_digest declarations =
  frame "hermes.ops-capability.declarations.v1"
  ^ encode_list canonical_declaration declarations
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let source_digest = declaration_digest all
