type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type kind =
  | Workspace
  | Capability
  | Session
  | Contract
  | Projection
  | Runtime
  | Receipt
  | Controller

type lifecycle =
  | Declared
  | Implemented
  | Tested
  | Live_observed
  | Current
  | Unavailable_observed

type rca_origin =
  | Specification
  | Implementation
  | Environment
  | Evidence
  | Control

type node = {
  id : string;
  parent_id : string option;
  level : level;
  kind : kind;
  carrier : string;
  operations : string list;
  observations : string list;
  invariants : string list;
  hazards : string list;
  sources : string list;
  lifecycle : lifecycle;
  rca_origin : rca_origin;
  implementation_paths : string list;
  test_paths : string list;
  residuals : string list;
}

let id value = value.id
let parent_id value = value.parent_id
let level value = value.level
let kind value = value.kind
let carrier value = value.carrier
let operations value = value.operations
let observations value = value.observations
let invariants value = value.invariants
let hazards value = value.hazards
let sources value = value.sources
let lifecycle value = value.lifecycle
let rca_origin value = value.rca_origin
let implementation_paths value = value.implementation_paths
let test_paths value = value.test_paths
let residuals value = value.residuals
let with_parent value parent_id = { value with parent_id }

let level_name = function
  | L0 -> "L0"
  | L1 -> "L1"
  | L2 -> "L2"
  | L3 -> "L3"
  | L4 -> "L4"
  | L5 -> "L5"
  | L6 -> "L6"
  | LX -> "LX"

let kind_name = function
  | Workspace -> "workspace"
  | Capability -> "capability"
  | Session -> "session"
  | Contract -> "contract"
  | Projection -> "projection"
  | Runtime -> "runtime"
  | Receipt -> "receipt"
  | Controller -> "controller"

let lifecycle_name = function
  | Declared -> "Declared"
  | Implemented -> "Implemented"
  | Tested -> "Tested"
  | Live_observed -> "Live_observed"
  | Current -> "Current"
  | Unavailable_observed -> "Unavailable_observed"

let source_design =
  "docs/hermes/specs/20260813-1337-zellij-declarative-integration-design.md"

let make ~id ~parent_id ~level ~kind ~carrier ~operations ~observations
    ~invariants ~hazards ~sources ~lifecycle ~rca_origin
    ?(implementation_paths = []) ?(test_paths = []) ?(residuals = []) () =
  {
    id;
    parent_id;
    level;
    kind;
    carrier;
    operations;
    observations;
    invariants;
    hazards;
    sources;
    lifecycle;
    rca_origin;
    implementation_paths;
    test_paths;
    residuals;
  }

let workspace =
  make ~id:"harness-bionic" ~parent_id:None ~level:L0 ~kind:Workspace
    ~carrier:"one governed harness-bionic workspace"
    ~operations:[ "configure"; "observe"; "verify" ]
    ~observations:[ "workspace identity"; "source authority" ]
    ~invariants:[ "workspace root is exact"; "tmux is not mutated" ]
    ~hazards:[ "HZ-ZELLIJ-WORKSPACE-DRIFT" ]
    ~sources:[ source_design ] ~lifecycle:Implemented ~rca_origin:Control
    ~implementation_paths:[ "modules/hermes_zellij" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
    ()

let capability =
  make ~id:"harness-bionic.zellij" ~parent_id:(Some workspace.id) ~level:L1
    ~kind:Capability ~carrier:"finite set of declared Zellij session holons"
    ~operations:[ "plan"; "apply"; "ensure"; "attach"; "status" ]
    ~observations:[ "binary version"; "configuration"; "session set" ]
    ~invariants:[ "six independent sessions"; "manual attachment" ]
    ~hazards:[ "HZ-ZELLIJ-CAPABILITY-DRIFT" ]
    ~sources:
      [ source_design; "https://zellij.dev/documentation/introduction.html" ]
    ~lifecycle:Implemented ~rca_origin:Control
    ~implementation_paths:[ "modules/hermes_zellij" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
    ()

let session_node session =
  let name = Zellij_intent.session_name session in
  make
    ~id:(capability.id ^ "." ^ name)
    ~parent_id:(Some capability.id) ~level:L2 ~kind:Session
    ~carrier:("one independent session named " ^ name)
    ~operations:[ "attach"; "ensure"; "observe"; "verify" ]
    ~observations:[ "command present"; "session live"; "cwd exact" ]
    ~invariants:[ "command name equals session name"; "identity is unique" ]
    ~hazards:[ "HZ-ZELLIJ-SESSION-MISMATCH" ]
    ~sources:[ source_design; "https://zellij.dev/documentation/commands.html" ]
    ~lifecycle:Implemented ~rca_origin:Control
    ~implementation_paths:[ "modules/hermes_zellij/zellij_intent.ml" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
    ()

let contracts =
  make ~id:"harness-bionic.zellij.contracts" ~parent_id:(Some capability.id)
    ~level:L3 ~kind:Contract
    ~carrier:"name, path, KDL, version, and lifecycle predicates"
    ~operations:[ "validate"; "reject" ]
    ~observations:[ "validation errors"; "negative controls" ]
    ~invariants:[ "unknown names fail closed"; "empty is not complete" ]
    ~hazards:[ "HZ-ZELLIJ-CONTRACT-VACUITY" ]
    ~sources:[ source_design ] ~lifecycle:Tested ~rca_origin:Specification
    ~implementation_paths:
      [
        "modules/hermes_zellij/zellij_intent.ml";
        "modules/hermes_zellij/zellij_algebra.ml";
      ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
    ()

let projection =
  make ~id:"harness-bionic.zellij.projections" ~parent_id:(Some capability.id)
    ~level:L4 ~kind:Projection ~carrier:"owned KDL, links, Markdown, JSON, MBSE"
    ~operations:[ "render"; "compare"; "replace atomically" ]
    ~observations:[ "byte digest"; "native KDL verdict" ]
    ~invariants:[ "equal intent renders equal bytes"; "writes are atomic" ]
    ~hazards:[ "HZ-ZELLIJ-PROJECTION-DRIFT" ]
    ~sources:[ source_design ] ~lifecycle:Declared ~rca_origin:Control
    ~implementation_paths:[ "modules/hermes_zellij/zellij_projection.ml" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_projection.ml" ]
    ~residuals:[ "projection implementation follows the model checkpoint" ]
    ()

let runtime =
  make ~id:"harness-bionic.zellij.runtime" ~parent_id:(Some capability.id)
    ~level:L5 ~kind:Runtime ~carrier:"observed Zellij process and session state"
    ~operations:[ "list"; "attach"; "create-background"; "inspect cwd" ]
    ~observations:[ "CLI exit"; "session names"; "pane cwd" ]
    ~invariants:[ "observations are total"; "unknown is unavailable" ]
    ~hazards:[ "HZ-ZELLIJ-RUNTIME-UNKNOWN" ]
    ~sources:
      [
        source_design;
        "https://zellij.dev/documentation/programmatic-control.html";
      ]
    ~lifecycle:Declared ~rca_origin:Environment
    ~implementation_paths:[ "modules/hermes_zellij/zellij_observe.ml" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_live.ml" ]
    ~residuals:[ "live observation follows projection checkpoint" ]
    ()

let receipt =
  make ~id:"harness-bionic.zellij.receipts" ~parent_id:(Some capability.id)
    ~level:L6 ~kind:Receipt ~carrier:"current intent/projection/runtime receipt"
    ~operations:[ "normalize"; "digest"; "classify" ]
    ~observations:[ "intent digest"; "projection digest"; "live denominator" ]
    ~invariants:[ "all six required"; "stale evidence is not current" ]
    ~hazards:[ "HZ-ZELLIJ-RECEIPT-STALE" ]
    ~sources:[ source_design ] ~lifecycle:Declared ~rca_origin:Evidence
    ~implementation_paths:[ "modules/hermes_zellij/zellij_configurator.ml" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_live.ml" ]
    ~residuals:[ "current receipt requires a live run" ]
    ()

let controller =
  make ~id:"harness-bionic.zellij.controller" ~parent_id:(Some capability.id)
    ~level:LX ~kind:Controller
    ~carrier:"closed OCaml plan/check/apply/ensure/status CLI"
    ~operations:[ "preflight"; "plan"; "apply"; "refuse" ]
    ~observations:[ "resource envelope"; "change plan"; "effect receipt" ]
    ~invariants:[ "fail before mutation"; "unknown flags are refused" ]
    ~hazards:[ "HZ-ZELLIJ-CONTROL-BYPASS" ]
    ~sources:[ source_design ] ~lifecycle:Declared ~rca_origin:Control
    ~implementation_paths:[ "modules/hermes_zellij/zellij_configurator.ml" ]
    ~test_paths:[ "modules/hermes_zellij/test_zellij_live.ml" ]
    ~residuals:[ "governed effect admission follows focused implementation" ]
    ()

let nodes =
  (workspace :: capability :: List.map session_node Zellij_intent.all_sessions)
  @ [ contracts; projection; runtime; receipt; controller ]

let find_in nodes id = List.find_opt (fun node -> node.id = id) nodes
let find id = find_in nodes id

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop acc = function
    | left :: (right :: _ as tail) when left = right -> loop (left :: acc) tail
    | _ :: tail -> loop acc tail
    | [] -> List.rev acc
  in
  loop [] sorted

let validate_nodes candidate =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  duplicates (List.map (fun node -> node.id) candidate)
  |> List.iter (fun id -> add ("duplicate ontology id: " ^ id));
  List.iter
    (fun node ->
      if String.trim node.id = "" then add "blank ontology id";
      (match node.parent_id with
      | Some parent when parent = node.id -> add ("self parent: " ^ node.id)
      | Some parent when Option.is_none (find_in candidate parent) ->
          add ("dangling parent " ^ parent ^ " for " ^ node.id)
      | _ -> ());
      if String.trim node.carrier = "" then add ("blank carrier: " ^ node.id);
      if node.operations = [] then add ("no operations: " ^ node.id);
      if node.observations = [] then add ("no observations: " ^ node.id);
      if node.invariants = [] then add ("no invariants: " ^ node.id);
      if node.hazards = [] then add ("no hazards: " ^ node.id);
      if node.sources = [] then add ("no sources: " ^ node.id))
    candidate;
  let count level =
    List.length (List.filter (fun node -> node.level = level) candidate)
  in
  if count L0 <> 1 then add "ontology requires exactly one L0 node";
  if count L1 <> 1 then add "ontology requires exactly one L1 node";
  if count L2 <> 6 then add "ontology requires exactly six L2 session nodes";
  List.iter
    (fun level ->
      if count level = 0 then add ("ontology lacks " ^ level_name level))
    [ L3; L4; L5; L6; LX ];
  List.rev !errors

let validate () = validate_nodes nodes
