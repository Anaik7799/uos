(* The normative FPP window registry. See the .mli: raw facts only, no
   host verdict, and a leaf so both the projections and the formal
   relation can reach it without closing a dependency cycle. *)

type owner = Harness | Wiki | Ops_monitor | Completion | Operations

let owners = [ Harness; Wiki; Ops_monitor; Completion; Operations ]

let owner_name = function
  | Harness -> "Harness"
  | Wiki -> "Wiki"
  | Ops_monitor -> "Ops_monitor"
  | Completion -> "Completion"
  | Operations -> "Operations"

let declared_model_name = function
  | Harness -> "Hermes"
  | Wiki -> "HermesWikiZk"
  | Ops_monitor -> "HermesOps"
  | Completion -> "HermesCompletion"
  | Operations -> "HermesOperations"

type allocation = {
  alloc_owner : owner;
  instance_id : string;
  component_id : string;
  base_id : int;
}

(* Moved here verbatim from the five projections, which is why each value
   is stated once. The order is owner order then declaration order; the
   digest depends on it. *)
let allocations =
  [ { alloc_owner = Harness; instance_id = "harness_config";
      component_id = "harness_config"; base_id = 0x700 };
    { alloc_owner = Wiki; instance_id = "auditLoop";
      component_id = "auditLoop"; base_id = 0x1800 };
    { alloc_owner = Ops_monitor; instance_id = "opsVerifier";
      component_id = "opsVerifier"; base_id = 0x2000 };
    { alloc_owner = Completion; instance_id = "commandGateway";
      component_id = "commandGateway"; base_id = 0x3000 };
    { alloc_owner = Completion; instance_id = "completionHistory";
      component_id = "completionHistory"; base_id = 0x3200 };
    { alloc_owner = Completion; instance_id = "mbseProjector";
      component_id = "mbseProjector"; base_id = 0x3400 };
    { alloc_owner = Completion; instance_id = "formalOracle";
      component_id = "formalOracle"; base_id = 0x3600 } ]

let allocations_of o = List.filter (fun (a : allocation) -> a.alloc_owner = o) allocations

(* Operations allocates its instances sequentially from one window base
   rather than declaring each, so its window is stated here and its
   per-instance rows derive from the model it supplies. *)
let window_base = function
  | Harness -> 0x700
  | Wiki -> 0x1800
  | Ops_monitor -> 0x2000
  | Completion -> 0x3000
  | Operations -> 0x4000

let base_of_instance owner instance_id =
  match
    List.find_opt
      (fun (a : allocation) ->
        a.alloc_owner = owner && a.instance_id = instance_id)
      allocations
  with
  | Some a -> a.base_id
  | None ->
      invalid_arg
        (Printf.sprintf
           "Fpp_window_authority: %s declares no allocation for instance %S"
           (owner_name owner) instance_id)

type row = {
  owner : owner;
  sequential : bool;
  declared_model_name : string;
  observed_model_name : string;
  instance_id : string;
  observed_instance_id : string;
  component_id : string;
  observed_component_id : string;
  allocation_present : bool;
  declared_base_id : int;
  observed_base_id : int;
  component_present : bool;
  span : int;
}

let rows owner (model : Fpp_model.model) =
  let observed_model_name = model.Fpp_model.model_name in
  let find_instance name =
    List.find_opt
      (fun (i : Fpp_model.instance) -> i.Fpp_model.inst_name = name)
      model.Fpp_model.instances
  in
  let find_component name =
    List.find_opt
      (fun (c : Fpp_model.component) -> c.Fpp_model.comp_name = name)
      model.Fpp_model.components
  in
  let row_of_observation ~sequential ~declared_instance_id
      ~declared_component_id ~declared_base_id instance =
    let observed_instance_id, observed_component_id, observed_base_id =
      match instance with
      | None -> ("", "", -1)
      | Some (item : Fpp_model.instance) ->
          (item.inst_name, item.of_component, item.base_id)
    in
    let component =
      match instance with
      | None -> find_component declared_component_id
      | Some item -> find_component item.of_component
    in
    { owner; sequential;
      declared_model_name = declared_model_name owner;
      observed_model_name;
      instance_id = declared_instance_id;
      observed_instance_id;
      component_id = declared_component_id;
      observed_component_id;
      allocation_present = instance <> None;
      declared_base_id;
      observed_base_id;
      component_present = component <> None;
      span =
        (match component with
         | Some value -> Fpp_model.id_span value
         | None -> 0) }
  in
  let declared = allocations_of owner in
  (* Declared allocations first, in registry order. An absent instance
     stays as a row with allocation_present = false: dropping it would
     remove the very fact the formula needs in order to refute it. *)
  let declared_rows =
    List.map
      (fun (a : allocation) ->
        row_of_observation ~sequential:false
          ~declared_instance_id:a.instance_id
          ~declared_component_id:a.component_id ~declared_base_id:a.base_id
          (find_instance a.instance_id))
      declared
  in
  let sequential_rows =
    List.mapi
      (fun index (instance : Fpp_model.instance) ->
        row_of_observation ~sequential:true
          ~declared_instance_id:instance.inst_name
          ~declared_component_id:instance.of_component
          ~declared_base_id:(if index = 0 then window_base owner else -1)
          (Some instance))
      model.Fpp_model.instances
  in
  match owner with Operations -> sequential_rows | _ -> declared_rows

let unregistered_actual_rows owner (model : Fpp_model.model) =
  match owner with
  | Operations -> []
  | Harness | Wiki | Ops_monitor | Completion ->
      let known =
        allocations_of owner
        |> List.map (fun (allocation : allocation) -> allocation.instance_id)
      in
      List.filter_map
        (fun (instance : Fpp_model.instance) ->
          if List.mem instance.inst_name known then None
          else
            let component =
              List.find_opt
                (fun (item : Fpp_model.component) ->
                  item.comp_name = instance.of_component)
                model.components
            in
            Some
              { owner; sequential = false;
                declared_model_name = declared_model_name owner;
                observed_model_name = model.model_name;
                instance_id = instance.inst_name;
                observed_instance_id = instance.inst_name;
                component_id = instance.of_component;
                observed_component_id = instance.of_component;
                allocation_present = false;
                declared_base_id = -1;
                observed_base_id = instance.base_id;
                component_present = component <> None;
                span =
                  (match component with
                   | Some value -> Fpp_model.id_span value
                   | None -> 0) })
        model.instances

let allocation_digest () =
  let buffer = Buffer.create 512 in
  (* Length framing: without it ("ab","c") and ("a","bc") would digest
     alike and a renamed instance could hide behind its neighbour. *)
  let field s =
    Buffer.add_string buffer (string_of_int (String.length s));
    Buffer.add_char buffer ':';
    Buffer.add_string buffer s;
    Buffer.add_char buffer '|'
  in
  List.iter
    (fun (a : allocation) ->
      field (owner_name a.alloc_owner);
      field (declared_model_name a.alloc_owner);
      field a.instance_id;
      field a.component_id;
      field (string_of_int a.base_id))
    allocations;
  List.iter
    (fun o ->
      field (owner_name o);
      field (match o with Operations -> "sequential" | _ -> "fixed");
      field (string_of_int (window_base o)))
    owners;
  Digestif.SHA256.to_hex (Digestif.SHA256.digest_string (Buffer.contents buffer))
