//// Track A: live gateway transport and immutable candidate regression tests.

import cepaf_gleam/harness/admission as harness_admission
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/profiles/modern
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/task_extension
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/version
import cepaf_gleam/mcp/wire
import cepaf_gleam/web/server as web_server
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as otp_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn workspace_command(
  path: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn fixture_time() -> Int

pub fn workspace_subprocess_accepts_workspace_and_absolute_temp_cwd_test() {
  workspace_command("/usr/bin/pwd", [], root, 3000)
  |> should.equal(Ok(#(0, root <> "\n")))
  let temporary = "/tmp/uos-c04-workspace-" <> int.to_string(fixture_time())
  let assert Ok(Nil) = simplifile.create_directory(temporary)
  let output = workspace_command("/usr/bin/pwd", [], temporary, 3000)
  let assert Ok(Nil) = simplifile.delete(temporary)
  output |> should.equal(Ok(#(0, temporary <> "\n")))
}

pub fn workspace_subprocess_rejects_invalid_cwd_and_time_bounds_test() {
  list.each(["relative", root <> "/../uos", "/does-not-exist/uos-c04"], fn(cwd) {
    workspace_command("/usr/bin/pwd", [], cwd, 3000)
    |> should.equal(Error("backend_spawn_failed"))
  })
  list.each([0, -1, 60_001], fn(timeout_ms) {
    workspace_command("/usr/bin/pwd", [], root, timeout_ms)
    |> should.equal(Error("invalid_resource_bound"))
  })
  workspace_command("/usr/bin/printf", ["%s", "arg;$(literal)"], root, 3000)
  |> should.equal(Ok(#(0, "arg;$(literal)")))
}

pub fn workspace_subprocess_bounds_timeout_output_and_preserves_exit_code_test() {
  workspace_command("/usr/bin/sleep", ["1"], root, 80)
  |> should.equal(Error("timeout"))
  workspace_command("/usr/bin/false", [], root, 3000)
  |> should.equal(Ok(#(1, "")))
  workspace_command("/usr/bin/head", ["-c", "1048576", "/dev/zero"], root, 3000)
  |> fn(output) {
    let assert Ok(#(0, bytes)) = output
    string.byte_size(bytes) |> should.equal(1_048_576)
  }
  let overflow =
    workspace_command(
      "/usr/bin/head",
      ["-c", "1048577", "/dev/zero"],
      root,
      3000,
    )
  case overflow {
    Error("backend_output_or_process_failure") | Error("output_limit") -> Nil
    _ -> panic as "Output overflow must fail closed"
  }
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)

const root = "/home/an/NAS-setup/uos"

const now = 100_000

const origin = "https://nas-1.tail55d152.ts.net:4101"

fn reviewed_scope(task: String) -> harness_admission.Scope {
  harness_admission.Scope(
    "private-plan",
    task,
    [],
    [],
    [],
    [],
    "fixture-risk.json",
    [],
    [],
  )
}

fn task_row(
  state: String,
  worker: Option(String),
  deadline: Option(Int),
) -> dev.TaskRecord {
  dev.TaskRecord(state, worker, 7, deadline, 0, None, None)
}

pub fn observed_preattach_fences_never_invent_executing_authority_test() {
  let state = fixture()
  let p = test_principal("private-worker", "observed-preattach")
  let grant = successor_fixture().grant
  let #(raw, msg) = private_request("harness_status", json.object([]))
  list.each(
    [
      #(task_row("available", None, None), "TASK_FENCE_NOT_EXECUTING"),
      #(
        task_row(
          "completed",
          Some("private-worker"),
          Some(9_000_000_000_000_000),
        ),
        "TASK_FENCE_NOT_EXECUTING",
      ),
      #(
        task_row("unknown", Some("private-worker"), Some(9_000_000_000_000_000)),
        "TASK_FENCE_NOT_EXECUTING",
      ),
      #(
        task_row("executing", Some("foreign"), Some(9_000_000_000_000_000)),
        "PRINCIPAL_WORKER_MISMATCH",
      ),
      #(
        task_row("executing", None, Some(9_000_000_000_000_000)),
        "PRINCIPAL_WORKER_MISMATCH",
      ),
      #(
        task_row(
          "executing",
          Some("private-worker"),
          Some({ now - 1 } * 1_000_000),
        ),
        "TASK_LEASE_EXPIRED",
      ),
      #(
        task_row("executing", Some("private-worker"), None),
        "TASK_LEASE_EXPIRED",
      ),
      #(
        task_row("executing", Some("private-worker"), Some(0)),
        "TASK_LEASE_EXPIRED",
      ),
      #(
        task_row("executing", Some("private-worker"), Some(-1)),
        "TASK_LEASE_EXPIRED",
      ),
    ],
    fn(case_) {
      let #(ticket, fence) =
        gateway.project_observed_preattach_fence(
          grant,
          "private-plan",
          "private-task",
          case_.0,
          now,
          root,
        )
      ticket.expires_at_ms |> should.equal(grant.expires_us / 1000)
      fence.worker_id |> should.equal(option.unwrap(case_.0.worker, ""))
      fence.attempt |> should.equal(7)
      fence.grant |> should.equal(Some(ticket))
      let #(outcome, _) =
        gateway.dispatch_private_with_resolver(
          state,
          p,
          "successor",
          raw,
          msg,
          now,
          fn(_, route, tool, _, _) {
            Ok(
              gateway.PrivateBinding(
                Some(route_convergence.RouteGrant(route, [tool], ticket)),
                Some(fence),
                fn() {
                  panic as "Unobserved/foreign/expired task must never execute"
                },
              ),
            )
          },
        )
      refusal(outcome, case_.1)
    },
  )
  let row =
    task_row(
      "executing",
      Some("private-worker"),
      Some({ now + 5000 } * 1_000_000),
    )
  let #(ticket, fence) =
    gateway.project_observed_preattach_fence(
      grant,
      "private-plan",
      "private-task",
      row,
      now,
      root,
    )
  ticket.expires_at_ms |> should.equal(grant.expires_us / 1000)
  fence.lease_until_ms |> should.equal(now + 5000)
  let #(outcome, _) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        Ok(
          gateway.PrivateBinding(
            Some(route_convergence.RouteGrant(route, [tool], ticket)),
            Some(fence),
            fn() { #(Ok("{}"), None) },
          ),
        )
      },
    )
  completed(outcome) |> should.equal("{}")
  let expired_grant = harness_admission.Grant(..grant, expires_us: now * 1000)
  let #(expired_ticket, expired_fence) =
    gateway.project_observed_preattach_fence(
      expired_grant,
      "private-plan",
      "private-task",
      row,
      now,
      root,
    )
  let #(outcome, _) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        Ok(
          gateway.PrivateBinding(
            Some(route_convergence.RouteGrant(route, [tool], expired_ticket)),
            Some(expired_fence),
            fn() { panic as "Grant expiry must be checked independently" },
          ),
        )
      },
    )
  refusal(outcome, "ROUTE_GRANT_EXPIRED")
}

pub fn preattach_selection_requires_explicit_task_for_task_acting_tools_test() {
  let grant =
    harness_admission.Grant(..successor_fixture().grant, scopes: [
      reviewed_scope("first"),
      reviewed_scope("live"),
    ])
  list.each(["harness_claim", "harness_attach", "harness_assess"], fn(tool) {
    list.each(
      [
        value.Object([]),
        value.Object([#("plan", value.Text("private-plan"))]),
        value.Object([
          #("plan", value.Text("private-plan")),
          #("task", value.Boolean(False)),
        ]),
      ],
      fn(args) {
        gateway.observe_preattach_scope(grant, tool, args, now, fn(_) {
          panic as "Explicit scope must precede any task read"
        })
        |> should.equal(Error("explicit_plan_and_task_required"))
      },
    )
    let args =
      value.Object([
        #("plan", value.Text("private-plan")),
        #("task", value.Text("live")),
      ])
    let row =
      task_row(
        "executing",
        Some(grant.worker),
        Some({ now + 5000 } * 1_000_000),
      )
    gateway.observe_preattach_scope(grant, tool, args, now, fn(scope) {
      scope.task |> should.equal("live")
      Ok(row)
    })
    |> should.equal(Ok(Some(#(reviewed_scope("live"), row))))
    gateway.observe_preattach_scope(
      grant,
      tool,
      value.Object([
        #("plan", value.Text("private-plan")),
        #("task", value.Text("foreign")),
      ]),
      now,
      fn(_) { panic as "Scope lookup must precede task read" },
    )
    |> should.equal(Error("task_not_in_reviewed_grant"))
  })
}

pub fn preattach_general_tools_scan_owned_live_scope_and_preserve_nonexecuting_fallback_test() {
  let grant =
    harness_admission.Grant(..successor_fixture().grant, scopes: [
      reviewed_scope("first"),
      reviewed_scope("foreign"),
      reviewed_scope("expired"),
      reviewed_scope("live"),
    ])
  let available = task_row("available", None, None)
  let live =
    task_row("executing", Some(grant.worker), Some({ now + 5000 } * 1_000_000))
  list.each(
    [
      "harness_status",
      "harness_clock",
      "harness_heartbeat",
      "harness_reconcile",
    ],
    fn(tool) {
      gateway.observe_preattach_scope(
        grant,
        tool,
        value.Object([]),
        now,
        fn(scope) {
          case scope.task {
            "first" -> Ok(available)
            "foreign" -> Ok(dev.TaskRecord(..live, worker: Some("foreign")))
            "expired" ->
              Ok(
                dev.TaskRecord(
                  ..live,
                  lease_until_ns: Some({ now - 1 } * 1_000_000),
                ),
              )
            _ -> Ok(live)
          }
        },
      )
      |> should.equal(Ok(Some(#(reviewed_scope("live"), live))))
      gateway.observe_preattach_scope(grant, tool, value.Object([]), now, fn(_) {
        Ok(available)
      })
      |> should.equal(Ok(Some(#(reviewed_scope("first"), available))))
      gateway.observe_preattach_scope(grant, tool, value.Object([]), now, fn(_) {
        Error("unavailable")
      })
      |> should.equal(Ok(None))
      gateway.observe_preattach_scope(
        grant,
        tool,
        value.Object([
          #("plan", value.Text("private-plan")),
          #("task", value.Text("first")),
        ]),
        now,
        fn(scope) {
          scope.task |> should.equal("first")
          Ok(available)
        },
      )
      |> should.equal(Ok(Some(#(reviewed_scope("first"), available))))
    },
  )
}

fn dropped_commit_actor(
  state: gateway.GatewayState,
  reply_to_snapshot: Bool,
) -> process.Subject(gateway.Message) {
  let ready = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let inbox = process.new_subject()
      process.send(ready, inbox)
      let assert Ok(gateway.Snapshot(p, reply)) = process.receive(inbox, 2000)
      case reply_to_snapshot {
        False -> Nil
        True -> {
          process.send(reply, gateway.private_snapshot(state, p))
          let assert Ok(gateway.CommitPrivate(_, _)) =
            process.receive(inbox, 2000)
          Nil
        }
      }
    })
  let assert Ok(inbox) = process.receive(ready, 1000)
  inbox
}

pub fn private_commit_timeouts_return_exact_uncertain_receipt_after_effect_test() {
  let p = test_principal("private-worker", "timeout-receipt")
  let state = fixture()
  list.each([[], [#("intent_id", "explicit-stable")]], fn(fields) {
    let #(raw, msg) = private_request("harness_status", json.object([]))
    let msg = wire.NormalizedMessage(..msg, args: fields)
    let completed_resolver = fn(_, route, tool, _, _) {
      Ok(
        private_binding(route, tool, "private-worker", fn() {
          #(Ok("{}"), None)
        }),
      )
    }
    let #(completed_call, committed_state) =
      gateway.dispatch_private_with_resolver(
        state,
        p,
        "successor",
        raw,
        msg,
        now,
        completed_resolver,
      )
    completed(completed_call) |> should.equal("{}")
    let assert [canonical_intent_id] =
      dict.keys(committed_state.pool.ledger.entries)
    let ran = process.new_subject()
    let outcome =
      gateway.dispatch_private_actor_with_timeouts(
        dropped_commit_actor(state, True),
        p,
        "successor",
        raw,
        msg,
        fn(_, route, tool, _, _) {
          Ok(
            private_binding(route, tool, "private-worker", fn() {
              process.send(ran, True)
              #(Ok("{}"), None)
            }),
          )
        },
        1000,
        10,
      )
    process.receive(ran, 0) |> should.equal(Ok(True))
    let assert types.Uncertain(receipt) = outcome
    receipt.intent_id |> should.equal(canonical_intent_id)
    receipt.route |> should.equal("successor")
    receipt.tool |> should.equal("harness_status")
    receipt.candidate |> should.equal(state.pool.ledger.candidate)
    receipt.reason
    |> should.equal(
      "Private commit timed out after effect execution; reconcile required",
    )
    let encoded =
      gateway.standard_response(wire.IntId(71), "tools/call", outcome)
    list.each(
      [
        #("intent_id", receipt.intent_id),
        #("route", "successor"),
        #("tool", "harness_status"),
        #("candidate", receipt.candidate),
        #("retryability", "reconcile_first"),
      ],
      fn(field) {
        json.parse(
          encoded,
          decode.at(["error", "data", field.0], decode.string),
        )
        |> should.equal(Ok(field.1))
      },
    )
    let replay =
      gateway.dispatch_private_actor_with_timeouts(
        dropped_commit_actor(committed_state, True),
        p,
        "successor",
        raw,
        msg,
        fn(_, route, tool, _, _) {
          Ok(
            private_binding(route, tool, "private-worker", fn() {
              panic as "Replay must not execute"
            }),
          )
        },
        1000,
        10,
      )
    refusal(replay, "GATEWAY_TIMEOUT")
  })
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let before_effect =
    gateway.dispatch_private_actor_with_timeouts(
      dropped_commit_actor(state, False),
      p,
      "successor",
      raw,
      msg,
      fn(_, _, _, _, _) { panic as "No resolver before snapshot reply" },
      10,
      10,
    )
  refusal(before_effect, "GATEWAY_TIMEOUT")
}

pub fn successor_identity_keys_and_record_owners_are_principal_bound_test() {
  let p = test_principal("private-worker", "shared-session")
  let state = successor_fixture()
  let record = gateway.successor_session_record(p, state)
  gateway.successor_session_for_principal(p, Some(record), state.grant)
  |> should.equal(Ok(state))
  let principals = [
    p,
    test_principal("other-worker", "shared-session"),
    test_principal("private-worker", "other-session"),
    principal.from_http_auth_middleware(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "shared-session",
    ),
    principal.from_signed_zenoh_envelope(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "shared-session",
    ),
    principal.from_launcher_env(
      "private-worker",
      types.ClientProfile("pi"),
      root,
      "shared-session",
    ),
  ]
  let keys = list.map(principals, gateway.successor_session_key)
  list.length(list.unique(keys)) |> should.equal(6)
  list.each(list.drop(principals, 1), fn(foreign) {
    let assert Error(err) =
      gateway.successor_session_for_principal(
        foreign,
        Some(record),
        state.grant,
      )
    err.code |> should.equal("CROSS_PRINCIPAL_SUCCESSOR_SESSION_FORBIDDEN")
  })
  let assert Error(err) =
    gateway.successor_session_for_principal(
      p,
      Some(record),
      harness_admission.Grant(..state.grant, digest: string.repeat("f", 64)),
    )
  err.code |> should.equal("SUCCESSOR_SESSION_GRANT_CHANGED")
  let confusing_a =
    principal.from_launcher_env(
      "a:stdio",
      types.ClientProfile("b"),
      root,
      "c:λ",
    )
  let confusing_b =
    principal.from_launcher_env(
      "a",
      types.ClientProfile("stdio:b"),
      root,
      "c:λ",
    )
  {
    gateway.successor_session_key(confusing_a)
    == gateway.successor_session_key(confusing_b)
  }
  |> should.be_false
  let first_default = gateway.default_stdio_session_id()
  string.starts_with(first_default, "stdio:") |> should.be_true
  { first_default == gateway.default_stdio_session_id() } |> should.be_false
}

pub fn successor_store_isolates_same_session_across_transport_and_client_test() {
  let principals = [
    test_principal("private-worker", "same-session"),
    principal.from_http_auth_middleware(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "same-session",
    ),
    principal.from_signed_zenoh_envelope(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "same-session",
    ),
    principal.from_launcher_env(
      "private-worker",
      types.ClientProfile("pi"),
      root,
      "same-session",
    ),
    test_principal("private-worker", "other-session"),
  ]
  let #(state, _) =
    list.fold(principals, #(fixture(), 0), fn(acc, p) {
      let #(state, n) = acc
      // Separate logical requests avoid canonical effect replay, whose owner
      // deliberately remains stable across transport reconnects.
      let #(raw, msg) =
        private_request(
          "harness_status",
          json.object([#("request", json.int(n))]),
        )
      let #(outcome, next) =
        gateway.dispatch_private_with_resolver(
          state,
          p,
          "successor",
          raw,
          msg,
          now,
          fn(_, route, tool, _, current) {
            current |> should.equal(None)
            Ok(
              private_binding(route, tool, "private-worker", fn() {
                #(
                  Ok("{}"),
                  Some(
                    successor_mcp.State(
                      ..successor_fixture(),
                      initialized: True,
                    ),
                  ),
                )
              }),
            )
          },
        )
      completed(outcome) |> should.equal("{}")
      #(next, n + 1)
    })
  dict.size(state.successor_sessions) |> should.equal(5)
  list.each(principals, fn(p) {
    let assert Ok(record) =
      dict.get(state.successor_sessions, gateway.successor_session_key(p))
    let assert Ok(saved) =
      gateway.successor_session_for_principal(
        p,
        Some(record),
        successor_fixture().grant,
      )
    saved.initialized |> should.be_true
  })
}

pub fn private_pure_tool_precheck_precedes_resolver_and_all_admission_observations_test() {
  let state = fixture()
  let p = test_principal("private-worker", "cheap-precheck")
  list.each(
    [
      #("successor", "unknown", [], "UNKNOWN_ROUTE_OR_TOOL"),
      #("development", "system_health", [], "UNKNOWN_ROUTE_OR_TOOL"),
      #(
        "development",
        "harness_status",
        [#("_client_schema_digest", "wrong")],
        "SCHEMA_MIGRATION_REQUIRED",
      ),
      #(
        "successor",
        "harness_status",
        [#("_client_schema_digest", "wrong")],
        "SCHEMA_MIGRATION_REQUIRED",
      ),
    ],
    fn(attempt) {
      let #(raw, msg) = private_request(attempt.1, json.object([]))
      let msg = wire.NormalizedMessage(..msg, args: attempt.2)
      let #(outcome, _) =
        gateway.dispatch_private_with_resolver(
          state,
          p,
          attempt.0,
          raw,
          msg,
          now,
          fn(_, _, _, _, _) { panic as "Precheck must precede resolver" },
        )
      refusal(outcome, attempt.3)
    },
  )
}

pub fn successor_sibling_workspace_rebind_preserves_principal_labels_and_rejects_foreign_roots_test() {
  let sibling = root <> "/.uos-workspaces/fable-w4"
  let initial = fixture()
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let principals = [
    test_principal("private-worker", "sibling-stdio"),
    principal.from_http_auth_middleware(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "sibling-http",
    ),
    principal.from_signed_zenoh_envelope(
      "private-worker",
      types.ClientProfile("codex"),
      root,
      "sibling-zenoh",
    ),
    principal.from_launcher_env(
      "private-worker",
      types.ClientProfile("codex"),
      sibling,
      "sibling-direct",
    ),
  ]
  list.each(principals, fn(p) {
    let p =
      principal.apply_untrusted_payload_labels(
        p,
        Some("audit-actor"),
        Some("audit-client"),
        Some("audit-header"),
      )
    let resolver = fn(_, route, tool, _, _) {
      let ticket =
        admission.GrantTicket(..private_ticket(), workspace_root: sibling)
      let fence =
        admission.TaskFence(
          "private-plan",
          "private-task",
          "private-worker",
          1,
          admission.TaskExecuting,
          ticket.expires_at_ms,
          Some(ticket),
        )
      Ok(
        gateway.PrivateBinding(
          Some(route_convergence.RouteGrant(route, [tool], ticket)),
          Some(fence),
          fn() { #(Ok("{}"), Some(successor_fixture())) },
        ),
      )
    }
    let #(outcome, state) =
      gateway.dispatch_private_with_resolver(
        initial,
        p,
        "successor",
        raw,
        msg,
        now,
        resolver,
      )
    completed(outcome) |> should.equal("{}")
    let assert Ok(saved) =
      dict.get(state.successor_sessions, gateway.successor_session_key(p))
    saved.owner_actor |> should.equal(principal.actor_id(p))
    saved.owner_client |> should.equal(principal.client_profile(p).name)
    saved.owner_transport |> should.equal(principal.transport(p))
    saved.owner_session |> should.equal(principal.session_id(p))
    let Ok(binding) =
      resolver(p, "successor", "harness_status", value.Object([]), None)
    let context =
      gateway.private_route_context(root, p, "successor", binding, now)
    principal.workspace_root(context.principal) |> should.equal(sibling)
    principal.untrusted_actor_label(context.principal)
    |> should.equal(Some("audit-actor"))
    principal.untrusted_client_label(context.principal)
    |> should.equal(Some("audit-client"))
    principal.untrusted_header_actor(context.principal)
    |> should.equal(Some("audit-header"))
    // Canonical ledger owner hash includes the effective sibling root, proving
    // that the actual admitted principal was rebound, not just the ticket.
    let assert [id] = dict.keys(state.pool.ledger.entries)
    let owner =
      receipts.hash_payload("harness_status", [
        #("actor", "private-worker"),
        #("workspace", sibling),
        #("plan_id", "private-plan"),
        #("task_id", "private-task"),
        #("attempt", "1"),
        #("grant_id", private_ticket().grant_id),
      ])
    string.starts_with(id, "successor:harness_status:" <> owner <> ":")
    |> should.be_true
  })
  list.each(
    [
      #("/foreign", sibling, "PRINCIPAL_WORKSPACE_MISMATCH"),
      #(root, "/foreign", "ROUTE_GRANT_WORKSPACE_MISMATCH"),
    ],
    fn(attempt) {
      let p =
        principal.from_launcher_env(
          "private-worker",
          types.ClientProfile("codex"),
          attempt.0,
          "foreign-root",
        )
      let #(outcome, _) =
        gateway.dispatch_private_with_resolver(
          initial,
          p,
          "successor",
          raw,
          msg,
          now,
          fn(_, route, tool, _, _) {
            let ticket =
              admission.GrantTicket(
                ..private_ticket(),
                workspace_root: attempt.1,
              )
            Ok(
              gateway.PrivateBinding(
                Some(route_convergence.RouteGrant(route, [tool], ticket)),
                Some(admission.TaskFence(
                  "private-plan",
                  "private-task",
                  "private-worker",
                  1,
                  admission.TaskExecuting,
                  ticket.expires_at_ms,
                  Some(ticket),
                )),
                fn() { panic as "Foreign root must not execute" },
              ),
            )
          },
        )
      refusal(outcome, attempt.2)
    },
  )
}

pub fn gateway_owner_never_waits_for_unresponsive_supervised_gateway_test() {
  let ready = process.new_subject()
  let stalled_pid =
    process.spawn_unlinked(fn() {
      let inbox = process.new_subject()
      process.send(ready, inbox)
      let assert Ok(_) = process.receive(inbox, 2000)
      process.sleep_forever()
    })
  let assert Ok(stalled_subject) = process.receive(ready, 1000)
  let fake =
    supervisor.SupervisedGateway(
      "nonreplying-child",
      stalled_pid,
      stalled_subject,
    )
  gateway.supervised_gateway_pids_alive(fake) |> should.be_true
  let state = gateway.GatewayState(..fixture(), supervised_gateway: fake)
  let assert Ok(owner) = gateway.start_state_owner(state)
  process.unlink(owner.pid)
  let ping = process.new_subject()
  let output = process.new_subject()
  process.send(owner.data, gateway.Ping(ping))
  let #(raw, _) = private_request("system_health", json.object([]))
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  process.send(
    owner.data,
    gateway.Dispatch(
      test_principal("burst-worker", "nonblocking"),
      types.Modern20260728,
      "public",
      raw,
      msg,
      fixture_time() / 1_000_000,
      None,
      None,
      None,
      None,
      output,
    ),
  )
  process.receive(ping, 200) |> should.equal(Ok(True))
  let assert Ok(result) = process.receive(output, 200)
  completed(result) |> string.contains("healthy") |> should.be_true
  process.kill(owner.pid)
  process.kill(stalled_pid)
}

pub fn concurrent_public_observation_burst_and_ping_do_not_starve_owner_test() {
  gateway.ensure_started() |> should.be_true
  let replies = process.new_subject()
  let start = fixture_time()
  int.range(0, 24, Nil, fn(_, n) {
    let _ =
      process.spawn_unlinked(fn() {
        let #(raw, _) = private_request("system_health", json.object([]))
        let assert Some(reply) =
          gateway.handle_standard_mcp_line(
            "burst-worker",
            "codex",
            root,
            "burst-" <> int.to_string(n),
            "public",
            raw,
            now,
          )
        process.send(replies, #(
          gateway.is_running(),
          string.contains(reply, "\"isError\":false"),
        ))
      })
    Nil
  })
  int.range(0, 24, Nil, fn(_, _) {
    process.receive(replies, 1500) |> should.equal(Ok(#(True, True)))
  })
  { fixture_time() - start < 1_500_000_000 } |> should.be_true
}

pub fn private_route_bridge_admits_before_running_backend_test() {
  let state = fixture()
  let p = test_principal("private-worker", "private-session")
  let raw =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_execution_progress\",\"arguments\":{}}}"
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  let #(outcome, _) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "development",
      raw,
      msg,
      now,
      fn(_, _, _, _, _) {
        Ok(
          gateway.PrivateBinding(None, None, fn() {
            panic as "An ungranted backend must never run"
          }),
        )
      },
    )
  refusal(outcome, "ROUTE_GRANT_REQUIRED")
}

fn private_request(
  tool: String,
  args: json.Json,
) -> #(String, wire.NormalizedMessage) {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(71)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([#("name", json.string(tool)), #("arguments", args)]),
      ),
    ])
    |> json.to_string
  // The structural argument seam is intentionally independent of wire's
  // string-only argument projection, which cannot represent typed JSON.
  #(raw, wire.NormalizedMessage(wire.IntId(71), "tools/call", [], ""))
}

fn private_ticket() -> admission.GrantTicket {
  admission.GrantTicket(
    "private-reviewed-fixture",
    types.TaskScopedMutation,
    False,
    9_999_999_999_999,
    root,
  )
}

fn private_binding(
  route: String,
  tool: String,
  worker: String,
  execute: fn() -> #(Result(String, String), Option(successor_mcp.State)),
) -> gateway.PrivateBinding {
  let ticket = private_ticket()
  gateway.PrivateBinding(
    Some(route_convergence.RouteGrant(route, [tool], ticket)),
    Some(admission.TaskFence(
      "private-plan",
      "private-task",
      worker,
      1,
      admission.TaskExecuting,
      ticket.expires_at_ms,
      Some(ticket),
    )),
    execute,
  )
}

fn successor_fixture() -> successor_mcp.State {
  successor_mcp.initial(harness_admission.Grant(
    "private-reviewed-fixture",
    "fixture/grant.json",
    string.repeat("a", 64),
    "fixture-launcher",
    "private-worker",
    "fixture-host",
    "fixture-boot",
    9_999_999_999_999_000,
    [],
    "",
    "fixture/review.json",
    string.repeat("b", 64),
  ))
}

pub fn private_live_ungranted_routes_and_all_route_tool_lists_test() {
  list.each(
    [
      #("development", "harness_execution_progress"),
      #("successor", "harness_status"),
      #("successor", "harness_write_file"),
    ],
    fn(pair) {
      let #(raw, _) = private_request(pair.1, json.object([]))
      let assert Some(reply) =
        gateway.handle_standard_mcp_line(
          "ungranted-S01",
          "codex",
          root,
          "ungranted-S01",
          pair.0,
          raw,
          now,
        )
      string.contains(reply, "ROUTE_GRANT_REQUIRED") |> should.be_true
    },
  )
  let state = fixture()
  list.each(
    [#("public", 53), #("development", 21), #("successor", 15)],
    fn(pair) {
      let raw = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"
      let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
      let #(outcome, _) =
        gateway.dispatch_normalized(
          state,
          test_principal("private-worker", "lists"),
          types.Modern20260728,
          pair.0,
          raw,
          msg,
          now,
        )
      let assert Ok(tools) =
        json.parse(
          completed(outcome),
          decode.at(["tools"], decode.list(decode.dynamic)),
        )
      list.length(tools) |> should.equal(pair.1)
      let assert Some(live) =
        gateway.handle_standard_mcp_line(
          "private-worker",
          "codex",
          root,
          "S01-live-lists",
          pair.0,
          raw,
          now,
        )
      let assert Ok(live_tools) =
        json.parse(
          live,
          decode.at(["result", "tools"], decode.list(decode.dynamic)),
        )
      list.length(live_tools) |> should.equal(pair.1)
    },
  )
  list.length(registry.all_specs()) |> should.equal(101)
  list.each(
    [#("public", 65), #("development", 21), #("successor", 15)],
    fn(pair) {
      registry.all_specs()
      |> list.filter(fn(s) { s.route == pair.0 })
      |> list.length
      |> should.equal(pair.1)
    },
  )
}

pub fn private_development_executes_with_candidate_evidence_and_lossless_arguments_test() {
  let p = test_principal("private-worker", "dev-authenticated")
  let #(raw, msg) =
    private_request(
      "harness_execution_progress",
      json.object([
        #(
          "typed",
          json.object([
            #("flag", json.bool(True)),
            #("count", json.int(17)),
            #("items", json.array([json.null(), json.float(2.5)], fn(x) { x })),
          ]),
        ),
      ]),
    )
  let assert Ok(expected) =
    json.parse(raw, decode.at(["params", "arguments"], value.decoder()))
  let #(outcome, state) =
    gateway.dispatch_private_with_resolver(
      fixture(),
      p,
      "development",
      raw,
      msg,
      now,
      fn(_, route, tool, args, current) {
        args |> should.equal(expected)
        current |> should.equal(None)
        Ok(
          private_binding(route, tool, "private-worker", fn() {
            #(Ok(json.to_string(value.encode(args))), None)
          }),
        )
      },
    )
  let assert types.Complete(body, evidence) = outcome
  json.parse(body, value.decoder()) |> should.equal(Ok(expected))
  evidence.candidate
  |> should.equal(
    "sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663",
  )
  evidence.route |> should.equal("development")
  evidence.admission_state |> should.equal("not_admitted")
  dict.size(state.pool.ledger.entries) |> should.equal(1)
}

pub fn private_successor_threads_session_state_and_refuses_escalation_test() {
  let p = test_principal("private-worker", "successor-threaded")
  let resolver = fn(
    _,
    route,
    tool,
    _,
    current: Option(gateway.SuccessorSessionRecord),
  ) {
    let previous = case current {
      None -> successor_fixture()
      Some(s) -> s.state
    }
    Ok(
      private_binding(route, tool, "private-worker", fn() {
        #(
          Ok(json.to_string(json.bool(previous.initialized))),
          Some(successor_mcp.State(..previous, initialized: True)),
        )
      }),
    )
  }
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let #(first, state) =
    gateway.dispatch_private_with_resolver(
      fixture(),
      p,
      "successor",
      raw,
      msg,
      now,
      resolver,
    )
  completed(first) |> should.equal("false")
  let #(raw2, msg2) = private_request("harness_clock", json.object([]))
  let #(second, state) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "successor",
      raw2,
      msg2,
      now,
      resolver,
    )
  completed(second) |> should.equal("true")
  dict.size(state.successor_sessions) |> should.equal(1)
  let #(other, _) =
    gateway.dispatch_private_with_resolver(
      state,
      test_principal("private-worker", "successor-other"),
      "successor",
      raw,
      msg,
      now,
      resolver,
    )
  completed(other) |> should.equal("false")
  list.each(
    [
      #("development", "private-worker", "CROSS_ROUTE_GRANT_FORBIDDEN"),
      #("successor", "foreign-worker", "PRINCIPAL_WORKER_MISMATCH"),
    ],
    fn(attempt) {
      let #(refused, _) =
        gateway.dispatch_private_with_resolver(
          state,
          p,
          "successor",
          raw,
          msg,
          now,
          fn(_, _, tool, _, _) {
            Ok(
              private_binding(attempt.0, tool, attempt.1, fn() {
                panic as "Escalation must not invoke a backend"
              }),
            )
          },
        )
      refusal(refused, attempt.2)
    },
  )
}

pub fn private_successor_capacity_bounds_new_sessions_and_allows_existing_test() {
  let full =
    int.range(1, gateway.max_successor_sessions + 1, dict.new(), fn(store, n) {
      let p = test_principal("private-worker", "session-" <> int.to_string(n))
      dict.insert(
        store,
        gateway.successor_session_key(p),
        gateway.successor_session_record(p, successor_fixture()),
      )
    })
  let state = gateway.GatewayState(..fixture(), successor_sessions: full)
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let #(outcome, unchanged) =
    gateway.dispatch_private_with_resolver(
      state,
      test_principal("private-worker", "session-new"),
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        Ok(
          private_binding(route, tool, "private-worker", fn() {
            panic as "Capacity refusal must precede execution"
          }),
        )
      },
    )
  refusal(outcome, "SUCCESSOR_SESSION_CAPACITY_EXCEEDED")
  dict.size(unchanged.successor_sessions) |> should.equal(1024)
  let #(outcome, updated) =
    gateway.dispatch_private_with_resolver(
      state,
      test_principal("private-worker", "session-1"),
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, current) {
        Ok(
          private_binding(route, tool, "private-worker", fn() {
            #(Ok("{}"), option.map(current, fn(r) { r.state }))
          }),
        )
      },
    )
  completed(outcome) |> should.equal("{}")
  dict.size(updated.successor_sessions) |> should.equal(1024)
}

pub fn private_finish_candidate_and_missing_fence_checks_precede_effect_test() {
  let p = test_principal("private-worker", "finish-precondition")
  let #(raw, msg) = private_request("harness_finish", json.object([]))
  list.each(["development", "successor"], fn(route) {
    let #(outcome, _) =
      gateway.dispatch_private_with_resolver(
        fixture(),
        p,
        route,
        raw,
        msg,
        now,
        fn(_, route, tool, _, _) {
          Ok(
            private_binding(route, tool, "private-worker", fn() {
              panic as "Finish without passing receipt must never run"
            }),
          )
        },
      )
    refusal(outcome, "COMPLETION_EVIDENCE_REQUIRED")
  })
  let initial = fixture()
  let stale =
    gateway.GatewayState(
      ..initial,
      backends: server.ServerBackends(
        ..initial.backends,
        features: features.FeatureEvidenceStore(
          ..initial.backends.features,
          active_candidate: "stale",
        ),
      ),
    )
  let #(outcome, _) =
    gateway.dispatch_private_with_resolver(
      stale,
      p,
      "successor",
      raw,
      msg,
      now,
      fn(_, _, _, _, _) { panic as "Candidate mismatch must precede resolver" },
    )
  refusal(outcome, "CANDIDATE_EVIDENCE_MISMATCH")
  let #(raw, msg) = private_request("harness_write_file", json.object([]))
  let #(outcome, _) =
    gateway.dispatch_private_with_resolver(
      initial,
      p,
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        let binding =
          private_binding(route, tool, "private-worker", fn() {
            panic as "Attach required"
          })
        Ok(gateway.PrivateBinding(..binding, task_fence: None))
      },
    )
  refusal(outcome, "MISSING_TASK_FENCE")
}

pub fn private_receipt_replay_and_typed_conflict_never_repeat_effect_test() {
  let p = test_principal("private-worker", "private-receipt")
  let #(raw, msg) =
    private_request(
      "harness_execution_progress",
      json.object([#("nested", json.int(1))]),
    )
  let msg = wire.NormalizedMessage(..msg, args: [#("intent_id", "stable")])
  let #(first, state) =
    gateway.dispatch_private_with_resolver(
      fixture(),
      p,
      "development",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        Ok(
          private_binding(route, tool, "private-worker", fn() {
            #(Ok("{}"), None)
          }),
        )
      },
    )
  let not_called = fn(_, route, tool, _, _) {
    Ok(
      private_binding(route, tool, "private-worker", fn() {
        panic as "Committed or conflicting intent must not repeat effect"
      }),
    )
  }
  let #(replayed, _) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "development",
      raw,
      msg,
      now,
      not_called,
    )
  replayed |> should.equal(first)
  let #(changed, _) =
    private_request(
      "harness_execution_progress",
      json.object([#("nested", json.int(2))]),
    )
  let #(conflict, _) =
    gateway.dispatch_private_with_resolver(
      state,
      p,
      "development",
      changed,
      msg,
      now,
      not_called,
    )
  refusal(conflict, "IDEMPOTENCY_CONFLICT")
}

pub fn private_arguments_omission_fallback_and_explicit_invalid_rejection_test() {
  let msg =
    wire.NormalizedMessage(
      wire.IntId(1),
      "tools/call",
      [#("path", "file.txt")],
      "",
    )
  gateway.private_arguments("{\"params\":{}}", msg)
  |> should.equal(Ok(value.Object([#("path", value.Text("file.txt"))])))
  // Go SDK nil argument maps are the empty object, independent of the
  // omission-only legacy fallback. Other non-object bindings stay invalid.
  gateway.private_arguments("{\"params\":{\"arguments\":null}}", msg)
  |> should.equal(Ok(value.Object([])))
  list.each(["[]", "false", "17", "\"bad\""], fn(invalid) {
    gateway.private_arguments(
      "{\"params\":{\"arguments\":" <> invalid <> "}}",
      msg,
    )
    |> should.be_error
  })
}

pub fn private_session_rechecks_grant_identity_and_preserves_error_state_test() {
  let state = successor_fixture()
  gateway.successor_session(Some(state), state.grant) |> should.equal(Ok(state))
  list.each(
    [
      harness_admission.Grant(..state.grant, id: "other"),
      harness_admission.Grant(..state.grant, digest: string.repeat("c", 64)),
    ],
    fn(changed) {
      gateway.successor_session(Some(state), changed)
      |> should.equal(Error("successor_session_grant_changed"))
    },
  )
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let #(outcome, next) =
    gateway.dispatch_private_with_resolver(
      fixture(),
      test_principal("private-worker", "unresolved-state"),
      "successor",
      raw,
      msg,
      now,
      fn(_, route, tool, _, _) {
        Ok(
          private_binding(route, tool, "private-worker", fn() {
            #(
              Error("uncertain:backend_commit"),
              Some(successor_mcp.State(..state, unresolved: True)),
            )
          }),
        )
      },
    )
  refusal(outcome, "WORKER_ISOLATED_FAILURE")
  let assert Ok(saved) =
    dict.get(
      next.successor_sessions,
      gateway.successor_session_key(test_principal(
        "private-worker",
        "unresolved-state",
      )),
    )
  saved.state.unresolved |> should.be_true
}

pub fn private_typed_live_ingress_retains_original_security_checks_test() {
  let #(raw, _) =
    private_request(
      "harness_status",
      json.object([
        #(
          "nested",
          json.object([#("flag", json.bool(True)), #("number", json.int(3))]),
        ),
      ]),
    )
  let assert Some(reply) =
    gateway.handle_standard_mcp_line(
      "ungranted-typed",
      "codex",
      root,
      "ungranted-typed",
      "successor",
      raw,
      now,
    )
  string.contains(reply, "ROUTE_GRANT_REQUIRED") |> should.be_true
  let assert Ok(frames) =
    gateway.process_stdio_input(
      "ungranted-typed",
      "codex",
      root,
      "ungranted-typed",
      "successor",
      types.Modern20260728,
      [string.slice(raw, 0, 20), string.drop_start(raw, 20) <> "\n"],
      now,
    )
  list.length(frames) |> should.equal(1)
  let assert Ok(frame) = list.first(frames)
  string.contains(frame, "ROUTE_GRANT_REQUIRED") |> should.be_true
  let hs = [
    #("uos-mcp-route", "successor"),
    ..authenticated_headers_with_scopes(["mcp:operational", "mcp:successor"])
  ]
  let #(status, _, reply) =
    gateway.handle_http_with_config("POST", "/mcp", hs, raw, config(), now)
  status |> should.equal(200)
  string.contains(reply, "ROUTE_GRANT_REQUIRED") |> should.be_true
  let #(status, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      [#("uos-mcp-route", "successor"), ..headers()],
      raw,
      config(),
      now,
    )
  status |> should.equal(401)
  let #(status, _, reply) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      [#("uos-mcp-route", "successor"), ..authenticated_headers()],
      raw,
      config(),
      now,
    )
  status |> should.equal(200)
  string.contains(reply, "HTTP_ROUTE_SCOPE_FORBIDDEN") |> should.be_true
  list.each(
    [
      json.object([
        #("actor", json.string("foreign")),
        #("nested", json.bool(True)),
      ]),
      json.object([
        #("nested", json.object([#("Authorization", json.string("fixture"))])),
      ]),
      json.object([
        #(
          "nested",
          json.array([json.string(config().signing_secret)], fn(x) { x }),
        ),
      ]),
    ],
    fn(args) {
      let #(unsafe, _) = private_request("harness_status", args)
      let #(status, _, _) =
        gateway.handle_http_with_config(
          "POST",
          "/mcp",
          hs,
          unsafe,
          config(),
          now,
        )
      status |> should.equal(403)
    },
  )
  let deep =
    "{\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_status\",\"arguments\":{\"nested\":"
    <> string.repeat("[", 40)
    <> "0"
    <> string.repeat("]", 40)
    <> "}}}"
  let #(status, _, reply) =
    gateway.handle_http_with_config("POST", "/mcp", hs, deep, config(), now)
  status |> should.equal(400)
  string.contains(reply, "HTTP_JSON_DEPTH_EXCEEDED") |> should.be_true
}

pub fn private_blocking_backend_does_not_block_public_actor_and_serializes_successor_test() {
  let started = process.new_subject()
  let results = process.new_subject()
  let p = test_principal("private-worker", "actor-private-serialization")
  let #(raw, msg) = private_request("harness_status", json.object([]))
  let _ =
    process.spawn_unlinked(fn() {
      let release = process.new_subject()
      let outcome =
        gateway.dispatch_private_live_with_resolver(
          p,
          "successor",
          raw,
          msg,
          fn(_, route, tool, _, _) {
            Ok(
              private_binding(route, tool, "private-worker", fn() {
                process.send(started, release)
                let assert Ok(True) = process.receive(release, 5000)
                #(
                  Ok("{}"),
                  Some(
                    successor_mcp.State(
                      ..successor_fixture(),
                      initialized: True,
                    ),
                  ),
                )
              }),
            )
          },
        )
      process.send(results, outcome)
    })
  let assert Ok(release) = process.receive(started, 2000)
  let second_started = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let #(raw, msg) = private_request("harness_clock", json.object([]))
      let outcome =
        gateway.dispatch_private_live_with_resolver(
          p,
          "successor",
          raw,
          msg,
          fn(_, route, tool, _, current) {
            let assert Some(previous) = current
            previous.state.initialized |> should.be_true
            process.send(second_started, True)
            Ok(
              private_binding(route, tool, "private-worker", fn() {
                #(Ok("{}"), option.map(current, fn(r) { r.state }))
              }),
            )
          },
        )
      process.send(results, outcome)
    })
  process.receive(second_started, 50) |> should.equal(Error(Nil))
  let public = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      process.send(
        public,
        gateway.handle_standard_mcp_line(
          "public-S01",
          "codex",
          root,
          "public-S01",
          "public",
          "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/list\"}",
          now,
        ),
      )
    })
  let assert Ok(Some(reply)) = process.receive(public, 1000)
  string.contains(reply, "\"tools\":") |> should.be_true
  process.send(release, True)
  let assert Ok(first) = process.receive(results, 5000)
  completed(first) |> should.equal("{}")
  process.receive(second_started, 5000) |> should.equal(Ok(True))
  let assert Ok(second) = process.receive(results, 5000)
  completed(second) |> should.equal("{}")
}

pub fn modern_revision_initialize_and_http_followup_test() {
  version.matches_profile(types.Legacy20241105, "2024-11-05") |> should.be_true
  version.matches_profile(types.Modern20260728, "2024-11-05") |> should.be_false
  list.each(["", "2025-01-01", "2026-07-28suffix"], fn(rev) {
    version.matches_profile(types.Legacy20241105, rev) |> should.be_false
    version.matches_profile(types.Modern20260728, rev) |> should.be_false
  })
  list.each(["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"], fn(rev) {
    version.negotiate(rev) |> should.equal(Ok(types.Modern20260728))
    version.matches_profile(types.Modern20260728, rev) |> should.be_true
    version.matches_profile(types.Legacy20241105, rev) |> should.be_false
    let assert Ok(initialized) = modern.initialize("codex", "1", rev)
    json.parse(initialized, decode.at(["protocolVersion"], decode.string))
    |> should.equal(Ok(rev))
    let hs =
      list.map(authenticated_headers(), fn(h) {
        case h.0 {
          "Mcp-Protocol-Version" -> #(h.0, rev)
          _ -> h
        }
      })
    list.each(["initialize", "tools/list", "discovery/list"], fn(method) {
      let raw =
        json.object([
          #("jsonrpc", json.string("2.0")),
          #("id", json.int(81)),
          #("method", json.string(method)),
          #("params", json.object([#("protocolVersion", json.string(rev))])),
        ])
        |> json.to_string
      let #(status, _, body) =
        gateway.handle_http_with_config("POST", "/mcp", hs, raw, config(), now)
      status |> should.equal(200)
      json.parse(body, decode.at(["error"], decode.dynamic)) |> should.be_error
      let assert Ok(payload) =
        json.parse(body, decode.at(["result", "value"], decode.string))
      case method {
        "initialize" ->
          json.parse(payload, decode.at(["protocolVersion"], decode.string))
          |> should.equal(Ok(rev))
        _ -> string.contains(payload, "tools") |> should.be_true
      }
    })
  })
  let hs =
    list.map(authenticated_headers(), fn(h) {
      case h.0 {
        "Mcp-Protocol-Version" -> #(h.0, "2025-06-18")
        _ -> h
      }
    })
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      hs,
      "{\"jsonrpc\":\"2.0\",\"id\":82,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}",
      config(),
      now,
    )
  status |> should.equal(400)
  string.contains(body, "HEADER_BODY_MISMATCH") |> should.be_true
}

pub fn resource_metadata_challenge_uses_resource_origin_test() {
  list.each(
    [
      #(origin <> "/mcp", "https://idp.tail55d152.ts.net", origin),
      #(
        origin <> "/nested/mcp/",
        "https://idp.tail55d152.ts.net/issuer/",
        origin,
      ),
      #(origin, "https://idp.tail55d152.ts.net", origin),
      #(
        "http://nas-1.tail55d152.ts.net:4100/mcp/",
        "https://idp.tail55d152.ts.net",
        "http://nas-1.tail55d152.ts.net:4100",
      ),
      #(
        "not-a-url",
        "https://idp.tail55d152.ts.net/issuer/",
        "https://idp.tail55d152.ts.net",
      ),
      #(
        "https:///missing-authority",
        "https://idp.tail55d152.ts.net/issuer/",
        "https://idp.tail55d152.ts.net",
      ),
      #("invalid", "invalid", ""),
    ],
    fn(case_data) {
      let cfg =
        http_auth.AuthConfig(
          ..config(),
          expected_audience: case_data.0,
          expected_issuer: case_data.1,
        )
      let #(status, hs, _) =
        gateway.handle_http_with_config(
          "POST",
          "/mcp",
          headers(),
          request("initialize"),
          cfg,
          now,
        )
      status |> should.equal(401)
      http_auth.header(hs, "www-authenticate")
      |> should.equal(Ok(
        "Bearer resource_metadata=\""
        <> case_data.2
        <> "/.well-known/oauth-protected-resource\"",
      ))
    },
  )
}

fn test_principal(actor: String, session: String) -> principal.Principal {
  principal.from_launcher_env(
    actor,
    types.ClientProfile("codex"),
    root,
    session,
  )
}

fn fixture() -> gateway.GatewayState {
  let assert Ok(pool) =
    supervisor.start_worker_pool_for_candidate(1, candidate_id.from_root(root))
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state =
    gateway.new_state(root, candidate_id.from_root(root), pool, supervised)
  let backends =
    server.ServerBackends(
      ..state.backends,
      planning_read: planning_read.AvailableStore("fixture-plan", [
        planning_read.CanonicalTaskRow(
          "fixture-plan",
          "running",
          "fixture only",
          "executing",
          "task-owner",
          7,
        ),
        planning_read.CanonicalTaskRow(
          "fixture-plan",
          "fresh",
          "fixture only",
          "executing",
          "task-owner",
          7,
        ),
      ]),
    )
  gateway.GatewayState(..state, backends: backends)
}

fn transition(
  state: gateway.GatewayState,
  p: principal.Principal,
  method: String,
  params: json.Json,
) -> #(types.Outcome, gateway.GatewayState) {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(99)),
      #("method", json.string(method)),
      #("params", params),
    ])
    |> json.to_string
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  gateway.dispatch_normalized(
    state,
    p,
    types.Modern20260728,
    "public",
    raw,
    msg,
    now,
  )
}

fn completed(outcome: types.Outcome) -> String {
  let assert types.Complete(body, _) = outcome
  body
}

fn refusal(outcome: types.Outcome, code: String) {
  let assert types.Refused(error) = outcome
  error.code |> should.equal(code)
}

fn negotiate_tasks(
  state: gateway.GatewayState,
  p: principal.Principal,
  capabilities: json.Json,
) -> gateway.GatewayState {
  let #(outcome, state) =
    transition(
      state,
      p,
      "initialize",
      json.object([
        #("protocolVersion", json.string("2026-07-28")),
        #("capabilities", capabilities),
      ]),
    )
  completed(outcome) |> string.contains("2026-07-28") |> should.be_true
  state
}

fn task_params(task: String) -> json.Json {
  json.object([
    #("planId", json.string("fixture-plan")),
    #("taskId", json.string(task)),
  ])
}

pub fn task_extension_requires_real_session_negotiation_and_runs_lifecycle_test() {
  let p = test_principal("task-owner", "tasks-negotiated")
  let initial = fixture()
  let #(before, untouched) =
    transition(initial, p, "tasks/create", task_params("running"))
  refusal(before, "TASK_EXTENSION_NOT_NEGOTIATED")
  task_extension.size(untouched.tasks) |> should.equal(0)
  let negotiated =
    negotiate_tasks(initial, p, json.object([#("tasks", json.object([]))]))
  let #(created, state) =
    transition(negotiated, p, "tasks/create", task_params("running"))
  let assert Ok(handle) =
    json.parse(completed(created), decode.at(["handleId"], decode.string))
  handle |> should.equal("fixture-plan:running:7")
  task_extension.has_handle(state.tasks, handle) |> should.be_true
  let params = json.object([#("handleId", json.string(handle))])
  list.each(["tasks/get", "tasks/result"], fn(method) {
    let #(outcome, _) = transition(state, p, method, params)
    json.parse(completed(outcome), decode.at(["state"], decode.string))
    |> should.equal(Ok("running"))
    let #(foreign, _) =
      transition(state, test_principal("foreign", "foreign"), method, params)
    refusal(foreign, "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
  })
  let #(foreign_cancel, _) =
    transition(
      state,
      test_principal("foreign", "foreign"),
      "tasks/cancel",
      params,
    )
  refusal(foreign_cancel, "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
  let #(cancelled, state) = transition(state, p, "tasks/cancel", params)
  let body = completed(cancelled)
  json.parse(body, decode.at(["cancelAcknowledged"], decode.bool))
  |> should.equal(Ok(True))
  json.parse(body, decode.at(["effectStopped"], decode.bool))
  |> should.equal(Ok(False))
  let #(after, _) = transition(state, p, "tasks/get", params)
  json.parse(completed(after), decode.at(["state"], decode.string))
  |> should.equal(Ok("cancel_requested"))
  let #(other_session, _) =
    transition(
      state,
      test_principal("task-owner", "tasks-other-session"),
      "tasks/create",
      task_params("fresh"),
    )
  refusal(other_session, "TASK_EXTENSION_NOT_NEGOTIATED")
}

pub fn task_capability_false_null_missing_and_experimental_test() {
  let p = test_principal("task-owner", "tasks-capability-shapes")
  let initial = fixture()
  list.each(
    [
      json.object([]),
      json.object([#("tasks", json.bool(False))]),
      json.object([#("tasks", json.null())]),
      json.object([
        #("experimental", json.object([#("tasks", json.bool(False))])),
      ]),
      json.object([#("experimental", json.object([#("tasks", json.null())]))]),
    ],
    fn(caps) {
      let state = negotiate_tasks(initial, p, caps)
      let #(outcome, _) =
        transition(state, p, "tasks/create", task_params("running"))
      refusal(outcome, "TASK_EXTENSION_NOT_NEGOTIATED")
    },
  )
  let state =
    negotiate_tasks(
      initial,
      p,
      json.object([
        #("experimental", json.object([#("tasks", json.object([]))])),
      ]),
    )
  let #(created, _) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(created)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  let state = negotiate_tasks(state, p, json.object([]))
  let #(reset, _) = transition(state, p, "tasks/create", task_params("running"))
  refusal(reset, "TASK_EXTENSION_NOT_NEGOTIATED")
}

pub fn task_handle_capacity_refuses_new_but_allows_existing_test() {
  let p = test_principal("task-owner", "tasks-capacity")
  let state =
    negotiate_tasks(fixture(), p, json.object([#("tasks", json.object([]))]))
  let #(created, state) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(created)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  let record =
    task_extension.SaPlanTaskRecord(
      "fixture-plan",
      "filler",
      "task-owner",
      7,
      True,
      task_extension.RunningTask,
    )
  let full =
    int.range(1, task_extension.max_task_handles, state.tasks, fn(store, n) {
      task_extension.register(store, "filler:" <> int.to_string(n), record)
    })
  task_extension.size(full) |> should.equal(1024)
  let state = gateway.GatewayState(..state, tasks: full)
  let #(refused, next) =
    transition(state, p, "tasks/create", task_params("fresh"))
  refusal(refused, "TASK_HANDLE_CAPACITY_EXCEEDED")
  next.tasks |> should.equal(full)
  let #(existing, next) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(existing)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  task_extension.size(next.tasks) |> should.equal(1024)
}

pub fn task_negotiation_session_store_is_bounded_test() {
  let state = fixture()
  let sessions =
    int.range(1, 1025, dict.new(), fn(store, n) {
      dict.insert(store, "session:" <> int.to_string(n), False)
    })
  let state = gateway.GatewayState(..state, negotiated_task_sessions: sessions)
  let params =
    json.object([
      #("protocolVersion", json.string("2026-07-28")),
      #("capabilities", json.object([#("tasks", json.object([]))])),
    ])
  let #(refused, next) =
    transition(
      state,
      test_principal("task-owner", "new-session"),
      "initialize",
      params,
    )
  refusal(refused, "TASK_NEGOTIATION_CAPACITY_EXCEEDED")
  next.negotiated_task_sessions |> should.equal(sessions)
  let #(existing, next) =
    transition(
      state,
      test_principal("task-owner", "session:1"),
      "initialize",
      params,
    )
  completed(existing) |> string.contains("2026-07-28") |> should.be_true
  dict.size(next.negotiated_task_sessions) |> should.equal(1024)
  dict.get(next.negotiated_task_sessions, "session:1") |> should.equal(Ok(True))
}

fn subscription_params(id: String) -> json.Json {
  json.object([
    #("uri", json.string("uos://governance/ev-provenance-ceiling")),
    #("subscriptionId", json.string(id)),
  ])
}

pub fn subscriptions_namespace_ids_and_roundtrip_through_live_gateway_test() {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(101)),
      #("method", json.string("resources/subscribe")),
      #("params", subscription_params("roundtrip")),
    ])
    |> json.to_string
  standard(raw)
  |> std_result("subscriptionId")
  |> should.equal(Ok("cutover-operator:roundtrip"))
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(102)),
      #("method", json.string("resources/unsubscribe")),
      #("params", subscription_params("cutover-operator:roundtrip")),
    ])
    |> json.to_string
  json.parse(standard(raw), decode.at(["result", "unsubscribed"], decode.bool))
  |> should.equal(Ok(True))

  let a = test_principal("actor-a", "sub-a")
  let b = test_principal("actor-b", "sub-b")
  // B's attempt to reserve A's ID remains entirely within B's namespace.
  let #(squat, state) =
    transition(
      fixture(),
      b,
      "resources/subscribe",
      subscription_params("actor-a:shared"),
    )
  json.parse(completed(squat), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-b:actor-a:shared"))
  let #(owned, state) =
    transition(state, a, "resources/subscribe", subscription_params("shared"))
  json.parse(completed(owned), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-a:shared"))
  let #(unsquat, state) =
    transition(
      state,
      b,
      "resources/unsubscribe",
      subscription_params("actor-a:shared"),
    )
  completed(unsquat) |> string.contains("true") |> should.be_true
  subscriptions.read_subscription(
    state.subscriptions,
    types.Modern20260728,
    a,
    "actor-a:shared",
  )
  |> should.be_ok
  let #(unsubscribed, state) =
    transition(
      state,
      a,
      "resources/unsubscribe",
      subscription_params("actor-a:shared"),
    )
  completed(unsubscribed) |> string.contains("true") |> should.be_true
  dict.size(state.subscriptions.subscriptions) |> should.equal(0)
  let #(blank, state) =
    transition(state, a, "resources/subscribe", subscription_params("   "))
  json.parse(completed(blank), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-a:uos://governance/ev-provenance-ceiling"))
  let #(removed, state) =
    transition(state, a, "resources/unsubscribe", subscription_params(""))
  completed(removed) |> string.contains("true") |> should.be_true
  dict.size(state.subscriptions.subscriptions) |> should.equal(0)
}

pub fn subscription_capacity_refuses_without_growing_and_can_recover_test() {
  let p = test_principal("actor-a", "sub-capacity")
  let full =
    int.range(
      1,
      subscriptions.max_subscriptions + 1,
      subscriptions.empty_store(),
      fn(store, n) {
        let assert Ok(next) =
          subscriptions.subscribe(
            store,
            types.Modern20260728,
            p,
            "actor-a:" <> int.to_string(n),
            subscriptions.ResourceSubscription(
              "uos://governance/ev-provenance-ceiling",
            ),
          )
        next
      },
    )
  dict.size(full.subscriptions) |> should.equal(1024)
  let state = gateway.GatewayState(..fixture(), subscriptions: full)
  let #(outcome, next) =
    transition(state, p, "resources/subscribe", subscription_params("new"))
  refusal(outcome, "SUBSCRIPTION_CAPACITY_EXCEEDED")
  let assert types.Refused(error) = outcome
  error.retryability |> should.equal(types.Retryable)
  next.subscriptions |> should.equal(full)
  let #(duplicate, _) =
    transition(state, p, "resources/subscribe", subscription_params("1"))
  refusal(duplicate, "SUBSCRIPTION_ID_ALREADY_EXISTS")
  let #(removed, state) =
    transition(state, p, "resources/unsubscribe", subscription_params("1"))
  completed(removed) |> string.contains("true") |> should.be_true
  let #(replacement, next) =
    transition(state, p, "resources/subscribe", subscription_params("new"))
  completed(replacement) |> string.contains("actor-a:new") |> should.be_true
  dict.size(next.subscriptions.subscriptions) |> should.equal(1024)
}

pub fn logging_completion_and_cancel_notification_live_wiring_test() {
  let logging =
    standard(
      "{\"jsonrpc\":\"2.0\",\"id\":103,\"method\":\"logging/setLevel\",\"params\":{\"level\":\"info\"}}",
    )
  json.parse(logging, decode.at(["error"], decode.dynamic)) |> should.be_error
  let completion = standard(request("completion/complete"))
  json.parse(
    completion,
    decode.at(["result", "completion", "values"], decode.list(decode.string)),
  )
  |> should.equal(Ok([]))
  json.parse(
    completion,
    decode.at(["result", "completion", "hasMore"], decode.bool),
  )
  |> should.equal(Ok(False))
  gateway.handle_standard_mcp_line(
    "cutover-operator",
    "codex",
    root,
    "cutover-session",
    "public",
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":103}}",
    now,
  )
  |> should.equal(None)
}

pub fn signed_zenoh_nul_and_json_depth_guards_test() {
  list.each(
    [
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":\"\u{0000}\"}",
        "ZENOH_NUL_BYTE_FORBIDDEN",
      ),
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":\"\\u0000\"}",
        "ZENOH_NUL_BYTE_FORBIDDEN",
      ),
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":"
          <> string.repeat("[", 33)
          <> "0"
          <> string.repeat("]", 33)
          <> "}",
        "ZENOH_JSON_DEPTH_EXCEEDED",
      ),
    ],
    fn(case_data) {
      let original = signed_envelope("cutover-zenoh-test-key")
      let envelope =
        zenoh.SignedZenohEnvelope(
          ..original,
          payload: case_data.0,
          signature: zenoh.compute_signature(
            "cutover-zenoh-test-key",
            original.topic,
            original.reply_topic,
            original.sender_actor,
            original.client_name,
            original.workspace_root,
            original.session_id,
            case_data.0,
          ),
        )
      let assert Error(error) =
        gateway.handle_zenoh_with_secret(
          "cutover-zenoh-test-key",
          "codex",
          types.Modern20260728,
          envelope,
          now,
        )
      error.code |> should.equal(case_data.1)
    },
  )
}

pub fn health_reports_loaded_code_digest_test() {
  let assert Ok(digest) =
    json.parse(
      gateway.gateway_health_json(),
      decode.at(["loaded_beam_sha256"], decode.string),
    )
  string.length(digest) |> should.equal(64)
  list.all(string.to_graphemes(digest), fn(c) {
    string.contains("0123456789abcdef", c)
  })
  |> should.be_true
}

@external(erlang, "mcp_stdio_ffi", "register_or_stop_supervisor")
fn register_or_stop(pid: process.Pid) -> Bool

@external(erlang, "erlang", "process_info")
fn process_links(
  pid: process.Pid,
  key: atom.Atom,
) -> #(atom.Atom, List(process.Pid))

pub fn losing_linked_boot_racer_cannot_kill_untrapping_caller_test() {
  gateway.ensure_started() |> should.be_true
  let reply = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      process.trap_exits(False)
      let dummy = process.spawn(fn() { process.sleep_forever() })
      let monitor = process.monitor(dummy)
      let #(_, before) = process_links(process.self(), atom.create("links"))
      before |> list.contains(dummy) |> should.be_true
      register_or_stop(dummy) |> should.be_false
      let #(_, after) = process_links(process.self(), atom.create("links"))
      after |> list.contains(dummy) |> should.be_false
      let down =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_) { True })
        |> process.selector_receive(2000)
      process.send(reply, down == Ok(True))
    })
  let monitor = process.monitor(caller)
  process.receive(reply, 4000) |> should.equal(Ok(True))
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { True })
  |> process.selector_receive(1000)
  |> should.equal(Ok(True))
}

pub fn web_metadata_without_origin_has_no_unsolicited_cors_test() {
  let #(status, headers, body) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [],
      "",
      config(),
      now,
    )
  status |> should.equal(200)
  let response = web_server.apply_gateway_response([], status, headers, body)
  http_auth.header(response.headers, "access-control-allow-origin")
  |> should.be_error
  let duplicate =
    web_server.apply_gateway_response(
      [#("Origin", origin), #("origin", origin)],
      status,
      headers,
      body,
    )
  http_auth.header(duplicate.headers, "access-control-allow-origin")
  |> should.be_error
  let invalid =
    web_server.apply_gateway_response(
      [#("Origin", "https://outside.example")],
      status,
      headers,
      body,
    )
  http_auth.header(invalid.headers, "access-control-allow-origin")
  |> should.be_error
}

pub fn web_origin_policy_honors_configured_approved_origins_test() {
  let cfg = gateway.http_auth_config()
  list.each(
    [
      origin,
      "https://vm-1.tail55d152.ts.net:8443",
      "https://nas-99.tail55d152.ts.net:4101",
    ],
    fn(request_origin) {
      let response =
        web_server.apply_gateway_response(
          [#("Origin", request_origin)],
          200,
          [],
          "{}",
        )
      case http_auth.approved_origin(cfg, request_origin) {
        True ->
          http_auth.header(response.headers, "access-control-allow-origin")
          |> should.equal(Ok(request_origin))
        False ->
          http_auth.header(response.headers, "access-control-allow-origin")
          |> should.be_error
      }
    },
  )
}

fn config() -> http_auth.AuthConfig {
  http_auth.AuthConfig(
    [origin],
    origin,
    origin <> "/mcp",
    "mcp:operational",
    "cutover-test-signing-key",
  )
}

fn headers() -> List(#(String, String)) {
  [
    #("Origin", origin),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("Mcp-Protocol-Version", "2026-07-28"),
    #("Mcp-Session-Id", "cutover-session"),
  ]
}

fn authenticated_headers_with_scopes(
  scopes: List(String),
) -> List(#(String, String)) {
  let token =
    http_auth.sign_token(
      http_auth.TokenClaims(
        origin,
        origin <> "/mcp",
        "cutover-operator",
        "codex",
        root,
        "cutover-session",
        scopes,
        now - 1,
        now + 60_000,
      ),
      config().signing_secret,
    )
  [#("Authorization", "Bearer " <> token), ..headers()]
}

fn authenticated_headers() -> List(#(String, String)) {
  authenticated_headers_with_scopes(["mcp:operational"])
}

fn request(method: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(7)),
    #("method", json.string(method)),
  ])
  |> json.to_string
}

fn call(tool: String, args: List(#(String, String))) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(9)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(tool)),
        #(
          "arguments",
          json.object(list.map(args, fn(p) { #(p.0, json.string(p.1)) })),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn standard(raw: String) -> String {
  let assert Some(body) =
    gateway.handle_standard_mcp_line(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      raw,
      now,
    )
  body
}

fn std_result(body: String, field: String) -> Result(String, json.DecodeError) {
  json.parse(body, decode.at(["result", field], decode.string))
}

fn http_payload(raw: String) -> String {
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      raw,
      config(),
      now,
    )
  status |> should.equal(200)
  let assert Ok(payload) =
    json.parse(body, decode.at(["result", "value"], decode.string))
  payload
}

pub fn gateway_actor_is_idempotent_and_candidate_bound_test() {
  gateway.ensure_started() |> should.be_true
  gateway.ensure_started() |> should.be_true
  gateway.is_running() |> should.be_true
  let health = gateway.gateway_health_json()
  json.parse(health, decode.at(["status"], decode.string))
  |> should.equal(Ok("running"))
  json.parse(health, decode.at(["child_id"], decode.string))
  |> should.equal(Ok("mcp_unified_gateway"))
  json.parse(health, decode.at(["total_routes"], decode.int))
  |> should.equal(Ok(101))
  json.parse(health, decode.at(["application_admitted"], decode.bool))
  |> should.equal(Ok(False))
  let assert Ok(candidate) =
    json.parse(health, decode.at(["candidate"], decode.string))
  candidate_id.is_sha256_digest(candidate) |> should.be_true
  candidate |> should.equal(candidate_id.from_root(root))
}

pub fn http_metadata_is_available_without_signing_secret_test() {
  let cfg = http_auth.AuthConfig(..config(), signing_secret: "")
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [],
      "",
      cfg,
      now,
    )
  status |> should.equal(200)
  json.parse(body, decode.at(["resource"], decode.string))
  |> should.equal(Ok(origin <> "/mcp"))
  json.parse(
    body,
    decode.at(["authorization_servers"], decode.list(decode.string)),
  )
  |> should.equal(Ok([origin]))
  json.parse(
    body,
    decode.at(["bearer_methods_supported"], decode.list(decode.string)),
  )
  |> should.equal(Ok(["header"]))
}

pub fn http_authentication_refuses_missing_token_and_untrusted_origin_test() {
  let #(status, response_headers, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers(),
      request("initialize"),
      config(),
      now,
    )
  status |> should.equal(401)
  http_auth.header(response_headers, "www-authenticate") |> should.be_ok
  let bad = [
    #("Origin", "https://evil.example"),
    ..list.filter(authenticated_headers(), fn(p) { p.0 != "Origin" })
  ]
  let #(forbidden, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      bad,
      request("initialize"),
      config(),
      now,
    )
  forbidden |> should.equal(403)
  let #(no_secret, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      request("initialize"),
      http_auth.AuthConfig(..config(), signing_secret: ""),
      now,
    )
  no_secret |> should.equal(401)
}

pub fn authenticated_http_dispatches_live_registries_and_backends_test() {
  http_payload(request("initialize"))
  |> string.contains("uos-mcp-unified-gateway")
  |> should.be_true
  let tools = http_payload(request("tools/list"))
  let assert Ok(definitions) =
    json.parse(tools, decode.at(["tools"], decode.list(decode.dynamic)))
  list.length(definitions) |> should.equal(53)
  http_payload(call("mcp_capability_inventory", []))
  |> string.contains("101")
  |> should.be_true
  http_payload(call("read_file", [#("path", "AGENTS.md")]))
  |> string.contains("Unified Operational System")
  |> should.be_true
  http_payload(
    call("sa_plan_status_for", [
      #("plan", "20261029-1913-mcp-server-completion"),
    ]),
  )
  |> string.contains("canonical_authority")
  |> should.be_true
  http_payload(call("system_health", []))
  |> string.contains("beam_otp29_live")
  |> should.be_true
  http_payload(request("resources/list"))
  |> string.contains("uos://system/mcp-gateway-health")
  |> should.be_true
  http_payload(request("prompts/list"))
  |> string.contains("uos_poodavr_review")
  |> should.be_true
}

pub fn canonical_stdio_both_profiles_and_split_frames_test() {
  list.each([types.Legacy20241105, types.Modern20260728], fn(profile) {
    let raw = call("mcp_capability_inventory", [])
    let assert Ok(frames) =
      gateway.process_stdio_input(
        "cutover-operator",
        "codex",
        root,
        "cutover-session",
        "public",
        profile,
        [
          string.slice(raw, 0, 20),
          string.drop_start(raw, 20) <> "\n",
          request("resources/list") <> "\n",
        ],
        now,
      )
    list.length(frames) |> should.equal(2)
    list.each(frames, fn(frame) {
      json.parse(frame, decode.at(["jsonrpc"], decode.string))
      |> should.equal(Ok("2.0"))
      json.parse(frame, decode.at(["error"], decode.dynamic))
      |> should.be_error
    })
    let payloads =
      list.map(frames, fn(frame) {
        case profile {
          types.Legacy20241105 ->
            json.parse(frame, decode.at(["result"], decode.string))
          types.Modern20260728 ->
            json.parse(frame, decode.at(["result", "value"], decode.string))
        }
      })
    let assert [Ok(inventory), Ok(resources)] = payloads
    inventory |> string.contains("101") |> should.be_true
    resources
    |> string.contains("uos://system/mcp-gateway-health")
    |> should.be_true
  })
  let assert Error(nul) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Modern20260728,
      ["\u{0000}\n"],
      now,
    )
  nul.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")
  let assert Error(escaped) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Legacy20241105,
      ["\\u0000\n"],
      now,
    )
  escaped.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")
  let assert Error(truncated) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Modern20260728,
      [request("ping")],
      now,
    )
  truncated.code |> should.equal("STDIO_TRUNCATED_FRAME_AT_EOF")
}

pub fn standard_mcp_returns_structured_results_and_silent_notifications_test() {
  standard(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}",
  )
  |> std_result("protocolVersion")
  |> should.equal(Ok("2024-11-05"))
  standard(request("initialize"))
  |> std_result("protocolVersion")
  |> should.equal(Ok("2026-07-28"))
  let assert Ok(tools) =
    json.parse(
      standard(request("tools/list")),
      decode.at(["result", "tools"], decode.list(decode.dynamic)),
    )
  list.length(tools) |> should.equal(53)
  list.each(
    [
      call("read_file", [#("path", "AGENTS.md")]),
      call("mcp_capability_inventory", []),
    ],
    fn(raw) {
      let body = standard(raw)
      json.parse(
        body,
        decode.at(["result", "_meta", "candidate"], decode.string),
      )
      |> should.equal(Ok(candidate_id.from_root(root)))
      json.parse(body, decode.at(["result", "isError"], decode.bool))
      |> should.equal(Ok(False))
      string.contains(body, "\"isError\":true") |> should.be_false
    },
  )
  standard(request("resources/list"))
  |> string.contains("uos://system/mcp-gateway-health")
  |> should.be_true
  standard(request("resources/templates/list"))
  |> string.contains("uos://docs/{slug}")
  |> should.be_true
  standard(request("prompts/list"))
  |> string.contains("uos_jidoka_rca")
  |> should.be_true
  gateway.handle_standard_mcp_line(
    "a",
    "codex",
    root,
    "s",
    "public",
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    now,
  )
  |> should.equal(None)
  standard(request("ping"))
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}")
}

pub fn standard_mcp_credential_traversal_and_frame_guards_test() {
  list.each(
    [".env", "var/sa-plan/uos.sqlite3", "../AGENTS.md", "/etc/passwd"],
    fn(path) {
      let body = standard(call("read_file", [#("path", path)]))
      json.parse(body, decode.at(["result", "isError"], decode.bool))
      |> should.equal(Ok(True))
      string.contains(body, "PATH_SECURITY_VIOLATION") |> should.be_true
    },
  )
  standard("{\"id\":1,\"method\":\"ping\",\"nul\":\"\\u0000\"}")
  |> string.contains("STDIO_NUL_BYTE_FORBIDDEN")
  |> should.be_true
  let deep = string.repeat("[", 33) <> "0" <> string.repeat("]", 33)
  standard("{\"id\":1,\"method\":\"ping\",\"data\":" <> deep <> "}")
  |> string.contains("STDIO_JSON_DEPTH_EXCEEDED")
  |> should.be_true
  standard(string.repeat("x", 1_048_577))
  |> string.contains("STDIO_FRAME_TOO_LARGE")
  |> should.be_true
}

fn signed_envelope(secret: String) -> zenoh.SignedZenohEnvelope {
  let envelope =
    zenoh.SignedZenohEnvelope(
      "indrajaal/mcp/request/codex/test1",
      "indrajaal/mcp/response/codex/test1",
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      call("mcp_capability_inventory", []),
      "",
    )
  zenoh.SignedZenohEnvelope(
    ..envelope,
    signature: zenoh.compute_signature(
      secret,
      envelope.topic,
      envelope.reply_topic,
      envelope.sender_actor,
      envelope.client_name,
      envelope.workspace_root,
      envelope.session_id,
      envelope.payload,
    ),
  )
}

pub fn signed_zenoh_dispatch_and_forgery_refusal_test() {
  let envelope = signed_envelope("cutover-zenoh-test-key")
  let assert Ok(Some(#(reply, body))) =
    gateway.handle_zenoh_with_secret(
      "cutover-zenoh-test-key",
      "codex",
      types.Modern20260728,
      envelope,
      now,
    )
  reply |> should.equal(envelope.reply_topic)
  body |> string.contains("101") |> should.be_true
  let assert Error(forged) =
    gateway.handle_zenoh_with_secret(
      "cutover-zenoh-test-key",
      "codex",
      types.Modern20260728,
      zenoh.SignedZenohEnvelope(..envelope, signature: "forged"),
      now,
    )
  forged.code |> should.equal("ZENOH_SIGNATURE_INVALID")
  let assert Error(empty) =
    gateway.handle_zenoh_with_secret(
      "",
      "codex",
      types.Modern20260728,
      envelope,
      now,
    )
  empty.code |> should.equal("ZENOH_SECRET_REQUIRED")
  gateway.handle_zenoh_raw(envelope.topic, "{}") |> should.equal(None)
  gateway.handle_zenoh_raw("wrong/topic", "not json") |> should.equal(None)
}

pub fn immutable_six_core_source_candidate_test() {
  candidate_id.from_root(root)
  |> should.equal(
    "sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663",
  )
}

pub fn standard_resources_prompts_and_fresh_observation_test() {
  let resource =
    standard(
      "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"resources/read\",\"params\":{\"uri\":\"uos://governance/ev-provenance-ceiling\"}}",
    )
  let assert Ok([text]) =
    json.parse(
      resource,
      decode.at(
        ["result", "contents"],
        decode.list(decode.at(["text"], decode.string)),
      ),
    )
  json.parse(text, decode.at(["admitted_ev_ceiling"], decode.int))
  |> should.equal(Ok(93))
  let prompt =
    standard(
      "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"prompts/get\",\"params\":{\"name\":\"uos_poodavr_review\"}}",
    )
  json.parse(prompt, decode.at(["result", "advisory_only"], decode.bool))
  |> should.equal(Ok(True))
  json.parse(prompt, decode.at(["result", "effect_authority"], decode.bool))
  |> should.equal(Ok(False))
  let assert Some(health) =
    gateway.handle_standard_mcp_line(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      call("system_health", []),
      now + 60_000,
    )
  let assert Ok([text]) =
    json.parse(
      health,
      decode.at(
        ["result", "content"],
        decode.list(decode.at(["text"], decode.string)),
      ),
    )
  json.parse(text, decode.at(["observed_at_ms"], decode.int))
  |> should.equal(Ok(now + 60_000))
  json.parse(text, decode.at(["age_ms"], decode.int)) |> should.equal(Ok(0))
  let assert Some(foreign) =
    gateway.handle_standard_mcp_line(
      "foreign",
      "codex",
      "/foreign",
      "s",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"resources/read\",\"params\":{\"uri\":\"uos://governance/ev-provenance-ceiling\"}}",
      now,
    )
  foreign |> string.contains("PRINCIPAL_WORKSPACE_MISMATCH") |> should.be_true
  standard(request("Unknown"))
  |> string.contains("METHOD_NOT_FOUND")
  |> should.be_true
}

fn encode_envelope(envelope: zenoh.SignedZenohEnvelope) -> String {
  json.object([
    #("reply_topic", json.string(envelope.reply_topic)),
    #("sender_actor", json.string(envelope.sender_actor)),
    #("client_name", json.string(envelope.client_name)),
    #("workspace_root", json.string(envelope.workspace_root)),
    #("session_id", json.string(envelope.session_id)),
    #("payload", json.string(envelope.payload)),
    #("signature", json.string(envelope.signature)),
  ])
  |> json.to_string
}

pub fn raw_zenoh_uses_configured_secret_and_pins_actual_topic_test() {
  // Never mutate the process environment. Configured deployments exercise
  // positive raw ingress; an unset secret must always refuse it.
  let secret = case get_env("UOS_MCP_ZENOH_SHARED_SECRET") {
    Ok(s) -> s
    Error(_) -> ""
  }
  let envelope = signed_envelope(secret)
  case secret {
    "" ->
      gateway.handle_zenoh_raw(envelope.topic, encode_envelope(envelope))
      |> should.equal(None)
    _ -> {
      let assert Some(#(reply, body)) =
        gateway.handle_zenoh_raw(envelope.topic, encode_envelope(envelope))
      reply |> should.equal(envelope.reply_topic)
      body |> string.contains("101") |> should.be_true
    }
  }
  let forged = zenoh.SignedZenohEnvelope(..envelope, signature: "forged")
  gateway.handle_zenoh_raw(envelope.topic, encode_envelope(forged))
  |> should.equal(None)
  gateway.handle_zenoh_raw(
    "indrajaal/mcp/request/codex/foreign",
    encode_envelope(envelope),
  )
  |> should.equal(None)
}

pub fn zenoh_unauthenticated_read_file_environ_is_dropped_test() {
  gateway.handle_zenoh_raw(
    "indrajaal/mcp/request/c1/r1",
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"path\":\"/proc/self/environ\"}}}",
  )
  |> should.equal(None)
}

pub fn http_nul_byte_and_excess_json_depth_rejected_test() {
  let #(raw_nul_status, _, raw_nul_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":\""
        <> "\u{0000}"
        <> "\"}}",
      config(),
      now,
    )
  raw_nul_status |> should.equal(400)
  raw_nul_body |> string.contains("HTTP_NUL_BYTE_FORBIDDEN") |> should.be_true

  let #(escaped_nul_status, _, escaped_nul_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":\"\\\\u0000\"}}",
      config(),
      now,
    )
  escaped_nul_status |> should.equal(400)
  escaped_nul_body
  |> string.contains("HTTP_NUL_BYTE_FORBIDDEN")
  |> should.be_true

  let deep = string.repeat("{\"a\":", 33) <> "1" <> string.repeat("}", 33)
  let #(depth_status, _, depth_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      deep,
      config(),
      now,
    )
  depth_status |> should.equal(400)
  depth_body
  |> string.contains("HTTP_JSON_DEPTH_EXCEEDED")
  |> should.be_true
}

pub fn http_private_route_header_requires_matching_token_scope_test() {
  let low_scope_headers = [
    #("uos-mcp-route", "development"),
    ..authenticated_headers_with_scopes(["mcp:operational"])
  ]
  let #(forbidden_status, _, forbidden_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      low_scope_headers,
      request("tools/list"),
      config(),
      now,
    )
  forbidden_status |> should.equal(200)
  forbidden_body
  |> string.contains("HTTP_ROUTE_SCOPE_FORBIDDEN")
  |> should.be_true
  forbidden_body |> string.contains("\"tools\":[") |> should.be_false

  let dev_scope_headers = [
    #("uos-mcp-route", "development"),
    ..authenticated_headers_with_scopes(["mcp:operational", "mcp:development"])
  ]
  let #(allowed_status, _, allowed_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      dev_scope_headers,
      request("tools/list"),
      config(),
      now,
    )
  allowed_status |> should.equal(200)
  let assert Ok(payload) =
    json.parse(allowed_body, decode.at(["result", "value"], decode.string))
  let assert Ok(tools) =
    json.parse(payload, decode.at(["tools"], decode.list(decode.dynamic)))
  list.length(tools) |> should.equal(21)
}

pub fn http_oauth_metadata_and_401_emit_cors_and_absolute_resource_metadata_test() {
  let #(metadata_status, metadata_headers, _) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [#("Origin", origin), #("Accept", "application/json")],
      "",
      config(),
      now,
    )
  metadata_status |> should.equal(200)
  http_auth.header(metadata_headers, "access-control-allow-origin")
  |> should.equal(Ok(origin))

  let #(unauthorized_status, unauthorized_headers, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers(),
      request("initialize"),
      config(),
      now,
    )
  unauthorized_status |> should.equal(401)
  let assert Ok(challenge) =
    http_auth.header(unauthorized_headers, "www-authenticate")
  challenge
  |> string.contains(
    "https://nas-1.tail55d152.ts.net:4101/.well-known/oauth-protected-resource",
  )
  |> should.be_true
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_loopback_fixture")
fn sse_loopback_fixture(
  valid: String,
  forged: String,
  ping: String,
  start: fn(Int) -> Result(process.Pid, String),
) -> Result(#(String, String), String)

fn sse_sample(topic: String, payload: json.Json) -> String {
  "data: "
  <> json.to_string(
    json.object([
      #("key", json.string(topic)),
      #("value", payload),
      #("encoding", json.string("application/json")),
    ]),
  )
  <> "\r\n\r\n"
}

pub fn zenoh_sse_decodes_object_string_multiline_and_alias_samples_test() {
  let topic = "indrajaal/mcp/request/codex/loop1"
  let envelope = signed_envelope("sse-test-secret") |> encode_envelope
  let assert Ok(object) = json.parse(envelope, value.decoder())
  let assert Some(#(actual_topic, raw)) =
    gateway.decode_zenoh_sse_event(sse_sample(topic, value.encode(object)))
  actual_topic |> should.equal(topic)
  json.parse(raw, value.decoder()) |> should.equal(Ok(object))
  gateway.decode_zenoh_sse_event(sse_sample(topic, json.string(envelope)))
  |> should.equal(Some(#(topic, envelope)))
  gateway.decode_zenoh_sse_event(
    ":keepalive\r\ndata: {\"key_expr\": \""
    <> topic
    <> "\",\r\ndata: \"payload\": {\"nested\": [1, true, null]}}\r\n",
  )
  |> fn(result) {
    let assert Some(#(key, payload)) = result
    key |> should.equal(topic)
    json.parse(payload, value.decoder())
    |> should.equal(json.parse("{\"nested\":[1,true,null]}", value.decoder()))
  }
}

pub fn zenoh_sse_rejects_heartbeats_bad_json_and_unsafe_topics_test() {
  list.each(
    ["", ":keepalive\n\n", "event: heartbeat", "data: {bad}"],
    fn(block) { gateway.decode_zenoh_sse_event(block) |> should.equal(None) },
  )
  list.each(
    [
      "indrajaal/mcp/response/codex/loop1", "c3i/a2a/request/codex/loop1",
      "indrajaal/mcp/request//loop1", "indrajaal/mcp/request/codex/..",
      "indrajaal/mcp/request/codex/loop1/extra",
      "indrajaal/mcp/request/codex/x?url=evil",
      "indrajaal/mcp/request/codex/%2e%2e",
    ],
    fn(topic) {
      gateway.decode_zenoh_sse_event(sse_sample(topic, json.object([])))
      |> should.equal(None)
    },
  )
  gateway.decode_zenoh_sse_event(
    "data: {\"key\":\"indrajaal/mcp/request/codex/x\",\"value\":42}",
  )
  |> should.equal(None)
  gateway.decode_zenoh_sse_event(string.repeat("x", 1_048_577))
  |> should.equal(None)
  gateway.decode_zenoh_sse_event(
    "data: " <> string.repeat("[", 40) <> "0" <> string.repeat("]", 40),
  )
  |> should.equal(None)
}

pub fn zenoh_sse_endpoint_guard_refuses_untrusted_hosts_before_connect_test() {
  list.each(
    ["evil.example", "localhost", "127.0.0.2", "nas-1.tail55d152.ts.net/evil"],
    fn(host) {
      gateway.start_zenoh_sse_subscriber_for_test(host, 8080, "secret")
      |> should.equal(Error("invalid_zenoh_subscriber_endpoint_or_secret"))
    },
  )
  list.each([0, -1, 65_536], fn(port) {
    gateway.start_zenoh_sse_subscriber_for_test("127.0.0.1", port, "secret")
    |> should.equal(Error("invalid_zenoh_subscriber_endpoint_or_secret"))
  })
  gateway.start_zenoh_sse_subscriber_for_test("127.0.0.1", 8080, "")
  |> should.equal(Error("invalid_zenoh_subscriber_endpoint_or_secret"))
}

fn sse_signed_request(
  id: String,
  payload: String,
  secret: String,
) -> zenoh.SignedZenohEnvelope {
  let base =
    zenoh.SignedZenohEnvelope(
      ..signed_envelope(secret),
      topic: "indrajaal/mcp/request/codex/" <> id,
      reply_topic: "indrajaal/mcp/response/codex/" <> id,
      payload: payload,
    )
  zenoh.SignedZenohEnvelope(
    ..base,
    signature: zenoh.compute_signature(
      secret,
      base.topic,
      base.reply_topic,
      base.sender_actor,
      base.client_name,
      base.workspace_root,
      base.session_id,
      base.payload,
    ),
  )
}

pub fn zenoh_sse_loopback_chunked_hmac_overflow_reconnect_and_put_test() {
  let secret = "loopback-sse-test-secret"
  let valid =
    sse_signed_request(
      "loop1",
      "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"tools/list\"}",
      secret,
    )
  let forged = zenoh.SignedZenohEnvelope(..valid, signature: "forged")
  let ping =
    sse_signed_request(
      "loop2",
      "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"ping\"}",
      secret,
    )
  let to_sample = fn(envelope: zenoh.SignedZenohEnvelope) {
    let assert Ok(object) =
      json.parse(encode_envelope(envelope), value.decoder())
    sse_sample(envelope.topic, value.encode(object))
  }
  let output =
    sse_loopback_fixture(
      to_sample(valid),
      to_sample(forged),
      to_sample(ping),
      fn(port) {
        gateway.start_zenoh_sse_subscriber_for_test("127.0.0.1", port, secret)
      },
    )
  let assert Ok(#(tools, pong)) = output
  let decoder =
    decode.map(decode.at(["tools"], decode.list(decode.dynamic)), list.length)
  let assert Ok(tool_payload) =
    json.parse(tools, decode.at(["result", "value"], decode.string))
  json.parse(tool_payload, decoder) |> should.equal(Ok(53))
  json.parse(pong, decode.at(["id"], decode.int)) |> should.equal(Ok(32))
  string.contains(pong, "\"error\"") |> should.be_false
}

// Same OneForOne strategy/worker wrapper as production. The SSE child may die
// during a connect/reconnect without replacing the GatewayState owner.
pub fn zenoh_sse_one_for_one_restart_preserves_gateway_owner_test() {
  let owner_started = process.new_subject()
  let subscriber_started = process.new_subject()
  let gateway_state = fixture()
  let owner_child =
    supervision.worker(fn() {
      let started = gateway.start_state_owner(gateway_state)
      case started {
        Ok(owner) -> process.send(owner_started, owner)
        Error(_) -> Nil
      }
      started
    })
  let sse_child =
    supervision.worker(fn() {
      gateway.start_zenoh_sse_subscriber_for_test(
        "127.0.0.1",
        1,
        "isolation-test-secret",
      )
      |> result.map(fn(pid) {
        process.send(subscriber_started, pid)
        actor.Started(pid, Nil)
      })
      |> result.map_error(actor.InitFailed)
    })
  let assert Ok(sup) =
    otp_supervisor.new(otp_supervisor.OneForOne)
    |> otp_supervisor.add(owner_child)
    |> otp_supervisor.add(sse_child)
    |> otp_supervisor.start
  process.unlink(sup.pid)
  let assert Ok(owner) = process.receive(owner_started, 500)
  let assert Ok(first) = process.receive(subscriber_started, 500)
  process.kill(first)
  let assert Ok(second) = process.receive(subscriber_started, 500)
  let reply = process.new_subject()
  process.send(owner.data, gateway.Ping(reply))
  let alive = process.receive(reply, 200)
  let replaced = process.receive(owner_started, 20)
  process.kill(sup.pid)
  list.each([sup.pid, owner.pid, second], fn(pid) {
    let monitor = process.monitor(pid)
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_) { Nil })
    |> process.selector_receive(1000)
    |> should.equal(Ok(Nil))
  })
  alive |> should.equal(Ok(True))
  replaced |> should.equal(Error(Nil))
  { first != second } |> should.be_true
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_registered_health_fixture")
fn registered_sse_health_fixture(
  start: fn(Int, Int) -> Result(process.Pid, String),
) -> Result(Nil, String)

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_registered_isolation_fixture")
fn registered_sse_isolation_fixture(
  start_supervisor: fn(Int, Int) -> Result(process.Pid, String),
  start: fn(Int, Bool, Int) -> Result(process.Pid, String),
  boot: fn() -> Bool,
) -> Result(Nil, String)

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_stdio_guard_fixture")
fn stdio_sse_guard_fixture(
  enabled: fn() -> Bool,
  main: fn() -> Nil,
) -> Result(Nil, String)

@external(erlang, "mcp_stdio_ffi", "zenoh_test_environment")
fn zenoh_test_environment(f: fn() -> a) -> a

pub fn registered_sse_idle_timeout_health_and_recovery_test() {
  registered_sse_health_fixture(fn(port, lock) {
    gateway.start_zenoh_sse_subscriber_with_options(
      "127.0.0.1",
      port,
      "registered-fixture-secret",
      True,
      lock,
      150,
    )
  })
  |> should.equal(Ok(Nil))
}

pub fn registered_sse_mutex_cross_beam_restart_storm_and_gateway_isolation_test() {
  registered_sse_isolation_fixture(
    fn(port, lock) {
      gateway.start_zenoh_supervisor_with_options_for_test(
        "127.0.0.1",
        port,
        "registered-fixture-secret",
        True,
        lock,
        150,
      )
    },
    fn(port, register, lock) {
      gateway.start_zenoh_sse_subscriber_with_options(
        "127.0.0.1",
        port,
        "registered-fixture-secret",
        register,
        lock,
        150,
      )
    },
    gateway.ensure_started,
  )
  |> should.equal(Ok(Nil))
}

pub fn stdio_inherited_subscriber_settings_never_enable_sse_test() {
  stdio_sse_guard_fixture(gateway.zenoh_subscriber_enabled, gateway.stdio_main)
  |> should.equal(Ok(Nil))
}

pub fn raw_zenoh_topic_bound_is_identical_to_sse_precondition_test() {
  zenoh_test_environment(fn() {
    let secret = "raw-topic-test-secret"
    let valid =
      sse_signed_request(
        "valid",
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
        secret,
      )
    let assert Some(_) =
      gateway.handle_zenoh_raw(valid.topic, encode_envelope(valid))
    list.each(
      [
        "indrajaal/mcp/request/codex/" <> string.repeat("x", 513),
        "indrajaal/mcp/request/codex/*",
        "indrajaal/mcp/request/codex/..",
        "indrajaal/mcp/request/codex/id/extra",
      ],
      fn(topic) {
        let reply = string.replace(topic, "/request/", "/response/")
        let envelope =
          zenoh.SignedZenohEnvelope(
            ..valid,
            topic: topic,
            reply_topic: reply,
            signature: zenoh.compute_signature(
              secret,
              topic,
              reply,
              valid.sender_actor,
              valid.client_name,
              valid.workspace_root,
              valid.session_id,
              valid.payload,
            ),
          )
        gateway.handle_zenoh_raw(topic, encode_envelope(envelope))
        |> should.equal(None)
      },
    )
  })
}

pub fn zenoh_freshness_health_fields_keep_stable_types_test() {
  let health = gateway.gateway_health_json()
  json.parse(health, decode.at(["zenoh_subscriber_enabled"], decode.bool))
  |> should.be_ok
  json.parse(health, decode.at(["zenoh_subscriber_alive"], decode.bool))
  |> should.be_ok
  json.parse(health, decode.at(["zenoh_subscriber_state"], decode.string))
  |> should.be_ok
  json.parse(
    health,
    decode.at(["zenoh_subscriber_last_activity_age_ms"], decode.int),
  )
  |> should.be_ok
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_handshake_fixture")
fn sse_handshake_fixture() -> Result(Nil, String)

pub fn sse_init_crash_dead_ready_timeout_leave_untrapping_caller_mailbox_clean_test() {
  sse_handshake_fixture() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_atomics_fixture")
fn sse_atomics_fixture(
  start: fn(Int) -> Result(process.Pid, String),
) -> Result(Nil, String)

pub fn registered_sse_atomically_refreshes_without_persistent_term_churn_test() {
  sse_atomics_fixture(fn(port) {
    gateway.start_zenoh_sse_subscriber_with_options(
      "127.0.0.1",
      port,
      "atomics-fixture-secret",
      True,
      0,
      150,
    )
  })
  |> should.equal(Ok(Nil))
}
