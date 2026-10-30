//// T17 acceptance tests for MCP server facilities: principal-partitioned
//// resources, advisory-only prompts, durable Sa-plan task handles, cancellation
//// acknowledgement semantics, subscription isolation, and backpressure.

import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/prompts
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/task_extension
import cepaf_gleam/mcp/types
import gleam/dict
import gleam/int
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// Principals
// ---------------------------------------------------------------------------

fn principal_a() -> principal.Principal {
  principal.from_launcher_env(
    actor: "actor-a",
    client: types.ClientProfile("facilities-test"),
    workspace_root: "/ws/shared",
    session_id: "session-a",
  )
}

fn principal_b() -> principal.Principal {
  principal.from_launcher_env(
    actor: "actor-b",
    client: types.ClientProfile("facilities-test"),
    workspace_root: "/ws/shared",
    session_id: "session-b",
  )
}

fn principal_a_other_workspace() -> principal.Principal {
  principal.from_launcher_env(
    actor: "actor-a",
    client: types.ClientProfile("facilities-test"),
    workspace_root: "/ws/other",
    session_id: "session-a2",
  )
}

fn private_entry() -> resources.ResourceEntry {
  resources.ResourceEntry(
    uri: "uos://ws/private/report",
    title: "Private Report",
    mime_type: "text/plain",
    visibility: resources.PrivatePrincipalResource,
    owner_actor: "actor-a",
    workspace_root: "/ws/shared",
    content: "principal-a-secret",
  )
}

// ---------------------------------------------------------------------------
// 1. Resources
// ---------------------------------------------------------------------------

pub fn private_resource_cache_never_crosses_principal_test() {
  let registry = resources.registry([private_entry()], [])

  // Pagination bounds are refused before any cache access.
  let assert Error(low) =
    resources.list_resources(
      registry,
      resources.empty_cache(),
      principal_a(),
      0,
      0,
    )
  low.code |> should.equal("INVALID_PAGE_LIMIT")

  let assert Error(high) =
    resources.list_resources(
      registry,
      resources.empty_cache(),
      principal_a(),
      resources.page_max + 1,
      0,
    )
  high.code |> should.equal("INVALID_PAGE_LIMIT")

  // URI validation: foreign scheme, traversal, NUL, and credential markers.
  let assert Error(scheme) =
    resources.read_resource(
      registry,
      resources.empty_cache(),
      principal_a(),
      "file:///etc/passwd",
    )
  scheme.code |> should.equal("INVALID_RESOURCE_URI")

  let assert Error(traversal) =
    resources.read_resource(
      registry,
      resources.empty_cache(),
      principal_a(),
      "uos://ws/../private/report",
    )
  traversal.code |> should.equal("INVALID_RESOURCE_URI")

  let assert Error(nul) =
    resources.read_resource(
      registry,
      resources.empty_cache(),
      principal_a(),
      "uos://ws/private/\u{0000}report",
    )
  nul.code |> should.equal("INVALID_RESOURCE_URI")

  list.each([".env", ".ssh", ".sqlite3", ".key", ".pem"], fn(marker) {
    let assert Error(credential) =
      resources.read_resource(
        registry,
        resources.empty_cache(),
        principal_a(),
        "uos://ws/private/secret" <> marker,
      )
    credential.code |> should.equal("INVALID_RESOURCE_URI")
  })

  // Principal A reads and caches the private resource.
  let assert Ok(#(entry, cache_a)) =
    resources.read_resource(
      registry,
      resources.empty_cache(),
      principal_a(),
      "uos://ws/private/report",
    )
  entry.content |> should.equal("principal-a-secret")
  dict.size(cache_a.entries) |> should.equal(1)
  dict.has_key(cache_a.entries, #(
    "actor-a",
    "/ws/shared",
    "uos://ws/private/report",
  ))
  |> should.be_true()

  // Principal B shares the workspace but not the actor. The read is refused
  // before the cache is consulted, and A's cache is untouched.
  let assert Error(cross) =
    resources.read_resource(
      registry,
      cache_a,
      principal_b(),
      "uos://ws/private/report",
    )
  cross.code |> should.equal("CROSS_PRINCIPAL_RESOURCE_FORBIDDEN")
  dict.size(cache_a.entries) |> should.equal(1)
  dict.has_key(cache_a.entries, #(
    "actor-b",
    "/ws/shared",
    "uos://ws/private/report",
  ))
  |> should.be_false()

  // A principal in another workspace is refused with a workspace mismatch.
  let assert Error(workspace) =
    resources.read_resource(
      registry,
      cache_a,
      principal_a_other_workspace(),
      "uos://ws/private/report",
    )
  workspace.code |> should.equal("PRINCIPAL_WORKSPACE_MISMATCH")

  // Listing as B never discloses A's private resource.
  let assert Ok(#(b_entries, _)) =
    resources.list_resources(registry, cache_a, principal_b(), 100, 0)
  b_entries |> should.equal([])

  // Template listing is bound to the principal workspace.
  let template =
    resources.ResourceTemplate(
      uri_template: "uos://ws/{path}",
      name: "workspace",
      description: "Workspace template",
    )
  let assert Ok(templates) =
    resources.list_templates(resources.registry([], [template]), principal_a())
  templates |> list.length |> should.equal(1)
}

// ---------------------------------------------------------------------------
// 2. Prompts
// ---------------------------------------------------------------------------

pub fn prompt_cannot_authorize_effect_test() {
  let registry = [
    prompts.PromptSpec(
      name: "summarize_plan",
      description: "Summarize a plan",
      required_args: ["plan_id"],
      template_body: "Summarize {{plan_id}}",
    ),
    prompts.PromptSpec(
      name: "sampling",
      description: "Deprecated sampling prompt",
      required_args: [],
      template_body: "noop",
    ),
    prompts.PromptSpec(
      name: "roots",
      description: "Deprecated roots prompt",
      required_args: [],
      template_body: "noop",
    ),
  ]

  // Deprecated prompts are not advertised.
  let listed = prompts.list_prompts(registry)
  listed |> list.length |> should.equal(1)
  list.any(listed, fn(spec) { spec.name == "sampling" || spec.name == "roots" })
  |> should.be_false()

  // Deprecated prompts are refused even when requested directly, including
  // case/whitespace-normalized variants.
  let assert Error(deprecated_sampling) =
    prompts.get_prompt(registry, "sampling", dict.new())
  deprecated_sampling.code |> should.equal("DEPRECATED_PROMPT_FORBIDDEN")

  let assert Error(deprecated_roots) =
    prompts.get_prompt(registry, "  ROOTS  ", dict.new())
  deprecated_roots.code |> should.equal("DEPRECATED_PROMPT_FORBIDDEN")

  // A rendered prompt is advisory only and never carries effect authority.
  let assert Ok(rendered) =
    prompts.get_prompt(
      registry,
      "summarize_plan",
      dict.from_list([#("plan_id", "plan-1")]),
    )
  rendered.advisory_only |> should.be_true()
  rendered.effect_authority |> should.be_false()
  rendered.messages
  |> should.equal(["Summarize plan-1"])

  // Authority-escalation arguments are refused.
  list.each(
    ["grant_id", "authorize_effect", "bypass_sa_plan", "execute_effect"],
    fn(escalation) {
      let assert Error(refused) =
        prompts.get_prompt(
          registry,
          "summarize_plan",
          dict.from_list([#("plan_id", "plan-1"), #(escalation, "true")]),
        )
      refused.code |> should.equal("PROMPT_CANNOT_AUTHORIZE_EFFECT")
    },
  )

  // Required arguments are enforced.
  let assert Error(missing) =
    prompts.get_prompt(registry, "summarize_plan", dict.new())
  missing.code |> should.equal("PROMPT_MISSING_ARGUMENT")
}

// ---------------------------------------------------------------------------
// 3. Durable task extension
// ---------------------------------------------------------------------------

fn running_record() -> task_extension.SaPlanTaskRecord {
  task_extension.SaPlanTaskRecord(
    plan_id: "plan-1",
    task_id: "task-1",
    owner_actor: "actor-a",
    attempt: 1,
    persisted_in_sa_plan: True,
    lifecycle: task_extension.RunningTask,
  )
}

pub fn durable_handle_persisted_before_reply_test() {
  let unpersisted =
    task_extension.SaPlanTaskRecord(
      ..running_record(),
      persisted_in_sa_plan: False,
    )
  let assert Error(not_persisted) =
    task_extension.issue_durable_handle(
      types.Modern20260728,
      True,
      principal_a(),
      unpersisted,
      2000,
      1000,
    )
  not_persisted.code |> should.equal("UNPERSISTED_TASK_HANDLE_FORBIDDEN")

  // Legacy profile cannot negotiate the extension.
  let assert Error(legacy) =
    task_extension.issue_durable_handle(
      types.Legacy20241105,
      True,
      principal_a(),
      running_record(),
      2000,
      1000,
    )
  legacy.code |> should.equal("TASK_EXTENSION_NOT_NEGOTIATED")

  // Modern profile without explicit negotiation is refused.
  let assert Error(unnegotiated) =
    task_extension.issue_durable_handle(
      types.Modern20260728,
      False,
      principal_a(),
      running_record(),
      2000,
      1000,
    )
  unnegotiated.code |> should.equal("TASK_EXTENSION_NOT_NEGOTIATED")

  // A persisted, owner-bound, unexpired Sa-plan record yields a valid handle.
  let assert Ok(handle) =
    task_extension.issue_durable_handle(
      types.Modern20260728,
      True,
      principal_a(),
      running_record(),
      2000,
      1000,
    )
  handle.plan_id |> should.equal("plan-1")
  handle.task_id |> should.equal("task-1")
  handle.owner_actor |> should.equal("actor-a")
  handle.expires_at_ms |> should.equal(2000)

  // Owner binding is enforced.
  let assert Error(foreign) =
    task_extension.issue_durable_handle(
      types.Modern20260728,
      True,
      principal_b(),
      running_record(),
      2000,
      1000,
    )
  foreign.code |> should.equal("CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
}

// ---------------------------------------------------------------------------
// 4. Cancellation acknowledgement, subscriptions, and backpressure
// ---------------------------------------------------------------------------

pub fn cancel_ack_is_not_effect_stopped_test() {
  let handle_id = "handle-1"
  let store =
    task_extension.register(
      task_extension.empty_store(),
      handle_id,
      running_record(),
    )

  // A foreign principal may not request cancellation of another's handle.
  let assert Error(cross_cancel) =
    task_extension.request_cancel(store, principal_b(), handle_id)
  cross_cancel.code |> should.equal("CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")

  // A cancel request acknowledges but never claims the effect stopped.
  let assert Ok(#(receipt, after_cancel)) =
    task_extension.request_cancel(store, principal_a(), handle_id)
  receipt.cancel_acknowledged |> should.be_true()
  receipt.effect_stopped |> should.be_false()

  // A foreign principal may not confirm another's worker stop.
  let assert Error(cross_stop) =
    task_extension.confirm_worker_stopped(
      after_cancel,
      principal_b(),
      handle_id,
      "candidate-1",
      "whatever",
    )
  cross_stop.code |> should.equal("CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")

  // A stop confirmation without a digest is refused.
  let assert Error(empty_digest) =
    task_extension.confirm_worker_stopped(
      after_cancel,
      principal_a(),
      handle_id,
      "candidate-1",
      "  ",
    )
  empty_digest.code |> should.equal("EMPTY_STOP_RECEIPT")

  // A forged stop receipt digest is refused.
  let assert Error(forged_digest) =
    task_extension.confirm_worker_stopped(
      after_cancel,
      principal_a(),
      handle_id,
      "candidate-1",
      "forged-receipt-sha256",
    )
  forged_digest.code |> should.equal("INVALID_STOP_RECEIPT_DIGEST")
  receipt.effect_stopped |> should.be_false()

  // Only the exact expected worker stop receipt digest flips effect_stopped.
  let valid_digest =
    task_extension.expected_stop_receipt_digest(handle_id, 1, "candidate-1")
  let assert Ok(#(confirmation, _)) =
    task_extension.confirm_worker_stopped(
      after_cancel,
      principal_a(),
      handle_id,
      "candidate-1",
      valid_digest,
    )
  confirmation.effect_stopped |> should.be_true()
  confirmation.lifecycle |> should.equal(task_extension.CancelledStopped)

  // Subscription profile and principal isolation.
  let assert Ok(store) =
    subscriptions.subscribe(
      subscriptions.empty_store(),
      types.Modern20260728,
      principal_a(),
      "sub-1",
      subscriptions.ResourceSubscription("uos://ws/private/report"),
    )

  // Duplicate subscription IDs are refused rather than overwriting the owner.
  let assert Error(duplicate) =
    subscriptions.subscribe(
      store,
      types.Modern20260728,
      principal_b(),
      "sub-1",
      subscriptions.ResourceSubscription("uos://ws/private/report"),
    )
  duplicate.code |> should.equal("SUBSCRIPTION_ID_ALREADY_EXISTS")

  let assert Ok(_) =
    subscriptions.read_subscription(
      store,
      types.Modern20260728,
      principal_a(),
      "sub-1",
    )

  let assert Error(profile_mismatch) =
    subscriptions.read_subscription(
      store,
      types.Legacy20241105,
      principal_a(),
      "sub-1",
    )
  profile_mismatch.code |> should.equal("SUBSCRIPTION_PROFILE_MISMATCH")

  let assert Error(foreign_principal) =
    subscriptions.read_subscription(
      store,
      types.Modern20260728,
      principal_b(),
      "sub-1",
    )
  foreign_principal.code
  |> should.equal("CROSS_PRINCIPAL_SUBSCRIPTION_FORBIDDEN")

  // Pending notifications are principal/profile authorized.
  let assert Error(pending_foreign) =
    subscriptions.pending_notifications(
      store,
      types.Modern20260728,
      principal_b(),
      "sub-1",
    )
  pending_foreign.code
  |> should.equal("CROSS_PRINCIPAL_SUBSCRIPTION_FORBIDDEN")

  let assert Error(pending_profile) =
    subscriptions.pending_notifications(
      store,
      types.Legacy20241105,
      principal_a(),
      "sub-1",
    )
  pending_profile.code |> should.equal("SUBSCRIPTION_PROFILE_MISMATCH")

  let assert Error(unsubscribe_mismatch) =
    subscriptions.unsubscribe(
      store,
      types.Modern20260728,
      principal_b(),
      "sub-1",
    )
  unsubscribe_mismatch.code
  |> should.equal("CROSS_PRINCIPAL_SUBSCRIPTION_FORBIDDEN")

  // Bounded notification queue: 128 pending, the 129th is backpressured.
  let full =
    int.range(
      from: 0,
      to: subscriptions.max_pending_notifications,
      with: store,
      run: fn(acc, index) {
        let assert Ok(next) =
          subscriptions.push_notification(
            acc,
            "sub-1",
            "n" <> int.to_string(index),
          )
        next
      },
    )
  let assert Ok(pending) =
    subscriptions.pending_notifications(
      full,
      types.Modern20260728,
      principal_a(),
      "sub-1",
    )
  pending
  |> list.length
  |> should.equal(subscriptions.max_pending_notifications)

  let assert Error(backpressure) =
    subscriptions.push_notification(full, "sub-1", "overflow")
  backpressure.code |> should.equal("SUBSCRIPTION_BACKPRESSURE_LIMIT")
}
