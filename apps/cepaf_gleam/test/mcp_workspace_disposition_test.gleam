import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/disposition.{
  type HeadEntry, ActiveCandidate, HeadEntry, Held, Incorporated, Superseded,
  Unclassified, validate_reconciliation,
}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  type Outcome, ClientProfile, Complete, Refused, TaskScopedMutation, ToolError,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import simplifile

pub fn ancestry_without_content_disposition_is_not_integrated_test() {
  let ids = ["candidate", "workspace", "head", "source4-test-2219"]
  let holds = ["source4-test-2219"]
  let valid = [
    HeadEntry("candidate", False, ActiveCandidate("cand-combined")),
    HeadEntry("workspace", True, Incorporated("content-sha256")),
    HeadEntry(
      "head",
      True,
      Superseded("cand-combined", "content replaced explicitly"),
    ),
    HeadEntry("source4-test-2219", True, Held("SourceFX", "operator hold")),
  ]
  validate_reconciliation(ids, holds, valid) |> should.equal(Ok(4))
  list.each(ids, fn(id) {
    validate_reconciliation(
      ids,
      holds,
      list.filter(valid, fn(e) { e.id != id }),
    )
    |> should.be_error
    validate_reconciliation(
      ids,
      holds,
      list.map(valid, fn(e) {
        case e.id == id {
          True -> HeadEntry(id, True, Unclassified)
          False -> e
        }
      }),
    )
    |> should.be_error
  })
  list.each(
    [
      HeadEntry("workspace", True, Incorporated("")),
      HeadEntry("head", True, Superseded("cand-combined", " ")),
      HeadEntry("head", True, Superseded("", "reason")),
      HeadEntry("candidate", True, ActiveCandidate("")),
      HeadEntry("source4-test-2219", True, Incorporated("digest")),
      HeadEntry("source4-test-2219", True, Held("", "reason")),
      HeadEntry("source4-test-2219", True, Held("SourceFX", "")),
    ],
    fn(bad) {
      validate_reconciliation(
        ids,
        holds,
        list.map(valid, fn(e) {
          case e.id == bad.id {
            True -> bad
            False -> e
          }
        }),
      )
      |> should.be_error
    },
  )
  validate_reconciliation(ids, holds, list.append(valid, valid))
  |> should.be_error
}

fn receipt(id: String, candidate: String) -> features.ExecutionReceipt {
  features.ExecutionReceipt(
    id,
    candidate,
    0,
    None,
    None,
    "observed-output-sha256",
  )
}

fn code(outcome: Outcome) -> String {
  let assert Refused(ToolError(code, _, _)) = outcome
  code
}

pub fn combined_candidate_invalidates_parent_only_receipts_test() {
  let parent_receipts =
    dict.from_list([
      #("task-a", receipt("task-a", "cand-parent-a")),
      #("task-b", receipt("task-b", "cand-parent-b")),
    ])
  let store =
    features.FeatureEvidenceStore(
      active_candidate: "cand-combined",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["task-a", "task-b"],
      receipts: parent_receipts,
      intents: dict.new(),
    )
  let progress = features.compute_progress(store)
  progress.stale_receipt_count |> should.equal(2)
  progress.verified_complete_count |> should.equal(0)
  let workspace = "/home/an/NAS-setup/uos"
  let ticket =
    admission.GrantTicket(
      "T21-grant",
      TaskScopedMutation,
      False,
      9_999_999_999_999,
      workspace,
    )
  let grant =
    Some(route_convergence.RouteGrant("development", ["harness_finish"], ticket))
  let fresh =
    features.FeatureEvidenceStore(
      ..store,
      receipts: dict.from_list([
        #("task-a", receipt("task-a", "cand-combined")),
        #("task-b", receipt("task-b", "cand-combined")),
      ]),
    )
  features.compute_progress(fresh).stale_receipt_count |> should.equal(0)
  features.compute_progress(fresh).verified_complete_count |> should.equal(2)
  list.each(["task-a", "task-b"], fn(id) {
    features.harness_system_feature_observations(store, id)
    |> code
    |> should.equal("STALE_CANDIDATE_RECEIPT")
    let assert Complete(_, _) =
      features.harness_system_feature_observations(fresh, id)
    let context =
      admission.AdmissionContext(
        principal: principal.from_launcher_env(
          "T21-worker",
          ClientProfile("test"),
          workspace,
          "T21-session",
        ),
        mode: admission.EnforcedMode,
        now_ms: 1_000_000,
        workspace_root: workspace,
        task_fence: Some(admission.TaskFence(
          "T21-plan",
          id,
          "T21-worker",
          1,
          admission.TaskExecuting,
          9_999_999_999_999,
          Some(ticket),
        )),
      )
    let args =
      dict.from_list([
        #("task_id", id),
        #("journal_path", "/tmp/journal"),
        #("build_intent_id", "build-1"),
        #("test_intent_id", "test-1"),
      ])
    let assert Ok(pool) =
      supervisor.start_worker_pool_for_candidate(
        size: 1,
        candidate: "cand-combined",
      )
    let run = fn(evidence_store) {
      route_convergence.execute_converged(
        pool,
        context,
        grant,
        evidence_store,
        "development",
        "harness_finish",
        args,
        fn(_, _) { Ok("finished") },
      ).0
    }
    run(store) |> code |> should.equal("COMPLETION_EVIDENCE_REQUIRED")
    let assert Complete(_, evidence) = run(fresh)
    evidence.candidate |> should.equal("cand-combined")
  })
}

// ---------------------------------------------------------------------------
// T21 disposition artifact -> typed validator binding
// ---------------------------------------------------------------------------

fn artifact_text(entry: value.Value, key: String) -> String {
  case value.get(entry, key) {
    Ok(value.Text(text)) -> text
    _ -> ""
  }
}

fn artifact_array(root: value.Value, key: String) -> List(value.Value) {
  case value.get(root, key) {
    Ok(value.Array(items)) -> items
    _ -> []
  }
}

fn artifact_entry(id: String, entry: value.Value) -> HeadEntry {
  let disposition = case artifact_text(entry, "typed_kind") {
    "ActiveCandidate" ->
      ActiveCandidate(artifact_text(entry, "typed_commit_id"))
    "Held" ->
      Held(artifact_text(entry, "hold_id"), artifact_text(entry, "hold_reason"))
    "Incorporated" -> Incorporated(artifact_text(entry, "content_sha256"))
    "Superseded" ->
      Superseded(
        artifact_text(entry, "by_commit"),
        artifact_text(entry, "rationale"),
      )
    _ -> Unclassified
  }
  HeadEntry(id, True, disposition)
}

fn typed_entry_complete(entry: value.Value) -> Bool {
  let kind = artifact_text(entry, "typed_kind")
  let id_present = artifact_text(entry, "commit_id") != ""
  let kind_valid = case kind {
    "ActiveCandidate" -> artifact_text(entry, "typed_commit_id") != ""
    "Held" ->
      artifact_text(entry, "hold_id") != ""
      && artifact_text(entry, "hold_reason") != ""
    "Incorporated" -> artifact_text(entry, "content_sha256") != ""
    "Superseded" ->
      artifact_text(entry, "by_commit") != ""
      && artifact_text(entry, "rationale") != ""
    _ -> False
  }
  id_present && kind_valid
}

fn held_entry_ids(entries: List(HeadEntry)) -> List(String) {
  list.filter_map(entries, fn(entry) {
    case entry.disposition {
      Held(_, _) -> Ok(entry.id)
      _ -> Error(Nil)
    }
  })
}

fn read_t21_disposition_artifact() -> Result(String, simplifile.FileError) {
  case
    simplifile.read(
      "governance/planning/20261030-1052-t21-workspace-and-head-disposition.json",
    )
  {
    Ok(content) -> Ok(content)
    Error(_) ->
      simplifile.read(
        "../../governance/planning/20261030-1052-t21-workspace-and-head-disposition.json",
      )
  }
}

pub fn actual_t21_disposition_artifact_validates_through_typed_gate_test() {
  let assert Ok(raw) = read_t21_disposition_artifact()
  let assert Ok(root) = json.parse(raw, value.decoder())
  let workspaces = artifact_array(root, "registered_workspaces")
  let heads = artifact_array(root, "visible_heads")
  list.length(workspaces) |> should.equal(143)
  list.length(heads) |> should.equal(147)
  list.all(workspaces, typed_entry_complete) |> should.be_true()
  list.all(heads, typed_entry_complete) |> should.be_true()

  let workspace_entries =
    list.map(workspaces, fn(entry) {
      artifact_entry(artifact_text(entry, "name"), entry)
    })
  let head_entries =
    list.map(heads, fn(entry) {
      artifact_entry(artifact_text(entry, "commit_id"), entry)
    })
  let workspace_ids = list.map(workspace_entries, fn(entry) { entry.id })
  let head_ids = list.map(head_entries, fn(entry) { entry.id })
  let workspace_holds = held_entry_ids(workspace_entries)
  let head_holds = held_entry_ids(head_entries)

  validate_reconciliation(workspace_ids, workspace_holds, workspace_entries)
  |> should.equal(Ok(143))
  validate_reconciliation(head_ids, head_holds, head_entries)
  |> should.equal(Ok(147))
  list.contains(workspace_holds, "client-source-editor-20261028-1514")
  |> should.be_true()

  let assert Ok(client_source) =
    list.find(workspaces, fn(entry) {
      artifact_text(entry, "name") == "client-source-editor-20261028-1514"
    })
  artifact_text(client_source, "hold_id")
  |> should.equal("uos/development-harness/client-source/20261028-1514")
  artifact_text(client_source, "hold_reason")
  |> should.equal("Preserved byte-for-byte per SourceFX source4-test-2219 hold")

  let assert Ok(canonical) =
    list.find(workspaces, fn(entry) {
      artifact_text(entry, "name") == "default"
    })
  artifact_text(canonical, "typed_kind") |> should.equal("ActiveCandidate")
  artifact_text(canonical, "typed_commit_id") |> should.not_equal("")
}
