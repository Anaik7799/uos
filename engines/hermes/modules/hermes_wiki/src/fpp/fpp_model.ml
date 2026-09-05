(* The FPP metamodel in OCaml. See fpp_model.mli for the contract and
   docs/hermes/fprime-alignment.md for the construct-by-construct mapping.

   Design: pure data in, pure verdicts out. The validator enforces the FPP
   spec's semantic rules and reports each violation as a fractal diagnostic
   at L3/contract with Specification origin — a model defect is the
   specification saying the wrong thing, and it can never touch parity
   credit. Emitters are fail-closed on invalid models. *)

type prim = U8 | U16 | U32 | U64 | I8 | I16 | I32 | I64 | F32 | F64 | Bool
          | String of int option

type ty = Prim of prim | Named of string

type type_def =
  | Abstract of { name : string }
  | Alias of { name : string; target : ty }
  | Array_t of { name : string; size : int; element : ty; format : string option }
  | Enum_t of { name : string; repr : prim; constants : (string * int) list }
  | Struct_t of { name : string; members : (string * ty) list }

type port_def = {
  port_name : string;
  params : (string * ty) list;
  return_type : ty option;
}

type queue_full = Assert | Block | Drop

type direction =
  | Sync_input
  | Guarded_input
  | Async_input of { priority : int option; queue_full : queue_full }
  | Output

type special_port =
  | Command_recv | Command_reg | Command_resp
  | Event_p | Text_event_p | Telemetry_p | Time_get
  | Param_get_p | Param_set_p
  | Product_get_p | Product_request_p | Product_recv_p | Product_send_p

type port_instance =
  | General of { name : string; port : string; direction : direction; count : int }
  | Special of special_port

type command_kind =
  | Sync_cmd
  | Guarded_cmd
  | Async_cmd of { priority : int option; queue_full : queue_full }

type command = {
  cmd_name : string;
  opcode : int;
  cmd_kind : command_kind;
  cmd_params : (string * ty) list;
}

type severity =
  | Activity_hi | Activity_lo | Command_sev | Diagnostic | Fatal
  | Warning_hi | Warning_lo

type event = {
  event_name : string;
  event_id : int;
  severity : severity;
  format : string;
  throttle : int option;
}

type update = Always | On_change

type threshold = { yellow : float option; orange : float option; red : float option }

type channel = {
  chan_name : string;
  chan_id : int;
  chan_type : ty;
  update : update;
  chan_format : string option;
  low : threshold option;
  high : threshold option;
}

type parameter = {
  param_name : string;
  param_id : int;
  param_type : ty;
  default : string option;
  set_opcode : int;
  save_opcode : int;
  external_ : bool;
}

type record_spec = {
  record_name : string;
  record_id : int;
  record_type : ty;
  record_is_array : bool;
}

type container_spec = {
  container_name : string;
  container_id : int;
  default_priority : int option;
}

type internal_port = {
  internal_name : string;
  internal_params : (string * ty) list;
  internal_priority : int option;
  internal_queue_full : queue_full;
}

type target = To_state of string | To_choice of string

type transition = {
  on_signal : string;
  guard : string option;
  do_actions : string list;
  target : target;
}

type state = {
  state_name : string;
  entry : string list;
  exit_ : string list;
  transitions : transition list;
}

type signal_def = { signal_name : string; signal_type : ty option }

type choice = {
  choice_name : string;
  choice_guard : string;
  if_true : string list * target;
  if_false : string list * target;
}

type state_machine =
  | External_machine of { machine_name : string }
  | Internal_machine of {
      machine_name : string;
      signals : signal_def list;
      guards : string list;
      actions : string list;
      states : state list;
      choices : choice list;
      initial : string list * string;
    }

type component_kind = Passive | Queued | Active

type component = {
  comp_name : string;
  kind : component_kind;
  ports : port_instance list;
  commands : command list;
  events : event list;
  channels : channel list;
  parameters : parameter list;
  records : record_spec list;
  containers : container_spec list;
  internal_ports : internal_port list;
  machines : (string * string) list;
  matched : (string * string) list;
}

type instance = {
  inst_name : string;
  of_component : string;
  base_id : int;
  queue_size : int option;
  stack_size : int option;
  inst_priority : int option;
  cpu : int option;
}

type endpoint = { ep_instance : string; ep_port : string; ep_index : int option }

type connection = { from_ : endpoint; to_ : endpoint }

type pattern_kind =
  | P_command | P_event | P_telemetry | P_text_event | P_time | P_health | P_param

type graph =
  | Direct of { graph_name : string; connections : connection list }
  | Pattern of { pattern : pattern_kind; source : string; targets : string list }

type topology = {
  topo_name : string;
  members : string list;
  graphs : graph list;
}

type model = {
  model_name : string;
  type_defs : type_def list;
  port_defs : port_def list;
  constants : (string * int) list;
  components : component list;
  machines : state_machine list;
  instances : instance list;
  topologies : topology list;
}

(* -------------------------------------------------------------- helpers *)

let diag hazard node subject message cause fix =
  { Fractal_diagnostic.hazard; level = Fractal_diagnostic.L3_contract;
    origin = Fractal_diagnostic.Specification;
    impact = Fractal_diagnostic.No_effect; node; subject; message; cause; fix }

let type_def_name = function
  | Abstract { name } | Alias { name; _ } | Array_t { name; _ }
  | Enum_t { name; _ } | Struct_t { name; _ } -> name

let machine_name = function
  | External_machine { machine_name } -> machine_name
  | Internal_machine { machine_name; _ } -> machine_name

let find_component model name =
  List.find_opt (fun c -> c.comp_name = name) model.components

let find_instance model name =
  List.find_opt (fun i -> i.inst_name = name) model.instances

let duplicates values =
  let sorted = List.sort compare values in
  let rec go = function
    | a :: (b :: _ as rest) -> if a = b then a :: go rest else go rest
    | _ -> []
  in
  List.sort_uniq compare (go sorted)

(* The canonical name of each special port, used for endpoints and pattern
   expansion. Direction is fixed by the framework. *)
let special_name = function
  | Command_recv -> "cmdIn"
  | Command_reg -> "cmdRegOut"
  | Command_resp -> "cmdResponseOut"
  | Event_p -> "logOut"
  | Text_event_p -> "logTextOut"
  | Telemetry_p -> "tlmOut"
  | Time_get -> "timeGetOut"
  | Param_get_p -> "prmGetOut"
  | Param_set_p -> "prmSetOut"
  | Product_get_p -> "productGetOut"
  | Product_request_p -> "productRequestOut"
  | Product_recv_p -> "productRecvIn"
  | Product_send_p -> "productSendOut"

let special_is_output = function
  | Command_recv | Product_recv_p -> false
  | Command_reg | Command_resp | Event_p | Text_event_p | Telemetry_p
  | Time_get | Param_get_p | Param_set_p | Product_get_p
  | Product_request_p | Product_send_p -> true

type resolved_port =
  | R_general of { direction : direction; count : int; port : string }
  | R_special of special_port

let resolve_port component name =
  List.find_map
    (function
      | General g when g.name = name ->
          Some (R_general { direction = g.direction; count = g.count; port = g.port })
      | Special s when special_name s = name -> Some (R_special s)
      | _ -> None)
    component.ports

let port_is_output = function
  | R_general { direction = Output; _ } -> true
  | R_general _ -> false
  | R_special s -> special_is_output s

(* ------------------------------------------------------------- id_span *)

let id_span component =
  let ids =
    List.map (fun c -> c.opcode) component.commands
    @ List.map (fun e -> e.event_id) component.events
    @ List.map (fun c -> c.chan_id) component.channels
    @ List.concat_map
        (fun p -> [ p.param_id; p.set_opcode; p.save_opcode ])
        component.parameters
    @ List.map (fun r -> r.record_id) component.records
    @ List.map (fun c -> c.container_id) component.containers
  in
  List.fold_left (fun acc id -> if id + 1 > acc then id + 1 else acc) 1 ids

(* ------------------------------------------------------------- validate *)

let check_names model =
  let bad kind name =
    diag "FPP-NAME-01" kind name "empty name" "a definition has no name"
      "name every definition; FPP identifiers are non-empty"
  in
  List.filter_map
    (fun (kind, name) -> if name = "" then Some (bad kind name) else None)
    (List.map (fun c -> ("component", c.comp_name)) model.components
    @ List.map (fun p -> ("port", p.port_name)) model.port_defs
    @ List.map (fun i -> ("instance", i.inst_name)) model.instances
    @ List.map (fun t -> ("topology", t.topo_name)) model.topologies
    @ List.map (fun m -> ("state machine", machine_name m)) model.machines
    @ List.map (fun d -> ("type", type_def_name d)) model.type_defs)

let named_uses model =
  let of_ty context = function Named n -> [ (context, n) ] | Prim _ -> [] in
  let of_params context params =
    List.concat_map (fun (_, t) -> of_ty context t) params
  in
  List.concat_map
    (fun d ->
      match d with
      | Abstract _ | Enum_t _ -> []
      | Alias { name; target } -> of_ty ("alias " ^ name) target
      | Array_t { name; element; _ } -> of_ty ("array " ^ name) element
      | Struct_t { name; members } -> of_params ("struct " ^ name) members)
    model.type_defs
  @ List.concat_map
      (fun p ->
        of_params ("port " ^ p.port_name) p.params
        @ match p.return_type with Some t -> of_ty ("port " ^ p.port_name) t | None -> [])
      model.port_defs
  @ List.concat_map
      (fun c ->
        of_params ("component " ^ c.comp_name)
          (List.concat_map (fun cmd -> cmd.cmd_params) c.commands)
        @ List.concat_map (fun ch -> of_ty ("component " ^ c.comp_name) ch.chan_type) c.channels
        @ List.concat_map (fun p -> of_ty ("component " ^ c.comp_name) p.param_type) c.parameters
        @ List.concat_map (fun r -> of_ty ("component " ^ c.comp_name) r.record_type) c.records
        @ of_params ("component " ^ c.comp_name)
            (List.concat_map (fun ip -> ip.internal_params) c.internal_ports))
      model.components

let check_types model =
  let defined = List.map type_def_name model.type_defs in
  let unresolved =
    List.filter_map
      (fun (context, name) ->
        if List.mem name defined then None
        else
          Some
            (diag "FPP-TYPE-01" context name
               ("type " ^ name ^ " does not resolve")
               "a named type is used but never defined"
               "define the type or correct the reference"))
      (named_uses model)
  in
  (* Use-def cycles among type definitions (alias chains, struct/array
     nesting): a cycle makes evaluation undefined, exactly what the spec's
     acyclic use-def graph forbids. *)
  let edges =
    List.concat_map
      (fun d ->
        let source = type_def_name d in
        let targets =
          match d with
          | Abstract _ | Enum_t _ -> []
          | Alias { target = Named n; _ } -> [ n ]
          | Alias _ -> []
          | Array_t { element = Named n; _ } -> [ n ]
          | Array_t _ -> []
          | Struct_t { members; _ } ->
              List.filter_map (function _, Named n -> Some n | _ -> None) members
        in
        List.map (fun t -> (source, t)) targets)
      model.type_defs
  in
  let rec reaches seen origin current =
    List.exists
      (fun (s, t) ->
        s = current
        && (t = origin || ((not (List.mem t seen)) && reaches (t :: seen) origin t)))
      edges
  in
  let cyclic =
    List.filter (fun d -> reaches [] (type_def_name d) (type_def_name d)) model.type_defs
  in
  unresolved
  @ List.map
      (fun d ->
        diag "FPP-TYPE-02" "type definitions" (type_def_name d)
          ("type " ^ type_def_name d ^ " participates in a use-def cycle")
          "the type depends on itself through aliases or members"
          "break the cycle; the use-def graph must be acyclic")
      cyclic

let has_async_element component =
  List.exists
    (function General { direction = Async_input _; _ } -> true | _ -> false)
    component.ports
  || component.internal_ports <> []
  || List.exists (fun c -> match c.cmd_kind with Async_cmd _ -> true | _ -> false)
       component.commands
  || component.machines <> []

let check_component model c =
  let where = "component " ^ c.comp_name in
  let passive_law =
    match c.kind with
    | Passive when has_async_element c ->
        [ diag "FPP-CMP-01" where c.comp_name
            "a passive component carries async machinery"
            "passive components have no queue: async ports, internal ports, \
             async commands and state machine instances are all queue-fed"
            "make the component queued/active, or remove the async member" ]
    | Queued | Active when not (has_async_element c) ->
        [ diag "FPP-CMP-02" where c.comp_name
            "a queued/active component has no async element"
            "the queue would exist with nothing to feed it"
            "add an async port/command/internal port/state machine, or make \
             the component passive" ]
    | _ -> []
  in
  let dup hazard what values =
    List.map
      (fun v ->
        diag hazard where v
          (what ^ " " ^ v ^ " is not distinct")
          ("two " ^ what ^ "s share a name or identifier")
          "names and identifiers are per-component dictionaries; renumber")
      (duplicates values)
  in
  let commands =
    dup "FPP-CMP-03" "command name" (List.map (fun x -> x.cmd_name) c.commands)
    @ dup "FPP-CMP-03" "command opcode"
        (List.map (fun x -> string_of_int x.opcode) c.commands)
  in
  let events =
    dup "FPP-CMP-04" "event name" (List.map (fun x -> x.event_name) c.events)
    @ dup "FPP-CMP-04" "event id" (List.map (fun x -> string_of_int x.event_id) c.events)
  in
  let channels =
    dup "FPP-CMP-05" "channel name" (List.map (fun x -> x.chan_name) c.channels)
    @ dup "FPP-CMP-05" "channel id" (List.map (fun x -> string_of_int x.chan_id) c.channels)
  in
  let parameters =
    dup "FPP-CMP-06" "parameter name" (List.map (fun x -> x.param_name) c.parameters)
    @ dup "FPP-CMP-06" "parameter id"
        (List.map (fun x -> string_of_int x.param_id) c.parameters)
    @
    (* set/save opcodes live in the command opcode space *)
    let opcode_space =
      List.map (fun x -> x.opcode) c.commands
      @ List.concat_map (fun p -> [ p.set_opcode; p.save_opcode ]) c.parameters
    in
    List.map
      (fun v ->
        diag "FPP-CMP-06" where (string_of_int v)
          ("opcode " ^ string_of_int v ^ " is claimed twice (command vs param set/save)")
          "parameter set/save opcodes share the command opcode space"
          "renumber the parameter opcodes")
      (duplicates opcode_space)
  in
  let products =
    dup "FPP-CMP-07" "record/container name"
      (List.map (fun r -> r.record_name) c.records
      @ List.map (fun k -> k.container_name) c.containers)
    @ dup "FPP-CMP-07" "record/container id"
        (List.map (fun r -> string_of_int r.record_id) c.records
        @ List.map (fun k -> string_of_int k.container_id) c.containers)
    @
    match (c.records, c.containers) with
    | [], [] -> []
    | _ :: _, _ :: _ -> []
    | _ ->
        [ diag "FPP-CMP-08" where c.comp_name
            "records and containers must appear together"
            "a record with no container (or vice versa) can never produce a \
             data product"
            "add the missing half or remove both" ]
  in
  let specials =
    dup "FPP-CMP-09" "special port"
      (List.filter_map
         (function Special s -> Some (special_name s) | General _ -> None)
         c.ports)
  in
  let machines =
    dup "FPP-CMP-10" "state machine instance"
      (List.map fst c.machines)
    @ List.filter_map
        (fun (inst, machine) ->
          if List.exists (fun m -> machine_name m = machine) model.machines
          then None
          else
            Some
              (diag "FPP-CMP-10" where inst
                 ("state machine " ^ machine ^ " does not exist")
                 "a state machine instance names an undefined machine"
                 "define the machine or fix the reference"))
        c.machines
  in
  passive_law @ commands @ events @ channels @ parameters @ products @ specials
  @ machines

let check_machine m =
  match m with
  | External_machine _ -> []
  | Internal_machine m ->
      let where = "state machine " ^ m.machine_name in
      let state_names = List.map (fun s -> s.state_name) m.states in
      let choice_names = List.map (fun c -> c.choice_name) m.choices in
      let signal_names = List.map (fun s -> s.signal_name) m.signals in
      let target_ok = function
        | To_state s -> List.mem s state_names
        | To_choice c -> List.mem c choice_names
      in
      let initial =
        let _, target = m.initial in
        if List.mem target state_names then []
        else
          [ diag "FPP-SM-01" where target
              ("initial transition enters undefined state " ^ target)
              "every internal machine needs exactly one initial transition \
               into a defined state"
              "define the state or retarget the initial transition" ]
      in
      let transition_diags =
        List.concat_map
          (fun s ->
            List.concat_map
              (fun t ->
                let bad what name =
                  diag "FPP-SM-02" where (s.state_name ^ "/" ^ name)
                    (what ^ " " ^ name ^ " is not defined")
                    "a transition references an undefined element"
                    "define it or fix the reference"
                in
                (if List.mem t.on_signal signal_names then []
                 else [ bad "signal" t.on_signal ])
                @ (match t.guard with
                  | Some g when not (List.mem g m.guards) -> [ bad "guard" g ]
                  | _ -> [])
                @ List.filter_map
                    (fun a -> if List.mem a m.actions then None else Some (bad "action" a))
                    t.do_actions
                @ if target_ok t.target then []
                  else
                    [ bad "target"
                        (match t.target with To_state s -> s | To_choice c -> c) ])
              s.transitions
            @ List.filter_map
                (fun a ->
                  if List.mem a m.actions then None
                  else
                    Some
                      (diag "FPP-SM-02" where (s.state_name ^ "/entry-exit")
                         ("action " ^ a ^ " is not defined")
                         "an entry/exit action is undefined" "define the action"))
                (s.entry @ s.exit_))
          m.states
      in
      let choice_diags =
        List.concat_map
          (fun (c : choice) ->
            let arc (actions, target) =
              List.filter_map
                (fun a ->
                  if List.mem a m.actions then None
                  else
                    Some
                      (diag "FPP-SM-02" where (c.choice_name ^ "/" ^ a)
                         ("action " ^ a ^ " is not defined")
                         "a choice arc runs an undefined action" "define the action"))
                actions
              @ if target_ok target then []
                else
                  [ diag "FPP-SM-02" where c.choice_name
                      "choice arc targets an undefined state/choice"
                      "a choice arc references an undefined element"
                      "define it or fix the reference" ]
            in
            (if List.mem c.choice_guard m.guards then []
             else
               [ diag "FPP-SM-02" where c.choice_name
                   ("guard " ^ c.choice_guard ^ " is not defined")
                   "a choice references an undefined guard" "define the guard" ])
            @ arc c.if_true @ arc c.if_false)
          m.choices
      in
      let choice_cycles =
        (* Edges choice -> choice; the spec forbids cycles in this subgraph. *)
        let edges =
          List.concat_map
            (fun (c : choice) ->
              let arc (_, target) =
                match target with To_choice t -> [ (c.choice_name, t) ] | To_state _ -> []
              in
              arc c.if_true @ arc c.if_false)
            m.choices
        in
        let rec reaches seen origin current =
          List.exists
            (fun (s, t) ->
              s = current
              && (t = origin || ((not (List.mem t seen)) && reaches (t :: seen) origin t)))
            edges
        in
        List.filter_map
          (fun (c : choice) ->
            if reaches [] c.choice_name c.choice_name then
              Some
                (diag "FPP-SM-03" where c.choice_name
                   ("choice " ^ c.choice_name ^ " lies on a cycle")
                   "the choice subgraph must be acyclic (branching must \
                    terminate)"
                   "break the cycle with a state target")
            else None)
          m.choices
      in
      initial @ transition_diags @ choice_diags @ choice_cycles

let check_instances model =
  let resolution =
    List.concat_map
      (fun i ->
        let where = "instance " ^ i.inst_name in
        match find_component model i.of_component with
        | None ->
            [ diag "FPP-INST-01" where i.of_component
                ("component " ^ i.of_component ^ " does not exist")
                "an instance names an undefined component"
                "define the component or fix the reference" ]
        | Some c ->
            let queue =
              match (c.kind, i.queue_size) with
              | Passive, Some _ ->
                  [ diag "FPP-INST-01" where i.inst_name
                      "a passive instance declares a queue size"
                      "passive components have no queue" "remove the queue size" ]
              | (Queued | Active), None ->
                  [ diag "FPP-INST-01" where i.inst_name
                      "a queued/active instance has no queue size"
                      "the dispatch queue must be dimensioned" "declare a queue size" ]
              | _ -> []
            in
            let thread_only =
              if c.kind <> Active
                 && (i.stack_size <> None || i.inst_priority <> None || i.cpu <> None)
              then
                [ diag "FPP-INST-01" where i.inst_name
                    "stack/priority/cpu on a threadless instance"
                    "only active components own a thread"
                    "remove the thread attributes or make the component active" ]
              else []
            in
            queue @ thread_only)
      model.instances
  in
  let names =
    List.map
      (fun v ->
        diag "FPP-INST-03" "instances" v
          ("instance name " ^ v ^ " is not distinct")
          "two instances share a name" "rename one instance")
      (duplicates (List.map (fun i -> i.inst_name) model.instances))
  in
  let ranges =
    (* Sorted-by-base consecutive comparison: subtraction, never addition,
       so ids near max_int cannot overflow the check. *)
    let spans =
      List.filter_map
        (fun i ->
          match find_component model i.of_component with
          | Some c -> Some (i.inst_name, i.base_id, id_span c)
          | None -> None)
        model.instances
    in
    let sorted = List.sort (fun (_, a, _) (_, b, _) -> compare a b) spans in
    let rec go = function
      | (a_name, a_base, a_span) :: ((b_name, b_base, _) :: _ as rest) ->
          (if b_base - a_base < a_span then
             [ diag "FPP-INST-02" "instances" (a_name ^ "/" ^ b_name)
                 (Printf.sprintf "base-id ranges of %s and %s overlap" a_name b_name)
                 "two instances claim the same identifier window"
                 "move a base id; ranges are [base, base + id span)" ]
           else [])
          @ go rest
      | _ -> []
    in
    go sorted
  in
  resolution @ names @ ranges

let direct_connections topology =
  List.concat_map
    (function Direct { connections; _ } -> connections | Pattern _ -> [])
    topology.graphs

let check_topology model topology =
  let where = "topology " ^ topology.topo_name in
  let member_instances =
    List.filter_map
      (fun m ->
        match find_instance model m with
        | Some i -> Some (m, i)
        | None -> None)
      topology.members
  in
  let members =
    List.filter_map
      (fun m ->
        if find_instance model m <> None then None
        else
          Some
            (diag "FPP-TOPO-01" where m
               ("member " ^ m ^ " is not a component instance")
               "a topology lists an undefined instance"
               "define the instance or remove the member"))
      topology.members
  in
  let resolve_endpoint ep =
    match List.assoc_opt ep.ep_instance member_instances with
    | None -> Error ("instance " ^ ep.ep_instance ^ " is not a topology member")
    | Some i -> (
        match find_component model i.of_component with
        | None -> Error ("component " ^ i.of_component ^ " does not exist")
        | Some c -> (
            match resolve_port c ep.ep_port with
            | None ->
                Error
                  ("port " ^ ep.ep_port ^ " does not exist on " ^ c.comp_name)
            | Some r -> Ok (i, c, r)))
  in
  let connection_diags =
    List.concat_map
      (fun conn ->
        let label =
          conn.from_.ep_instance ^ "." ^ conn.from_.ep_port ^ " -> "
          ^ conn.to_.ep_instance ^ "." ^ conn.to_.ep_port
        in
        match (resolve_endpoint conn.from_, resolve_endpoint conn.to_) with
        | Error e, _ | _, Error e ->
            [ diag "FPP-TOPO-01" where label e "a connection endpoint does not resolve"
                "wire only declared ports of member instances" ]
        | Ok (_, _, from_port), Ok (_, _, to_port) ->
            let direction =
              if not (port_is_output from_port) then
                [ diag "FPP-TOPO-02" where label
                    "connection must run output -> input"
                    "the from endpoint is an input port" "swap the endpoints" ]
              else if port_is_output to_port then
                [ diag "FPP-TOPO-02" where label
                    "connection must run output -> input"
                    "the to endpoint is an output port" "swap the endpoints" ]
              else []
            in
            let types =
              match (from_port, to_port) with
              | R_general a, R_general b when a.port <> b.port ->
                  [ diag "FPP-TOPO-03" where label
                      (Printf.sprintf "port types differ (%s vs %s)" a.port b.port)
                      "output and input must speak the same port type"
                      "use matching port definitions" ]
              | _ -> []
            in
            let bounds ep resolved =
              match (ep.ep_index, resolved) with
              | Some k, R_general { count; _ } when k < 0 || k >= count ->
                  [ diag "FPP-TOPO-04" where label
                      (Printf.sprintf "port index %d outside [0, %d)" k count)
                      "the port array is smaller than the index"
                      "grow the array or renumber" ]
              | _ -> []
            in
            direction @ types @ bounds conn.from_ from_port @ bounds conn.to_ to_port)
      (direct_connections topology)
  in
  let output_conflicts =
    let froms =
      List.filter_map
        (fun c ->
          match c.from_.ep_index with
          | Some k -> Some ((c.from_.ep_instance, c.from_.ep_port, k), c)
          | None -> None)
        (direct_connections topology)
    in
    List.map
      (fun (inst, port, k) ->
        diag "FPP-TOPO-04" where (Printf.sprintf "%s.%s[%d]" inst port k)
          "an output port index drives two connections"
          "each output index carries exactly one connection"
          "fan out through distinct indexes")
      (duplicates (List.map fst froms))
      |> List.filter_map (fun d ->
             (* Only outputs conflict; fan-in to one input index is legal. *)
             match
               List.find_opt
                 (fun ((i, p, k), _) ->
                   Printf.sprintf "%s.%s[%d]" i p k = d.Fractal_diagnostic.subject)
                 froms
             with
             | Some _ -> Some d
             | None -> None)
  in
  let patterns =
    List.concat_map
      (function
        | Direct _ -> []
        | Pattern { source; targets; _ } ->
            List.filter_map
              (fun name ->
                if List.mem name topology.members && find_instance model name <> None
                then None
                else
                  Some
                    (diag "FPP-TOPO-05" where name
                       ("pattern endpoint " ^ name ^ " is not a topology member")
                       "patterns wire only member instances"
                       "add the instance to the topology or fix the pattern"))
              (source :: targets))
      topology.graphs
  in
  let matched =
    (* For every instance whose component declares `match p with q`, the
       connected index sets of p and q must be identical. *)
    let touched inst port =
      List.sort_uniq compare
        (List.filter_map
           (fun c ->
             if c.from_.ep_instance = inst && c.from_.ep_port = port then c.from_.ep_index
             else if c.to_.ep_instance = inst && c.to_.ep_port = port then c.to_.ep_index
             else None)
           (direct_connections topology))
    in
    List.concat_map
      (fun (name, i) ->
        match find_component model i.of_component with
        | None -> []
        | Some c ->
            List.filter_map
              (fun (p, q) ->
                if touched name p = touched name q then None
                else
                  Some
                    (diag "FPP-TOPO-06" where (name ^ ": " ^ p ^ " with " ^ q)
                       "matched ports connect different index sets"
                       "the match specifier requires index-for-index pairing"
                       "wire both ports at the same indexes"))
              c.matched)
      member_instances
  in
  members @ connection_diags @ output_conflicts @ patterns @ matched

let validate model =
  check_names model
  @ check_types model
  @ List.concat_map (check_component model) model.components
  @ List.concat_map check_machine model.machines
  @ check_instances model
  @ List.concat_map (check_topology model) model.topologies

(* ------------------------------------------------------ pattern expansion *)

let pattern_links = function
  (* (consuming special/general port on the target, serving general port on
     the source, direction target->source?) as (target_port, source_port,
     target_is_from) triples. *)
  | P_time -> [ (`Special Time_get, "timeGetIn", true) ]
  | P_telemetry -> [ (`Special Telemetry_p, "tlmIn", true) ]
  | P_event -> [ (`Special Event_p, "logIn", true) ]
  | P_text_event -> [ (`Special Text_event_p, "textLogIn", true) ]
  | P_param ->
      [ (`Special Param_get_p, "prmGetIn", true); (`Special Param_set_p, "prmSetIn", true) ]
  | P_command ->
      [ (`Special Command_recv, "cmdSendOut", false);
        (`Special Command_reg, "cmdRegIn", true);
        (`Special Command_resp, "cmdRespIn", true) ]
  | P_health -> [ (`General "pingIn", "pingOut", false); (`General "pingOut", "pingIn", true) ]

let connections model topology =
  let resolve name =
    match find_instance model name with
    | None -> Error ("unknown instance " ^ name)
    | Some i -> (
        match find_component model i.of_component with
        | None -> Error ("unknown component " ^ i.of_component)
        | Some c -> Ok c)
  in
  let expand_pattern pattern source targets =
    match resolve source with
    | Error e -> Error e
    | Ok _ ->
        let links = pattern_links pattern in
        Ok
          (List.concat_map
             (fun target ->
               match resolve target with
               | Error _ -> []
               | Ok c ->
                   List.filter_map
                     (fun (consumer, source_port, target_is_from) ->
                       let target_port =
                         match consumer with
                         | `Special s ->
                             if
                               List.exists
                                 (function Special x -> x = s | General _ -> false)
                                 c.ports
                             then Some (special_name s)
                             else None
                         | `General name -> (
                             match resolve_port c name with
                             | Some _ -> Some name
                             | None -> None)
                       in
                       match target_port with
                       | None -> None
                       | Some port ->
                           let t_ep = { ep_instance = target; ep_port = port; ep_index = None } in
                           let s_ep =
                             { ep_instance = source; ep_port = source_port; ep_index = None }
                           in
                           Some
                             (if target_is_from then { from_ = t_ep; to_ = s_ep }
                              else { from_ = s_ep; to_ = t_ep }))
                     links)
             targets)
  in
  List.fold_left
    (fun acc graph ->
      match (acc, graph) with
      | Error e, _ -> Error e
      | Ok done_, Direct { connections; _ } -> Ok (done_ @ connections)
      | Ok done_, Pattern { pattern; source; targets } -> (
          match expand_pattern pattern source targets with
          | Error e -> Error e
          | Ok more -> Ok (done_ @ more)))
    (Ok []) topology.graphs

(* --------------------------------------------------------------- to_fpp *)

let prim_name = function
  | U8 -> "U8" | U16 -> "U16" | U32 -> "U32" | U64 -> "U64"
  | I8 -> "I8" | I16 -> "I16" | I32 -> "I32" | I64 -> "I64"
  | F32 -> "F32" | F64 -> "F64" | Bool -> "bool"
  | String None -> "string"
  | String (Some n) -> Printf.sprintf "string size %d" n

let ty_name = function Prim p -> prim_name p | Named n -> n

let params_text params =
  String.concat ", " (List.map (fun (n, t) -> n ^ ": " ^ ty_name t) params)

let queue_full_name = function Assert -> "assert" | Block -> "block" | Drop -> "drop"

let severity_fpp = function
  | Activity_hi -> "activity high"
  | Activity_lo -> "activity low"
  | Command_sev -> "command"
  | Diagnostic -> "diagnostic"
  | Fatal -> "fatal"
  | Warning_hi -> "warning high"
  | Warning_lo -> "warning low"

let special_fpp = function
  | Command_recv -> "command recv port cmdIn"
  | Command_reg -> "command reg port cmdRegOut"
  | Command_resp -> "command resp port cmdResponseOut"
  | Event_p -> "event port logOut"
  | Text_event_p -> "text event port logTextOut"
  | Telemetry_p -> "telemetry port tlmOut"
  | Time_get -> "time get port timeGetOut"
  | Param_get_p -> "param get port prmGetOut"
  | Param_set_p -> "param set port prmSetOut"
  | Product_get_p -> "product get port productGetOut"
  | Product_request_p -> "product request port productRequestOut"
  | Product_recv_p -> "product recv port productRecvIn"
  | Product_send_p -> "product send port productSendOut"

let to_fpp model =
  let buffer = Buffer.create 4096 in
  let line indent text =
    Buffer.add_string buffer (String.make (indent * 2) ' ');
    Buffer.add_string buffer text;
    Buffer.add_char buffer '\n'
  in
  line 0 ("module " ^ model.model_name ^ " {");
  List.iter
    (fun d ->
      match d with
      | Abstract { name } -> line 1 ("type " ^ name)
      | Alias { name; target } -> line 1 ("type " ^ name ^ " = " ^ ty_name target)
      | Array_t { name; size; element; format } ->
          line 1
            (Printf.sprintf "array %s = [%d] %s%s" name size (ty_name element)
               (match format with Some f -> " format \"" ^ f ^ "\"" | None -> ""))
      | Enum_t { name; repr; constants } ->
          line 1
            (Printf.sprintf "enum %s : %s { %s }" name (prim_name repr)
               (String.concat ", "
                  (List.map (fun (n, v) -> Printf.sprintf "%s = %d" n v) constants)))
      | Struct_t { name; members } ->
          line 1 (Printf.sprintf "struct %s { %s }" name (params_text members)))
    model.type_defs;
  List.iter
    (fun (name, value) -> line 1 (Printf.sprintf "constant %s = %d" name value))
    model.constants;
  List.iter
    (fun p ->
      line 1
        (Printf.sprintf "port %s(%s)%s" p.port_name (params_text p.params)
           (match p.return_type with Some t -> " -> " ^ ty_name t | None -> "")))
    model.port_defs;
  List.iter
    (fun m ->
      match m with
      | External_machine { machine_name } -> line 1 ("state machine " ^ machine_name)
      | Internal_machine m ->
          line 1 ("state machine " ^ m.machine_name ^ " {");
          List.iter
            (fun s ->
              line 2
                ("signal " ^ s.signal_name
                ^ match s.signal_type with Some t -> ": " ^ ty_name t | None -> ""))
            m.signals;
          List.iter (fun g -> line 2 ("guard " ^ g)) m.guards;
          List.iter (fun a -> line 2 ("action " ^ a)) m.actions;
          (let actions, target = m.initial in
           line 2
             ("initial "
             ^ (if actions = [] then ""
                else "do { " ^ String.concat ", " actions ^ " } ")
             ^ "enter " ^ target));
          List.iter
            (fun s ->
              line 2 ("state " ^ s.state_name ^ " {");
              if s.entry <> [] then
                line 3 ("entry do { " ^ String.concat ", " s.entry ^ " }");
              if s.exit_ <> [] then
                line 3 ("exit do { " ^ String.concat ", " s.exit_ ^ " }");
              List.iter
                (fun t ->
                  line 3
                    ("on " ^ t.on_signal
                    ^ (match t.guard with Some g -> " if " ^ g | None -> "")
                    ^ (if t.do_actions = [] then ""
                       else " do { " ^ String.concat ", " t.do_actions ^ " }")
                    ^ " enter "
                    ^ match t.target with To_state s -> s | To_choice c -> c))
                s.transitions;
              line 2 "}")
            m.states;
          List.iter
            (fun (c : choice) ->
              let arc (actions, target) =
                (if actions = [] then "" else "do { " ^ String.concat ", " actions ^ " } ")
                ^ "enter "
                ^ match target with To_state s -> s | To_choice x -> x
              in
              line 2
                ("choice " ^ c.choice_name ^ " { if " ^ c.choice_guard ^ " "
               ^ arc c.if_true ^ " else " ^ arc c.if_false ^ " }"))
            m.choices;
          line 1 "}")
    model.machines;
  List.iter
    (fun c ->
      let kind =
        match c.kind with Passive -> "passive" | Queued -> "queued" | Active -> "active"
      in
      line 1 (kind ^ " component " ^ c.comp_name ^ " {");
      List.iter
        (fun p ->
          match p with
          | General g ->
              let dir =
                match g.direction with
                | Sync_input -> "sync input"
                | Guarded_input -> "guarded input"
                | Async_input { priority; queue_full } ->
                    "async input"
                    ^ (match priority with
                      | Some p -> Printf.sprintf " priority %d" p
                      | None -> "")
                    ^ " " ^ queue_full_name queue_full
                | Output -> "output"
              in
              line 2
                (Printf.sprintf "%s port %s: [%d] %s" dir g.name g.count g.port)
          | Special s -> line 2 (special_fpp s))
        c.ports;
      List.iter
        (fun (m : internal_port) ->
          line 2
            (Printf.sprintf "internal port %s(%s) %s" m.internal_name
               (params_text m.internal_params)
               (queue_full_name m.internal_queue_full)))
        c.internal_ports;
      List.iter
        (fun cmd ->
          let kind =
            match cmd.cmd_kind with
            | Sync_cmd -> "sync"
            | Guarded_cmd -> "guarded"
            | Async_cmd _ -> "async"
          in
          let suffix =
            match cmd.cmd_kind with
            | Async_cmd { priority; queue_full } ->
                (match priority with
                | Some p -> Printf.sprintf " priority %d" p
                | None -> "")
                ^ " " ^ queue_full_name queue_full
            | Sync_cmd | Guarded_cmd -> ""
          in
          line 2
            (Printf.sprintf "%s command %s%s opcode 0x%X%s" kind cmd.cmd_name
               (if cmd.cmd_params = [] then ""
                else "(" ^ params_text cmd.cmd_params ^ ")")
               cmd.opcode suffix))
        c.commands;
      List.iter
        (fun e ->
          line 2
            (Printf.sprintf "event %s severity %s id 0x%X format \"%s\"%s" e.event_name
               (severity_fpp e.severity) e.event_id e.format
               (match e.throttle with
               | Some t -> Printf.sprintf " throttle %d" t
               | None -> "")))
        c.events;
      List.iter
        (fun ch ->
          line 2
            (Printf.sprintf "telemetry %s: %s id 0x%X update %s%s" ch.chan_name
               (ty_name ch.chan_type) ch.chan_id
               (match ch.update with Always -> "always" | On_change -> "on change")
               (match ch.chan_format with
               | Some f -> " format \"" ^ f ^ "\""
               | None -> "")))
        c.channels;
      List.iter
        (fun p ->
          line 2
            (Printf.sprintf "param %s: %s%s id 0x%X set opcode 0x%X save opcode 0x%X"
               p.param_name (ty_name p.param_type)
               (match p.default with Some d -> " default " ^ d | None -> "")
               p.param_id p.set_opcode p.save_opcode))
        c.parameters;
      List.iter
        (fun r ->
          line 2
            (Printf.sprintf "product record %s: %s%s id 0x%X" r.record_name
               (ty_name r.record_type)
               (if r.record_is_array then " array" else "")
               r.record_id))
        c.records;
      List.iter
        (fun k ->
          line 2
            (Printf.sprintf "product container %s id 0x%X%s" k.container_name
               k.container_id
               (match k.default_priority with
               | Some p -> Printf.sprintf " default priority %d" p
               | None -> "")))
        c.containers;
      List.iter
        (fun (inst, machine) -> line 2 ("state machine instance " ^ inst ^ ": " ^ machine))
        c.machines;
      List.iter (fun (p, q) -> line 2 ("match " ^ p ^ " with " ^ q)) c.matched;
      line 1 "}")
    model.components;
  List.iter
    (fun i ->
      line 1
        (Printf.sprintf "instance %s: %s base id 0x%X%s%s%s%s" i.inst_name
           i.of_component i.base_id
           (match i.queue_size with
           | Some q -> Printf.sprintf " queue size %d" q
           | None -> "")
           (match i.stack_size with
           | Some s -> Printf.sprintf " stack size %d" s
           | None -> "")
           (match i.inst_priority with
           | Some p -> Printf.sprintf " priority %d" p
           | None -> "")
           (match i.cpu with Some c -> Printf.sprintf " cpu %d" c | None -> "")))
    model.instances;
  List.iter
    (fun t ->
      line 1 ("topology " ^ t.topo_name ^ " {");
      List.iter (fun m -> line 2 ("instance " ^ m)) t.members;
      List.iter
        (fun g ->
          match g with
          | Direct { graph_name; connections } ->
              line 2 ("connections " ^ graph_name ^ " {");
              List.iter
                (fun c ->
                  let ep e =
                    e.ep_instance ^ "." ^ e.ep_port
                    ^ match e.ep_index with
                      | Some k -> Printf.sprintf "[%d]" k
                      | None -> ""
                  in
                  line 3 (ep c.from_ ^ " -> " ^ ep c.to_))
                connections;
              line 2 "}"
          | Pattern { pattern; source; targets } ->
              let name =
                match pattern with
                | P_command -> "command" | P_event -> "event"
                | P_telemetry -> "telemetry" | P_text_event -> "text event"
                | P_time -> "time" | P_health -> "health" | P_param -> "param"
              in
              line 2
                (name ^ " connections instance " ^ source ^ " { "
               ^ String.concat ", " targets ^ " }"))
        t.graphs;
      line 1 "}")
    model.topologies;
  line 0 "}";
  Buffer.contents buffer

(* ---------------------------------------------------------- dictionary *)

let type_descriptor = function
  | Prim (U8 | U16 | U32 | U64 | I8 | I16 | I32 | I64) as t ->
      let name = ty_name t in
      let size = int_of_string (String.sub name 1 (String.length name - 1)) in
      `Assoc
        [ ("kind", `String "integer"); ("name", `String name); ("size", `Int size);
          ("signed", `Bool (name.[0] = 'I')) ]
  | Prim (F32 | F64) as t ->
      let name = ty_name t in
      `Assoc
        [ ("kind", `String "float"); ("name", `String name);
          ("size", `Int (int_of_string (String.sub name 1 2))) ]
  | Prim Bool ->
      `Assoc [ ("kind", `String "bool"); ("name", `String "bool"); ("size", `Int 8) ]
  | Prim (String size) ->
      `Assoc
        [ ("kind", `String "string"); ("name", `String "string");
          ("size", `Int (match size with Some n -> n | None -> 80)) ]
  | Named n -> `Assoc [ ("kind", `String "qualifiedIdentifier"); ("name", `String n) ]

let formal_params params =
  `List
    (List.map
       (fun (name, t) ->
         `Assoc [ ("name", `String name); ("type", type_descriptor t); ("ref", `Bool false) ])
       params)

let severity_dict = function
  | Activity_hi -> "ACTIVITY_HI"
  | Activity_lo -> "ACTIVITY_LO"
  | Command_sev -> "COMMAND"
  | Diagnostic -> "DIAGNOSTIC"
  | Fatal -> "FATAL"
  | Warning_hi -> "WARNING_HI"
  | Warning_lo -> "WARNING_LO"

let threshold_json t =
  `Assoc
    (List.filter_map
       (fun (k, v) -> match v with Some f -> Some (k, `Float f) | None -> None)
       [ ("yellow", t.yellow); ("orange", t.orange); ("red", t.red) ])

let to_dictionary ?(framework_version = "hermes-harness") ?(project_version = "0.0.0")
    model ~topology =
  match List.find_opt (fun t -> t.topo_name = topology) model.topologies with
  | None -> Error ("unknown topology " ^ topology)
  | Some topo -> (
      match validate model with
      | _ :: _ as diagnostics ->
          Error
            (Printf.sprintf "model invalid: %d diagnostics (fail-closed)"
               (List.length diagnostics))
      | [] ->
          let members =
            List.filter_map
              (fun name ->
                match find_instance model name with
                | None -> None
                | Some i -> (
                    match find_component model i.of_component with
                    | None -> None
                    | Some c -> Some (i, c)))
              topo.members
          in
          let qualified i name = i.inst_name ^ "." ^ name in
          let commands =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun cmd ->
                    let base =
                      [ ("name", `String (qualified i cmd.cmd_name));
                        ("commandKind",
                         `String
                           (match cmd.cmd_kind with
                           | Sync_cmd -> "sync"
                           | Guarded_cmd -> "guarded"
                           | Async_cmd _ -> "async"));
                        ("opcode", `Int (i.base_id + cmd.opcode));
                        ("formalParams", formal_params cmd.cmd_params) ]
                    in
                    let async =
                      match cmd.cmd_kind with
                      | Async_cmd { priority; queue_full } ->
                          (match priority with
                          | Some p -> [ ("priority", `Int p) ]
                          | None -> [])
                          @ [ ("queueFullBehavior", `String (queue_full_name queue_full)) ]
                      | _ -> []
                    in
                    `Assoc (base @ async))
                  c.commands
                @ List.concat_map
                    (fun p ->
                      [ `Assoc
                          [ ("name", `String (qualified i (p.param_name ^ "_PRM_SET")));
                            ("commandKind", `String "set");
                            ("opcode", `Int (i.base_id + p.set_opcode));
                            ("formalParams", formal_params [ ("val", p.param_type) ]) ];
                        `Assoc
                          [ ("name", `String (qualified i (p.param_name ^ "_PRM_SAVE")));
                            ("commandKind", `String "save");
                            ("opcode", `Int (i.base_id + p.save_opcode));
                            ("formalParams", formal_params []) ] ])
                    c.parameters)
              members
          in
          let events =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun e ->
                    `Assoc
                      ([ ("name", `String (qualified i e.event_name));
                         ("severity", `String (severity_dict e.severity));
                         ("formalParams", formal_params []);
                         ("id", `Int (i.base_id + e.event_id));
                         ("format", `String e.format) ]
                      @ match e.throttle with
                        | Some t -> [ ("throttle", `Int t) ]
                        | None -> []))
                  c.events)
              members
          in
          let channels =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun ch ->
                    let limit =
                      match (ch.low, ch.high) with
                      | None, None -> []
                      | low, high ->
                          [ ("limit",
                             `Assoc
                               ((match low with
                                | Some t -> [ ("low", threshold_json t) ]
                                | None -> [])
                               @ match high with
                                 | Some t -> [ ("high", threshold_json t) ]
                                 | None -> [])) ]
                    in
                    `Assoc
                      ([ ("name", `String (qualified i ch.chan_name));
                         ("type", type_descriptor ch.chan_type);
                         ("id", `Int (i.base_id + ch.chan_id));
                         ("telemetryUpdate",
                          `String
                            (match ch.update with Always -> "always" | On_change -> "on change"))
                       ]
                      @ (match ch.chan_format with
                        | Some f -> [ ("format", `String f) ]
                        | None -> [])
                      @ limit))
                  c.channels)
              members
          in
          let parameters =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun p ->
                    `Assoc
                      ([ ("name", `String (qualified i p.param_name));
                         ("type", type_descriptor p.param_type);
                         ("id", `Int (i.base_id + p.param_id)) ]
                      @ match p.default with
                        | Some d -> [ ("default", `String d) ]
                        | None -> []))
                  c.parameters)
              members
          in
          let records =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun r ->
                    `Assoc
                      [ ("name", `String (qualified i r.record_name));
                        ("type", type_descriptor r.record_type);
                        ("array", `Bool r.record_is_array);
                        ("id", `Int (i.base_id + r.record_id)) ])
                  c.records)
              members
          in
          let containers =
            List.concat_map
              (fun (i, c) ->
                List.map
                  (fun k ->
                    `Assoc
                      ([ ("name", `String (qualified i k.container_name));
                         ("id", `Int (i.base_id + k.container_id)) ]
                      @ match k.default_priority with
                        | Some p -> [ ("defaultPriority", `Int p) ]
                        | None -> []))
                  c.containers)
              members
          in
          let type_definitions =
            List.map
              (fun d ->
                match d with
                | Abstract { name } ->
                    `Assoc
                      [ ("kind", `String "alias");
                        ("qualifiedName", `String (model.model_name ^ "." ^ name));
                        ("type", type_descriptor (Prim (String None)));
                        ("annotation", `String "abstract type (opaque)") ]
                | Alias { name; target } ->
                    `Assoc
                      [ ("kind", `String "alias");
                        ("qualifiedName", `String (model.model_name ^ "." ^ name));
                        ("type", type_descriptor target);
                        ("underlyingType", type_descriptor target) ]
                | Array_t { name; size; element; _ } ->
                    `Assoc
                      [ ("kind", `String "array");
                        ("qualifiedName", `String (model.model_name ^ "." ^ name));
                        ("size", `Int size);
                        ("elementType", type_descriptor element) ]
                | Enum_t { name; repr; constants } ->
                    `Assoc
                      [ ("kind", `String "enum");
                        ("qualifiedName", `String (model.model_name ^ "." ^ name));
                        ("representationType", type_descriptor (Prim repr));
                        ("enumeratedConstants",
                         `List
                           (List.map
                              (fun (n, v) ->
                                `Assoc [ ("name", `String n); ("value", `Int v) ])
                              constants)) ]
                | Struct_t { name; members } ->
                    `Assoc
                      [ ("kind", `String "struct");
                        ("qualifiedName", `String (model.model_name ^ "." ^ name));
                        ("members",
                         `Assoc
                           (List.mapi
                              (fun index (n, t) ->
                                (n,
                                 `Assoc
                                   [ ("type", type_descriptor t); ("index", `Int index) ]))
                              members)) ])
              model.type_defs
          in
          let constants =
            List.map
              (fun (name, value) ->
                `Assoc
                  [ ("qualifiedName", `String (model.model_name ^ "." ^ name));
                    ("type", type_descriptor (Prim I64));
                    ("value", `Int value) ])
              model.constants
          in
          Ok
            (`Assoc
              [ ("metadata",
                 `Assoc
                   [ ("deploymentName", `String topo.topo_name);
                     ("frameworkVersion", `String framework_version);
                     ("projectVersion", `String project_version);
                     ("libraryVersions", `List []);
                     ("dictionarySpecVersion", `String "1.0.0") ]);
                ("typeDefinitions", `List type_definitions);
                ("constants", `List constants);
                ("commands", `List commands);
                ("events", `List events);
                ("telemetryChannels", `List channels);
                ("parameters", `List parameters);
                ("records", `List records);
                ("containers", `List containers);
                (* Packet sets are carried per the spec but not yet modeled;
                   an empty list is the honest value, not a placeholder. *)
                ("telemetryPacketSets", `List []) ]))
