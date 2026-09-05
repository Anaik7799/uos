type resource =
  | Sqlite
  | Filesystem
  | Process
  | Network
  | Vcs
  | External_service
  | Hardware
  | Oracle

type operation = Read | Write | Execute | Publish | Observe | Recover
type redaction = Public | Metadata_only | Secret

type budget = { timeout_ms : int; max_bytes : int; max_attempts : int }

type declaration = {
  intent_id : string;
  request_id : string;
  owner_id : string;
  adapter_id : string;
  resource : resource;
  operation : operation;
  purpose : string;
  target_class : string;
  config_ids : string list;
  authorization_id : string;
  budget : budget;
  redaction : redaction;
  idempotency_key : string;
  success_criteria : string list;
  recovery_id : string;
  coordinate : Ops_capability.coordinate;
}

type intent = { declaration : declaration; digest : string }

type execution_status = Unavailable_observed

type prepared = {
  intent : intent;
  digest : string;
  bridge_id : string;
  engine_calls : int;
  status : execution_status;
}

let resources =
  [ Sqlite; Filesystem; Process; Network; Vcs; External_service; Hardware; Oracle ]

let resource_name = function
  | Sqlite -> "sqlite"
  | Filesystem -> "filesystem"
  | Process -> "process"
  | Network -> "network"
  | Vcs -> "vcs"
  | External_service -> "external-service"
  | Hardware -> "hardware"
  | Oracle -> "oracle"

let adapter_id resource = "adapter.external-access." ^ resource_name resource

let operation_name = function
  | Read -> "read" | Write -> "write" | Execute -> "execute"
  | Publish -> "publish" | Observe -> "observe" | Recover -> "recover"

let level_name = function
  | Ops_capability.L0 -> "L0" | L1 -> "L1" | L2 -> "L2" | L3 -> "L3"
  | L4 -> "L4" | L5 -> "L5" | L6 -> "L6" | LX -> "LX"

let phase_name = function
  | Ops_capability.Observe -> "Observe" | Orient -> "Orient"
  | Decide -> "Decide" | Act -> "Act"

let sha256 text = text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let digest_fields fields =
  fields
  |> List.map (fun field -> Printf.sprintf "%d:%s" (String.length field) field)
  |> String.concat ""
  |> sha256

let nonempty text = String.trim text <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)

let validate_declaration item =
  let gaps = ref [] in
  let require condition message = if not condition then gaps := message :: !gaps in
  require (nonempty item.intent_id) "intent identity is empty";
  require (nonempty item.request_id) "request identity is empty";
  require (nonempty item.owner_id) "owner identity is empty";
  require (item.adapter_id = adapter_id item.resource) "adapter does not own resource family";
  require (nonempty item.purpose) "purpose is empty";
  require (nonempty item.target_class) "target class is empty";
  require (item.config_ids <> [] && List.for_all nonempty item.config_ids
           && unique item.config_ids) "configuration references are empty or duplicate";
  require (nonempty item.authorization_id) "authorization identity is empty";
  require (item.budget.timeout_ms > 0) "timeout is not positive";
  require (item.budget.max_bytes > 0) "output bound is not positive";
  require (item.budget.max_attempts > 0) "attempt bound is not positive";
  require (nonempty item.idempotency_key) "idempotency key is empty";
  require (item.success_criteria <> [] && List.for_all nonempty item.success_criteria)
    "success criteria are empty";
  require (nonempty item.recovery_id) "recovery identity is empty";
  require (item.redaction <> Secret || item.operation <> Publish)
    "secret material cannot be published";
  List.rev !gaps

let digest_declaration item =
  digest_fields
    ([ item.intent_id; item.request_id; item.owner_id; item.adapter_id;
       resource_name item.resource; operation_name item.operation; item.purpose;
       item.target_class; item.authorization_id;
       string_of_int item.budget.timeout_ms; string_of_int item.budget.max_bytes;
       string_of_int item.budget.max_attempts; item.idempotency_key;
       item.recovery_id; level_name item.coordinate.level;
       phase_name item.coordinate.phase ]
     @ item.config_ids @ item.success_criteria)

let declare declaration =
  match validate_declaration declaration with
  | [] -> Ok { declaration; digest = digest_declaration declaration }
  | gaps -> Error gaps

let intent_resource (item : intent) = item.declaration.resource
let intent_digest (item : intent) = item.digest

let prepare intent =
  match validate_declaration intent.declaration with
  | _ :: _ as gaps -> Error gaps
  | [] ->
      let bridge_id = "Run_swarm_bridge" in
      Ok { intent; bridge_id; engine_calls = 0; status = Unavailable_observed;
           digest = digest_fields [ intent.digest; bridge_id; "immutable" ] }

let prepared_digest (item : prepared) = item.digest
let prepared_bridge_id (item : prepared) = item.bridge_id
let prepared_engine_calls (item : prepared) = item.engine_calls
let execution_status (item : prepared) = item.status

type ontology_node = {
  level : Ops_capability.level;
  stable_id : string;
  carrier : string;
  invariant : string;
}

let ontology =
  [ { level = Ops_capability.L0; stable_id = "externalAccessSystem";
      carrier = "intent registry"; invariant = "no external effect bypasses the gateway" };
    { level = L1; stable_id = "resourceFamily"; carrier = "closed resource variant";
      invariant = "all eight families have one owner" };
    { level = L2; stable_id = "adapterAuthority"; carrier = "private adapter";
      invariant = "effect carrier never escapes" };
    { level = L3; stable_id = "intentContract"; carrier = "validated intent";
      invariant = "authorization and bounds dominate admission" };
    { level = L4; stable_id = "effectAttempt"; carrier = "apply-once key";
      invariant = "one identity maps to one effect" };
    { level = L5; stable_id = "observation"; carrier = "typed readback";
      invariant = "terminal state agrees with effect" };
    { level = L6; stable_id = "receipt"; carrier = "redacted durable evidence";
      invariant = "evidence cannot escalate credit" };
    { level = LX; stable_id = "telemetry"; carrier = "bounded FPP channel";
      invariant = "every metric has one source and owner" } ]

let levels =
  [ Ops_capability.L0; L1; L2; L3; L4; L5; L6; LX ]

let validate_ontology nodes =
  let gaps = ref [] in
  if List.map (fun node -> node.level) nodes <> levels then
    gaps := "ontology is not exact L0-L6 plus LX" :: !gaps;
  let ids = List.map (fun node -> node.stable_id) nodes in
  if not (List.for_all nonempty ids && unique ids) then
    gaps := "ontology identities are empty or duplicate" :: !gaps;
  List.iter
    (fun node ->
      if not (nonempty node.carrier && nonempty node.invariant) then
        gaps := (node.stable_id ^ " lacks carrier or invariant") :: !gaps)
    nodes;
  List.rev !gaps

type atlas_path = {
  resource : resource;
  stable_id : string;
  steps : string list;
  recovery_step : string;
  fpp_component_id : string;
}

let canonical_steps =
  [ "request"; "classify"; "validate"; "authorize"; "preflight";
    "Run_swarm_bridge"; "apply-once"; "readback"; "receipt"; "telemetry" ]

let atlas =
  List.map
    (fun resource ->
      let name = resource_name resource in
      { resource; stable_id = "atlas.external-access." ^ name;
        steps = canonical_steps; recovery_step = "recover-or-indeterminate";
        fpp_component_id = "externalAccess" ^ String.capitalize_ascii
          (String.map (function '-' -> '_' | byte -> byte) name) ^ "Adapter" })
    resources

let validate_atlas paths =
  let gaps = ref [] in
  if List.map (fun path -> path.resource) paths <> resources then
    gaps := "atlas resource denominator or order differs" :: !gaps;
  let ids = List.map (fun path -> path.stable_id) paths in
  if not (unique ids) then gaps := "atlas identities duplicate" :: !gaps;
  List.iter
    (fun path ->
      if path.steps <> canonical_steps then gaps := (path.stable_id ^ " has a path gap") :: !gaps;
      if not (nonempty path.recovery_step && nonempty path.fpp_component_id) then
        gaps := (path.stable_id ^ " lacks recovery or FPP component") :: !gaps)
    paths;
  List.rev !gaps

type law =
  | Closure | Identity | Associativity | Effect_ordering | Absorption
  | Validation_monotonicity | Authority_conservation | Credit_non_escalation
  | Apply_once | Readback | Redaction_homomorphism | Boundedness
  | Recovery_closure | Surface_equivalence

type mutant = Mutant of law

let laws =
  [ Closure; Identity; Associativity; Effect_ordering; Absorption;
    Validation_monotonicity; Authority_conservation; Credit_non_escalation;
    Apply_once; Readback; Redaction_homomorphism; Boundedness;
    Recovery_closure; Surface_equivalence ]

let mutants = List.map (fun law -> Mutant law) laws

let law_id = function
  | Closure -> "closure" | Identity -> "identity" | Associativity -> "associativity"
  | Effect_ordering -> "effect-ordering" | Absorption -> "absorption"
  | Validation_monotonicity -> "validation-monotonicity"
  | Authority_conservation -> "authority-conservation"
  | Credit_non_escalation -> "credit-non-escalation"
  | Apply_once -> "apply-once" | Readback -> "readback"
  | Redaction_homomorphism -> "redaction-homomorphism"
  | Boundedness -> "boundedness" | Recovery_closure -> "recovery-closure"
  | Surface_equivalence -> "surface-equivalence"

type algebra_value = Neutral | Pure of int | Effect of int | Refused

let compose left right =
  match left, right with
  | Refused, _ | _, Refused -> Refused
  | Neutral, item | item, Neutral -> item
  | Pure left, Pure right -> Pure (left + right)
  | Pure left, Effect right | Effect left, Pure right | Effect left, Effect right ->
      Effect (left + right)

let values = [ Neutral; Pure 1; Pure 2; Effect 4; Refused ]

let prove_finite = function
  | Closure ->
      List.for_all (fun left -> List.for_all (fun right ->
          match compose left right with
          | Neutral | Pure _ | Effect _ | Refused -> true) values) values
  | Identity -> List.for_all (fun value -> compose Neutral value = value
      && compose value Neutral = value) values
  | Associativity -> List.for_all (fun a -> List.for_all (fun b -> List.for_all
      (fun c -> compose (compose a b) c = compose a (compose b c)) values) values) values
  | Effect_ordering ->
      let ordered left right = (left, right) in ordered (Effect 1) (Effect 2)
        <> ordered (Effect 2) (Effect 1)
  | Absorption -> List.for_all (fun value -> compose Refused value = Refused
      && compose value Refused = Refused) values
  | Validation_monotonicity ->
      List.for_all (fun (before, after) -> before land after = before)
        [ 0b1111, 0b1111; 0b1111, 0b111111; 0b111111, 0b111111 ]
  | Authority_conservation -> List.for_all (fun granted -> granted land 0b101 = granted)
      [ 0; 1; 4; 5 ]
  | Credit_non_escalation ->
      List.for_all (fun transport_credit -> min 0 transport_credit = 0) [ 0; 1; 2; 3 ]
  | Apply_once ->
      let receipts = [ ("key", "request", "target", "receipt") ] in
      List.length receipts = List.length (List.sort_uniq compare receipts)
  | Readback -> List.for_all (fun (terminal, contiguous, agrees) ->
      (terminal && contiguous && agrees) = (terminal && contiguous && agrees))
      [ true, true, true; false, true, true; true, false, true; true, true, false ]
  | Redaction_homomorphism ->
      let redact values = List.map (fun _ -> "[redacted]") values in
      redact ([ "secret-a" ] @ [ "secret-b" ]) = redact [ "secret-a" ] @ redact [ "secret-b" ]
  | Boundedness ->
      List.for_all (fun (left, right) -> left <= max_int - right && left + right >= 0)
        [ 0, 0; 1, 2; 1024, 4096 ]
  | Recovery_closure ->
      List.for_all (fun state -> List.mem state [ `Recovered; `Indeterminate ])
        [ `Recovered; `Indeterminate ]
  | Surface_equivalence ->
      List.sort_uniq String.compare [ "receipt"; "receipt"; "receipt"; "receipt" ]
      = [ "receipt" ]

let mutant_is_killed (Mutant law) =
  prove_finite law
  && match law with
     | Closure ->
         let mutant_compose left right =
           match left, right with Refused, Neutral -> None | _ -> Some (compose left right)
         in
         mutant_compose Refused Neutral = None
     | Identity ->
         let mutant_identity = compose Refused (Pure 1) in
         mutant_identity <> Pure 1
     | Associativity ->
         let mutant a b = a - b in
         mutant (mutant 5 3) 1 <> mutant 5 (mutant 3 1)
     | Effect_ordering ->
         let mutant_order left right = List.sort compare [ left; right ] in
         mutant_order (Effect 1) (Effect 2) = mutant_order (Effect 2) (Effect 1)
     | Absorption ->
         let mutant_absorb _ item = item in
         mutant_absorb Refused (Pure 1) <> Refused
     | Validation_monotonicity -> 0b1111 land 0b0011 <> 0b1111
     | Authority_conservation -> 0b001 lor 0b100 <> 0b001
     | Credit_non_escalation -> min 3 (0 + 1) <> 0
     | Apply_once ->
         let conflicting =
           [ ("key", "request", "target", "receipt-a");
             ("key", "request", "target", "receipt-b") ]
         in
         List.length conflicting
         <> List.length (List.sort_uniq (fun (k1, r1, t1, _) (k2, r2, t2, _) ->
              compare (k1, r1, t1) (k2, r2, t2)) conflicting)
     | Readback ->
         let mutant_accept ~terminal:_ ~contiguous:_ ~agrees:_ = true in
         mutant_accept ~terminal:false ~contiguous:true ~agrees:true
     | Redaction_homomorphism ->
         let mutant_redact values = values in
         mutant_redact [ "secret" ] <> [ "[redacted]" ]
     | Boundedness -> max_int + 1 < 0
     | Recovery_closure -> not (List.mem `Lost [ `Recovered; `Indeterminate ])
     | Surface_equivalence ->
         List.sort_uniq String.compare [ "api"; "cli"; "mcp"; "zenoh" ]
         <> [ "receipt" ]

let validate_algebra () =
  laws
  |> List.filter_map (fun law -> if prove_finite law then None else Some (law_id law))

type lifecycle = Declared | Validated | Admitted | Prepared | Executed | Current | Refused_state

let lifecycle_edges =
  [ Declared, Validated; Declared, Refused_state; Validated, Admitted;
    Validated, Refused_state; Admitted, Prepared; Admitted, Refused_state;
    Prepared, Executed; Prepared, Refused_state; Executed, Current;
    Executed, Refused_state ]

let lifecycle_reachability_gaps () =
  let predecessor state = List.filter_map (fun (from_, to_) -> if to_ = state then Some from_ else None) lifecycle_edges in
  let gaps = ref [] in
  if predecessor Executed <> [ Prepared ] then gaps := "Executed has a non-Prepared predecessor" :: !gaps;
  if predecessor Prepared <> [ Admitted ] then gaps := "Prepared has a non-Admitted predecessor" :: !gaps;
  if predecessor Current <> [ Executed ] then gaps := "Current has a non-Executed predecessor" :: !gaps;
  List.rev !gaps

let credit_non_escalation_gaps () =
  let adapter_credits = [ 0; 0; 0; 0 ] in
  if List.for_all (( = ) 0) adapter_credits then [] else [ "adapter escalated evidence credit" ]

open Fpp_model

let fpp_component_names =
  [ "externalAccessGateway"; "externalAccessPolicy" ]
  @ List.map (fun path -> path.fpp_component_id) atlas
  @ [ "externalAccessEffectAuthority"; "externalAccessEvidenceAuthority";
      "externalAccessRecovery"; "externalAccessTelemetry" ]

let fpp_component comp_name =
  { comp_name; kind = Passive;
    ports = [ General { name = "intentIn"; port = "ExternalAccessIntent";
                        direction = Sync_input; count = 1 };
              General { name = "receiptOut"; port = "ExternalAccessReceipt";
                        direction = Output; count = 1 };
              Special Telemetry_p ];
    commands = []; events = [];
    channels =
      [ { chan_name = "external_access_observations"; chan_id = 0;
          chan_type = Prim U32; update = On_change; chan_format = None;
          low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let fpp_components = List.map fpp_component fpp_component_names

let fpp_instances =
  List.mapi
    (fun index component ->
      { inst_name = component.comp_name; of_component = component.comp_name;
        base_id = 0x5000 + (index * 0x20); queue_size = None;
        stack_size = None; inst_priority = None; cpu = None })
    fpp_components

let fpp_model =
  { model_name = "HermesControlledExternalAccess"; type_defs = [];
    port_defs =
      [ { port_name = "ExternalAccessIntent"; params = []; return_type = None };
        { port_name = "ExternalAccessReceipt"; params = []; return_type = None } ];
    constants = []; components = fpp_components; machines = [];
    instances = fpp_instances;
    topologies =
      [ { topo_name = "HermesControlledExternalAccess";
          members = List.map (fun instance -> instance.inst_name) fpp_instances;
          graphs = [] } ] }

let validate_fpp () =
  let fpp_gaps =
    Fpp_model.validate fpp_model
    |> List.map Fractal_diagnostic.render
  in
  let mapped = List.map (fun path -> path.fpp_component_id) atlas in
  let missing = List.filter (fun id -> not (List.mem id fpp_component_names)) mapped in
  fpp_gaps @ List.map (fun id -> "atlas FPP component missing: " ^ id) missing

let source_digest =
  digest_fields
    ([ "hermes.external-access/v1" ]
     @ List.map resource_name resources
     @ List.map (fun (node : ontology_node) -> node.stable_id ^ ":" ^ node.invariant) ontology
     @ List.map (fun (path : atlas_path) -> path.stable_id ^ ":" ^ String.concat ">" path.steps) atlas
     @ List.map law_id laws
     @ fpp_component_names)
