type release
type formal
type disposable
type a0
type a1
type b_recovery
type completion_reserve
type completion_record
type completion_record_recovery
type completion_final
type fixture_manifest = Fixture_manifest of Jj_id.Receipt.t
type causal_failure = Causal_failure of Jj_id.Event.t
type sealed_vault = Sealed_vault of Jj_id.Receipt.t
let digest value =
  Digestif.SHA256.(to_hex (digest_string value))
let maximum = 1024
let fixture_manifest value = Fixture_manifest value
let causal_failure value = Causal_failure value
let sealed_vault value = Sealed_vault value
type formal_manifest = {
  formal_tool : Jj_action_kind.formal_tool;
  formal_model : Jj_id.Formal_model.t;
  formal_source : Jj_id.Formal_source.t;
  formal_negative_controls : Jj_id.Negative_control.t list;
  formal_cases : Jj_action_kind.formal_case list;
  formal_digest : string;
}
type fault_case =
  | B_recovery_fault of Jj_recovery_schema.b_success_cut
  | Completion_record_recovery_fault of
      Jj_recovery_schema.completion_record_cut_point
      * Jj_recovery_schema.workspace_branch
      * Jj_recovery_schema.execution_mode
type disposable_profile = Semantics | Surface_equivalence | Fault of fault_case
type recovery_scope_class = Disposable_test | Production_record
type b_recovery_input = {
  causal_failure : causal_failure;
  cut : Jj_recovery_schema.b_success_cut;
  sealed_vault : sealed_vault;
}
type completion_record_recovery_input = {
  causal_failure : causal_failure;
  cut : Jj_recovery_schema.completion_record_cut_point;
  workspace_branch : Jj_recovery_schema.workspace_branch;
  mode : Jj_recovery_schema.execution_mode;
  sealed_vault : sealed_vault;
  scope_class : recovery_scope_class;
}
type error =
  | Empty_manifest
  | Unbounded_manifest
  | Phase_context_mismatch
  | Empty_negative_control_denominator
  | Duplicate_negative_control
  | Unbounded_negative_control_denominator

let formal_manifest_frame ~tool ~model ~source ~cases =
  Jj_id.length_frame
    [ "formal-request-manifest-v1";
      Jj_action_kind.formal_tool_key tool;
      Jj_id.Formal_model.to_string model;
      Jj_id.Formal_source.to_string source;
      Jj_id.length_frame (List.map Jj_action_kind.formal_case_key cases) ]

let formal_manifest ~tool ~model ~source ~negative_controls =
  let control_keys =
    List.map Jj_id.Negative_control.to_string negative_controls
  in
  if negative_controls = [] then Error Empty_negative_control_denominator
  else if List.length negative_controls >= maximum then
    Error Unbounded_negative_control_denominator
  else if List.length control_keys
          <> List.length (List.sort_uniq String.compare control_keys)
  then Error Duplicate_negative_control
  else
    let cases =
      Jj_action_kind.Positive
      :: List.map
           (fun identity -> Jj_action_kind.Negative_control identity)
           negative_controls
    in
    let formal_digest =
      digest (formal_manifest_frame ~tool ~model ~source ~cases)
    in
    Ok
      { formal_tool = tool; formal_model = model; formal_source = source;
        formal_negative_controls = negative_controls; formal_cases = cases;
        formal_digest }

let formal_manifest_tool manifest = manifest.formal_tool
let formal_manifest_model manifest = manifest.formal_model
let formal_manifest_source manifest = manifest.formal_source
let formal_manifest_negative_controls manifest =
  manifest.formal_negative_controls
let formal_manifest_cases manifest = manifest.formal_cases
let formal_manifest_digest manifest = manifest.formal_digest

type _ phase_data =
  | Release : release phase_data
  | Formal : formal_manifest -> formal phase_data
  | Disposable : disposable_profile * fixture_manifest -> disposable phase_data
  | A0 : a0 phase_data
  | A1 : int * int -> a1 phase_data
  | B_recovery : b_recovery_input -> b_recovery phase_data
  | Completion_reserve : completion_reserve phase_data
  | Completion_record : Jj_recovery_schema.workspace_branch -> completion_record phase_data
  | Completion_record_recovery :
      completion_record_recovery_input -> completion_record_recovery phase_data
  | Completion_final : completion_final phase_data
type standalone_phase_kind =
  | Release_phase
  | Formal_phase
  | Disposable_phase
  | A0_phase
  | A1_phase
  | B_recovery_phase
  | Completion_reserve_phase
  | Completion_record_phase
  | Completion_record_recovery_phase
  | Completion_final_phase
let standalone_phase_kinds =
  [ Release_phase; Formal_phase; Disposable_phase; A0_phase; A1_phase;
    B_recovery_phase; Completion_reserve_phase; Completion_record_phase;
    Completion_record_recovery_phase; Completion_final_phase ]
let standalone_phase_kind_id = function
  | Release_phase -> "release"
  | Formal_phase -> "formal"
  | Disposable_phase -> "disposable"
  | A0_phase -> "a0"
  | A1_phase -> "a1"
  | B_recovery_phase -> "b-recovery"
  | Completion_reserve_phase -> "completion-reserve"
  | Completion_record_phase -> "completion-record"
  | Completion_record_recovery_phase -> "completion-record-recovery"
  | Completion_final_phase -> "completion-final"
type 'phase standalone_phase_request = {
  request_id : Jj_id.Request.t;
  data : 'phase phase_data;
}
let release_request ~request_id = { request_id; data = Release }
let a0_request ~request_id = { request_id; data = A0 }
let formal_request ~request_id ~manifest =
  { request_id; data = Formal manifest }
let disposable_request ~request_id ~profile ~fixture =
  { request_id; data = Disposable (profile, fixture) }
let a1_request ~request_id ~selected_objects ~classified_objects =
  if selected_objects < 0 || classified_objects < 0 || selected_objects + classified_objects > maximum
  then Error Unbounded_manifest else Ok { request_id; data = A1 (selected_objects, classified_objects) }
let completion_reserve_request ~request_id =
  { request_id; data = Completion_reserve }
let completion_record_request ~request_id ~workspace_branch =
  { request_id; data = Completion_record workspace_branch }
let b_recovery_request ~request_id ~causal_failure ~cut ~sealed_vault =
  { request_id;
    data = B_recovery { causal_failure; cut; sealed_vault } }
let completion_record_recovery_request ~request_id ~causal_failure ~cut
    ~workspace_branch ~mode ~sealed_vault ~scope_class =
  { request_id;
    data =
      Completion_record_recovery
        { causal_failure; cut; workspace_branch; mode; sealed_vault;
          scope_class } }
let completion_final_request ~request_id =
  { request_id; data = Completion_final }
let standalone_phase_kind : type phase.
    phase standalone_phase_request -> standalone_phase_kind =
  fun request ->
    match request.data with
    | Release -> Release_phase
    | Formal _ -> Formal_phase
    | Disposable _ -> Disposable_phase
    | A0 -> A0_phase
    | A1 _ -> A1_phase
    | B_recovery _ -> B_recovery_phase
    | Completion_reserve -> Completion_reserve_phase
    | Completion_record _ -> Completion_record_phase
    | Completion_record_recovery _ -> Completion_record_recovery_phase
    | Completion_final -> Completion_final_phase
type occurrence = {
  id : string;
  nonce : string;
  phase : string;
  ordinal : int;
  action : Jj_action_kind.t;
}
type occurrence_descriptor = {
  stable_occurrence_id : string;
  stable_nonce_id : string;
  occurrence_phase_id : string;
  occurrence_phase_ordinal : int;
  occurrence_action_identity : Jj_action_kind.t;
}
let occurrence_id x = x.id
let occurrence_nonce x = x.nonce
let occurrence_action x = x.action
let occurrence_phase x = x.phase
let occurrence_ordinal x = x.ordinal
let occurrence_descriptor occurrence =
  { stable_occurrence_id = occurrence.id;
    stable_nonce_id = occurrence.nonce;
    occurrence_phase_id = occurrence.phase;
    occurrence_phase_ordinal = occurrence.ordinal;
    occurrence_action_identity = occurrence.action }
let aux x = Jj_action_kind.Auxiliary x
let op x = Jj_action_kind.Jujutsu_operation x
let candidate x = Jj_action_kind.Candidate_process x
let formal x = Jj_action_kind.Formal_process x
let occurrence_descriptor_frame descriptor =
  Jj_id.length_frame
    [ descriptor.stable_occurrence_id; descriptor.stable_nonce_id;
      descriptor.occurrence_phase_id;
      string_of_int descriptor.occurrence_phase_ordinal;
      Jj_action_kind.action_key descriptor.occurrence_action_identity ]
let occurrence_projection_digest occurrence =
  digest
    (Jj_id.length_frame
       [ "occurrence-descriptor-v1";
         occurrence_descriptor_frame (occurrence_descriptor occurrence) ])
let phase_denominator_frame phase_ids =
  Jj_id.length_frame ("standalone-phase-denominator-v1" :: phase_ids)
let standalone_phase_denominator_digest =
  standalone_phase_kinds
  |> List.map standalone_phase_kind_id
  |> phase_denominator_frame
  |> digest
let occurrences ~request_id ~phase actions =
  List.mapi (fun ordinal action ->
    let framed = Jj_id.length_frame [Jj_id.Request.to_string request_id; phase; string_of_int ordinal; Jj_action_kind.action_key action] in
    { id = "occ-" ^ digest ("occ:" ^ framed);
      nonce = "nonce-" ^ digest ("nonce:" ^ framed);
      phase; ordinal; action }) actions
let repeat n x = List.init n (fun _ -> x)
let a0_actions =
  [ aux Acquire_clock; aux Observe_external_resource; op Operation_head; op Status_at_operation;
    op Resolve_list_at_operation; op Operation_log_at_operation; op Revision_log_at_operation;
    op Bookmark_list_at_operation; op Workspace_list_at_operation; op Remote_list_at_operation;
    op Diff_summary_at_operation; op Diff_stat_at_operation; op Diff_patch_at_operation;
    aux Observe_repository_source; aux Observe_tree ]

let partial_key prefix =
  string_of_int (Jj_recovery_schema.partial_prefix_completed prefix)
  ^ "/" ^ string_of_int (Jj_recovery_schema.partial_prefix_total prefix)

let phase_b_slot_key = function
  | Jj_recovery_schema.B_acquire_writer_lease -> "acquire-writer-lease"
  | B_stage_recovery_set -> "stage-recovery-set"
  | B_bookmark_set -> "bookmark-set"
  | B_bookmark_readback -> "bookmark-readback"
  | B_duplicate -> "duplicate"
  | B_duplicate_readback -> "duplicate-readback"
  | B_observe_repository_source_before_partition -> "source-before-partition"
  | B_observe_tree_before_partition -> "tree-before-partition"
  | B_write_partition_partial prefix ->
      "write-partition-partial:" ^ partial_key prefix
  | B_write_partition -> "write-partition"
  | B_observe_tree_after_write -> "tree-after-write"
  | B_working_copy_snapshot_1 -> "snapshot-1"
  | B_snapshot_1_readback -> "snapshot-1-readback"
  | B_new_change -> "new-change"
  | B_new_change_readback -> "new-change-readback"
  | B_restore_partition_partial prefix ->
      "restore-partition-partial:" ^ partial_key prefix
  | B_restore_partition -> "restore-partition"
  | B_observe_tree_after_restore -> "tree-after-restore"
  | B_working_copy_snapshot_2 -> "snapshot-2"
  | B_snapshot_2_readback -> "snapshot-2-readback"
  | B_observe_tree_final -> "tree-final"
  | B_observe_repository_source_final -> "source-final"
  | B_set_activity_frontier -> "set-frontier"
  | B_cleanup_recovery_set -> "cleanup-recovery-set"
  | B_release_writer_lease -> "release-writer-lease"

let phase_b_cut_key = function
  | Jj_recovery_schema.Before_engine -> "before-engine"
  | After_consume slot -> "after-consume:" ^ phase_b_slot_key slot
  | After_action slot -> "after-action:" ^ phase_b_slot_key slot

let phase_completion_slot_key = function
  | Jj_recovery_schema.Record_acquire_writer_lease -> "acquire-writer-lease"
  | Record_stage_recovery_set -> "stage-recovery-set"
  | Record_workspace_add -> "workspace-add"
  | Record_workspace_readback -> "workspace-readback"
  | Record_workspace_observe_tree -> "workspace-tree"
  | Record_workspace_observe_repository_source -> "workspace-source"
  | Record_new_change -> "new-change"
  | Record_new_change_readback -> "new-change-readback"
  | Record_write_candidate_partial prefix ->
      "write-candidate-partial:" ^ partial_key prefix
  | Record_write_sealed_record_candidate -> "write-candidate"
  | Record_write_observe_tree -> "write-tree"
  | Record_working_copy_snapshot -> "snapshot"
  | Record_snapshot_readback -> "snapshot-readback"
  | Record_snapshot_observe_tree -> "snapshot-tree"
  | Record_describe -> "describe"
  | Record_describe_readback -> "describe-readback"
  | Record_observe_tree_final -> "tree-final"
  | Record_observe_repository_source_final -> "source-final"
  | Record_set_activity_frontier -> "set-frontier"
  | Record_cleanup_recovery_set -> "cleanup-recovery-set"
  | Record_release_writer_lease -> "release-writer-lease"

let phase_completion_cut_key = function
  | Jj_recovery_schema.Completion_before_engine -> "before-engine"
  | Completion_after_consume slot ->
      "after-consume:" ^ phase_completion_slot_key slot
  | Completion_after_action slot ->
      "after-action:" ^ phase_completion_slot_key slot

let execution_mode_key = function
  | Jj_recovery_schema.In_process -> "in-process"
  | Restarted -> "restarted"

let workspace_key = function
  | Jj_recovery_schema.Existing -> "existing"
  | Newly_allocated -> "newly-allocated"

let scope_class_key = function
  | Disposable_test -> "disposable-test"
  | Production_record -> "production-record"

let fault_case_key = function
  | B_recovery_fault cut -> "b:" ^ phase_b_cut_key cut
  | Completion_record_recovery_fault (cut, workspace, mode) ->
      Jj_id.length_frame
        [ "completion-record"; phase_completion_cut_key cut;
          workspace_key workspace; execution_mode_key mode ]

let disposable_profile_key = function
  | Semantics -> "semantics"
  | Surface_equivalence -> "surface-equivalence"
  | Fault fault -> "fault:" ^ fault_case_key fault

let fixture_key (Fixture_manifest value) = Jj_id.Receipt.to_string value
let failure_key (Causal_failure value) = Jj_id.Event.to_string value
let vault_key (Sealed_vault value) = Jj_id.Receipt.to_string value

let recovery_actions request =
  match Jj_recovery_schema.schema request with
  | schema when Jj_recovery_schema.family schema = Jj_recovery_schema.B_family ->
      Jj_recovery_schema.b_branches schema
      |> List.concat_map Jj_recovery_schema.b_steps
      |> List.map Jj_recovery_schema.recovery_step_action
  | schema ->
      Jj_recovery_schema.completion_record_branches schema
      |> List.concat_map Jj_recovery_schema.completion_record_steps
      |> List.map Jj_recovery_schema.recovery_step_action

let standalone_phase_declarations : type phase.
    phase standalone_phase_request -> occurrence list =
  fun request ->
  let phase, actions = match request.data with
    | Release -> "release", [aux Acquire_clock; aux Observe_external_resource; aux Observe_release_bundle; aux Observe_tree]
    | Formal manifest ->
        ("formal:" ^ manifest.formal_digest),
        ([ aux Acquire_clock; aux Observe_external_resource ]
         @ List.map
             (fun case ->
               formal
                 (Jj_action_kind.formal_process
                    ~tool:manifest.formal_tool ~case))
             manifest.formal_cases)
    | Disposable (profile, fixture) ->
        ("disposable:"
         ^ digest
             (Jj_id.length_frame
                [ disposable_profile_key profile; fixture_key fixture ])),
        [ aux Acquire_clock; aux Observe_external_resource;
          aux Materialize_candidate; op Repository_init;
          aux Remove_disposable_scope ]
    | A0 -> "a0", a0_actions
    | A1 (selected, classified) -> "a1",
        repeat selected (op File_show_at_operation) @ repeat classified (aux Observe_object)
        @ [aux Materialize_candidate] @ List.map candidate Jj_action_kind.candidate_steps
        @ [aux Remove_disposable_scope]
    | B_recovery input ->
        ("b-recovery:"
         ^ digest
             (Jj_id.length_frame
                [ failure_key input.causal_failure;
                  phase_b_cut_key input.cut; "restarted";
                  vault_key input.sealed_vault ])),
        recovery_actions
          (Jj_recovery_schema.B_success
             (input.cut, Jj_recovery_schema.Restarted))
    | Completion_reserve -> "completion-reserve",
        [aux Reserve_completion_receipt]
    | Completion_record workspace_branch -> "completion-record",
        [aux Acquire_writer_lease; aux Stage_recovery_set]
        @ (match workspace_branch with
           | Jj_recovery_schema.Existing -> []
           | Newly_allocated ->
               [op Workspace_add; aux Readback_jj_state; aux Observe_tree;
                aux Observe_repository_source])
        @ [op New_change; aux Readback_jj_state;
           aux Write_sealed_record_candidate; aux Observe_tree;
           op Working_copy_snapshot; aux Readback_jj_state; aux Observe_tree;
           op Describe; aux Readback_jj_state; aux Observe_tree;
           aux Observe_repository_source;
           Jj_action_kind.Frontier_action
             (Set_activity_frontier Reconciled_terminal);
           aux Cleanup_recovery_set; aux Release_writer_lease]
    | Completion_record_recovery input ->
        ("completion-record-recovery:"
         ^ digest
             (Jj_id.length_frame
                [ failure_key input.causal_failure;
                  phase_completion_cut_key input.cut;
                  workspace_key input.workspace_branch;
                  execution_mode_key input.mode;
                  vault_key input.sealed_vault;
                  scope_class_key input.scope_class ])),
        recovery_actions
          (Jj_recovery_schema.Completion_record
             (input.cut, input.workspace_branch, input.mode))
    | Completion_final -> "completion-final",
        [aux Acquire_writer_lease; op Bookmark_set; aux Readback_jj_state;
         aux Observe_tree; aux Observe_repository_source;
         Jj_action_kind.Frontier_action
           (Set_activity_frontier Reconciled_terminal);
         aux Release_writer_lease; aux Finalize_completion_receipt]
  in occurrences ~request_id:request.request_id ~phase actions

type approval_consume = {
  consume_id : string;
  parent_occurrence_id : string;
  parent_ordinal : int;
  consume_action : Jj_action_kind.auxiliary_role;
}

let approval_consume_id consume = consume.consume_id
let approval_consume_parent_occurrence_id consume =
  consume.parent_occurrence_id
let approval_consume_parent_ordinal consume = consume.parent_ordinal
let approval_consume_action consume = consume.consume_action

let approval_consume_frame consume =
  Jj_id.length_frame
    [ consume.consume_id; consume.parent_occurrence_id;
      string_of_int consume.parent_ordinal;
      Jj_action_kind.auxiliary_role_key consume.consume_action ]

let approval_consume_for occurrence =
  let consume_action = Jj_action_kind.Consume_approval_nonce in
  let consume_id =
    "consume-"
    ^ digest
        (Jj_id.length_frame
           [ "formal-approval-consume-v1"; occurrence.id;
             string_of_int occurrence.ordinal;
             Jj_action_kind.auxiliary_role_key consume_action;
             Jj_action_kind.action_key occurrence.action ])
  in
  { consume_id; parent_occurrence_id = occurrence.id;
    parent_ordinal = occurrence.ordinal; consume_action }

let standalone_approval_consumptions : type phase.
    phase standalone_phase_request -> approval_consume list =
  fun request ->
    match request.data with
    | Formal _ ->
        standalone_phase_declarations request
        |> List.filter_map (fun occurrence ->
             match occurrence.action with
             | Jj_action_kind.Formal_process _ ->
                 Some (approval_consume_for occurrence)
             | Jujutsu_operation _ | Auxiliary _ | Candidate_process _
             | Frontier_action _ -> None)
    | Release | Disposable _ | A0 | A1 _ | B_recovery _
    | Completion_reserve | Completion_record _
    | Completion_record_recovery _ | Completion_final -> []

let standalone_phase_count = List.length standalone_phase_kinds
let canonical_unsigned_bytes xs =
  xs
  |> List.concat_map (fun x ->
       [ x.id; x.nonce; x.phase; string_of_int x.ordinal;
         Jj_action_kind.action_key x.action ])
  |> Jj_id.length_frame
let standalone_projection_digest_of ~include_approval_consumptions request =
  let declarations = standalone_phase_declarations request in
  let approval_consumptions =
    if include_approval_consumptions then
      standalone_approval_consumptions request
    else []
  in
  digest
    (Jj_id.length_frame
       [ "standalone-projection-v2";
         standalone_phase_kind request |> standalone_phase_kind_id;
         declarations
         |> List.map occurrence_descriptor
         |> List.map occurrence_descriptor_frame
         |> Jj_id.length_frame;
         approval_consumptions
         |> List.map approval_consume_frame
         |> Jj_id.length_frame ])

let standalone_projection_digest request =
  standalone_projection_digest_of ~include_approval_consumptions:true request
type b_campaign
type completion_reconcile
type _ conditional_family =
  | B_campaign : b_campaign conditional_family
  | Completion_reconcile_plan : completion_reconcile conditional_family
type completion_outcome = Applied_exact | Not_applied | Diverged
type approval_constraint =
  | Authorized_phase
  | Exact_head
  | Exact_tree
  | No_publication
  | Bounded_resources
  | Readback_required
  | Recovery_required
type expected_identity =
  | Expected_repository of Jj_id.Repository.t
  | Expected_workspace of Jj_id.Workspace.t
  | Expected_operation of Jj_id.Operation.t
  | Expected_change of Jj_id.Change.t
  | Expected_commit of Jj_id.Commit.t
  | Expected_bookmark of Jj_id.Bookmark.t
  | Expected_remote of Jj_id.Remote.t
  | Expected_receipt of Jj_id.Receipt.t
type b_approval_context =
  | B_success_context of Jj_id.Operation.t * Jj_id.Receipt.t
  | B_guard_context of
      Jj_recovery_schema.b_success_cut * Jj_recovery_schema.b_disposition
      * Jj_id.Operation.t * Jj_id.Receipt.t
  | B_recovery_context of
      Jj_recovery_schema.b_success_cut * Jj_id.Operation.t * Jj_id.Receipt.t
type completion_approval_context =
  | Completion_reserve_context of Jj_id.Receipt.t
  | Completion_record_context of
      Jj_recovery_schema.workspace_branch * Jj_id.Receipt.t
  | Completion_record_recovery_context of
      Jj_recovery_schema.completion_record_cut_point
      * Jj_recovery_schema.workspace_branch
      * Jj_recovery_schema.execution_mode
      * Jj_id.Receipt.t
  | Completion_final_context of Jj_id.Receipt.t
  | Completion_reconcile_pending_context of Jj_id.Receipt.t
  | Completion_reconcile_outcome_context of
      completion_outcome * Jj_id.Receipt.t
type approval_phase_context =
  | Approval_release of Jj_id.Receipt.t
  | Approval_formal of formal_manifest * Jj_id.Receipt.t
  | Approval_a0 of Jj_id.Operation.t
  | Approval_a1 of int * int * Jj_id.Receipt.t
  | Approval_b of b_approval_context
  | Approval_completion of completion_approval_context
type approval_projection = {
  approval_reference : Jj_id.Approval.t;
  occurrence : occurrence;
  occurrence_ordinal : int;
  phase_context : approval_phase_context;
  constraints : approval_constraint list;
  expected_identities : expected_identity list;
}
type approval_payload = approval_projection

let has_prefix ~prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length
  && String.sub value 0 prefix_length = prefix

let b_context_matches phase = function
  | B_success_context _ -> phase = "b-success"
  | B_guard_context _ -> has_prefix ~prefix:"b-cut-" phase
  | B_recovery_context _ -> has_prefix ~prefix:"b-recovery:" phase

let completion_context_matches phase = function
  | Completion_reserve_context _ -> phase = "completion-reserve"
  | Completion_record_context _ -> phase = "completion-record"
  | Completion_record_recovery_context _ ->
      has_prefix ~prefix:"completion-record-recovery:" phase
  | Completion_final_context _ -> phase = "completion-final"
  | Completion_reconcile_pending_context _ -> phase = "completion"
  | Completion_reconcile_outcome_context (Applied_exact, _) ->
      phase = "completion-0"
  | Completion_reconcile_outcome_context (Not_applied, _) ->
      phase = "completion-1"
  | Completion_reconcile_outcome_context (Diverged, _) ->
      phase = "completion-2"

let formal_context_matches occurrence manifest =
  String.equal occurrence.phase ("formal:" ^ manifest.formal_digest)
  && match occurrence.action with
     | Jj_action_kind.Formal_process process ->
         Jj_action_kind.formal_process_tool process = manifest.formal_tool
         && List.exists
              (fun case ->
                String.equal
                  (Jj_action_kind.formal_case_key case)
                  (Jj_action_kind.formal_case_key
                     (Jj_action_kind.formal_process_case process)))
              manifest.formal_cases
     | Jujutsu_operation _ | Auxiliary _ | Candidate_process _
     | Frontier_action _ -> false

let context_matches occurrence = function
  | Approval_release _ -> occurrence.phase = "release"
  | Approval_formal (manifest, _) ->
      formal_context_matches occurrence manifest
  | Approval_a0 _ -> occurrence.phase = "a0"
  | Approval_a1 _ -> occurrence.phase = "a1"
  | Approval_b context -> b_context_matches occurrence.phase context
  | Approval_completion context ->
      completion_context_matches occurrence.phase context

let context_is_bounded = function
  | Approval_formal (manifest, _) ->
      List.length manifest.formal_cases >= 2
      && List.length manifest.formal_cases <= maximum
  | Approval_a1 (selected, classified, _) ->
      selected >= 0 && classified >= 0 && selected + classified <= maximum
  | Approval_release _ | Approval_a0 _ | Approval_b _
  | Approval_completion _ -> true

let approval_payload ~approval_reference ~occurrence ~phase_context
    ~constraints ~expected_identities =
  if constraints = [] || expected_identities = [] then Error Empty_manifest
  else if List.length constraints > maximum
       || List.length expected_identities > maximum
       || not (context_is_bounded phase_context)
  then Error Unbounded_manifest
  else if not (context_matches occurrence phase_context) then
    Error Phase_context_mismatch
  else
    Ok { approval_reference; occurrence;
         occurrence_ordinal = occurrence.ordinal; phase_context;
         constraints; expected_identities }

let approval_projection payload = payload

let constraint_key = function
  | Authorized_phase -> "authorized-phase"
  | Exact_head -> "exact-head"
  | Exact_tree -> "exact-tree"
  | No_publication -> "no-publication"
  | Bounded_resources -> "bounded-resources"
  | Readback_required -> "readback-required"
  | Recovery_required -> "recovery-required"

let expected_identity_key = function
  | Expected_repository value ->
      Jj_id.length_frame ["repository"; Jj_id.Repository.to_string value]
  | Expected_workspace value ->
      Jj_id.length_frame ["workspace"; Jj_id.Workspace.to_string value]
  | Expected_operation value ->
      Jj_id.length_frame ["operation"; Jj_id.Operation.to_string value]
  | Expected_change value ->
      Jj_id.length_frame ["change"; Jj_id.Change.to_string value]
  | Expected_commit value ->
      Jj_id.length_frame ["commit"; Jj_id.Commit.to_string value]
  | Expected_bookmark value ->
      Jj_id.length_frame ["bookmark"; Jj_id.Bookmark.to_string value]
  | Expected_remote value ->
      Jj_id.length_frame ["remote"; Jj_id.Remote.to_string value]
  | Expected_receipt value ->
      Jj_id.length_frame ["receipt"; Jj_id.Receipt.to_string value]

let completion_outcome_key = function
  | Applied_exact -> "applied-exact"
  | Not_applied -> "not-applied"
  | Diverged -> "diverged"

let b_disposition_approval_key = function
  | Jj_recovery_schema.No_source_effect -> "no-source-effect"
  | Restore_operation_only -> "restore-operation-only"
  | Restore_operation_and_partition -> "restore-operation-and-partition"
  | Forward_complete_exact -> "forward-complete-exact"
  | Diverged -> "diverged"

let b_approval_context_key = function
  | B_success_context (operation, receipt) ->
      Jj_id.length_frame
        ["success"; Jj_id.Operation.to_string operation;
         Jj_id.Receipt.to_string receipt]
  | B_guard_context (cut, disposition, operation, receipt) ->
      Jj_id.length_frame
        ["guard"; phase_b_cut_key cut;
         b_disposition_approval_key disposition;
         Jj_id.Operation.to_string operation;
         Jj_id.Receipt.to_string receipt]
  | B_recovery_context (cut, operation, receipt) ->
      Jj_id.length_frame
        ["recovery"; phase_b_cut_key cut;
         Jj_id.Operation.to_string operation;
         Jj_id.Receipt.to_string receipt]

let completion_approval_context_key = function
  | Completion_reserve_context receipt ->
      Jj_id.length_frame ["reserve"; Jj_id.Receipt.to_string receipt]
  | Completion_record_context (workspace, receipt) ->
      Jj_id.length_frame
        ["record"; workspace_key workspace; Jj_id.Receipt.to_string receipt]
  | Completion_record_recovery_context (cut, workspace, mode, receipt) ->
      Jj_id.length_frame
        ["record-recovery"; phase_completion_cut_key cut;
         workspace_key workspace; execution_mode_key mode;
         Jj_id.Receipt.to_string receipt]
  | Completion_final_context receipt ->
      Jj_id.length_frame ["final"; Jj_id.Receipt.to_string receipt]
  | Completion_reconcile_pending_context receipt ->
      Jj_id.length_frame
        ["reconcile-pending"; Jj_id.Receipt.to_string receipt]
  | Completion_reconcile_outcome_context (outcome, receipt) ->
      Jj_id.length_frame
        ["reconcile-outcome"; completion_outcome_key outcome;
         Jj_id.Receipt.to_string receipt]

let approval_context_key = function
  | Approval_release receipt ->
      Jj_id.length_frame ["release"; Jj_id.Receipt.to_string receipt]
  | Approval_formal (manifest, receipt) ->
      Jj_id.length_frame
        [ "formal"; manifest.formal_digest;
          Jj_id.Receipt.to_string receipt ]
  | Approval_a0 operation ->
      Jj_id.length_frame ["a0"; Jj_id.Operation.to_string operation]
  | Approval_a1 (selected, classified, receipt) ->
      Jj_id.length_frame
        ["a1"; string_of_int selected; string_of_int classified;
         Jj_id.Receipt.to_string receipt]
  | Approval_b context ->
      Jj_id.length_frame ["b"; b_approval_context_key context]
  | Approval_completion context ->
      Jj_id.length_frame
        ["completion"; completion_approval_context_key context]

let canonical_approval ?phase_override ?ordinal_override
    ?constraint_override ?identity_override payload =
  let occurrence = payload.occurrence in
  let phase = Option.value phase_override ~default:occurrence.phase in
  let ordinal =
    Option.value ordinal_override ~default:payload.occurrence_ordinal
  in
  let constraints =
    Option.value constraint_override
      ~default:(List.map constraint_key payload.constraints)
  in
  let identities =
    Option.value identity_override
      ~default:(List.map expected_identity_key payload.expected_identities)
  in
  Jj_id.length_frame
    [ "approval-payload-v1";
      Jj_id.Approval.to_string payload.approval_reference;
      occurrence.id; occurrence.nonce; phase; string_of_int ordinal;
      Jj_action_kind.action_key occurrence.action;
      approval_context_key payload.phase_context;
      Jj_id.length_frame constraints;
      Jj_id.length_frame identities ]

let canonical_approval_unsigned_bytes payload = canonical_approval payload
type _ guard =
  | B_guard : Jj_recovery_schema.b_success_cut * Jj_recovery_schema.b_disposition -> b_campaign guard
  | Completion_guard : completion_outcome -> completion_reconcile guard
type conditional_control_id = string
type prefix_id = string
type 'family branch_id = string
type 'family conditional_branch = {
  guard : 'family guard;
  declarations : occurrence list;
  branch_id : 'family branch_id;
  control : conditional_control_id;
}
type 'family conditional_plan = {
  family : 'family conditional_family;
  request_id : Jj_id.Request.t;
  common : occurrence list;
  branches : 'family conditional_branch list;
  controls : conditional_control_id list;
}
let common_declarations x = x.common
let conditional_branches x = x.branches
let branch_guard x = x.guard
let branch_declarations x = x.declarations
let conditional_branch_count x = List.length x.branches
let conditional_family x = x.family
let frontier = Jj_action_kind.Frontier_action (Set_activity_frontier Reconciled_terminal)
let b_action = function
  | Jj_recovery_schema.B_acquire_writer_lease -> aux Acquire_writer_lease
  | B_stage_recovery_set -> aux Stage_recovery_set | B_bookmark_set -> op Bookmark_set
  | B_bookmark_readback | B_duplicate_readback | B_snapshot_1_readback | B_new_change_readback | B_snapshot_2_readback -> aux Readback_jj_state
  | B_duplicate -> op Duplicate
  | B_observe_repository_source_before_partition | B_observe_repository_source_final -> aux Observe_repository_source
  | B_observe_tree_before_partition | B_observe_tree_after_write | B_observe_tree_after_restore | B_observe_tree_final -> aux Observe_tree
  | B_write_partition -> aux Write_partition | B_working_copy_snapshot_1 | B_working_copy_snapshot_2 -> op Working_copy_snapshot
  | B_new_change -> op New_change | B_restore_partition -> aux Restore_partition
  | B_set_activity_frontier -> frontier | B_cleanup_recovery_set -> aux Cleanup_recovery_set
  | B_release_writer_lease -> aux Release_writer_lease
  | B_write_partition_partial _ | B_restore_partition_partial _ -> assert false

let b_disposition_key = function
  | Jj_recovery_schema.No_source_effect -> "no-source-effect"
  | Restore_operation_only -> "restore-operation-only"
  | Restore_operation_and_partition -> "restore-operation-and-partition"
  | Forward_complete_exact -> "forward-complete-exact"
  | Diverged -> "diverged"

let b_slot_key slot =
  let ordinal =
    let rec find index = function
      | [] -> -1
      | candidate :: rest ->
          if candidate = slot then index else find (index + 1) rest
    in
    find 0 Jj_recovery_schema.b_success_action_slots
  in
  string_of_int ordinal

let b_cut_key = function
  | Jj_recovery_schema.Before_engine -> "before-engine"
  | After_consume slot -> "after-consume:" ^ b_slot_key slot
  | After_action slot -> "after-action:" ^ b_slot_key slot

let guard_key : type family. family guard -> string = function
  | B_guard (cut, disposition) ->
      "b:" ^ b_cut_key cut ^ ":" ^ b_disposition_key disposition
  | Completion_guard Applied_exact -> "completion:applied-exact"
  | Completion_guard Not_applied -> "completion:not-applied"
  | Completion_guard Diverged -> "completion:diverged"

let stable_id prefix fields =
  prefix ^ digest (Jj_id.length_frame fields)

let control_id request_id ordinal =
  stable_id "control-"
    [ Jj_id.Request.to_string request_id; string_of_int ordinal ]

let make_branch_id request_id control guard ordinal =
  stable_id "branch-"
    [ Jj_id.Request.to_string request_id; control; guard_key guard;
      string_of_int ordinal ]

let derive_b_campaign_plan ~request_id =
  let controls =
    List.mapi (fun ordinal _ -> control_id request_id ordinal)
      Jj_recovery_schema.b_success_action_slots
  in
  let branches =
    List.mapi
      (fun slot_index slot ->
        let control = List.nth controls slot_index in
        [ Jj_recovery_schema.After_consume slot;
          Jj_recovery_schema.After_action slot ]
        |> List.mapi (fun cut_offset cut ->
             Jj_recovery_schema.schema (B_success (cut, In_process))
             |> Jj_recovery_schema.b_branches
             |> List.mapi (fun branch_index branch ->
                  let guard =
                    B_guard
                      (cut, Jj_recovery_schema.b_disposition branch)
                  in
                  let ordinal = (cut_offset * 8) + branch_index in
                  { guard;
                    declarations =
                      occurrences ~request_id
                        ~phase:
                          ("b-cut-" ^ string_of_int ((slot_index * 2) + cut_offset)
                           ^ "-branch-" ^ string_of_int branch_index)
                        (List.map Jj_recovery_schema.recovery_step_action
                           (Jj_recovery_schema.b_steps branch));
                    branch_id =
                      make_branch_id request_id control guard ordinal;
                    control }))
        |> List.concat)
      Jj_recovery_schema.b_success_action_slots
    |> List.concat
  in
  Ok
    { family = B_campaign; request_id;
      common =
        occurrences ~request_id ~phase:"b-success"
          (List.map b_action Jj_recovery_schema.b_success_action_slots);
      branches; controls }

let derive_completion_reconcile_plan ~request_id =
  let control = control_id request_id 0 in
  let make ordinal outcome actions =
    let guard = Completion_guard outcome in
    { guard;
      declarations =
        occurrences ~request_id
          ~phase:("completion-" ^ string_of_int ordinal) actions;
      branch_id = make_branch_id request_id control guard ordinal;
      control }
  in
  Ok
    { family = Completion_reconcile_plan; request_id;
      common =
        occurrences ~request_id ~phase:"completion"
          [ aux Acquire_writer_lease; aux Readback_jj_state; aux Observe_tree;
            aux Observe_repository_source ];
      branches =
        [ make 0 Applied_exact
            [ frontier; aux Release_writer_lease;
              aux Finalize_completion_receipt ];
          make 1 Not_applied [ frontier; aux Release_writer_lease ];
          make 2 Diverged [] ];
      controls = [ control ] }

let conditional_occurrences plan =
  plan.common @ List.concat_map (fun branch -> branch.declarations) plan.branches

let all_distinct values =
  List.length values = List.length (List.sort_uniq String.compare values)

type 'family node_guard =
  | Always
  | All_continue of conditional_control_id list
  | Branch_selected of conditional_control_id * 'family branch_id

type consume_occurrence = {
  consume_id : string;
  ordinal : int;
  parent : string;
  action : Jj_action_kind.auxiliary_role;
}

type 'family node =
  | Consume_node of {
      guard : 'family node_guard;
      parent : string;
      consume : consume_occurrence;
    }
  | Action_node of {
      guard : 'family node_guard;
      occurrence : occurrence;
    }
  | Decision_node of {
      guard : 'family node_guard;
      control : conditional_control_id;
      prefix : prefix_id;
      branches : 'family branch_id list;
    }

type node_kind = Consume_node_kind | Action_node_kind | Decision_node_kind
type node_guard_shape =
  | Always_guard
  | All_continue_guard of int
  | Branch_selected_guard

type guard_descriptor =
  | Always_guard_descriptor
  | All_continue_guard_descriptor of { control_ids : string list }
  | Branch_selected_guard_descriptor of {
      control_id : string;
      branch_id : string;
    }

type conditional_node_descriptor =
  | Consume_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      parent_occurrence_id : string;
      parent_occurrence_ordinal : int;
      consume_action_identity : Jj_action_kind.auxiliary_role;
    }
  | Action_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      occurrence : occurrence_descriptor;
    }
  | Decision_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      control_id : string;
      prefix_id : string;
      branch_ids : string list;
    }

type conditional_edge_descriptor = {
  edge_source_id : string;
  edge_target_id : string;
  edge_label : string;
  edge_guard_identity : string;
}

type conditional_edge = {
  source : string;
  target : string;
  label : string;
  guard_identity : string;
}

let take count values =
  let rec loop remaining acc = function
    | _ when remaining = 0 -> List.rev acc
    | [] -> List.rev acc
    | value :: rest -> loop (remaining - 1) (value :: acc) rest
  in
  loop count [] values

let consume_of occurrence =
  { consume_id = stable_id "consume-" [ occurrence.id ];
    ordinal = occurrence.ordinal; parent = occurrence.id;
    action = Jj_action_kind.Consume_approval_nonce }

let nodes_for_occurrences guard declarations =
  List.concat_map
    (fun occurrence ->
      let consume = consume_of occurrence in
      [ Consume_node { guard; parent = occurrence.id; consume };
        Action_node { guard; occurrence } ])
    declarations

let conditional_nodes : type family.
    family conditional_plan -> family node list =
  fun plan ->
    match plan.family with
    | B_campaign ->
        let common =
          List.mapi
            (fun index occurrence ->
              let guard =
                if index = 0 then Always
                else All_continue (take index plan.controls)
              in
              let control = List.nth plan.controls index in
              let branches =
                plan.branches
                |> List.filter (fun branch -> branch.control = control)
                |> List.map (fun branch -> branch.branch_id)
              in
              nodes_for_occurrences guard [ occurrence ]
              @ [ Decision_node
                    { guard; control; prefix = occurrence.id; branches } ])
            plan.common
          |> List.concat
        in
        let dormant =
          plan.branches
          |> List.concat_map (fun branch ->
               nodes_for_occurrences
                 (Branch_selected (branch.control, branch.branch_id))
                 branch.declarations)
        in
        common @ dormant
    | Completion_reconcile_plan ->
        let common = nodes_for_occurrences Always plan.common in
        let control = List.hd plan.controls in
        let prefix = (List.hd (List.rev plan.common)).id in
        let decision =
          Decision_node
            { guard = Always; control; prefix;
              branches = List.map (fun branch -> branch.branch_id) plan.branches }
        in
        let suffixes =
          plan.branches
          |> List.concat_map (fun branch ->
               nodes_for_occurrences
                 (Branch_selected (branch.control, branch.branch_id))
                 branch.declarations)
        in
        common @ [ decision ] @ suffixes

let node_kind = function
  | Consume_node _ -> Consume_node_kind
  | Action_node _ -> Action_node_kind
  | Decision_node _ -> Decision_node_kind

let node_guard = function
  | Consume_node value -> value.guard
  | Action_node value -> value.guard
  | Decision_node value -> value.guard

let node_guard_key = function
  | Always -> "always"
  | All_continue controls ->
      "all-continue:" ^ Jj_id.length_frame controls
  | Branch_selected (control, branch) ->
      "branch-selected:" ^ Jj_id.length_frame [ control; branch ]

let guard_descriptor = function
  | Always -> Always_guard_descriptor
  | All_continue control_ids ->
      All_continue_guard_descriptor { control_ids }
  | Branch_selected (control_id, branch_id) ->
      Branch_selected_guard_descriptor { control_id; branch_id }

let guard_descriptor_identity = function
  | Always_guard_descriptor -> "always"
  | All_continue_guard_descriptor { control_ids } ->
      "all-continue:" ^ Jj_id.length_frame control_ids
  | Branch_selected_guard_descriptor { control_id; branch_id } ->
      "branch-selected:" ^ Jj_id.length_frame [ control_id; branch_id ]

let node_guard_shape node =
  match node_guard node with
  | Always -> Always_guard
  | All_continue controls -> All_continue_guard (List.length controls)
  | Branch_selected _ -> Branch_selected_guard

let node_nonce = function
  | Consume_node _ | Decision_node _ -> None
  | Action_node value -> Some value.occurrence.nonce

let node_id = function
  | Consume_node value -> value.consume.consume_id
  | Action_node value -> value.occurrence.id
  | Decision_node value -> value.control

let conditional_node_descriptor = function
  | Consume_node value ->
      Consume_descriptor
        { node_id = value.consume.consume_id;
          guard = guard_descriptor value.guard;
          parent_occurrence_id = value.parent;
          parent_occurrence_ordinal = value.consume.ordinal;
          consume_action_identity = value.consume.action }
  | Action_node value ->
      Action_descriptor
        { node_id = value.occurrence.id;
          guard = guard_descriptor value.guard;
          occurrence = occurrence_descriptor value.occurrence }
  | Decision_node value ->
      Decision_descriptor
        { node_id = value.control;
          guard = guard_descriptor value.guard;
          control_id = value.control;
          prefix_id = value.prefix;
          branch_ids = value.branches }

let node_count plan = List.length (conditional_nodes plan)
let count_kind kind plan =
  conditional_nodes plan
  |> List.filter (fun node -> node_kind node = kind)
  |> List.length
let consume_node_count plan = count_kind Consume_node_kind plan
let action_node_count plan = count_kind Action_node_kind plan
let decision_node_count plan = count_kind Decision_node_kind plan
let control_count plan = List.length plan.controls

let consume_id occurrence = (consume_of occurrence).consume_id
let edge ?(label = "order") ~guard source target =
  { source; target; label; guard_identity = node_guard_key guard }

let occurrence_chain_edges guard declarations =
  let rec loop acc = function
    | [] -> List.rev acc
    | [ occurrence ] ->
        List.rev
          (edge ~guard (consume_id occurrence) occurrence.id :: acc)
    | occurrence :: ((next :: _) as rest) ->
        loop
          (edge ~label:"order" ~guard occurrence.id (consume_id next)
           :: edge ~guard (consume_id occurrence) occurrence.id :: acc)
          rest
  in
  loop [] declarations

let aggregate_id plan =
  stable_id "aggregate-" [ Jj_id.Request.to_string plan.request_id ]

let guarded_edges : type family.
    family conditional_plan -> conditional_edge list =
  fun plan ->
    let aggregate = aggregate_id plan in
    let family_edges =
      match plan.family with
      | B_campaign ->
          let common_edges =
            List.mapi
              (fun index occurrence ->
                let control = List.nth plan.controls index in
                let guard =
                  if index = 0 then Always
                  else All_continue (take index plan.controls)
                in
                [ edge ~guard (consume_id occurrence) occurrence.id;
                  edge ~guard occurrence.id control ]
                @ match List.nth_opt plan.common (index + 1) with
                  | None -> []
                  | Some next ->
                      let next_guard =
                        All_continue (take (index + 1) plan.controls)
                      in
                      [ edge ~guard:next_guard control (consume_id next) ])
              plan.common
            |> List.concat
          in
          let branch_edges =
            plan.branches
            |> List.concat_map (fun branch ->
                 let guard =
                   Branch_selected (branch.control, branch.branch_id)
                 in
                 let head =
                   match branch.declarations with
                   | [] ->
                       [ edge ~label:("branch:" ^ branch.branch_id) ~guard
                           branch.control aggregate ]
                   | first :: _ ->
                       [ edge ~label:("branch:" ^ branch.branch_id) ~guard
                           branch.control (consume_id first) ]
                 in
                 head @ occurrence_chain_edges guard branch.declarations)
          in
          common_edges @ branch_edges
      | Completion_reconcile_plan ->
          let common_chain = occurrence_chain_edges Always plan.common in
          let last = List.hd (List.rev plan.common) in
          let control = List.hd plan.controls in
          let common_chain =
            common_chain @ [ edge ~guard:Always last.id control ]
          in
          let branch_edges =
            plan.branches
            |> List.concat_map (fun branch ->
                 let guard =
                   Branch_selected (branch.control, branch.branch_id)
                 in
                 let head =
                   match branch.declarations with
                   | [] ->
                       [ edge ~label:("branch:" ^ branch.branch_id) ~guard
                           control aggregate ]
                   | first :: _ ->
                       [ edge ~label:("branch:" ^ branch.branch_id) ~guard
                           control (consume_id first) ]
                 in
                 head @ occurrence_chain_edges guard branch.declarations)
          in
          common_chain @ branch_edges
    in
    let aggregate_edges =
      conditional_nodes plan
      |> List.map (fun node ->
           edge ~label:"aggregate" ~guard:(node_guard node)
             (node_id node) aggregate)
    in
    family_edges @ aggregate_edges

let edge_source edge = edge.source
let edge_target edge = edge.target
let edge_label edge = edge.label
let edge_guard_identity edge = edge.guard_identity
let conditional_edge_descriptor edge =
  { edge_source_id = edge.source;
    edge_target_id = edge.target;
    edge_label = edge.label;
    edge_guard_identity = edge.guard_identity }

let edges_are_acyclic plan =
  let nodes = conditional_nodes plan in
  let aggregate = aggregate_id plan in
  let ranks =
    List.mapi (fun rank node -> (node_id node, rank)) nodes
    @ [ aggregate, List.length nodes ]
  in
  let rank id = List.assoc_opt id ranks in
  List.for_all
    (fun edge ->
      match rank edge.source, rank edge.target with
      | Some source, Some target -> source < target
      | _ -> false)
    (guarded_edges plan)

let all_nodes_reach_aggregate plan =
  let aggregate = aggregate_id plan in
  let edges = guarded_edges plan in
  conditional_nodes plan
  |> List.for_all (fun node ->
       List.exists
         (fun edge ->
           edge.source = node_id node && edge.target = aggregate
           && edge.label = "aggregate")
         edges)

let conditional_identities_are_disjoint plan =
  let declarations = conditional_occurrences plan in
  let occurrence_identities =
    List.map occurrence_id declarations @ List.map occurrence_nonce declarations
  in
  let structural_identities =
    conditional_nodes plan
    |> List.filter_map (fun node ->
         match node_kind node with
         | Action_node_kind -> None
         | Consume_node_kind | Decision_node_kind -> Some (node_id node))
  in
  let branch_identities = List.map (fun branch -> branch.branch_id) plan.branches in
  let structural_identities =
    aggregate_id plan :: branch_identities @ structural_identities
  in
  all_distinct occurrence_identities
  && all_distinct structural_identities
  && List.for_all
       (fun identity -> not (List.mem identity occurrence_identities))
       structural_identities

let node_frame node =
  match node with
  | Consume_node value ->
      Jj_id.length_frame
        [ "consume"; node_guard_key value.guard; value.consume.consume_id;
          string_of_int value.consume.ordinal; value.parent;
          Jj_action_kind.auxiliary_role_key value.consume.action ]
  | Action_node value ->
      Jj_id.length_frame
        [ "action"; node_guard_key value.guard;
          canonical_unsigned_bytes [ value.occurrence ] ]
  | Decision_node value ->
      Jj_id.length_frame
        [ "decision"; node_guard_key value.guard; value.control; value.prefix;
          Jj_id.length_frame value.branches ]

let edge_frame edge =
  Jj_id.length_frame
    [ edge.source; edge.target; edge.label; edge.guard_identity ]

type descriptor_mutation =
  | Drop_descriptor
  | Reorder_descriptors
  | Mismatch_identity

let mutate_descriptor_frames mutation = function
  | [] -> []
  | first :: rest ->
      match mutation with
      | Drop_descriptor -> rest
      | Reorder_descriptors -> List.rev (first :: rest)
      | Mismatch_identity -> ("identity-mismatch:" ^ first) :: rest

let descriptor_projection_digest domain frames =
  digest (Jj_id.length_frame [ domain; Jj_id.length_frame frames ])

let standalone_phase_denominator_digest_with_mutation mutation =
  standalone_phase_kinds
  |> List.map standalone_phase_kind_id
  |> mutate_descriptor_frames mutation
  |> phase_denominator_frame
  |> digest

let standalone_projection_digest_with_mutation request mutation =
  let occurrence_frames =
    standalone_phase_declarations request
    |> List.map occurrence_descriptor
    |> List.map occurrence_descriptor_frame
    |> mutate_descriptor_frames mutation
  in
  let consume_frames =
    standalone_approval_consumptions request
    |> List.map approval_consume_frame
  in
  digest
    (Jj_id.length_frame
       [ "standalone-projection-v2";
         standalone_phase_kind request |> standalone_phase_kind_id;
         Jj_id.length_frame occurrence_frames;
         Jj_id.length_frame consume_frames ])

let standalone_projection_digest_without_approval_consumptions request =
  standalone_projection_digest_of ~include_approval_consumptions:false
    request

let conditional_node_projection ?mutation plan =
  let frames = List.map node_frame (conditional_nodes plan) in
  let frames =
    match mutation with
    | None -> frames
    | Some value -> mutate_descriptor_frames value frames
  in
  descriptor_projection_digest "conditional-node-projection-v1" frames

let conditional_node_projection_digest plan =
  conditional_node_projection plan

let guarded_edge_projection ?mutation plan =
  let frames = List.map edge_frame (guarded_edges plan) in
  let frames =
    match mutation with
    | None -> frames
    | Some value -> mutate_descriptor_frames value frames
  in
  descriptor_projection_digest "guarded-edge-projection-v1" frames

let guarded_edge_projection_digest plan = guarded_edge_projection plan

type canonical_mutation = Drop_node | Drop_edge | Reverse_edge

let conditional_family_id : type family.
    family conditional_family -> string = function
  | B_campaign -> "b-campaign"
  | Completion_reconcile_plan -> "completion-reconcile"

let canonical_conditional ?mutation plan =
  let branch_frames =
    List.map
      (fun branch ->
        Jj_id.length_frame
          [ branch.branch_id; branch.control; guard_key branch.guard;
            canonical_unsigned_bytes branch.declarations ])
      plan.branches
  in
  let node_frames = List.map node_frame (conditional_nodes plan) in
  let edge_frames = List.map edge_frame (guarded_edges plan) in
  let node_frames, edge_frames =
    match mutation with
    | None -> node_frames, edge_frames
    | Some Drop_node -> List.tl node_frames, edge_frames
    | Some Drop_edge -> node_frames, List.tl edge_frames
    | Some Reverse_edge ->
        let reversed =
          match guarded_edges plan with
          | [] -> []
          | first :: rest ->
              edge_frame { first with source = first.target; target = first.source }
              :: List.map edge_frame rest
        in
        node_frames, reversed
  in
  Jj_id.length_frame
    ([ "conditional-plan-v3"; conditional_family_id plan.family;
       Jj_recovery_schema.source_digest;
       canonical_unsigned_bytes plan.common;
       Jj_id.length_frame plan.controls; aggregate_id plan ]
     @ branch_frames
     @ [ Jj_id.length_frame node_frames; Jj_id.length_frame edge_frames ])

let canonical_conditional_unsigned_bytes plan = canonical_conditional plan

let conditional_projection_digest plan =
  digest
    (Jj_id.length_frame
       [ "conditional-descriptor-projection-v1";
         conditional_family_id plan.family;
         canonical_conditional_unsigned_bytes plan;
         conditional_node_projection_digest plan;
         guarded_edge_projection_digest plan ])

let campaign_constraints =
  [ Authorized_phase; Exact_head; Exact_tree; No_publication;
    Bounded_resources; Readback_required; Recovery_required ]

let campaign_descriptor_schema =
  [ "conditional-family:b-campaign";
    "conditional-family:completion-reconcile";
    "occurrence-descriptor-v1";
    "occurrence-field:stable-occurrence-id";
    "occurrence-field:stable-nonce-id";
    "occurrence-field:phase-id";
    "occurrence-field:phase-ordinal";
    "occurrence-field:action-identity";
    "node:consume"; "node:action"; "node:decision";
    "node-field:stable-node-id";
    "node-field:control-prefix-branch-identities";
    "guard:always"; "guard:all-continue";
    "guard:branch-selected"; "edge:label";
    "edge:guard-identity";
    "conditional-node-projection-v1";
    "guarded-edge-projection-v1" ]

let formal_manifest_schema =
  [ "formal-request-manifest-v1";
    "formal-field:tool"; "formal-field:model-sha256";
    "formal-field:source-sha256"; "formal-field:ordered-cases";
    "formal-case:positive-first";
    "formal-case:negative-control-bounded-id";
    "formal-negative-controls:nonempty-unique-max-1023" ]

let formal_consume_schema =
  [ "formal-approval-consume-v1";
    "consume-field:stable-id"; "consume-field:parent-occurrence-id";
    "consume-field:parent-ordinal";
    "consume-action:consume-approval-nonce";
    "consume-cardinality:one-per-formal-process";
    "consume-order:immediately-before-parent";
    "consume-posture:nonce-free-nonauthorizing" ]

let campaign_source_projection ~manifest_bound ~constraints
    ~descriptor_schema ~formal_manifest_schema ~formal_consume_schema =
  Jj_id.length_frame
    [ "campaign-authority-v1";
      Jj_action_kind.source_digest;
      Jj_recovery_schema.source_digest;
      "manifest-bound:" ^ string_of_int manifest_bound;
      "standalone-count:" ^ string_of_int standalone_phase_count;
      standalone_phase_denominator_digest;
      Jj_id.length_frame (List.map constraint_key constraints);
      Jj_id.length_frame
        [ "repository"; "workspace"; "operation"; "change"; "commit";
          "bookmark"; "remote"; "receipt" ];
      Jj_id.length_frame
        [ "approval-release"; "approval-formal"; "approval-a0";
          "approval-a1"; "approval-b-success"; "approval-b-guard";
          "approval-b-recovery"; "completion-reserve";
          "completion-record-existing"; "completion-record-new";
          "completion-record-recovery"; "completion-final";
          "completion-reconcile-pending";
          "completion-reconcile-applied-exact";
          "completion-reconcile-not-applied";
          "completion-reconcile-diverged" ];
      Jj_id.length_frame descriptor_schema;
      Jj_id.length_frame
        [ "error:empty-manifest"; "error:unbounded-manifest";
          "error:phase-context-mismatch";
          "error:empty-negative-control-denominator";
          "error:duplicate-negative-control";
          "error:unbounded-negative-control-denominator" ];
      Jj_id.length_frame formal_manifest_schema;
      Jj_id.length_frame formal_consume_schema ]

let campaign_source_digest ~manifest_bound ~constraints ~descriptor_schema
    ~formal_manifest_schema ~formal_consume_schema =
  digest
    (campaign_source_projection ~manifest_bound ~constraints
       ~descriptor_schema ~formal_manifest_schema ~formal_consume_schema)

let source_digest =
  campaign_source_digest ~manifest_bound:maximum
    ~constraints:campaign_constraints
    ~descriptor_schema:campaign_descriptor_schema
    ~formal_manifest_schema ~formal_consume_schema

module For_test = struct
  type mutation = canonical_mutation = Drop_node | Drop_edge | Reverse_edge
  let canonical_with_mutation plan mutation =
    canonical_conditional ~mutation plan

  type nonrec descriptor_mutation = descriptor_mutation =
    | Drop_descriptor
    | Reorder_descriptors
    | Mismatch_identity

  let standalone_phase_denominator_digest_with_mutation =
    standalone_phase_denominator_digest_with_mutation

  let standalone_projection_digest_with_mutation =
    standalone_projection_digest_with_mutation

  let standalone_projection_digest_without_approval_consumptions =
    standalone_projection_digest_without_approval_consumptions

  let conditional_node_projection_digest_with_mutation plan mutation =
    conditional_node_projection ~mutation plan

  let guarded_edge_projection_digest_with_mutation plan mutation =
    guarded_edge_projection ~mutation plan

  type approval_mutation =
    | Change_approval_phase
    | Change_occurrence_ordinal
    | Change_approval_constraint
    | Change_expected_identity

  let canonical_approval_with_mutation payload = function
    | Change_approval_phase ->
        canonical_approval
          ~phase_override:
            (if has_prefix ~prefix:"formal:" payload.occurrence.phase
             then "release"
             else "formal")
          payload
    | Change_occurrence_ordinal ->
        canonical_approval
          ~ordinal_override:(payload.occurrence_ordinal + 1) payload
    | Change_approval_constraint ->
        canonical_approval
          ~constraint_override:
            (match payload.constraints with
             | [] -> [constraint_key Authorized_phase]
             | _ :: rest -> List.map constraint_key rest)
          payload
    | Change_expected_identity ->
        canonical_approval
          ~identity_override:
            (match payload.expected_identities with
             | [] -> []
             | _ :: rest -> List.map expected_identity_key rest)
          payload

  type source_mutation =
    | Change_manifest_bound
    | Drop_constraint
    | Drop_descriptor_schema
    | Drop_formal_manifest_schema
    | Drop_formal_consume_schema
  let source_digest_with_mutation = function
    | Change_manifest_bound ->
        campaign_source_digest ~manifest_bound:(maximum + 1)
          ~constraints:campaign_constraints
          ~descriptor_schema:campaign_descriptor_schema
          ~formal_manifest_schema ~formal_consume_schema
    | Drop_constraint ->
        campaign_source_digest ~manifest_bound:maximum
          ~constraints:(List.tl campaign_constraints)
          ~descriptor_schema:campaign_descriptor_schema
          ~formal_manifest_schema ~formal_consume_schema
    | Drop_descriptor_schema ->
        campaign_source_digest ~manifest_bound:maximum
          ~constraints:campaign_constraints
          ~descriptor_schema:(List.tl campaign_descriptor_schema)
          ~formal_manifest_schema ~formal_consume_schema
    | Drop_formal_manifest_schema ->
        campaign_source_digest ~manifest_bound:maximum
          ~constraints:campaign_constraints
          ~descriptor_schema:campaign_descriptor_schema
          ~formal_manifest_schema:(List.tl formal_manifest_schema)
          ~formal_consume_schema
    | Drop_formal_consume_schema ->
        campaign_source_digest ~manifest_bound:maximum
          ~constraints:campaign_constraints
          ~descriptor_schema:campaign_descriptor_schema
          ~formal_manifest_schema
          ~formal_consume_schema:(List.tl formal_consume_schema)
end
