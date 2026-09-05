(** Hermes feature-work projection backed by the existing OCaml Sa-plan store. *)

type materialization = {
  plan_id : string;
  task_ids : string list;
  capability_task_ids : string list;
}

let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.)

let with_store ~path f =
  match Sa_plan.Store.open_db path with
  | Error _ as error -> error
  | Ok store ->
      Fun.protect ~finally:(fun () -> Sa_plan.Store.close store) (fun () -> f store)

let task_id feature_id = "feature/" ^ feature_id
let plan_id snapshot_digest = "hermes/" ^ snapshot_digest
let plan_name snapshot_digest = "hermes/" ^ snapshot_digest

let ensure_plan store ~id ~name ~now_ns =
  match Sa_plan.Store.find_plan store ~id_or_name:id with
  | Error _ as error -> error
  | Ok (Some _) -> Ok ()
  | Ok None -> Sa_plan.Store.create_plan store ~id ~name
                 ~title:"Hermes parity feature plan" ~now_ns

let ensure_task store ~plan_id ~feature_id ~now_ns =
  let id = task_id feature_id in
  match Sa_plan.Store.find_task store ~plan_id ~id_or_name:id with
  | Error _ as error -> error
  | Ok (Some _) -> Ok id
  | Ok None ->
      (match Sa_plan.Store.create_task store ~plan_id ~id ~name:("feature/" ^ feature_id)
               ~title:("Hermes feature: " ^ feature_id) ~parent_id:None
               ~dependencies:[] ~priority:1 ~now_ns with
      | Error _ as error -> error
      | Ok () -> Ok id)

let capability_task_id key = "capability/" ^ key

(* A capability key is "<family>.<slice>"; the family names the parent task. *)
let family_of_key key =
  match String.index_opt key '.' with
  | None -> key
  | Some index -> String.sub key 0 index

let ensure_capability_task store ~plan_id ~key ~dependencies ~now_ns =
  let id = capability_task_id key in
  match Sa_plan.Store.find_task store ~plan_id ~id_or_name:id with
  | Error _ as error -> error
  | Ok (Some _) -> Ok id
  | Ok None ->
      (match
         Sa_plan.Store.create_task store ~plan_id ~id ~name:id
           ~title:("Hermes capability: " ^ key)
           ~parent_id:(Some (task_id (family_of_key key)))
           ~dependencies:(List.map capability_task_id dependencies) ~priority:2 ~now_ns
       with
      | Error _ as error -> error
      | Ok () -> Ok id)

(* Capabilities must arrive in topological order: each task's dependencies have
   to already exist as tasks before it can reference them. *)
let materialize ~path ~snapshot_digest ~features ~capabilities =
  let id = plan_id snapshot_digest in
  with_store ~path (fun store ->
      match ensure_plan store ~id ~name:(plan_name snapshot_digest) ~now_ns:(now_ns ()) with
      | Error _ as error -> error
      | Ok () ->
          let result =
            List.fold_left
              (fun state feature_id ->
                match state with
                | Error _ -> state
                | Ok task_ids ->
                    match ensure_task store ~plan_id:id ~feature_id ~now_ns:(now_ns ()) with
                    | Error _ as error -> error
                    | Ok task_id -> Ok (task_ids @ [ task_id ]))
              (Ok []) features
          in
          match result with
          | Error _ as error -> error
          | Ok task_ids ->
              let capability_result =
                List.fold_left
                  (fun state (key, dependencies) ->
                    match state with
                    | Error _ -> state
                    | Ok ids ->
                        match
                          ensure_capability_task store ~plan_id:id ~key ~dependencies
                            ~now_ns:(now_ns ())
                        with
                        | Error _ as error -> error
                        | Ok task_id -> Ok (ids @ [ task_id ]))
                  (Ok []) capabilities
              in
              match capability_result with
              | Error _ as error -> error
              | Ok capability_task_ids -> Ok { plan_id = id; task_ids; capability_task_ids })

let summary ~path ~plan_id =
  with_store ~path (fun store ->
      match Sa_plan.Store.summary store ~plan_id with
      | Error _ as error -> error
      | Ok summary -> Ok (summary.total, summary.ready, summary.executing, summary.completed))
