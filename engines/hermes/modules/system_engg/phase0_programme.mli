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

val approvals : (approval_id * approval_state) list
val tasks : task list
val validate : unit -> (unit, string list) result
val ready_to_apply : unit -> bool
val to_plan_node : task -> Sa_plan.Management.plan_node