type approval_id =
  | Authoring_authority
  | Baseline_policy
  | Semantic_authority
  | Phase_scope
  | Acquisition_policy
  | Mechanism_reuse
  | Completion_policy

type approval_state =
  | Pending
  | Approved of { rationale : string; approved_by : string; approved_at : string }
  | Rejected of { rationale : string; rejected_by : string; rejected_at : string }

type task = {
  id : string;
  parent_id : string option;
  title : string;
  dependencies : string list;
}

let approvals = [
  (Authoring_authority, Pending);
  (Baseline_policy, Pending);
  (Semantic_authority, Pending);
  (Phase_scope, Pending);
  (Acquisition_policy, Pending);
  (Mechanism_reuse, Pending);
  (Completion_policy, Pending);
]

let tasks = [
  { id = "SE.P0"; parent_id = None; title = "Phase 0"; dependencies = [] };
  { id = "SE.P0.1"; parent_id = Some "SE.P0"; title = "Review gate"; dependencies = ["SE.P0.1.1"; "SE.P0.1.2"; "SE.P0.1.3"; "SE.P0.1.4"; "SE.P0.1.5"; "SE.P0.1.6"; "SE.P0.1.7"] };
  { id = "SE.P0.1.1"; parent_id = Some "SE.P0.1"; title = "Authoring authority"; dependencies = [] };
  { id = "SE.P0.1.2"; parent_id = Some "SE.P0.1"; title = "Baseline policy"; dependencies = [] };
  { id = "SE.P0.1.3"; parent_id = Some "SE.P0.1"; title = "Semantic authority"; dependencies = [] };
  { id = "SE.P0.1.4"; parent_id = Some "SE.P0.1"; title = "Phase scope"; dependencies = [] };
  { id = "SE.P0.1.5"; parent_id = Some "SE.P0.1"; title = "Acquisition policy"; dependencies = [] };
  { id = "SE.P0.1.6"; parent_id = Some "SE.P0.1"; title = "Mechanism reuse"; dependencies = [] };
  { id = "SE.P0.1.7"; parent_id = Some "SE.P0.1"; title = "Completion policy"; dependencies = [] };
  { id = "SE.P0.2"; parent_id = Some "SE.P0"; title = "Production admission"; dependencies = ["SE.P0.1"] };
  { id = "SE.P0.3"; parent_id = Some "SE.P0"; title = "Toolchain authority"; dependencies = ["SE.P0.2"] };
  { id = "SE.P0.4"; parent_id = Some "SE.P0"; title = "Resource/license/network policy"; dependencies = ["SE.P0.2"] };
  { id = "SE.P0.5"; parent_id = Some "SE.P0"; title = "Registry and dry run"; dependencies = ["SE.P0.2"; "SE.P0.3"; "SE.P0.4"] };
  { id = "SE.P0.6"; parent_id = Some "SE.P0"; title = "Candidate full gate"; dependencies = ["SE.P0.5"] };
  { id = "SE.P0.7"; parent_id = Some "SE.P0"; title = "Journal/source closeout"; dependencies = ["SE.P0.6"] };
  { id = "SE.P0.8"; parent_id = Some "SE.P0"; title = "Final exact-head runtime receipt"; dependencies = ["SE.P0.7"] };
  { id = "SE.P0.9"; parent_id = Some "SE.P0"; title = "Authorized Sa-plan application"; dependencies = ["SE.P0.8"] };
]

let ready_to_apply () =
  List.for_all (fun (_, state) -> match state with Approved _ -> true | _ -> false) approvals

let validate () =
  let errors = ref [] in
  if List.length tasks <> 17 then
    errors := "Expected exactly 17 task nodes" :: !errors;
  
  let ids = Hashtbl.create 17 in
  List.iter (fun t -> Hashtbl.add ids t.id t) tasks;
  
  List.iter (fun t ->
    Option.iter (fun p -> if not (Hashtbl.mem ids p) then errors := ("Missing parent: " ^ p) :: !errors) t.parent_id;
    List.iter (fun d -> if not (Hashtbl.mem ids d) then errors := ("Missing dependency: " ^ d) :: !errors) t.dependencies
  ) tasks;

  let rec check_cycle visited path id =
    if List.mem id path then true
    else if List.mem id visited then false
    else
      let t = Hashtbl.find ids id in
      List.exists (check_cycle (id :: visited) (id :: path)) t.dependencies
  in
  List.iter (fun t -> if check_cycle [] [] t.id then errors := ("Cycle detected at " ^ t.id) :: !errors) tasks;
  
  let p02 = Hashtbl.find_opt ids "SE.P0.2" in
  (match p02 with
   | Some p -> if not (List.mem "SE.P0.1" p.dependencies) then errors := "SE.P0.2 must depend on SE.P0.1" :: !errors
   | None -> ());

  if !errors = [] then Ok () else Error (List.rev !errors)

let to_plan_node (t : task) : Sa_plan.Management.plan_node =
  {
    id = t.id;
    title = t.title;
    task_type = Sa_plan.Management.Story;
    estimate_points = None;
    parent_id = t.parent_id;
    dependencies = t.dependencies;
  }