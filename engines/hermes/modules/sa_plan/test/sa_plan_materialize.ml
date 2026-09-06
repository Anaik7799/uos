module Store = Sa_plan.Store

type selection = { plan_id : string; plan_name : string; plan_title : string; task_id : string; task_title : string; name : string; mapping : Store.bridge_mapping_request }
type receipt = { mapping : Store.bridge_mapping; task : Store.task_view }

let materialize store selection =
  Result.bind
    (Store.find_plan store ~id_or_name:selection.plan_id)
    (fun plan ->
      let ensure_plan = match plan with Some _ -> Ok () | None -> Store.create_plan store ~id:selection.plan_id ~name:selection.plan_name ~title:selection.plan_title ~now_ns:selection.mapping.created_at_ns in
      Result.bind ensure_plan (fun () ->
      Result.bind (Store.find_task store ~plan_id:selection.plan_id ~id_or_name:selection.task_id)
        (fun task ->
        let ensure_task = match task with Some _ -> Ok () | None ->
      Result.bind
        (Store.create_task store ~plan_id:selection.plan_id ~id:selection.task_id
           ~name:selection.name ~title:selection.task_title ~parent_id:None
           ~dependencies:[] ~priority:0 ~now_ns:selection.mapping.created_at_ns)
        (fun () -> Ok ()) in
        Result.bind ensure_task (fun () ->
          Result.bind (Store.ensure_bridge_mapping store selection.mapping) (fun mapping ->
            Result.bind
              (Store.find_task store ~plan_id:selection.plan_id ~id_or_name:selection.task_id)
              (function Some task -> Ok { mapping; task } | None -> Error "materialized task missing"))))))
