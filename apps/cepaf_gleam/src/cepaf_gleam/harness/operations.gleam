//// Task-scoped development effects with durable intent/result receipts.
//// Sa-plan remains the task authority. Receipts are evidence, never grants.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/client_mcp
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/planning_intents as planning
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge as sa
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import uos_swarm/session_authority

@external(erlang, "cepaf_gleam_ffi", "nanos_to_iso8601")
fn iso8601_from_nanos(nanos: Int) -> String

pub fn text(args: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(args, key))
  case found {
    value.Text(s) -> Ok(s)
    _ -> Error("string_field:" <> key)
  }
}

/// Thin boundary so the dispatch arm and the tests share one entry point.
pub fn submit_planning_outcome(
  execution: a.Execution,
  args: value.Value,
) -> Result(json.Json, String) {
  planning.submit(execution, args)
}

pub fn fields(name: String) -> List(String) {
  case name {
    "harness_claim" | "harness_attach" -> ["plan", "task", "intent_id"]
    "harness_read_file" -> ["path"]
    "harness_client_mcp_config" -> ["intent_id", "client", "action"]
    "harness_write_file" -> ["intent_id", "path", "content", "expected_sha256"]
    "harness_build"
    | "harness_test"
    | "harness_release"
    | "harness_reconcile" -> ["intent_id"]
    "harness_plan_intent" -> [
      "intent",
      "logical_id",
      "target_plan",
      "task_id",
      "title",
      "evidence_path",
      "evidence_body",
    ]
    "harness_assess" -> ["intent_id", "assessment_json", "reason"]
    "harness_finish" -> [
      "intent_id",
      "journal_path",
      "build_intent_id",
      "test_intent_id",
      "verification_path",
    ]
    _ -> []
  }
}

pub const names = [
  "harness_plan_intent",
  "harness_status",
  "harness_clock",
  "harness_heartbeat",
  "harness_claim",
  "harness_attach",
  "harness_release",
  "harness_read_file",
  "harness_client_mcp_config",
  "harness_write_file",
  "harness_build",
  "harness_test",
  "harness_assess",
  "harness_finish",
  "harness_reconcile",
]

pub fn validate_args(name: String, args: value.Value) -> Result(Nil, String) {
  use _ <- result.try(a.require(list.contains(names, name), "unknown_tool"))
  case args {
    value.Object(actual) -> {
      let required = fields(name)
      use _ <- result.try(a.require(
        list.length(actual) == list.length(required)
          && list.all(actual, fn(field) { list.contains(required, field.0) }),
        "unexpected_or_missing_fields",
      ))
      use _ <- result.try(
        list.try_each(required, fn(key) {
          text(args, key) |> result.map(fn(_) { Nil })
        }),
      )
      validate_enum_fields(name, args)
    }
    _ -> Error("arguments_object_required")
  }
}

fn validate_enum_fields(
  name: String,
  args: value.Value,
) -> Result(Nil, String) {
  case name {
    "harness_client_mcp_config" -> {
      use client <- result.try(text(args, "client"))
      use action <- result.try(text(args, "action"))
      use _ <- result.try(a.require(
        list.contains(["agy", "gemini", "codex", "claude", "pi"], client),
        "client_enum_refused",
      ))
      a.require(
        list.contains(["prepare", "status", "rollback"], action),
        "client_action_refused",
      )
    }
    _ -> Ok(Nil)
  }
}

// C3: `capture` folds over scope.sources ONLY, so a write to an authorized path
// outside that list -- in the live grant four of them, including the journal a
// completion must reference -- was invisible to every guard.
//
// AGY's patch fixed this by widening `capture` itself. That is WRONG and was
// corrected here: `capture` is candidate IDENTITY, bound into build and test
// receipts and compared at finish. The journal is legitimately written AFTER the
// build, so widening candidate identity to include it makes every honest
// completion fail with verification_candidate_mismatch -- the same shape of
// error as demanding a review task stay uncompleted. A fix that breaks the
// healthy path is not a fix.
//
// So identity stays narrow and a SECOND, wider manifest does the concurrent
// modification check within one effect. Two questions, two observables.
pub fn manifest_of(paths: List(String)) -> Result(String, String) {
  use entries <- result.try(
    list.try_map(paths, fn(path) {
      use content <- result.try(a.read_optional(path))
      let digest = case content {
        Some(body) -> json.string(files.digest(body))
        None -> json.null()
      }
      Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
    }),
  )
  Ok(json.array(entries, fn(x) { x }) |> json.to_string)
}

fn root_for_path(
  execution: a.Execution,
  path: String,
) -> Result(String, String) {
  case list.contains(execution.scope.sources, path) {
    True -> a.source_root(execution.grant)
    False -> Ok(dev.root)
  }
}

fn manifest_for_execution(
  execution: a.Execution,
  paths: List(String),
) -> Result(String, String) {
  use entries <- result.try(
    list.try_map(paths, fn(path) {
      use root <- result.try(root_for_path(execution, path))
      use content <- result.try(files.read_optional(root, path))
      let digest = case content {
        Some(body) -> json.string(files.digest(body))
        None -> json.null()
      }
      Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
    }),
  )
  Ok(json.array(entries, fn(x) { x }) |> json.to_string)
}

/// Everything the grant authorizes to change: sources plus writes, sorted and
/// deduplicated so the manifest is a function of the SET, not of declaration order.
pub fn guard_capture(scope: a.Scope) -> Result(String, String) {
  manifest_of(list.sort(
    list.unique(list.append(scope.sources, scope.writes)),
    string.compare,
  ))
}

fn guard_capture_execution(execution: a.Execution) -> Result(String, String) {
  manifest_for_execution(
    execution,
    list.sort(
      list.unique(list.append(execution.scope.sources, execution.scope.writes)),
      string.compare,
    ),
  )
}

/// Every path in the manifest must be unchanged, except the declared write
/// target, which must carry exactly the digest the effect claims to have written.
/// Replaces the old `name == "harness_write_file" || before == after` bypass,
/// which let ANY file move underneath a write.
pub fn write_manifest_clean(
  before_json: String,
  after_json: String,
  target_path: String,
  expected_digest: String,
) -> Result(Nil, String) {
  use before <- result.try(
    json.parse(before_json, value.decoder())
    |> result.map_error(fn(_) { "manifest_json" }),
  )
  use after <- result.try(
    json.parse(after_json, value.decoder())
    |> result.map_error(fn(_) { "manifest_json" }),
  )
  case before, after {
    value.Array(b), value.Array(c) -> {
      use _ <- result.try(a.require(
        list.length(b) == list.length(c),
        "manifest_structure_mismatch",
      ))
      list.try_each(list.zip(b, c), fn(pair) {
        use before_path <- result.try(text(pair.0, "path"))
        use after_path <- result.try(text(pair.1, "path"))
        use _ <- result.try(a.require(
          before_path == after_path,
          "manifest_path_mismatch",
        ))
        use before_sha <- result.try(value.get(pair.0, "sha256"))
        use after_sha <- result.try(value.get(pair.1, "sha256"))
        case before_path == target_path {
          True ->
            a.require(
              after_sha == value.Text(expected_digest),
              "write_target_digest_mismatch",
            )
          False ->
            a.require(
              before_sha == after_sha,
              "unauthorized_concurrent_modification:" <> before_path,
            )
        }
      })
    }
    _, _ -> Error("manifest_array_required")
  }
}

pub fn capture(scope: a.Scope) -> Result(String, String) {
  use sources <- result.try(
    list.try_map(scope.sources, fn(path) {
      use content <- result.try(a.read_optional(path))
      let digest = case content {
        Some(body) -> json.string(files.digest(body))
        None -> json.null()
      }
      Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
    }),
  )
  Ok(json.array(sources, fn(x) { x }) |> json.to_string)
}

fn capture_execution(execution: a.Execution) -> Result(String, String) {
  manifest_for_execution(execution, execution.scope.sources)
}

// C2: the old encoding was "<grant>-<intent>-<suffix>.json". "-" is inside the
// admission.component charset, so intent "x-completion" with suffix "intent" and
// intent "x" with suffix "completion-intent" produced THE SAME PATH. "@" is
// outside that charset, so the ambiguity is gone by construction rather than by
// convention. Pre-existing v9 effect files are deliberately unreadable under the
// new scheme: they carry no `kind` tag, so reading them would reinstate exactly
// the untyped observable this fix removes. Grant ids are fresh per session.
pub fn effect_path_for(
  grant_id: String,
  intent: String,
  suffix: String,
) -> String {
  "var/harness/effects/"
  <> grant_id
  <> "@"
  <> intent
  <> "@"
  <> suffix
  <> ".json"
}

fn effect_path(
  execution: a.Execution,
  intent: String,
  suffix: String,
) -> String {
  effect_path_for(execution.grant.id, intent, suffix)
}

fn signature(
  execution: a.Execution,
  tool: String,
  args: value.Value,
) -> String {
  json.object([
    #("grant", json.string(execution.grant.digest)),
    #("plan", json.string(execution.scope.plan)),
    #("task", json.string(execution.scope.task)),
    #("attempt", json.int(execution.binding.attempt)),
    #("worker", json.string(execution.binding.worker)),
    #("tool", json.string(tool)),
    #("args", value.encode(args)),
  ])
  |> json.to_string
  |> files.digest
}

pub fn replay(
  saved: String,
  expected_signature: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(
    json.parse(saved, value.decoder())
    |> result.map_error(fn(_) { "corrupt_result" }),
  )
  use sig <- result.try(value.get(parsed, "signature"))
  use status <- result.try(value.get(parsed, "status"))
  // Meaning comes from the record, never from where the record was found.
  use _ <- result.try(a.require(
    value.get(parsed, "schema")
      == Ok(value.Text("uos.harness-successor-effect.v1"))
      && value.get(parsed, "kind") == Ok(value.Text("effect_result")),
    "replay_kind_mismatch",
  ))
  use _ <- result.try(a.require(
    sig == value.Text(expected_signature),
    "replay_binding_mismatch",
  ))
  use _ <- result.try(a.require(
    status == value.Text("EXECUTED"),
    "saved_effect_failed_or_unverified_no_retry",
  ))
  Ok(value.encode(parsed))
}

fn perform(
  execution: a.Execution,
  name: String,
  args: value.Value,
  timeout: Int,
) -> Result(String, String) {
  case name {
    "harness_client_mcp_config" -> client_mcp.perform(execution, args, timeout)
    "harness_write_file" -> {
      use path <- result.try(text(args, "path"))
      use body <- result.try(text(args, "content"))
      use expected <- result.try(text(args, "expected_sha256"))
      use intent <- result.try(text(args, "intent_id"))
      use _ <- result.try(a.require(
        list.contains(execution.scope.writes, path),
        "write_scope_refused",
      ))
      use root <- result.try(root_for_path(execution, path))
      write_file_with_cas_at(
        session_authority.database,
        execution.binding.session,
        dev.task_resource(execution.binding),
        execution.binding.epoch,
        execution.grant.id,
        intent,
        root,
        path,
        body,
        expected,
      )
    }
    "harness_build" -> {
      use args <- result.try(build_args_for(execution, ["build"]))
      dev.bounded(dev.root <> "/toolchains/nix-profile/bin/env", args, timeout)
    }
    "harness_test" -> {
      use source_root <- result.try(a.source_root(execution.grant))
      use args <- result.try(test_runner_arguments(
        source_root,
        execution.scope.tests,
      ))
      dev.bounded(dev.root <> "/toolchains/nix-profile/bin/erl", args, timeout)
    }
    _ -> Error("effect_not_admitted")
  }
}

/// Task-authorized writes serialize on the resolved root identity plus relative
/// target path while the SQLite coordinator transaction validates the epoch.
/// `coordinator_path` is parameterized for isolated regression tests; production
/// dispatch supplies the canonical database above.
pub fn write_file_with_cas_at(
  coordinator_path: String,
  session: String,
  resource: String,
  epoch: Int,
  grant_id: String,
  intent: String,
  root: String,
  path: String,
  body: String,
  expected: String,
) -> Result(String, String) {
  session_authority.with_cas_critical_section_at(
    coordinator_path,
    session,
    resource,
    epoch,
    files.digest(root) <> "/" <> path,
    files.digest(grant_id <> "\u{0}" <> intent),
    fn() {
      use _ <- result.try(case expected {
        "ABSENT" -> files.create(root, path, body)
        _ -> files.replace(root, path, expected, body)
      })
      use readback <- result.try(files.read(root, path))
      use _ <- result.try(a.require(readback == body, "write_readback_mismatch"))
      Ok(files.digest(readback))
    },
  )
}

pub fn build_args(args: List(String)) -> List(String) {
  build_args_at(dev.root, args)
}

fn build_args_for(
  execution: a.Execution,
  args: List(String),
) -> Result(List(String), String) {
  use source_root <- result.try(a.source_root(execution.grant))
  Ok(build_args_at(source_root, args))
}

fn build_args_at(source_root: String, args: List(String)) -> List(String) {
  [
    "--chdir=" <> source_root <> "/apps/cepaf_gleam",
    "PATH="
      <> dev.root
      <> "/toolchains/nix-profile/bin:"
      <> dev.root
      <> "/toolchains/gleam-1.16.0/bin:"
      <> dev.root
      <> "/toolchains/opam-ocaml/bin",
    "ERL_FLAGS=+S 2:2 +A 2",
    "ERL_CRASH_DUMP_SECONDS=0",
    dev.root <> "/toolchains/gleam-1.16.0/bin/gleam",
    ..args
  ]
}

// B2: an intent written before dispatch with no result is refused forever, which
// is the correct no-retry rule -- but reconcile and recover both read the
// COMPLETION-intent path, so the state had no exit at all. Quarantine is that
// exit. It is RECORDED without proving quiescence; RESUMPTION would require it,
// and this substrate cannot supply it (see quiescence_grade below), so the
// logical effect is burned rather than resumed.
pub fn burned_intent_path(intent: String) -> String {
  "var/harness/effects/burned@" <> intent <> ".json"
}

pub fn burned_signature_path(signature: String) -> String {
  "var/harness/effects/burned-signature@" <> signature <> ".json"
}

/// A new grant must not become a fresh namespace for the same logical effect, so
/// the signature tombstone is keyed OUTSIDE the grant id.
pub fn check_not_burned(
  execution: a.Execution,
  intent: String,
  signature: String,
) -> Result(Nil, String) {
  use by_intent <- result.try(a.read_optional(burned_intent_path(intent)))
  use _ <- result.try(a.require(
    by_intent == None,
    "intent_permanently_quarantined_no_retry",
  ))
  use by_signature <- result.try(
    a.read_optional(burned_signature_path(signature)),
  )
  use _ <- result.try(a.require(
    by_signature == None,
    "logical_effect_permanently_quarantined_no_retry",
  ))
  use by_grant <- result.try(
    a.read_optional(effect_path(execution, intent, "quarantine")),
  )
  a.require(by_grant == None, "intent_permanently_quarantined_no_retry")
}

pub fn record_quarantine(
  execution: a.Execution,
  intent: String,
  intent_body: String,
  reason: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(
    json.parse(intent_body, value.decoder())
    |> result.map_error(fn(_) { "intent_json" }),
  )
  use signature <- result.try(text(parsed, "signature"))
  use tool <- result.try(text(parsed, "tool"))
  use original_input <- result.try(text(parsed, "input_sha256"))
  use now <- result.try(clock.observe())
  use observed <- result.try(guard_capture_execution(execution))
  let record =
    json.object([
      #("schema", json.string("uos.harness-successor-quarantine.v1")),
      #("kind", json.string("quarantine_record")),
      #("status", json.string("QUARANTINED_OUTCOME_UNKNOWN")),
      #("disposition", json.string("PERMANENT_NO_RETRY")),
      #(
        "statement",
        json.string(
          "No success, failure or rollback has been established for this effect. "
          <> "The outcome is unknown and remains unknown. This record retires the "
          <> "logical effect; it does not resolve it.",
        ),
      ),
      #("reason", json.string(reason)),
      #("intent_id", json.string(intent)),
      #("tool", json.string(tool)),
      #("signature", json.string(signature)),
      #(
        "original_intent_path",
        json.string(effect_path(execution, intent, "intent")),
      ),
      #("original_intent_sha256", json.string(files.digest(intent_body))),
      #("original_input_sha256_observation", json.string(original_input)),
      #("execution", a.observe_execution(execution)),
      #("original_clock", case value.get(parsed, "started") {
        Ok(v) -> value.encode(v)
        Error(_) -> json.null()
      }),
      #("manifest_observation_at_quarantine", json.string(observed)),
      #("manifest_sha256_at_quarantine", json.string(files.digest(observed))),
      // Labelled observations, NOT proof. A manifest that matches says the files
      // look the same right now; it says nothing about who can still write them.
      #(
        "observation_disclaimer",
        json.string(
          "Manifest fields are point-in-time OBSERVATIONS, not evidence of quiescence "
          <> "and not evidence about the effect's outcome.",
        ),
      ),
      #(
        "quiescence_grade",
        json.string("NO_SUFFICIENT_SAME_BOOT_EVIDENCE_IN_THIS_SUBSTRATE"),
      ),
      #("resumption", json.string("REFUSED")),
      #(
        "missing_evidence",
        json.array(
          [
            "no cgroup or equivalent containment was bound to the original dispatch, so "
              <> "the descendant population cannot be enumerated",
            "tools/ecology_process.ml reaps only its owned process group; its own header "
              <> "states it does not contain children that create new sessions, so its "
              <> "return is not evidence of descendant death",
            "a changed boot_id would prove the old executor is gone, but it also fails "
              <> "validate_window, so it is not a resumption path",
            "no evidence whether the effect succeeded, failed, or partially applied",
          ],
          json.string,
        ),
      ),
      #("quarantined_at", clock.to_json(now)),
      #("system_admission", json.bool(False)),
    ])
  let path = effect_path(execution, intent, "quarantine")
  use _ <- result.try(files.create(dev.root, path, json.to_string(record)))
  let tombstone =
    json.object([
      #("intent_id", json.string(intent)),
      #("signature", json.string(signature)),
      #("quarantine_receipt", json.string(path)),
    ])
    |> json.to_string
  use _ <- result.try(files.create(
    dev.root,
    burned_intent_path(intent),
    tombstone,
  ))
  use _ <- result.try(files.create(
    dev.root,
    burned_signature_path(signature),
    tombstone,
  ))
  Ok(record)
}

pub fn effect(
  execution: a.Execution,
  name: String,
  args: value.Value,
) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  // Shared durable parent-task Andon: one uncertain planning outcome
  // stops every mutation for that parent task, across process, grant
  // and attempt. Observations, status and reconcile do not call it.
  use _ <- result.try(planning.andon_guard(
    execution.binding.plan,
    execution.binding.task,
  ))
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.fence(execution, 1000))
  let sig = signature(execution, name, args)
  use _ <- result.try(check_not_burned(execution, intent, sig))
  let result_path = effect_path(execution, intent, "result")
  use saved <- result.try(a.read_optional(result_path))
  case saved {
    Some(body) -> {
      use receipt <- result.try(replay(body, sig))
      Ok(effect_response_summary(result_path, body, True))
    }
    None -> {
      use pending <- result.try(
        a.read_optional(effect_path(execution, intent, "intent")),
      )
      use _ <- result.try(a.require(
        pending == None,
        "unknown_effect_outcome_requires_reconciliation",
      ))
      use risk <- result.try(a.risk_check(
        execution.risk_path,
        execution.scope,
        execution.binding.worker,
        execution.binding.attempt,
        True,
      ))
      use before <- result.try(capture_execution(execution))
      // The wider manifest guards concurrent modification; `before` above stays
      // the narrow candidate identity that the receipt binds.
      use guard_before <- result.try(guard_capture_execution(execution))
      use proof <- result.try(a.fence(execution, 60_000))
      let trace =
        crypto.strong_random_bytes(16)
        |> bit_array.base16_encode
        |> string.lowercase
      let span =
        crypto.strong_random_bytes(8)
        |> bit_array.base16_encode
        |> string.lowercase
      let base = [
        #("schema", json.string("uos.harness-successor-effect.v1")),
        #("intent_id", json.string(intent)),
        #("tool", json.string(name)),
        #("signature", json.string(sig)),
        #("execution", a.observe_execution(execution)),
        #("trace_id", json.string(trace)),
        #("span_id", json.string(span)),
        #("input_manifest", json.string(before)),
        #("input_sha256", json.string(files.digest(before))),
        #("risk_receipt", json.string(risk)),
        #("started", clock.to_json(proof.clock)),
      ]
      let prepared = json.object([
        #("status", json.string("PREPARED")),
        #("kind", json.string("effect_intent")),
        ..base
      ]) |> json.to_string
      use _ <- result.try(files.create(
        dev.root,
        effect_path(execution, intent, "intent"),
        prepared,
      ))
      use _ <- result.try(write_task_effect_index(
        execution, intent, "intent", "effect_intent", prepared,
      ))
      let outcome = perform(execution, name, args, 60_000)
      let verified = {
        use output <- result.try(outcome)
        use after <- result.try(capture_execution(execution))
        use guard_after <- result.try(guard_capture_execution(execution))
        use _ <- result.try(case name {
          // Was: `name == "harness_write_file" || before == after`, which let ANY
          // file move underneath a write. Now the write target must carry exactly
          // the digest claimed and everything else must be untouched.
          "harness_write_file" -> {
            use target <- result.try(text(args, "path"))
            use content <- result.try(text(args, "content"))
            write_manifest_clean(
              guard_before,
              guard_after,
              target,
              files.digest(content),
            )
          }
          _ ->
            a.require(
              guard_before == guard_after,
              "scope_changed_during_effect",
            )
        })
        use final <- result.try(a.fence(execution, 0))
        use _ <- result.try(clock.continuity(proof.clock, final.clock))
        Ok(#(output, after, final.clock))
      }
      let record = case verified {
        Ok(#(output, after, final)) ->
          json.object(
            list.flatten([
              [
                #("status", json.string("EXECUTED")),
                #("kind", json.string("effect_result")),
              ],
              effect_output_fields(output),
              [
                #("output_manifest", json.string(after)),
                #("finished", clock.to_json(final)),
              ],
              base,
            ]),
          )
        Error(e) ->
          json.object([
            #("status", json.string("FAILED_OR_UNVERIFIED")),
            #("kind", json.string("effect_result")),
            #("failure", json.string(e)),
            ..base
          ])
      }
      let record_body = json.to_string(record)
      use _ <- result.try(files.create(dev.root, result_path, record_body))
      case verified {
        Ok(_) -> Ok(effect_response_summary(result_path, record_body, False))
        Error(e) -> {
          let known_exit = case outcome {
            Error(cause) ->
              string.starts_with(cause, "backend_exit:")
              && name != "harness_write_file"
            Ok(_) -> False
          }
          let label = case known_exit {
            True -> "effect_failed:"
            False -> "effect_unverified:"
          }
          Error(label <> e <> ";receipt:" <> result_path)
        }
      }
    }
  }
}

/// Build a literal OTP invocation for the one test dispatcher compiled from
/// the candidate's test tree. No caller-provided eval text, shell or executable
/// is accepted. Every `-pa` entry is an immediate compiled package ebin under
/// the already-admitted candidate root.
pub fn test_runner_arguments(
  source_root: String,
  modules: List(String),
) -> Result(List(String), String) {
  use _ <- result.try(a.require(
    test_module_manifest_valid(modules),
    "test_module_manifest_invalid",
  ))
  let package_root = source_root <> "/apps/cepaf_gleam/build/dev/erlang"
  use packages <- result.try(
    simplifile.read_directory(package_root)
    |> result.map_error(fn(_) { "test_runner_packages_unavailable" }),
  )
  use _ <- result.try(a.require(
    packages != []
      && list.length(packages) <= 128
      && list.all(packages, a.component),
    "test_runner_packages_invalid",
  ))
  let paths =
    list.fold(packages, [], fn(paths, package) {
      let ebin = package_root <> "/" <> package <> "/ebin"
      case simplifile.read_directory(ebin) {
        Ok(_) -> [ebin, ..paths]
        Error(_) -> paths
      }
    })
  use app_entries <- result.try(
    simplifile.read_directory(package_root <> "/cepaf_gleam/ebin")
    |> result.map_error(fn(_) { "test_runner_application_ebin_missing" }),
  )
  use _ <- result.try(a.require(
    list.contains(app_entries, "harness_task_verification.beam")
      && list.all(modules, fn(module) {
      list.contains(app_entries, module <> ".beam")
    }),
    "test_runner_module_not_compiled",
  ))
  test_runner_argv(paths, modules)
}

pub fn test_runner_argv(
  ebin_paths: List(String),
  modules: List(String),
) -> Result(List(String), String) {
  use _ <- result.try(a.require(
    test_module_manifest_valid(modules),
    "test_module_manifest_invalid",
  ))
  use _ <- result.try(a.require(
    ebin_paths != []
      && list.length(ebin_paths) <= 128
      && list.all(ebin_paths, fn(path) {
      string.starts_with(path, "/")
      && !string.contains(path, "\u{0}")
      && string.byte_size(path) <= 1024
    }),
    "test_runner_ebin_paths_invalid",
  ))
  Ok([
    "+S",
    "2:2",
    "+A",
    "2",
    "-noshell",
    ..list.flatten([
      list.flatten(list.map(ebin_paths, fn(path) { ["-pa", path] })),
      ["-s", "harness_task_verification", "main", "-extra", ..modules],
    ])
  ])
}

pub fn test_module_manifest_valid(modules: List(String)) -> Bool {
  modules != []
  && list.length(modules) <= 32
  && list.all(modules, fn(name) {
    string.ends_with(name, "_test")
    && string.byte_size(name) <= 120
    && list.all(string.to_graphemes(name), fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  })
}

/// Return only a compact response projection. The exact full receipt remains
/// durably stored and addressable by path and digest.
pub fn effect_response_summary(
  receipt_path: String,
  exact_receipt_body: String,
  replayed: Bool,
) -> json.Json {
  let parsed = case json.parse(exact_receipt_body, value.decoder()) {
    Ok(value.Object(fields)) -> value.Object(fields)
    _ -> value.Object([])
  }
  let retained = text_or_empty(parsed, "output")
  let tail = bounded_suffix(retained, 2048)
  json.object([
    #("status", json.string(text_or_empty(parsed, "status"))),
    #("kind", json.string(text_or_empty(parsed, "kind"))),
    #(
      "candidate_manifest_sha256",
      json.string(text_or_empty(parsed, "input_sha256")),
    ),
    #("failure", json.string(text_or_empty(parsed, "failure"))),
    #("replayed", json.bool(replayed)),
    #("replayed_from", json.string(text_or_empty(parsed, "replayed_from"))),
    #("original_sha256", json.string(text_or_empty(parsed, "original_sha256"))),
    #("receipt_path", json.string(receipt_path)),
    #("receipt_sha256", json.string(files.digest(exact_receipt_body))),
    #("receipt_bytes", json.int(string.byte_size(exact_receipt_body))),
    #("output_tail", json.string(tail)),
    #("output_tail_sha256", json.string(files.digest(tail))),
    #("output_tail_bytes", json.int(string.byte_size(tail))),
    #("output_tail_truncated", json.bool(tail != retained)),
    #(
      "output_truncated",
      json.bool(text_or_empty(parsed, "output_retention") != "full"),
    ),
    #(
      "output_retained_bytes",
      json.int(int_or_zero(parsed, "output_retained_bytes")),
    ),
    #("output_bytes", json.int(int_or_zero(parsed, "output_bytes"))),
    #("output_sha256", json.string(text_or_empty(parsed, "output_sha256"))),
    #(
      "output_retained_sha256",
      json.string(text_or_empty(parsed, "output_retained_sha256")),
    ),
    #(
      "output_retention",
      json.string(text_or_empty(parsed, "output_retention")),
    ),
  ])
}

fn bounded_suffix(text: String, byte_limit: Int) -> String {
  take_suffix_graphemes(
    string.to_graphemes(text) |> list.reverse,
    byte_limit,
    0,
    [],
  )
}

fn take_suffix_graphemes(
  reversed_graphemes: List(String),
  byte_limit: Int,
  used_bytes: Int,
  selected_reversed: List(String),
) -> String {
  case reversed_graphemes {
    [grapheme, ..rest] -> {
      let grapheme_bytes = string.byte_size(grapheme)
      case used_bytes + grapheme_bytes <= byte_limit {
        True ->
          take_suffix_graphemes(rest, byte_limit, used_bytes + grapheme_bytes, [
            grapheme,
            ..selected_reversed
          ])
        False -> string.concat(selected_reversed)
      }
    }
    _ -> string.concat(selected_reversed)
  }
}

fn text_or_empty(record: value.Value, key: String) -> String {
  case value.get(record, key) {
    Ok(value.Text(text)) -> text
    _ -> ""
  }
}

fn int_or_zero(record: value.Value, key: String) -> Int {
  case value.get(record, key) {
    Ok(value.Integer(number)) -> number
    _ -> 0
  }
}

pub fn read_file(
  execution: a.Execution,
  path: String,
) -> Result(json.Json, String) {
  use _ <- result.try(a.fence(execution, 1000))
  use _ <- result.try(a.require(
    list.contains(execution.scope.reads, path)
      || list.contains(execution.scope.writes, path)
      || list.contains(execution.scope.sources, path),
    "read_scope_refused",
  ))
  use root <- result.try(root_for_path(execution, path))
  use body <- result.try(files.read(root, path))
  use _ <- result.try(a.fence(execution, 0))
  Ok(
    json.object([
      #("path", json.string(path)),
      #("content", json.string(body)),
      #("sha256", json.string(files.digest(body))),
      #("execution", a.observe_execution(execution)),
    ]),
  )
}

pub fn assessment_paths_allowed(
  grant: a.Grant,
  body: String,
) -> Result(Nil, String) {
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "assessment_json" }),
  )
  use records <- result.try(case parsed {
    value.Array(xs) -> Ok(xs)
    _ -> Error("assessment_array")
  })
  let allowed =
    list.flatten(
      list.map(grant.scopes, fn(scope) {
        list.append(scope.sources, scope.reads)
      }),
    )
  list.try_each(records, fn(record) {
    use snapshot <- result.try(value.get(record, "snapshot"))
    use entries <- result.try(value.get(snapshot, "evidence"))
    use entries <- result.try(case entries {
      value.Array(xs) -> Ok(xs)
      _ -> Error("assessment_evidence_array")
    })
    list.try_each(entries, fn(entry) {
      use path <- result.try(text(entry, "path"))
      a.require(
        a.public_path(path) && list.contains(allowed, path),
        "assessment_source_outside_grant",
      )
    })
  })
}

fn evidence_judgment_projection(value: value.Value) -> value.Value {
  case value {
    value.Object(fields) -> value.Object(list.filter(fields, fn(field) {
      !list.contains(["observed_at", "sha256"], field.0)
    }))
    _ -> value
  }
}

fn snapshot_judgment_projection(value: value.Value) -> value.Value {
  case value {
    value.Object(fields) -> value.Object(list.map(fields, fn(field) {
      case field.0, field.1 {
        "evidence", value.Array(items) -> #(
          "evidence",
          value.Array(list.map(items, evidence_judgment_projection)),
        )
        _, _ -> field
      }
    }))
    _ -> value
  }
}

pub fn judgment_projection(value: value.Value) -> value.Value {
  case value {
    value.Object(fields) ->
      value.Object(list.filter_map(fields, fn(field) {
        case field.0, field.1 {
          "actor", _ | "task_state", _ | "observed_at", _ | "valid_until", _
          | "assessment_id", _ | "ready_since", _ -> Error(Nil)
          "snapshot", snapshot ->
            Ok(#("snapshot", snapshot_judgment_projection(snapshot)))
          _, _ -> Ok(field)
        }
      }))
    _ -> value
  }
}

pub fn judgments_match(original: String, proposed: String) -> Result(Nil, String) {
  use old_json <- result.try(json.parse(original, value.decoder()) |> result.map_error(fn(_) { "baseline_json" }))
  use new_json <- result.try(json.parse(proposed, value.decoder()) |> result.map_error(fn(_) { "assessment_json" }))
  use old_rows <- result.try(case old_json { value.Array(xs) -> Ok(xs) _ -> Error("baseline_array_required") })
  use new_rows <- result.try(case new_json { value.Array(xs) -> Ok(xs) _ -> Error("assessment_array_required") })
  use _ <- result.try(a.require(list.length(old_rows) == list.length(new_rows), "assessment_cardinality_changed"))
  list.try_each(new_rows, fn(record) {
    use task <- result.try(text(record, "task_id"))
    use previous <- result.try(case list.find(old_rows, fn(old) {
      value.get(old, "task_id") == Ok(value.Text(task))
    }) { Ok(found) -> Ok(found) Error(_) -> Error("baseline_task_missing") })
    a.require(judgment_projection(previous) == judgment_projection(record), "raw_judgment_mutation_refused")
  })
}

pub fn initial_plan_rows(raw: String) -> Result(List(value.Value), String) {
  let lines = string.split(raw, "\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { string.byte_size(line) > 0 })
  let task_lines = list.filter(lines, fn(line) { string.starts_with(line, "{") })
  let diagnostics = list.filter(lines, fn(line) { string.starts_with(line, "sa-plan-pipeline ") })
  use _ <- result.try(a.require(
    list.length(task_lines) > 0 && list.length(diagnostics) == 1
      && list.length(task_lines) + list.length(diagnostics) == list.length(lines),
    "canonical_task_list_output_invalid",
  ))
  list.try_map(task_lines, fn(line) {
    json.parse(line, value.decoder())
    |> result.map_error(fn(_) { "canonical_task_row_invalid" })
  })
}

fn initial_ids(rows: List(value.Value)) -> Result(List(String), String) {
  list.try_map(rows, fn(row) { text(row, "id") })
}

pub fn initial_rows_match(
  records: List(value.Value),
  rows: List(value.Value),
  baseline: List(value.Value),
  plan: String,
) -> Result(Nil, String) {
  use _ <- result.try(a.require(list.length(records) == list.length(rows), "canonical_task_count_mismatch"))
  use row_ids <- result.try(initial_ids(rows))
  use _ <- result.try(a.require(
    list.length(list.unique(row_ids)) == list.length(row_ids),
    "canonical_task_duplicate_id",
  ))
  use record_ids <- result.try(list.try_map(records, fn(record) { text(record, "task_id") }))
  use _ <- result.try(a.require(
    list.length(list.unique(record_ids)) == list.length(record_ids)
      && list.all(row_ids, fn(id) { list.contains(record_ids, id) }),
    "assessment_task_set_mismatch",
  ))
  list.try_each(records, fn(record) {
    use record_plan <- result.try(text(record, "plan_id"))
    use task <- result.try(text(record, "task_id"))
    use actor <- result.try(text(record, "actor"))
    use state <- result.try(text(record, "task_state"))
    use _ <- result.try(a.require(record_plan == plan, "assessment_plan_mismatch"))
    use row <- result.try(case list.find(rows, fn(row) {
      value.get(row, "id") == Ok(value.Text(task))
    }) {
      Ok(found) -> Ok(found)
      Error(_) -> Error("canonical_task_missing")
    })
    use row_state <- result.try(text(row, "state"))
    use _ <- result.try(a.require(row_state == state, "canonical_task_state_mismatch"))
    use row_worker <- result.try(value.get(row, "worker"))
    let verified_actor = case row_state, row_worker {
      "executing", value.Text(worker) -> actor == worker
      "completed", value.Text(worker) -> actor == worker
      _, _ -> case list.find(baseline, fn(old) {
        value.get(old, "task_id") == Ok(value.Text(task))
      }) {
        Ok(previous) -> value.get(previous, "actor") == Ok(value.Text(actor))
        Error(_) -> False
      }
    }
    a.require(verified_actor, "canonical_task_actor_mismatch")
  })
}

fn initial_int(row: value.Value, key: String) -> Result(Int, String) {
  use field <- result.try(value.get(row, key))
  case field {
    value.Integer(number) -> Ok(number)
    value.Text(number) -> int.parse(number) |> result.map_error(fn(_) { "canonical_attempt_invalid" })
    _ -> Error("canonical_attempt_invalid")
  }
}

pub type InitialPortfolioBefore {
  InitialPortfolioPresent(body: String, sha256: String)
  InitialPortfolioAbsent
}

pub fn assessment_seed_binding(
  grant_document: value.Value,
  scope: a.Scope,
) -> Result(#(String, String), String) {
  use candidate_binding <- result.try(
    value.get(grant_document, "candidate_binding")
      |> result.map_error(fn(_) { "assessment_seed_binding_missing" }),
  )
  use seed <- result.try(
    value.get(candidate_binding, "assessment_seed")
      |> result.map_error(fn(_) { "assessment_seed_binding_missing" }),
  )
  use plan <- result.try(text(seed, "plan"))
  use task <- result.try(text(seed, "task"))
  use path <- result.try(text(seed, "path"))
  use sha256 <- result.try(text(seed, "sha256"))
  use _ <- result.try(a.require(
    plan == scope.plan && task == scope.task,
    "assessment_seed_scope_mismatch",
  ))
  use _ <- result.try(a.require(
    a.public_path(path) && list.contains(scope.reads, path)
      && path != scope.portfolio,
    "assessment_seed_path_refused",
  ))
  use _ <- result.try(a.require(
    a.digest_valid(sha256),
    "assessment_seed_digest_invalid",
  ))
  Ok(#(path, sha256))
}

pub fn initial_portfolio_before(
  verified_seed: Result(String, String),
  target: Option(String),
) -> Result(InitialPortfolioBefore, String) {
  use _ <- result.try(verified_seed)
  case target {
    Some(body) -> Ok(InitialPortfolioPresent(body, files.digest(body)))
    None -> Ok(InitialPortfolioAbsent)
  }
}

pub fn assessment_seed_digest_matches(
  expected_sha256: String,
  seed_bytes: String,
) -> Bool {
  a.digest_valid(expected_sha256) && files.digest(seed_bytes) == expected_sha256
}

fn verified_assessment_seed(
  grant: a.Grant,
  scope: a.Scope,
) -> Result(String, String) {
  use _ <- result.try(a.check(grant))
  use grant_document <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(a.require(
    files.digest(grant_document) == grant.digest,
    "grant_document_digest_mismatch",
  ))
  use parsed <- result.try(
    json.parse(grant_document, value.decoder())
      |> result.map_error(fn(_) { "grant_document_json" }),
  )
  use #(path, expected_sha256) <- result.try(
    assessment_seed_binding(parsed, scope),
  )
  use seed <- result.try(files.read(dev.root, path))
  use _ <- result.try(a.require(
    assessment_seed_digest_matches(expected_sha256, seed),
    "assessment_seed_digest_mismatch",
  ))
  Ok(seed)
}

pub fn assess_initial(
  grant: a.Grant,
  args: value.Value,
) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  use body <- result.try(text(args, "assessment_json"))
  use reason <- result.try(text(args, "reason"))
  use _ <- result.try(a.require(
    a.intent_valid(intent) && string.byte_size(reason) >= 16 && string.byte_size(reason) <= 2048,
    "qualified_assessment_reason_required",
  ))
  use scope <- result.try(case grant.scopes {
    [only] -> Ok(only)
    _ -> Error("pre_attach_assessment_requires_unique_scope")
  })
  use _ <- result.try(a.check(grant))
  use _ <- result.try(a.require(a.scope_valid(scope), "scope_invalid"))
  use _ <- result.try(assessment_paths_allowed(grant, body))
  use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "assessment_json" }))
  use records <- result.try(case parsed {
    value.Array(xs) -> Ok(xs)
    _ -> Error("assessment_array_required")
  })
  use seed <- result.try(verified_assessment_seed(grant, scope))
  use #(seed_path, seed_sha) <- result.try(assessment_seed_binding_for_grant(grant, scope))
  let request_signature = assessment_request_signature(
    grant.digest, grant.worker, scope.plan, scope.task, scope.portfolio,
    seed_path, seed_sha, intent, files.digest(body), files.digest(reason),
  )
  // The replay lookup is optional, but its checked parent must exist.
  // Seed and scope validation above must succeed before metadata creation.
  use _ <- result.try(ensure_assessment_target_directory(scope))
  use replayed <- result.try(initial_assessment_replay(
    grant, scope, intent, request_signature, body,
  ))
  case replayed {
    Some(receipt) -> Ok(receipt)
    None -> {
      use pending <- result.try(assessment_target_pending(scope.plan, scope.task, scope.portfolio))
      use _ <- result.try(a.require(!pending, "assessment_prepared_stop_line"))
      initial_assessment_first_apply(
        grant, scope, intent, body, reason, seed, request_signature, records,
      )
    }
  }
}

pub fn assessment_pending_state(
  prepared: value.Value,
  terminal_exists: Bool,
  plan: String,
  task: String,
  portfolio: String,
) -> Result(Bool, String) {
  use schema <- result.try(text(prepared, "schema"))
  use state <- result.try(text(prepared, "state"))
  use found_plan <- result.try(text(prepared, "plan"))
  use found_task <- result.try(text(prepared, "task"))
  use found_portfolio <- result.try(text(prepared, "portfolio_path"))
  use intent <- result.try(text(prepared, "intent_id"))
  use signature <- result.try(text(prepared, "request_signature"))
  use grant_sha <- result.try(text(prepared, "grant_sha256"))
  use body_sha <- result.try(text(prepared, "body_sha256"))
  use reason_sha <- result.try(text(prepared, "reason_sha256"))
  use seed_sha <- result.try(text(prepared, "seed_sha256"))
  use before_state <- result.try(text(prepared, "before_state"))
  use before_sha <- result.try(text(prepared, "before_sha256"))
  use _ <- result.try(a.require(
    schema == "uos.harness-pre-attach-assessment-ledger.v1"
      && state == "PREPARED"
      && a.intent_valid(intent)
      && a.digest_valid(signature)
      && a.digest_valid(grant_sha)
      && a.digest_valid(body_sha)
      && a.digest_valid(reason_sha)
      && a.digest_valid(seed_sha)
      && {
        before_state == "ABSENT" && before_sha == "ABSENT"
          || before_state == "PRESENT" && a.digest_valid(before_sha)
      },
    "assessment_ledger_record_invalid",
  ))
  Ok(found_plan == plan && found_task == task && found_portfolio == portfolio && !terminal_exists)
}

pub fn assessment_terminal_valid(
  terminal: value.Value,
  signature: String,
  host: String,
  boot: String,
) -> Bool {
  let receipt_valid = case value.get(terminal, "receipt") {
    Ok(receipt) -> case value.get(receipt, "status") {
      Ok(value.Text("PASS")) | Ok(value.Text("NO_CHANGE")) ->
        case value.get(receipt, "assessment_path"),
             value.get(receipt, "assessment_sha256"),
             value.get(receipt, "portfolio_path"),
             value.get(receipt, "portfolio_sha256") {
          Ok(value.Text(assessment_path)), Ok(value.Text(assessment_sha)),
          Ok(value.Text(portfolio_path)), Ok(value.Text(portfolio_sha)) ->
            string.byte_size(assessment_path) > 0
              && string.byte_size(portfolio_path) > 0
              && a.digest_valid(assessment_sha)
              && a.digest_valid(portfolio_sha)
          _, _, _, _ -> False
        }
      _ -> False
    }
    _ -> False
  }
  let timestamp_valid = case value.get(terminal, "terminal_at") {
    Ok(timestamp) -> {
      let shape =
        value.get(timestamp, "host_id") == Ok(value.Text(host))
          && value.get(timestamp, "boot_id") == Ok(value.Text(boot))
          && value.get(timestamp, "authority") == Ok(value.Text("OBSERVATION_ONLY"))
          && case value.get(timestamp, "utc"), value.get(timestamp, "utc_us"),
                 value.get(timestamp, "boot_us"),
                 value.get(timestamp, "offset_us"),
                 value.get(timestamp, "uncertainty_us"),
                 value.get(timestamp, "reference_age_us"),
                 value.get(timestamp, "receipt_age_us"),
                 value.get(timestamp, "delivery_us"),
                 value.get(timestamp, "source"),
                 value.get(timestamp, "reference_max_age_us"),
                 value.get(timestamp, "sample_max_delivery_us") {
            Ok(value.Text(utc)), Ok(value.Text(utc_us)), Ok(value.Text(boot_us)),
            Ok(value.Integer(_offset)), Ok(value.Integer(uncertainty)),
            Ok(value.Integer(reference_age)), Ok(value.Integer(receipt_age)),
            Ok(value.Integer(delivery)), Ok(value.Text(source)),
            Ok(value.Integer(reference_max)), Ok(value.Integer(sample_max)) ->
              case int.parse(utc_us), int.parse(boot_us) {
                Ok(utc_value), Ok(boot_value) ->
                  utc_value > 0
                    && boot_value > 0
                    && iso8601_from_nanos(utc_value * 1000) == utc
                    && uncertainty >= 0
                    && reference_age >= 0
                    && receipt_age >= 0
                    && delivery >= 0
                    && reference_max > 0
                    && sample_max > 0
                    && string.byte_size(source) > 0
                _, _ -> False
              }
            _, _, _, _, _, _, _, _, _, _, _ -> False
          }
      shape
    }
    _ -> False
  }
  value.get(terminal, "schema")
    == Ok(value.Text("uos.harness-pre-attach-assessment-terminal.v1"))
    && value.get(terminal, "state") == Ok(value.Text("TERMINAL"))
    && value.get(terminal, "request_signature") == Ok(value.Text(signature))
    && a.digest_valid(signature)
    && receipt_valid
    && timestamp_valid
}

pub fn assessment_terminal_matches(
  terminal: value.Value,
  signature: String,
  assessment_path: String,
  assessment_sha: String,
  portfolio_path: String,
  portfolio_sha: String,
  host: String,
  boot: String,
) -> Bool {
  assessment_terminal_valid(terminal, signature, host, boot)
    && case value.get(terminal, "receipt") {
      Ok(receipt) ->
        value.get(receipt, "assessment_path") == Ok(value.Text(assessment_path))
          && value.get(receipt, "assessment_sha256") == Ok(value.Text(assessment_sha))
          && value.get(receipt, "portfolio_path") == Ok(value.Text(portfolio_path))
          && value.get(receipt, "portfolio_sha256") == Ok(value.Text(portfolio_sha))
      _ -> False
    }
}

fn prepared_assessment_body_sha(
  prepared: value.Value,
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  signature: String,
  assessment_path: String,
) -> Result(String, String) {
  use schema <- result.try(text(prepared, "schema"))
  use state <- result.try(text(prepared, "state"))
  use stored_signature <- result.try(text(prepared, "request_signature"))
  use stored_grant <- result.try(text(prepared, "grant_sha256"))
  use plan <- result.try(text(prepared, "plan"))
  use task <- result.try(text(prepared, "task"))
  use portfolio <- result.try(text(prepared, "portfolio_path"))
  use stored_intent <- result.try(text(prepared, "intent_id"))
  use stored_path <- result.try(text(prepared, "assessment_path"))
  use host <- result.try(text(prepared, "host_id"))
  use boot <- result.try(text(prepared, "boot_id"))
  use body_sha <- result.try(text(prepared, "body_sha256"))
  let schema_valid = case schema {
    "uos.harness-pre-attach-assessment-ledger.v1"
    | "uos.harness-attached-assessment-ledger.v1" -> True
    _ -> False
  }
  use _ <- result.try(a.require(
    schema_valid
      && state == "PREPARED"
      && stored_signature == signature
      && stored_grant == grant.digest
      && plan == scope.plan
      && task == scope.task
      && portfolio == scope.portfolio
      && stored_intent == intent
      && stored_path == assessment_path
      && host == grant.host
      && boot == grant.boot
      && a.digest_valid(body_sha),
    "assessment_prepared_binding_mismatch",
  ))
  Ok(body_sha)
}

pub fn assessment_ledger_candidates(
  names: List(String),
  target_prefix: String,
) -> Result(List(String), String) {
  let candidates = list.filter(names, fn(name) {
    string.starts_with(name, target_prefix)
      && string.ends_with(name, "-assessment-ledger.json")
  })
  case list.length(names) <= 8192 && list.length(candidates) <= 128 {
    True -> Ok(candidates)
    False -> Error("assessment_ledger_scan_bound_exceeded")
  }
}


pub fn assessment_lock_path_for(root: String, portfolio: String) -> String {
  "var/harness/assessment-path-lock-"
    <> files.digest(root <> "\u{0}" <> portfolio)
    <> ".json"
}

pub fn assessment_lock_path(portfolio: String) -> String {
  assessment_lock_path_for(dev.root, portfolio)
}

pub fn assessment_lock_record(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  signature: String,
) -> String {
  json.object([
    #("schema", json.string("uos.harness-assessment-path-lock.v1")),
    #("state", json.string("HELD")),
    #("canonical_root", json.string(dev.root)),
    #("portfolio_path", json.string(scope.portfolio)),
    #("plan", json.string(scope.plan)),
    #("task", json.string(scope.task)),
    #("grant_sha256", json.string(grant.digest)),
    #("worker", json.string(grant.worker)),
    #("intent_id", json.string(intent)),
    #("request_signature", json.string(signature)),
  ]) |> json.to_string
}

pub fn assessment_lock_matches(
  record: value.Value,
  grant_sha: String,
  plan: String,
  task: String,
  portfolio: String,
  worker: String,
  intent: String,
  signature: String,
) -> Bool {
  value.get(record, "schema") == Ok(value.Text("uos.harness-assessment-path-lock.v1"))
    && value.get(record, "state") == Ok(value.Text("HELD"))
    && value.get(record, "canonical_root") == Ok(value.Text(dev.root))
    && value.get(record, "portfolio_path") == Ok(value.Text(portfolio))
    && value.get(record, "plan") == Ok(value.Text(plan))
    && value.get(record, "task") == Ok(value.Text(task))
    && value.get(record, "grant_sha256") == Ok(value.Text(grant_sha))
    && value.get(record, "worker") == Ok(value.Text(worker))
    && value.get(record, "intent_id") == Ok(value.Text(intent))
    && value.get(record, "request_signature") == Ok(value.Text(signature))
    && a.digest_valid(grant_sha)
    && a.digest_valid(signature)
    && a.intent_valid(intent)
}

fn acquire_assessment_path_lock(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  signature: String,
) -> Result(String, String) {
  a.with_assessment_portfolio_lock(scope.portfolio, intent, fn() {
    let body = assessment_lock_record(grant, scope, intent, signature)
    use _ <- result.try(files.create(
      dev.root,
      assessment_lock_path(scope.portfolio),
      body,
    ) |> result.map_error(fn(_) { "assessment_path_lock_held_or_unavailable" }))
    Ok(body)
  })
}

fn attached_assessment_prepared_path(grant: a.Grant, intent: String) -> String {
  "var/harness/" <> grant.id <> "-" <> intent <> "-assessment-prepared.json"
}

fn release_assessment_path_lock(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  signature: String,
) -> Result(Nil, String) {
  a.with_assessment_portfolio_lock(scope.portfolio, intent <> "-release", fn() {
    let lock_path = assessment_lock_path(scope.portfolio)
    let expected_lock = assessment_lock_record(grant, scope, intent, signature)
    use current <- result.try(files.read_optional(dev.root, lock_path))
    case current {
      None -> Ok(Nil)
      Some(raw) -> {
        use parsed_lock <- result.try(
          json.parse(raw, value.decoder())
            |> result.map_error(fn(_) { "assessment_path_lock_json" }),
        )
        use _ <- result.try(a.require(
          raw == expected_lock
            && assessment_lock_matches(
              parsed_lock, grant.digest, scope.plan, scope.task, scope.portfolio,
              grant.worker, intent, signature,
            ),
          "assessment_path_lock_owner_mismatch",
        ))
        let ledger_path = initial_assessment_ledger_path(scope, grant, intent)
        use maybe_prepared <- result.try(files.read_optional(dev.root, ledger_path))
        use prepared_raw <- result.try(case maybe_prepared {
          Some(saved) -> Ok(saved)
          None -> files.read(dev.root, attached_assessment_prepared_path(grant, intent))
        })
        use prepared <- result.try(
          json.parse(prepared_raw, value.decoder())
            |> result.map_error(fn(_) { "assessment_prepared_json" }),
        )
        let assessment_path =
          "var/harness/" <> grant.id <> "-" <> intent <> "-assessment.json"
        use expected_body_sha <- result.try(prepared_assessment_body_sha(
          prepared,
          grant,
          scope,
          intent,
          signature,
          assessment_path,
        ))
        let terminal_path = ledger_path <> ".terminal.json"
        use terminal_raw <- result.try(files.read(dev.root, terminal_path))
        use terminal <- result.try(
          json.parse(terminal_raw, value.decoder())
            |> result.map_error(fn(_) { "assessment_terminal_json" }),
        )
        use assessment_body <- result.try(files.read(dev.root, assessment_path))
        use portfolio_body <- result.try(files.read(dev.root, scope.portfolio))
        use _ <- result.try(a.require(
          files.digest(assessment_body) == expected_body_sha
            && files.digest(portfolio_body) == expected_body_sha
            && assessment_terminal_matches(
              terminal,
              signature,
              assessment_path,
              expected_body_sha,
              scope.portfolio,
              expected_body_sha,
              grant.host,
              grant.boot,
            ),
          "assessment_terminal_binding_mismatch",
        ))
        simplifile.delete_file(dev.root <> "/" <> lock_path)
          |> result.map_error(fn(_) { "assessment_path_lock_release_failed" })
      }
    }
  })
}
pub fn task_effect_index_directory_for(root: String, plan: String, task: String) -> String {
  "var/harness/effects/by-task/" <> files.digest(root <> "\u{0}" <> plan <> "\u{0}" <> task)
}

fn task_effect_index_directory(plan: String, task: String) -> String {
  task_effect_index_directory_for(dev.root, plan, task)
}

fn task_effect_index_path(
  plan: String,
  task: String,
  grant_id: String,
  intent: String,
  suffix: String,
) -> String {
  task_effect_index_directory(plan, task)
    <> "/"
    <> grant_id
    <> "@"
    <> intent
    <> "@"
    <> suffix
    <> ".index.json"
}

fn write_task_effect_index(
  execution: a.Execution,
  intent: String,
  suffix: String,
  kind: String,
  prepared: String,
) -> Result(Nil, String) {
  let directory = task_effect_index_directory(
    execution.scope.plan,
    execution.scope.task,
  )
  use _ <- result.try(
    simplifile.create_directory_all(dev.root <> "/" <> directory)
      |> result.map_error(fn(_) { "task_effect_index_directory_unavailable" }),
  )
  let pointer = json.object([
    #("schema", json.string("uos.harness-task-effect-index.v1")),
    #("plan", json.string(execution.scope.plan)),
    #("task", json.string(execution.scope.task)),
    #("grant_id", json.string(execution.grant.id)),
    #("grant_sha256", json.string(execution.grant.digest)),
    #("worker", json.string(execution.binding.worker)),
    #("attempt", json.int(execution.binding.attempt)),
    #("intent_id", json.string(intent)),
    #("suffix", json.string(suffix)),
    #("kind", json.string(kind)),
    #("record_path", json.string(effect_path_for(execution.grant.id, intent, suffix))),
    #("prepared_sha256", json.string(files.digest(prepared))),
  ]) |> json.to_string
  files.create(
    dev.root,
    task_effect_index_path(
      execution.scope.plan,
      execution.scope.task,
      execution.grant.id,
      intent,
      suffix,
    ),
    pointer,
  )
}

pub fn task_effect_index_candidates(names: List(String)) -> Result(List(String), String) {
  let candidates = list.filter(names, fn(name) {
    string.ends_with(name, "@intent.index.json")
      || string.ends_with(name, "@completion-intent.index.json")
  })
  case list.length(names) <= 4096 && list.length(candidates) <= 256 {
    True -> Ok(candidates)
    False -> Error("task_effect_index_scan_bound_exceeded")
  }
}

pub fn task_effect_index_matches(
  pointer: value.Value,
  plan: String,
  task: String,
  grant_id: String,
  grant_sha: String,
  worker: String,
  attempt: Int,
  intent: String,
  suffix: String,
  kind: String,
  prepared_sha: String,
) -> Bool {
  value.get(pointer, "schema") == Ok(value.Text("uos.harness-task-effect-index.v1"))
    && value.get(pointer, "plan") == Ok(value.Text(plan))
    && value.get(pointer, "task") == Ok(value.Text(task))
    && value.get(pointer, "grant_id") == Ok(value.Text(grant_id))
    && value.get(pointer, "grant_sha256") == Ok(value.Text(grant_sha))
    && value.get(pointer, "worker") == Ok(value.Text(worker))
    && value.get(pointer, "attempt") == Ok(value.Integer(attempt))
    && value.get(pointer, "intent_id") == Ok(value.Text(intent))
    && value.get(pointer, "suffix") == Ok(value.Text(suffix))
    && value.get(pointer, "kind") == Ok(value.Text(kind))
    && value.get(pointer, "record_path")
      == Ok(value.Text(effect_path_for(grant_id, intent, suffix)))
    && value.get(pointer, "prepared_sha256") == Ok(value.Text(prepared_sha))
    && a.intent_valid(intent)
    && a.digest_valid(grant_sha)
    && a.digest_valid(prepared_sha)
    && attempt > 0
}

fn task_effect_index_candidate_pending(
  index_name: String,
  plan: String,
  task: String,
) -> Result(Bool, String) {
  use pointer_raw <- result.try(files.read(
    dev.root,
    task_effect_index_directory(plan, task) <> "/" <> index_name,
  ))
  use pointer <- result.try(
    json.parse(pointer_raw, value.decoder())
      |> result.map_error(fn(_) { "task_effect_index_json" }),
  )
  use grant_id <- result.try(text(pointer, "grant_id"))
  use grant_sha <- result.try(text(pointer, "grant_sha256"))
  use worker <- result.try(text(pointer, "worker"))
  use attempt <- result.try(case value.get(pointer, "attempt") {
    Ok(value.Integer(n)) -> Ok(n)
    _ -> Error("task_effect_index_attempt")
  })
  use intent <- result.try(text(pointer, "intent_id"))
  use suffix <- result.try(text(pointer, "suffix"))
  use kind <- result.try(text(pointer, "kind"))
  use prepared_sha <- result.try(text(pointer, "prepared_sha256"))
  let expected_kind = case suffix {
    "intent" -> "effect_intent"
    "completion-intent" -> "completion_intent"
    _ -> ""
  }
  use _ <- result.try(a.require(
    kind == expected_kind
      && task_effect_index_matches(
        pointer, plan, task, grant_id, grant_sha, worker, attempt,
        intent, suffix, kind, prepared_sha,
      ),
    "task_effect_index_binding_invalid",
  ))
  let record_name =
    grant_id <> "@" <> intent <> "@" <> suffix <> ".json"
  let record_path = effect_path_for(grant_id, intent, suffix)
  use raw <- result.try(files.read(dev.root, record_path))
  use _ <- result.try(a.require(
    files.digest(raw) == prepared_sha,
    "task_effect_index_prepared_digest_mismatch",
  ))
  use prepared <- result.try(
    json.parse(raw, value.decoder())
      |> result.map_error(fn(_) { "task_effect_index_prepared_json" }),
  )
  use identity <- result.try(value.get(prepared, "execution"))
  use _ <- result.try(a.require(
    value.get(prepared, "intent_id") == Ok(value.Text(intent))
      && value.get(identity, "grant_sha256") == Ok(value.Text(grant_sha))
      && value.get(identity, "worker") == Ok(value.Text(worker))
      && value.get(identity, "attempt") == Ok(value.Integer(attempt)),
    "task_effect_index_prepared_binding_mismatch",
  ))
  use matches <- result.try(prepared_task_identity_matches(
    prepared, plan, task, kind,
  ))
  case matches {
    False -> Error("task_effect_index_task_identity_mismatch")
    True -> task_intent_candidate_pending(record_name, plan, task)
  }
}

pub fn task_intent_candidates(names: List(String)) -> Result(List(String), String) {
  let candidates = list.filter(names, fn(name) {
    string.ends_with(name, "@intent.json")
      || string.ends_with(name, "@completion-intent.json")
  })
  case list.length(names) <= 4096 {
    True -> Ok(candidates)
    False -> Error("task_intent_scan_bound_exceeded")
  }
}

fn prepared_task_identity_matches(
  record: value.Value,
  plan: String,
  task: String,
  expected_kind: String,
) -> Result(Bool, String) {
  use identity <- result.try(value.get(record, "execution"))
  let matches =
    value.get(identity, "plan") == Ok(value.Text(plan))
      && value.get(identity, "task") == Ok(value.Text(task))
  case matches {
    False -> Ok(False)
    True -> {
      use schema <- result.try(text(record, "schema"))
      use kind <- result.try(text(record, "kind"))
      let expected_schema = case expected_kind {
        "effect_intent" -> "uos.harness-successor-effect.v1"
        "completion_intent" -> "uos.harness-successor-completion.v1"
        _ -> ""
      }
      use intent <- result.try(text(record, "intent_id"))
      use grant_sha <- result.try(text(identity, "grant_sha256"))
      use worker <- result.try(text(identity, "worker"))
      use attempt <- result.try(value.get(identity, "attempt"))
      let attempt_valid = case attempt { value.Integer(n) -> n >= 0 _ -> False }
      use _ <- result.try(a.require(
        schema == expected_schema
          && kind == expected_kind
          && a.intent_valid(intent)
          && a.digest_valid(grant_sha)
          && string.byte_size(worker) > 0
          && attempt_valid,
        "task_intent_record_invalid",
      ))
      Ok(True)
    }
  }
}

pub fn effect_result_matches_prepared(
  prepared: value.Value,
  settled: value.Value,
  plan: String,
  task: String,
  intent: String,
) -> Bool {
  let prepared_identity = value.get(prepared, "execution")
  let settled_identity = value.get(settled, "execution")
  let identity_matches = case prepared_identity, settled_identity {
    Ok(before), Ok(after) ->
      value.get(before, "plan") == Ok(value.Text(plan))
        && value.get(before, "task") == Ok(value.Text(task))
        && value.get(after, "plan") == Ok(value.Text(plan))
        && value.get(after, "task") == Ok(value.Text(task))
        && value.get(before, "grant_sha256") == value.get(after, "grant_sha256")
        && value.get(before, "worker") == value.get(after, "worker")
        && value.get(before, "attempt") == value.get(after, "attempt")
    _, _ -> False
  }
  identity_matches
    && value.get(prepared, "kind") == Ok(value.Text("effect_intent"))
    && value.get(settled, "kind") == Ok(value.Text("effect_result"))
    && value.get(prepared, "intent_id") == Ok(value.Text(intent))
    && value.get(settled, "intent_id") == Ok(value.Text(intent))
    && value.get(prepared, "signature") == value.get(settled, "signature")
    && value.get(prepared, "tool") == value.get(settled, "tool")
    && value.get(prepared, "input_sha256") == value.get(settled, "input_sha256")
}

pub fn known_no_effect_refusal(
  status: String,
  tool: String,
  failure: String,
) -> Bool {
  status == "FAILED_OR_UNVERIFIED"
    && tool == "harness_write_file"
    && { failure == "source_digest_conflict"
      || failure == "refused: source_digest_conflict" }
}

pub fn effect_resolution_matches(
  resolution: value.Value,
  prepared_raw: String,
  result_raw: String,
  plan: String,
  task: String,
  intent: String,
  signature: String,
) -> Bool {
  value.get(resolution, "schema") == Ok(value.Text("uos.harness-effect-resolution.v1"))
    && value.get(resolution, "state") == Ok(value.Text("KNOWN_NOT_APPLIED"))
    && value.get(resolution, "intent_id") == Ok(value.Text(intent))
    && value.get(resolution, "plan") == Ok(value.Text(plan))
    && value.get(resolution, "task") == Ok(value.Text(task))
    && value.get(resolution, "request_signature") == Ok(value.Text(signature))
    && value.get(resolution, "prepared_sha256") == Ok(value.Text(files.digest(prepared_raw)))
    && value.get(resolution, "result_sha256") == Ok(value.Text(files.digest(result_raw)))
    && value.get(resolution, "reason") == Ok(value.Text("source_digest_conflict"))
    && value.get(resolution, "attribution") == Ok(value.Text("KNOWN_NOT_APPLIED"))
}

pub fn legacy_effect_terminal_valid(
  name: String,
  prepared_raw: String,
  prepared: value.Value,
  plan: String,
  task: String,
  saved: Option(String),
  resolution: Option(String),
) -> Result(Bool, String) {
  use intent <- result.try(text(prepared, "intent_id"))
  let is_completion = string.ends_with(name, "@completion-intent.json")
  case saved {
    None -> Ok(False)
    Some(raw) -> {
      use parsed <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "task_intent_result_json" }),
      )
      case is_completion {
        True -> {
          let result_id = "uos.harness-successor-completion.v1:" <> files.digest(prepared_raw)
          Ok(
            value.get(parsed, "state") == Ok(value.Text("completed"))
              && value.get(parsed, "result") == Ok(value.Text(result_id))
              && value.get(parsed, "prepared") == Ok(value.Text(prepared_raw)),
          )
        }
        False -> {
          use signature <- result.try(text(prepared, "signature"))
          use status <- result.try(text(parsed, "status"))
          use tool <- result.try(text(parsed, "tool"))
          use failure <- result.try(case value.get(parsed, "failure") {
            Ok(value.Text(s)) -> Ok(s)
            _ -> Ok("")
          })
          use _ <- result.try(a.require(
            effect_result_matches_prepared(prepared, parsed, plan, task, intent),
            "task_effect_result_binding_mismatch",
          ))
          case status {
            "EXECUTED" ->
              replay(raw, signature) |> result.map(fn(_) { True })
            _ -> case known_no_effect_refusal(status, tool, failure) {
              True -> {
                case resolution {
                  None -> Ok(False)
                  Some(resolution_raw) -> {
                    use parsed_resolution <- result.try(
                      json.parse(resolution_raw, value.decoder())
                        |> result.map_error(fn(_) { "effect_resolution_json" }),
                    )
                    Ok(effect_resolution_matches(
                      parsed_resolution, prepared_raw, raw, plan, task, intent,
                      signature,
                    ))
                  }
                }
              }
              False -> Ok(False)
            }
          }
        }
      }
    }
  }
}

pub fn legacy_intent_identity(
  name: String,
  record: value.Value,
) -> Result(#(String, String, Bool), String) {
  use schema <- result.try(text(record, "schema"))
  case schema {
    "uos.harness-planning-intent.v1" -> {
      use plan <- result.try(text(record, "parent_plan"))
      use task <- result.try(text(record, "parent_task"))
      use key <- result.try(text(record, "key"))
      use payload <- result.try(text(record, "canonical_payload"))
      use payload_sha <- result.try(text(record, "payload_sha256"))
      use parsed <- result.try(json.parse(payload, value.decoder())
        |> result.map_error(fn(_) { "planning_intent_payload_json" }))
      use logical_id <- result.try(text(parsed, "logical_id"))
      use intent <- result.try(text(record, "intent"))
      use _ <- result.try(planning.parse_intent(intent))
      use _ <- result.try(a.require(
        dev.valid_identifier(plan) && string.starts_with(plan, "uos/")
          && dev.valid_identifier(task) && a.intent_valid(logical_id)
          && a.digest_valid(key) && a.digest_valid(payload_sha)
          && name == "planning@" <> key <> "@intent.json"
          && planning.logical_key(plan, task, logical_id) == key
          && files.digest(payload) == payload_sha
          && value.get(parsed, "intent") == Ok(value.Text(intent)),
        "planning_intent_identity_or_namespace_invalid",
      ))
      Ok(#(plan, task, True))
    }
    "uos.harness-successor-effect.v1"
    | "uos.harness-successor-completion.v1" -> {
      use identity <- result.try(value.get(record, "execution"))
      use plan <- result.try(text(identity, "plan"))
      use task <- result.try(text(identity, "task"))
      let kind = case schema {
        "uos.harness-successor-effect.v1" -> "effect_intent"
        _ -> "completion_intent"
      }
      let suffix = case kind {
        "effect_intent" -> "@intent.json"
        _ -> "@completion-intent.json"
      }
      let filename_matches = case string.split(name, "@") {
        [grant_id, intent_id, ending] ->
          a.intent_valid(grant_id) && a.intent_valid(intent_id)
            && ending == string.drop_start(suffix, 1)
            && value.get(record, "intent_id") == Ok(value.Text(intent_id))
        _ -> False
      }
      use _ <- result.try(a.require(
        dev.valid_identifier(plan) && string.starts_with(plan, "uos/")
          && dev.valid_identifier(task) && filename_matches
          && !string.starts_with(name, "planning@")
          && string.ends_with(name, suffix),
        "task_intent_identity_or_namespace_invalid",
      ))
      use _ <- result.try(prepared_task_identity_matches(record, plan, task, kind))
      Ok(#(plan, task, False))
    }
    _ -> Error("task_intent_schema_unclassified")
  }
}

pub fn legacy_planning_terminal_valid(
  name: String,
  prepared_raw: String,
  prepared: value.Value,
  saved: Option(String),
  resolution: Option(String),
) -> Result(Bool, String) {
  use #(plan, task, is_planning) <- result.try(legacy_intent_identity(name, prepared))
  use _ <- result.try(a.require(is_planning, "planning_intent_required"))
  use key <- result.try(text(prepared, "key"))
  case saved {
    None -> Ok(False)
    Some(raw) -> {
      use parsed <- result.try(json.parse(raw, value.decoder())
        |> result.map_error(fn(_) { "planning_terminal_json" }))
      use _ <- result.try(a.require(
        value.get(parsed, "schema") == value.get(prepared, "schema")
          && value.get(parsed, "key") == Ok(value.Text(key))
          && value.get(parsed, "parent_plan") == Ok(value.Text(plan))
          && value.get(parsed, "parent_task") == Ok(value.Text(task))
          && value.get(parsed, "intent") == value.get(prepared, "intent")
          && value.get(parsed, "canonical_payload") == value.get(prepared, "canonical_payload")
          && value.get(parsed, "payload_sha256") == value.get(prepared, "payload_sha256"),
        "planning_terminal_intent_binding_mismatch",
      ))
      use outcome <- result.try(text(parsed, "outcome"))
      let bound_resolution = case outcome, resolution {
        "Uncertain", Some(sidecar) -> {
          use resolved <- result.try(json.parse(sidecar, value.decoder())
            |> result.map_error(fn(_) { "planning_resolution_json" }))
          use _ <- result.try(a.require(
            value.get(resolved, "intent_sha256") == Ok(value.Text(files.digest(prepared_raw))),
            "planning_resolution_intent_digest_mismatch",
          ))
          Ok(Some(sidecar))
        }
        _, other -> Ok(other)
      }
      use sidecar <- result.try(bound_resolution)
      let pointer = json.object([
        #("schema", json.string("uos.harness-planning-current.v1")),
        #("parent_plan", json.string(plan)),
        #("parent_task", json.string(task)),
        #("current_key", json.string(key)),
      ]) |> json.to_string
      Ok(result.is_ok(planning.decide_andon_with_resolution(
        Some(pointer), Some(raw), sidecar, plan, task,
      )))
    }
  }
}

fn legacy_ledger_optional(
  name: String,
  bytes: Int,
) -> Result(#(Option(String), Int), String) {
  use raw <- result.try(files.read_optional(dev.root, "var/harness/effects/" <> name))
  let size = case raw { None -> 0 Some(body) -> string.byte_size(body) }
  use _ <- result.try(a.require(size <= 1_048_576, "legacy_task_intent_file_budget_exceeded"))
  use _ <- result.try(legacy_task_scan_budget(bytes + size, 0))
  Ok(#(raw, bytes + size))
}

fn bounded_legacy_terminal(
  name: String,
  prepared_raw: String,
  prepared: value.Value,
  plan: String,
  task: String,
  is_planning: Bool,
  bytes: Int,
) -> Result(#(Bool, Int), String) {
  let completion = string.ends_with(name, "@completion-intent.json")
  let result_name = case completion {
    True -> string.replace(name, "@completion-intent.json", "@completion-result.json")
    False -> string.replace(name, "@intent.json", "@result.json")
  }
  let resolution_name = case completion {
    True -> string.replace(name, "@completion-intent.json", "@completion-resolution.json")
    False -> string.replace(name, "@intent.json", "@resolution.json")
  }
  use #(saved, bytes) <- result.try(legacy_ledger_optional(result_name, bytes))
  use #(resolution, bytes) <- result.try(legacy_ledger_optional(resolution_name, bytes))
  use terminal <- result.try(case is_planning {
    True -> legacy_planning_terminal_valid(name, prepared_raw, prepared, saved, resolution)
    False -> legacy_effect_terminal_valid(name, prepared_raw, prepared, plan, task, saved, resolution)
  })
  Ok(#(terminal, bytes))
}

fn task_intent_terminal_valid(
  name: String,
  prepared_raw: String,
  prepared: value.Value,
  plan: String,
  task: String,
) -> Result(Bool, String) {
  bounded_legacy_terminal(name, prepared_raw, prepared, plan, task, False, 0)
  |> result.map(fn(observed) { observed.0 })
}


fn task_intent_candidate_pending(
  name: String,
  plan: String,
  task: String,
) -> Result(Bool, String) {
  use raw <- result.try(files.read(dev.root, "var/harness/effects/" <> name))
  use prepared <- result.try(
    json.parse(raw, value.decoder())
      |> result.map_error(fn(_) { "task_intent_json" }),
  )
  let expected_kind = case string.ends_with(name, "@completion-intent.json") {
    True -> "completion_intent"
    False -> "effect_intent"
  }
  use matches <- result.try(prepared_task_identity_matches(
    prepared, plan, task, expected_kind,
  ))
  case matches {
    False -> Ok(False)
    True ->
      task_intent_terminal_valid(name, raw, prepared, plan, task)
      |> result.map(fn(terminal) { !terminal })
  }
}


pub fn legacy_task_scan_budget(bytes: Int, matching: Int) -> Result(Nil, String) {
  use _ <- result.try(a.require(
    bytes >= 0 && bytes <= 16_777_216,
    "legacy_task_intent_byte_budget_exceeded",
  ))
  a.require(
    matching >= 0 && matching <= 256,
    "matching_task_intent_scan_bound_exceeded",
  )
}

fn bounded_legacy_task_effect_pending(
  plan: String,
  task: String,
) -> Result(Bool, String) {
  let observation = dev.bounded_observation(fn() {
    use names <- result.try(
      simplifile.read_directory(dev.root <> "/var/harness/effects")
        |> result.map_error(fn(_) { "legacy_task_intent_directory_unavailable" }),
    )
    use candidates <- result.try(task_intent_candidates(names))
    use #(_bytes, _matching, pending) <- result.try(
      list.try_fold(candidates, #(0, 0, False), fn(acc, name) {
        use info <- result.try(
          simplifile.link_info(dev.root <> "/var/harness/effects/" <> name)
            |> result.map_error(fn(_) { "legacy_task_intent_stat_failed" }),
        )
        use _ <- result.try(a.require(
          info.size >= 0 && info.size <= 1_048_576,
          "legacy_task_intent_file_budget_exceeded",
        ))
        use raw <- result.try(files.read(
          dev.root, "var/harness/effects/" <> name,
        ))
        let bytes = acc.0 + string.byte_size(raw)
        use _ <- result.try(legacy_task_scan_budget(bytes, acc.1))
        use prepared <- result.try(
          json.parse(raw, value.decoder())
            |> result.map_error(fn(_) { "task_intent_json" }),
        )
        use #(found_plan, found_task, is_planning) <- result.try(
          legacy_intent_identity(name, prepared),
        )
        let matches = found_plan == plan && found_task == task
        let matching = acc.1 + case matches { True -> 1 False -> 0 }
        use _ <- result.try(legacy_task_scan_budget(bytes, matching))
        case matches {
          False -> Ok(#(bytes, matching, acc.2))
          True -> {
            use #(terminal, bytes) <- result.try(bounded_legacy_terminal(
              name, raw, prepared, plan, task, is_planning, bytes,
            ))
            Ok(#(bytes, matching, acc.2 || !terminal))
          }
        }
      }),
    )
    Ok(case pending { True -> "pending" False -> "clear" })
  }, 2000)
  use observed <- result.try(
    observation |> result.map_error(fn(error) {
      case error {
        "coordinator_observation_timeout_no_effect_authority"
        | "coordinator_observation_relay_timeout_no_effect_authority" ->
          "legacy_task_intent_time_budget_exceeded"
        _ -> error
      }
    }),
  )
  case observed {
    "pending" -> Ok(True)
    "clear" -> Ok(False)
    _ -> Error("legacy_task_intent_observation_invalid")
  }
}

fn task_effect_pending(plan: String, task: String) -> Result(Bool, String) {
  let index_directory = task_effect_index_directory(plan, task)
  use index_exists <- result.try(
    simplifile.is_directory(dev.root <> "/" <> index_directory)
      |> result.map_error(fn(_) { "task_effect_index_directory_check_failed" }),
  )
  use index_names <- result.try(case index_exists {
    True ->
      simplifile.read_directory(dev.root <> "/" <> index_directory)
        |> result.map_error(fn(_) { "task_effect_index_directory_unavailable" })
    False -> Ok([])
  })
  use index_candidates <- result.try(task_effect_index_candidates(index_names))
  use indexed <- result.try(list.try_map(index_candidates, fn(name) {
    task_effect_index_candidate_pending(name, plan, task)
  }))
  case list.any(indexed, fn(is_pending) { is_pending }) {
    True -> Ok(True)
    False -> {
      // Parse bounded global history; apply the intent cap only after identity matching.
      bounded_legacy_task_effect_pending(plan, task)
    }
  }
}

pub fn assessment_pending(scope: a.Scope) -> Result(Bool, String) {
  assessment_target_pending(scope.plan, scope.task, scope.portfolio)
}

fn assessment_record_pending(
  path: String,
  plan: String,
  task: String,
  portfolio: String,
) -> Result(Bool, String) {
  use raw <- result.try(files.read(dev.root, path))
  use record <- result.try(
    json.parse(raw, value.decoder())
      |> result.map_error(fn(_) { "assessment_ledger_json" }),
  )
  use found_plan <- result.try(text(record, "plan"))
  use found_task <- result.try(text(record, "task"))
  use found_portfolio <- result.try(text(record, "portfolio_path"))
  case found_plan == plan && found_task == task && found_portfolio == portfolio {
    False -> Ok(False)
    True -> {
      use signature <- result.try(text(record, "request_signature"))
      use assessment_path <- result.try(text(record, "assessment_path"))
      use body_sha <- result.try(text(record, "body_sha256"))
      use host <- result.try(text(record, "host_id"))
      use boot <- result.try(text(record, "boot_id"))
      use terminal <- result.try(a.read_optional(path <> ".terminal.json"))
      use resolution <- result.try(a.read_optional(path <> ".resolution.json"))
      let settlement = case terminal, resolution {
        Some(terminal_raw), _ -> {
          use parsed <- result.try(
            json.parse(terminal_raw, value.decoder())
              |> result.map_error(fn(_) { "assessment_terminal_json" }),
          )
          use _ <- result.try(a.require(
            assessment_terminal_matches(
              parsed,
              signature,
              assessment_path,
              body_sha,
              portfolio,
              body_sha,
              host,
              boot,
            ),
            "assessment_terminal_binding_mismatch",
          ))
          Ok(True)
        }
        None, Some(resolution_raw) -> {
          use parsed <- result.try(
            json.parse(resolution_raw, value.decoder())
              |> result.map_error(fn(_) { "assessment_resolution_json" }),
          )
          use _ <- result.try(a.require(
            value.get(parsed, "schema")
              == Ok(value.Text("uos.harness-pre-attach-assessment-resolution.v1"))
              && value.get(parsed, "state") == Ok(value.Text("POSTCONDITION_OBSERVED"))
              && value.get(parsed, "request_signature") == Ok(value.Text(signature))
              && value.get(parsed, "portfolio_path") == Ok(value.Text(portfolio))
              && value.get(parsed, "portfolio_sha256") == value.get(record, "body_sha256")
              && value.get(parsed, "attribution") == Ok(value.Text("not_established")),
            "assessment_resolution_binding_mismatch",
          ))
          Ok(True)
        }
        None, None -> Ok(False)
      }
      use settled <- result.try(settlement)
      assessment_pending_state(record, settled, plan, task, portfolio)
    }
  }
}

fn assessment_target_pending(
  plan: String,
  task: String,
  portfolio: String,
) -> Result(Bool, String) {
  use lock <- result.try(files.read_optional(dev.root, assessment_lock_path(portfolio)))
  case lock {
    Some(_) -> Ok(True)
    None -> {
      let target_dir = assessment_target_directory(plan, task, portfolio)
      use target_dir_exists <- result.try(
        simplifile.is_directory(dev.root <> "/" <> target_dir)
          |> result.map_error(fn(_) { "assessment_target_directory_check_failed" }),
      )
      use target_names <- result.try(case target_dir_exists {
        True ->
          simplifile.read_directory(dev.root <> "/" <> target_dir)
            |> result.map_error(fn(_) { "assessment_target_directory_unavailable" })
        False -> Ok([])
      })
      use legacy_names <- result.try(
        simplifile.read_directory(dev.root <> "/var/harness")
          |> result.map_error(fn(_) { "legacy_assessment_directory_unavailable" }),
      )
      use target_candidates <- result.try(assessment_ledger_candidates(target_names, ""))
      use legacy_candidates <- result.try(assessment_ledger_candidates(
        legacy_names,
        assessment_target_prefix(plan, task, portfolio),
      ))
      let paths =
        list.append(
          list.map(target_candidates, fn(name) { target_dir <> "/" <> name }),
          list.map(legacy_candidates, fn(name) { "var/harness/" <> name }),
        )
      use pending <- result.try(list.try_map(paths, fn(path) {
        assessment_record_pending(path, plan, task, portfolio)
      }))
      case list.any(pending, fn(is_pending) { is_pending }) {
        True -> Ok(True)
        False -> task_effect_pending(plan, task)
      }
    }
  }
}


fn initial_assessment_first_apply(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  body: String,
  reason: String,
  seed: String,
  request_signature: String,
  records: List(value.Value),
) -> Result(json.Json, String) {
  use _ <- result.try(acquire_assessment_path_lock(
    grant, scope, intent, request_signature,
  ))
  use _ <- result.try(ensure_assessment_target_directory(scope))
  use target <- result.try(a.read_optional(scope.portfolio))
  use target_before <- result.try(initial_portfolio_before(Ok(seed), target))
  use _ <- result.try(case target_before {
    InitialPortfolioPresent(original, _) -> judgments_match(seed, original)
    InitialPortfolioAbsent -> Ok(Nil)
  })
  use baseline_json <- result.try(json.parse(seed, value.decoder()) |> result.map_error(fn(_) { "assessment_seed_json" }))
  use baseline_rows <- result.try(case baseline_json { value.Array(xs) -> Ok(xs) _ -> Error("assessment_seed_array_required") })
  use _ <- result.try(judgments_match(seed, body))
  use canonical <- result.try(sa.run_sa_plan_cli(["--format", "json", "--task-list", scope.plan]))
  use rows <- result.try(initial_plan_rows(canonical))
  use _ <- result.try(initial_rows_match(records, rows, baseline_rows, scope.plan))
  use selected <- result.try(case list.find(rows, fn(row) {
    value.get(row, "id") == Ok(value.Text(scope.task))
  }) {
    Ok(found) -> Ok(found)
    Error(_) -> Error("grant_task_missing_from_canonical_plan")
  })
  use selected_state <- result.try(text(selected, "state"))
  use selected_worker <- result.try(value.get(selected, "worker"))
  let active = selected_state == "executing" && selected_worker == value.Text(grant.worker)
  use selected_actor <- result.try(case list.find(records, fn(record) {
    value.get(record, "task_id") == Ok(value.Text(scope.task))
  }) { Ok(record) -> value.get(record, "actor") Error(_) -> Error("assessment_task_missing") })
  let selected_owned =
    active && selected_actor == value.Text(grant.worker)
      || selected_state == "available" && selected_actor == value.Text(grant.worker)
  use _ <- result.try(a.require(selected_owned, "pre_attach_task_not_owned_or_available"))
  let attempt = case active { True -> initial_int(selected, "attempt") False -> Ok(0) }
  use attempt <- result.try(attempt)
  use _ <- result.try(a.heartbeat(grant))
  let path = "var/harness/" <> grant.id <> "-" <> intent <> "-assessment.json"
  use _ <- result.try(create_or_same(path, body))
  use check <- result.try(a.risk_check(path, scope, grant.worker, attempt, active))
  use _ <- result.try(a.check(grant))
  use final_raw <- result.try(sa.run_sa_plan_cli(["--format", "json", "--task-list", scope.plan]))
  use final_rows <- result.try(initial_plan_rows(final_raw))
  use _ <- result.try(initial_rows_match(records, final_rows, baseline_rows, scope.plan))
  use final_selected <- result.try(case list.find(final_rows, fn(row) {
    value.get(row, "id") == Ok(value.Text(scope.task))
  }) {
    Ok(found) -> Ok(found)
    Error(_) -> Error("grant_task_missing_from_final_plan")
  })
  use final_state <- result.try(text(final_selected, "state"))
  use final_worker <- result.try(value.get(final_selected, "worker"))
  use final_attempt <- result.try(initial_int(final_selected, "attempt"))
  use initial_attempt <- result.try(initial_int(selected, "attempt"))
  use _ <- result.try(a.require(
    final_state == selected_state && final_worker == selected_worker
      && final_attempt == initial_attempt,
    "canonical_task_changed_during_assessment",
  ))
  let before_body = case target_before {
    InitialPortfolioPresent(original, _) -> original
    InitialPortfolioAbsent ->
      json.object([
        #("schema", json.string("uos.harness-assessment-before.v1")),
        #("target_state", json.string("ABSENT")),
        #("portfolio_path", json.string(scope.portfolio)),
        #("seed_sha256", json.string(files.digest(seed))),
      ]) |> json.to_string
  }
  use _ <- result.try(create_or_same(path <> ".before.json", before_body))
  let before_state = case target_before {
    InitialPortfolioPresent(_, _) -> "PRESENT"
    InitialPortfolioAbsent -> "ABSENT"
  }
  let before_sha = case target_before {
    InitialPortfolioPresent(_, sha) -> sha
    InitialPortfolioAbsent -> "ABSENT"
  }
  let prepared = json.object([
    #("schema", json.string("uos.harness-pre-attach-assessment-ledger.v1")),
    #("state", json.string("PREPARED")),
    #("request_signature", json.string(request_signature)),
    #("grant_sha256", json.string(grant.digest)),
    #("plan", json.string(scope.plan)),
    #("task", json.string(scope.task)),
    #("portfolio_path", json.string(scope.portfolio)),
    #("intent_id", json.string(intent)),
    #("assessment_path", json.string(path)),
    #("host_id", json.string(grant.host)),
    #("boot_id", json.string(grant.boot)),
    #("body_sha256", json.string(files.digest(body))),
    #("reason_sha256", json.string(files.digest(reason))),
    #("seed_sha256", json.string(files.digest(seed))),
    #("before_state", json.string(before_state)),
    #("before_sha256", json.string(before_sha)),
  ]) |> json.to_string
  let ledger_path = initial_assessment_ledger_path(scope, grant, intent)
  use _ <- result.try(create_or_same(ledger_path, prepared))
  use _ <- result.try(a.check(grant))
  use current <- result.try(a.read_optional(scope.portfolio))
  let classify = assessment_replay_state(
    case target_before {
      InitialPortfolioPresent(original, _) -> Some(original)
      InitialPortfolioAbsent -> None
    },
    current,
    body,
  )
  let outcome = case classify {
    AssessmentNoChange ->
      initial_assessment_terminal(grant, scope, intent, request_signature, json.object([
        #("status", json.string("NO_CHANGE")),
        #("assessment_path", json.string(path)),
        #("assessment_sha256", json.string(files.digest(body))),
        #("portfolio_path", json.string(scope.portfolio)),
        #("portfolio_sha256", json.string(files.digest(body))),
        #("risk_check", json.string(check)),
        #("production_admission", json.bool(False)),
      ]))
    AssessmentBeforeStillPresent ->
      initial_assessment_apply_target(grant, scope, intent, request_signature, path, body, check)
    AssessmentPostconditionObserved ->
      Error("assessment_prepared_postcondition_already_present")
    AssessmentDiverged ->
      Error("assessment_prepared_target_diverged")
  }
  use receipt <- result.try(outcome)
  use _ <- result.try(release_assessment_path_lock(
    grant, scope, intent, request_signature,
  ))
  Ok(receipt)
}
fn initial_assessment_apply_target(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  request_signature: String,
  path: String,
  body: String,
  check: String,
) -> Result(json.Json, String) {
  use _ <- result.try(a.check(grant))
  use current <- result.try(a.read_optional(scope.portfolio))
  use _ <- result.try(case current {
    Some(existing) -> case a.read_optional(path <> ".before.json") {
      Ok(Some(before)) -> case assessment_matches_before_or_absent(before, existing, body) {
        True -> files.replace(dev.root, scope.portfolio, files.digest(existing), body)
        False -> Error("assessment_target_changed")
      }
      _ -> Error("assessment_before_record_missing")
    }
    None -> case a.read_optional(path <> ".before.json") {
      Ok(Some(before)) -> case string.contains(before, "\"target_state\":\"ABSENT\"") {
        True -> files.create(dev.root, scope.portfolio, body)
        False -> Error("assessment_target_disappeared")
      }
      _ -> Error("assessment_before_record_missing")
    }
  })
  use readback <- result.try(files.read(dev.root, scope.portfolio))
  use _ <- result.try(a.require(files.digest(readback) == files.digest(body), "assessment_readback_mismatch"))
  initial_assessment_terminal(grant, scope, intent, request_signature, json.object([
    #("status", json.string("PASS")),
    #("assessment_path", json.string(path)),
    #("assessment_sha256", json.string(files.digest(body))),
    #("portfolio_path", json.string(scope.portfolio)),
    #("portfolio_sha256", json.string(files.digest(readback))),
    #("risk_check", json.string(check)),
    #("production_admission", json.bool(False)),
  ]))
}

fn assessment_matches_before_or_absent(before: String, current: String, desired: String) -> Bool {
  files.digest(current) != files.digest(desired)
    && !string.contains(before, "\"target_state\":\"ABSENT\"")
    && files.digest(current) == files.digest(before)
}

fn initial_assessment_terminal(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  request_signature: String,
  receipt: json.Json,
) -> Result(json.Json, String) {
  use _ <- result.try(ensure_assessment_target_directory(scope))
  use now <- result.try(clock.observe())
  let envelope = json.object([
    #("schema", json.string("uos.harness-pre-attach-assessment-terminal.v1")),
    #("state", json.string("TERMINAL")),
    #("request_signature", json.string(request_signature)),
    #("terminal_at", clock.to_json(now)),
    #("receipt", receipt),
  ])
  use _ <- result.try(files.create(
    dev.root,
    initial_assessment_ledger_path(scope, grant, intent) <> ".terminal.json",
    json.to_string(envelope),
  ))
  Ok(envelope)
}

pub fn assessment_request_signature(
  grant_sha: String,
  worker: String,
  plan: String,
  task: String,
  target: String,
  seed_path: String,
  seed_sha: String,
  intent: String,
  body_sha: String,
  reason_sha: String,
) -> String {
  json.object([
    #("grant_sha256", json.string(grant_sha)),
    #("worker", json.string(worker)),
    #("plan", json.string(plan)),
    #("task", json.string(task)),
    #("target", json.string(target)),
    #("seed_path", json.string(seed_path)),
    #("seed_sha256", json.string(seed_sha)),
    #("intent_id", json.string(intent)),
    #("body_sha256", json.string(body_sha)),
    #("reason_sha256", json.string(reason_sha)),
  ]) |> json.to_string |> files.digest
}

fn assessment_seed_binding_for_grant(
  grant: a.Grant,
  scope: a.Scope,
) -> Result(#(String, String), String) {
  use document <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(a.require(files.digest(document) == grant.digest, "grant_document_digest_mismatch"))
  use parsed <- result.try(json.parse(document, value.decoder()) |> result.map_error(fn(_) { "grant_document_json" }))
  assessment_seed_binding(parsed, scope)
}

fn assessment_target_key(plan: String, task: String, portfolio: String) -> String {
  files.digest(dev.root <> "\u{0}" <> plan <> "\u{0}" <> task <> "\u{0}" <> portfolio)
}

fn assessment_target_prefix(plan: String, task: String, portfolio: String) -> String {
  "assessment-ledger-" <> assessment_target_key(plan, task, portfolio) <> "-"
}

pub fn assessment_target_directory_for(
  root: String,
  _plan: String,
  _task: String,
  portfolio: String,
) -> String {
  "var/harness/assessment-ledgers/"
    <> files.digest(root <> "\u{0}" <> portfolio)
}

fn assessment_target_directory(plan: String, task: String, portfolio: String) -> String {
  assessment_target_directory_for(dev.root, plan, task, portfolio)
}

fn ensure_assessment_target_directory(scope: a.Scope) -> Result(Nil, String) {
  simplifile.create_directory_all(
    dev.root <> "/" <> assessment_target_directory(scope.plan, scope.task, scope.portfolio),
  )
  |> result.map_error(fn(_) { "assessment_target_directory_unavailable" })
}


fn initial_assessment_ledger_path(
  scope: a.Scope,
  grant: a.Grant,
  intent: String,
) -> String {
  assessment_target_directory(scope.plan, scope.task, scope.portfolio)
    <> "/"
    <> grant.id
    <> "-"
    <> intent
    <> "-assessment-ledger.json"
}

fn create_or_same(path: String, body: String) -> Result(Nil, String) {
  use existing <- result.try(a.read_optional(path))
  case existing {
    None -> files.create(dev.root, path, body)
    Some(previous) ->
      a.require(previous == body, "assessment_artifact_conflict")
  }
}

fn initial_assessment_replay(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
  request_signature: String,
  body: String,
) -> Result(Option(json.Json), String) {
  let ledger_path = initial_assessment_ledger_path(scope, grant, intent)
  use terminal <- result.try(a.read_optional(ledger_path <> ".terminal.json"))
  case terminal {
    Some(raw) -> {
      use parsed <- result.try(json.parse(raw, value.decoder()) |> result.map_error(fn(_) { "assessment_terminal_json" }))
      use _ <- result.try(a.require(
        assessment_terminal_matches(
          parsed,
          request_signature,
          "var/harness/" <> grant.id <> "-" <> intent <> "-assessment.json",
          files.digest(body),
          scope.portfolio,
          files.digest(body),
          grant.host,
          grant.boot,
        ),
        "assessment_terminal_binding_mismatch",
      ))
      use _ <- result.try(release_assessment_path_lock(
        grant, scope, intent, request_signature,
      ))
      Ok(Some(value.encode(parsed)))
    }
    None -> {
      use prepared <- result.try(a.read_optional(ledger_path))
      case prepared {
        None -> Ok(None)
        Some(raw) -> {
          use parsed <- result.try(json.parse(raw, value.decoder()) |> result.map_error(fn(_) { "assessment_ledger_json" }))
          use found <- result.try(text(parsed, "request_signature"))
          use _ <- result.try(a.require(found == request_signature, "assessment_intent_reuse_refused"))
          use target <- result.try(a.read_optional(scope.portfolio))
          let desired = target == Some(body)
          use before_state <- result.try(text(parsed, "before_state"))
          use before_sha <- result.try(text(parsed, "before_sha256"))
          let same_before = case before_state, target {
            "ABSENT", None -> True
            "PRESENT", Some(current) -> files.digest(current) == before_sha
            _, _ -> False
          }
          case desired && before_state == "PRESENT" && before_sha == files.digest(body) {
            True -> {
              let receipt = json.object([
                #("status", json.string("NO_CHANGE")),
                #("portfolio_path", json.string(scope.portfolio)),
                #("portfolio_sha256", json.string(files.digest(body))),
              ])
              initial_assessment_terminal(grant, scope, intent, request_signature, receipt)
                |> result.map(Some)
            }
            False -> case desired {
              True -> {
                let resolution_path = ledger_path <> ".resolution.json"
                use existing_resolution <- result.try(a.read_optional(resolution_path))
                case existing_resolution {
                  Some(raw) -> {
                    use parsed <- result.try(
                      json.parse(raw, value.decoder())
                        |> result.map_error(fn(_) { "assessment_resolution_json" }),
                    )
                    use signature <- result.try(text(parsed, "request_signature"))
                    use _ <- result.try(a.require(
                      signature == request_signature
                        && text(parsed, "state") == Ok("POSTCONDITION_OBSERVED")
                        && text(parsed, "portfolio_sha256") == Ok(files.digest(body)),
                      "assessment_resolution_binding_mismatch",
                    ))
                    Ok(Some(value.encode(parsed)))
                  }
                  None -> {
                    use observed <- result.try(clock.observe())
                    let resolution_value = json.object([
                      #("schema", json.string("uos.harness-pre-attach-assessment-resolution.v1")),
                      #("state", json.string("POSTCONDITION_OBSERVED")),
                      #("request_signature", json.string(request_signature)),
                      #("portfolio_path", json.string(scope.portfolio)),
                      #("portfolio_sha256", json.string(files.digest(body))),
                      #("attribution", json.string("not_established")),
                      #("observed_at", clock.to_json(observed)),
                    ])
                    use _ <- result.try(files.create(
                      dev.root,
                      resolution_path,
                      json.to_string(resolution_value),
                    ))
                    Ok(Some(resolution_value))
                  }
                }
              }
              False -> case same_before {
                True -> Error("assessment_prepared_writer_may_still_be_active")
                False -> Error("assessment_prepared_target_diverged")
              }
            }
          }
        }
      }
    }
  }
}

fn reconcile_initial_assessment(
  grant: a.Grant,
  scope: a.Scope,
  intent: String,
) -> Result(Option(json.Json), String) {
  let ledger_path = initial_assessment_ledger_path(scope, grant, intent)
  use ledger <- result.try(a.read_optional(ledger_path))
  case ledger {
    None -> Ok(None)
    Some(raw) -> {
      use prepared <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "assessment_ledger_json" }),
      )
      use belongs <- result.try(assessment_pending_state(
        prepared, False, scope.plan, scope.task, scope.portfolio,
      ))
      use _ <- result.try(a.require(belongs, "assessment_ledger_scope_mismatch"))
      use stored_signature <- result.try(text(prepared, "request_signature"))
      use stored_grant <- result.try(text(prepared, "grant_sha256"))
      use body_sha <- result.try(text(prepared, "body_sha256"))
      use reason_sha <- result.try(text(prepared, "reason_sha256"))
      use seed_sha <- result.try(text(prepared, "seed_sha256"))
      use #(seed_path, bound_seed_sha) <- result.try(
        assessment_seed_binding_for_grant(grant, scope),
      )
      use _ <- result.try(a.require(
        stored_grant == grant.digest && seed_sha == bound_seed_sha,
        "assessment_ledger_grant_or_seed_mismatch",
      ))
      let body_path =
        "var/harness/" <> grant.id <> "-" <> intent <> "-assessment.json"
      use body <- result.try(files.read(dev.root, body_path))
      use _ <- result.try(a.require(
        files.digest(body) == body_sha,
        "assessment_body_digest_mismatch",
      ))
      let expected_signature = assessment_request_signature(
        grant.digest,
        grant.worker,
        scope.plan,
        scope.task,
        scope.portfolio,
        seed_path,
        seed_sha,
        intent,
        body_sha,
        reason_sha,
      )
      use _ <- result.try(a.require(
        stored_signature == expected_signature,
        "assessment_ledger_signature_mismatch",
      ))
      use replay <- result.try(initial_assessment_replay(
        grant,
        scope,
        intent,
        stored_signature,
        body,
      ))
      case replay {
        Some(receipt) -> Ok(Some(receipt))
        None -> Error("assessment_ledger_replay_state_missing")
      }
    }
  }
}

pub type AssessmentReplayState {
  AssessmentNoChange
  AssessmentBeforeStillPresent
  AssessmentPostconditionObserved
  AssessmentDiverged
}

pub fn assessment_replay_state(
  before: Option(String),
  current: Option(String),
  desired: String,
) -> AssessmentReplayState {
  case before, current {
    Some(old), Some(now) if old == desired && now == desired -> AssessmentNoChange
    _, Some(now) if now == desired -> AssessmentPostconditionObserved
    Some(old), Some(now) if old == now -> AssessmentBeforeStillPresent
    None, None -> AssessmentBeforeStillPresent
    _, _ -> AssessmentDiverged
  }
}

pub fn attached_assessment_signature(
  grant_sha: String,
  plan: String,
  task: String,
  portfolio: String,
  worker: String,
  attempt: Int,
  intent: String,
  body_sha: String,
  reason_sha: String,
) -> String {
  json.object([
    #("grant_sha256", json.string(grant_sha)),
    #("plan", json.string(plan)),
    #("task", json.string(task)),
    #("portfolio", json.string(portfolio)),
    #("worker", json.string(worker)),
    #("attempt", json.int(attempt)),
    #("intent_id", json.string(intent)),
    #("body_sha256", json.string(body_sha)),
    #("reason_sha256", json.string(reason_sha)),
  ]) |> json.to_string |> files.digest
}

pub fn assess(
  execution: a.Execution,
  args: value.Value,
) -> Result(a.Execution, String) {
  // A prepared pre-attach assessment blocks every source mutation until its
  // exact intent has been reconciled.
  use pending <- result.try(assessment_pending(execution.scope))
  use _ <- result.try(a.require(!pending, "assessment_prepared_stop_line"))
  // Repairing an assessment needs the live task fence, not a passing old
  // assessment. This does not execute source/backend effects or grant admission.
  use _ <- result.try(a.fence(execution, 15_000))
  use intent <- result.try(text(args, "intent_id"))
  use body <- result.try(text(args, "assessment_json"))
  use reason <- result.try(text(args, "reason"))
  use _ <- result.try(a.require(
    a.intent_valid(intent)
      && string.byte_size(reason) >= 16
      && string.byte_size(reason) <= 2048,
    "qualified_assessment_reason_required",
  ))
  use _ <- result.try(assessment_paths_allowed(execution.grant, body))
  let path =
    "var/harness/" <> execution.grant.id <> "-" <> intent <> "-assessment.json"
  use _ <- result.try(files.create(dev.root, path, body))
  use _ <- result.try(a.risk_check(
    path,
    execution.scope,
    execution.binding.worker,
    execution.binding.attempt,
    True,
  ))
  use _ <- result.try(files.create(
    dev.root,
    "var/harness/"
      <> execution.grant.id
      <> "-"
      <> intent
      <> "-assessment-reason.json",
    json.object([
      #("reason", json.string(reason)),
      #("assessment", json.string(path)),
      #("execution", a.observe_execution(execution)),
    ])
      |> json.to_string,
  ))
  let lock_signature = attached_assessment_signature(
    execution.grant.digest,
    execution.scope.plan,
    execution.scope.task,
    execution.scope.portfolio,
    execution.binding.worker,
    execution.binding.attempt,
    intent,
    files.digest(body),
    files.digest(reason),
  )
  use _ <- result.try(acquire_assessment_path_lock(
    execution.grant,
    execution.scope,
    intent,
    lock_signature,
  ))
  let prepared = json.object([
    #("schema", json.string("uos.harness-attached-assessment-ledger.v1")),
    #("state", json.string("PREPARED")),
    #("request_signature", json.string(lock_signature)),
    #("grant_sha256", json.string(execution.grant.digest)),
    #("plan", json.string(execution.scope.plan)),
    #("task", json.string(execution.scope.task)),
    #("portfolio_path", json.string(execution.scope.portfolio)),
    #("intent_id", json.string(intent)),
    #("assessment_path", json.string(path)),
    #("host_id", json.string(execution.grant.host)),
    #("boot_id", json.string(execution.grant.boot)),
    #("body_sha256", json.string(files.digest(body))),
  ]) |> json.to_string
  use _ <- result.try(files.create(
    dev.root,
    attached_assessment_prepared_path(execution.grant, intent),
    prepared,
  ))
  use original <- result.try(files.read(dev.root, execution.scope.portfolio))
  use _ <- result.try(files.create(dev.root, path <> ".before.json", original))
  use _ <- result.try(a.fence(execution, 0))
  use _ <- result.try(files.replace(
    dev.root,
    execution.scope.portfolio,
    files.digest(original),
    body,
  ))
  use readback <- result.try(files.read(dev.root, execution.scope.portfolio))
  use _ <- result.try(a.require(
    files.digest(readback) == files.digest(body),
    "assessment_readback_mismatch",
  ))
  let receipt = json.object([
    #("status", json.string("PASS")),
    #(
      "assessment_path",
      json.string("var/harness/" <> execution.grant.id <> "-" <> intent <> "-assessment.json"),
    ),
    #("assessment_sha256", json.string(files.digest(body))),
    #("portfolio_path", json.string(execution.scope.portfolio)),
    #("portfolio_sha256", json.string(files.digest(readback))),
  ])
  use _ <- result.try(initial_assessment_terminal(
    execution.grant,
    execution.scope,
    intent,
    lock_signature,
    receipt,
  ))
  use _ <- result.try(release_assessment_path_lock(
    execution.grant,
    execution.scope,
    intent,
    lock_signature,
  ))
  Ok(a.Execution(..execution, risk_path: execution.scope.portfolio))
}
pub fn release(
  execution: a.Execution,
  intent: String,
) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.fence(execution, 5000))
  release_after_fence(execution, intent)
  |> result.map_error(fn(e) { "release_outcome_unknown:" <> e })
}

fn release_after_fence(
  execution: a.Execution,
  intent: String,
) -> Result(json.Json, String) {
  use _ <- result.try(
    sa.run_sa_plan_cli([
      "task",
      "release",
      execution.scope.plan,
      execution.scope.task,
      execution.binding.worker,
      int.to_string(execution.binding.attempt),
    ]),
  )
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(
    row.state == "available"
      && row.worker == None
      && row.attempt == execution.binding.attempt,
    "release_outcome_unknown",
  ))
  use _ <- result.try(
    a.coordinate([
      "release",
      execution.binding.session,
      dev.task_resource(execution.binding),
      int.to_string(execution.binding.epoch),
      execution.grant.id <> "-" <> intent <> "-release",
    ]),
  )
  use _ <- result.try(a.state_assessment(
    execution,
    "available",
    intent <> "-release",
  ))
  Ok(
    json.object([
      #("state", json.string("available")),
      #("released", a.observe_execution(execution)),
      #("next_task", json.string("READY_AFTER_FRESH_FULL_PLAN_ASSESSMENT")),
    ]),
  )
}

fn successful_check(
  execution: a.Execution,
  id: String,
  tool: String,
  candidate: String,
) -> Result(String, String) {
  use _ <- result.try(a.require(a.intent_valid(id), "check_intent"))
  let path = effect_path(execution, id, "result")
  use body <- result.try(files.read(dev.root, path))
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "check_receipt_json" }),
  )
  let sig =
    signature(execution, tool, value.Object([#("intent_id", value.Text(id))]))
  use _ <- result.try(replay(body, sig))
  use source <- result.try(value.get(parsed, "input_manifest"))
  use _ <- result.try(a.require(
    source == value.Text(candidate),
    "verification_candidate_mismatch",
  ))
  Ok(files.digest(body))
}

pub fn finish(
  execution: a.Execution,
  args: value.Value,
) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  use journal_path <- result.try(text(args, "journal_path"))
  use _ <- result.try(planning.andon_guard(
    execution.binding.plan,
    execution.binding.task,
  ))
  use verification_path <- result.try(text(args, "verification_path"))
  use build <- result.try(text(args, "build_intent_id"))
  use test_id <- result.try(text(args, "test_intent_id"))
  use _ <- result.try(a.require(
    a.intent_valid(intent)
      && list.contains(execution.scope.reads, journal_path)
      && list.contains(execution.scope.reads, verification_path),
    "completion_scope",
  ))
  use _ <- result.try(a.fence(execution, 20_000))
  use _ <- result.try(a.risk_check(
    execution.risk_path,
    execution.scope,
    execution.binding.worker,
    execution.binding.attempt,
    True,
  ))
  use candidate <- result.try(capture_execution(execution))
  use build_hash <- result.try(successful_check(
    execution,
    build,
    "harness_build",
    candidate,
  ))
  use test_hash <- result.try(successful_check(
    execution,
    test_id,
    "harness_test",
    candidate,
  ))
  use journal <- result.try(files.read(dev.root, journal_path))
  use _ <- result.try(a.require(
    dev.journal_sections_valid(journal),
    "thirteen_journal_sections_required",
  ))
  use verification <- result.try(files.read(dev.root, verification_path))
  use attestation <- result.try(
    json.parse(verification, value.decoder())
    |> result.map_error(fn(_) { "verification_json" }),
  )
  use _ <- result.try(
    list.try_each(
      [
        #("schema", value.Text("uos.harness-task-verification.v1")),
        #("plan", value.Text(execution.scope.plan)),
        #("task", value.Text(execution.scope.task)),
        #("attempt", value.Integer(execution.binding.attempt)),
        #("candidate_sha256", value.Text(files.digest(candidate))),
        #("build_receipt_sha256", value.Text(build_hash)),
        #("test_receipt_sha256", value.Text(test_hash)),
        #("verdict", value.Text("VERIFIED")),
      ],
      fn(pair) {
        use actual <- result.try(value.get(attestation, pair.0))
        a.require(actual == pair.1, "verification_binding:" <> pair.0)
      },
    ),
  )
  // Exact source/evidence peer acknowledgement is required as a file reference.
  // Its qualified authorship remains the cooperative local review boundary.
  use peer_path <- result.try(text(attestation, "peer_review_path"))
  use peer_digest <- result.try(text(attestation, "peer_review_sha256"))
  use formal_path <- result.try(text(attestation, "formal_evidence_path"))
  use formal_digest <- result.try(text(attestation, "formal_evidence_sha256"))
  use _ <- result.try(
    list.try_each(
      [#(peer_path, peer_digest), #(formal_path, formal_digest)],
      fn(pair) {
        use _ <- result.try(a.require(
          list.contains(execution.scope.reads, pair.0) && a.digest_valid(pair.1),
          "evidence_scope",
        ))
        use evidence <- result.try(files.read(dev.root, pair.0))
        a.require(files.digest(evidence) == pair.1, "evidence_digest_mismatch")
      },
    ),
  )
  let prepared =
    json.object([
      #("schema", json.string("uos.harness-successor-completion.v1")),
      #("kind", json.string("completion_intent")),
      #("intent_id", json.string(intent)),
      #("execution", a.observe_execution(execution)),
      #("candidate_sha256", json.string(files.digest(candidate))),
      #("build_receipt_sha256", json.string(build_hash)),
      #("test_receipt_sha256", json.string(test_hash)),
      #("journal_path", json.string(journal_path)),
      #("journal_sha256", json.string(files.digest(journal))),
      #("verification_path", json.string(verification_path)),
      #("verification_sha256", json.string(files.digest(verification))),
    ])
    |> json.to_string
  use _ <- result.try(a.fence(execution, 10_000))
  use current <- result.try(capture_execution(execution))
  use _ <- result.try(a.require(
    current == candidate,
    "source_changed_before_completion",
  ))
  use _ <- result.try(
    files.create(
      dev.root,
      effect_path(execution, intent, "completion-intent"),
      prepared,
    )
    |> result.map_error(fn(e) { "completion_outcome_unknown:prepared:" <> e }),
  )
  use _ <- result.try(write_task_effect_index(
    execution, intent, "completion-intent", "completion_intent", prepared,
  ))
  finish_after_prepare(execution, intent, prepared)
  |> result.map_error(fn(e) { "completion_outcome_unknown:" <> e })
}

fn finish_after_prepare(
  execution: a.Execution,
  intent: String,
  prepared: String,
) -> Result(json.Json, String) {
  let result_id =
    "uos.harness-successor-completion.v1:" <> files.digest(prepared)
  use _ <- result.try(sa.complete_sa_task(
    execution.scope.plan,
    execution.scope.task,
    execution.binding.worker,
    execution.binding.attempt,
    result_id,
  ))
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(
    row.state == "completed"
      && row.attempt == execution.binding.attempt
      && row.result == Some(result_id)
      && row.completed_at_ns != None,
    "completion_outcome_unknown",
  ))
  use _ <- result.try(a.check(execution.grant))
  use _ <- result.try(
    a.coordinate([
      "release",
      execution.binding.session,
      dev.task_resource(execution.binding),
      int.to_string(execution.binding.epoch),
      execution.grant.id <> "-" <> intent <> "-complete-release",
    ]),
  )
  let receipt =
    json.object([
      #("state", json.string("completed")),
      #("result", json.string(result_id)),
      #("prepared", json.string(prepared)),
      #("system_admission", json.bool(False)),
    ])
  use _ <- result.try(files.create(
    dev.root,
    effect_path(execution, intent, "completion-result"),
    json.to_string(receipt),
  ))
  use _ <- result.try(a.state_assessment(
    execution,
    "completed",
    intent <> "-complete",
  ))
  Ok(receipt)
}

/// Recover a committed completion by exact canonical result digest. This is a
/// terminal read/reconciliation path and grants no ordinary source effects.
pub fn assessment_lock_pending_for(
  execution: a.Execution,
  intent: String,
) -> Result(Bool, String) {
  use lock <- result.try(files.read_optional(
    dev.root,
    assessment_lock_path(execution.scope.portfolio),
  ))
  case lock {
    None -> Ok(False)
    Some(raw) -> {
      use parsed <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "assessment_path_lock_json" }),
      )
      use lock_intent <- result.try(text(parsed, "intent_id"))
      let same_scope =
        value.get(parsed, "schema") == Ok(value.Text("uos.harness-assessment-path-lock.v1"))
          && value.get(parsed, "state") == Ok(value.Text("HELD"))
          && value.get(parsed, "canonical_root") == Ok(value.Text(dev.root))
          && value.get(parsed, "portfolio_path") == Ok(value.Text(execution.scope.portfolio))
          && value.get(parsed, "plan") == Ok(value.Text(execution.scope.plan))
          && value.get(parsed, "task") == Ok(value.Text(execution.scope.task))
          && value.get(parsed, "grant_sha256") == Ok(value.Text(execution.grant.digest))
          && value.get(parsed, "worker") == Ok(value.Text(execution.grant.worker))
      use signature <- result.try(text(parsed, "request_signature"))
      use _ <- result.try(a.require(
        same_scope && a.digest_valid(signature) && a.intent_valid(lock_intent),
        "assessment_path_lock_binding_invalid",
      ))
      Ok(lock_intent == intent)
    }
  }
}

fn reconcile_assessment_path_lock(
  execution: a.Execution,
  intent: String,
) -> Result(Option(json.Json), String) {
  use lock <- result.try(files.read_optional(
    dev.root,
    assessment_lock_path(execution.scope.portfolio),
  ))
  case lock {
    None -> Ok(None)
    Some(raw) -> {
      use parsed <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "assessment_path_lock_json" }),
      )
      use lock_intent <- result.try(text(parsed, "intent_id"))
      let same_scope =
        value.get(parsed, "schema") == Ok(value.Text("uos.harness-assessment-path-lock.v1"))
          && value.get(parsed, "state") == Ok(value.Text("HELD"))
          && value.get(parsed, "canonical_root") == Ok(value.Text(dev.root))
          && value.get(parsed, "portfolio_path") == Ok(value.Text(execution.scope.portfolio))
          && value.get(parsed, "plan") == Ok(value.Text(execution.scope.plan))
          && value.get(parsed, "task") == Ok(value.Text(execution.scope.task))
          && value.get(parsed, "grant_sha256") == Ok(value.Text(execution.grant.digest))
          && value.get(parsed, "worker") == Ok(value.Text(execution.grant.worker))
      use signature <- result.try(text(parsed, "request_signature"))
      use _ <- result.try(a.require(
        same_scope && a.digest_valid(signature) && a.intent_valid(lock_intent),
        "assessment_path_lock_binding_invalid",
      ))
      case lock_intent == intent {
        False -> Ok(None)
        True -> {
          let terminal_path =
            initial_assessment_ledger_path(execution.scope, execution.grant, intent)
              <> ".terminal.json"
          use terminal_raw <- result.try(files.read_optional(dev.root, terminal_path))
          case terminal_raw {
            None -> Error("assessment_path_lock_requires_terminal_or_quiescence")
            Some(saved) -> {
              use terminal <- result.try(
                json.parse(saved, value.decoder())
                  |> result.map_error(fn(_) { "assessment_terminal_json" }),
              )
              use _ <- result.try(a.require(
                assessment_terminal_valid(
                  terminal,
                  signature,
                  execution.grant.host,
                  execution.grant.boot,
                ),
                "assessment_terminal_binding_mismatch",
              ))
              use _ <- result.try(release_assessment_path_lock(
                execution.grant, execution.scope, intent, signature,
              ))
              Ok(Some(value.encode(terminal)))
            }
          }
        }
      }
    }
  }
}

pub fn reconciliation_intent_is_pending(
  execution: a.Execution,
  intent: String,
) -> Result(Bool, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use assessment_lock <- result.try(assessment_lock_pending_for(execution, intent))
  case assessment_lock {
    True -> Ok(True)
    False -> {
      let assessment_path = initial_assessment_ledger_path(
        execution.scope,
        execution.grant,
        intent,
      )
      use assessment <- result.try(a.read_optional(assessment_path))
      case assessment {
        Some(raw) -> {
          use prepared <- result.try(
            json.parse(raw, value.decoder())
              |> result.map_error(fn(_) { "assessment_ledger_json" }),
          )
          use pending <- result.try(assessment_pending_state(
            prepared, False, execution.scope.plan, execution.scope.task,
            execution.scope.portfolio,
          ))
          use terminal <- result.try(a.read_optional(assessment_path <> ".terminal.json"))
          use resolution <- result.try(a.read_optional(assessment_path <> ".resolution.json"))
          case pending && terminal == None && resolution == None {
            True -> Ok(True)
            False -> Ok(False)
          }
        }
        None -> pending_effect_or_completion_intent(execution, intent)
      }
    }
  }
}

fn pending_effect_or_completion_intent(
  execution: a.Execution,
  intent: String,
) -> Result(Bool, String) {
  use effect <- result.try(
    a.read_optional(effect_path(execution, intent, "intent")),
  )
  use effect_result <- result.try(
    a.read_optional(effect_path(execution, intent, "result")),
  )
  use quarantine <- result.try(
    a.read_optional(effect_path(execution, intent, "quarantine")),
  )
  use resolution <- result.try(
    a.read_optional(effect_path(execution, intent, "resolution")),
  )
  use completion <- result.try(
    a.read_optional(effect_path(execution, intent, "completion-intent")),
  )
  use completion_result <- result.try(
    a.read_optional(effect_path(execution, intent, "completion-result")),
  )
  case effect, effect_result, quarantine, resolution, completion, completion_result {
    Some(raw), None, _, _, None, _ -> {
      use prepared <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "effect_intent_json" }),
      )
      Ok(pending_effect_record_matches(
        prepared, execution.grant.digest, execution.scope.plan,
        execution.scope.task, execution.binding.worker,
        execution.binding.attempt, intent,
      ))
    }
    Some(raw), Some(result_raw), _, _, None, _ -> {
      use prepared <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "effect_intent_json" }),
      )
      use result_record <- result.try(
        json.parse(result_raw, value.decoder())
          |> result.map_error(fn(_) { "effect_result_json" }),
      )
      use status <- result.try(text(result_record, "status"))
      use tool <- result.try(text(result_record, "tool"))
      use failure <- result.try(case value.get(result_record, "failure") {
        Ok(value.Text(s)) -> Ok(s)
        _ -> Ok("")
      })
      use signature <- result.try(text(prepared, "signature"))
      use _ <- result.try(a.require(
        effect_result_matches_prepared(
          prepared,
          result_record,
          execution.scope.plan,
          execution.scope.task,
          intent,
        ),
        "effect_result_binding_mismatch",
      ))
      case status {
        "EXECUTED" ->
          replay(result_raw, signature) |> result.map(fn(_) { False })
        _ -> case known_no_effect_refusal(status, tool, failure) {
          True -> case resolution {
            None -> Ok(True)
            Some(resolution_raw) -> {
              use parsed_resolution <- result.try(
                json.parse(resolution_raw, value.decoder())
                  |> result.map_error(fn(_) { "effect_resolution_json" }),
              )
              Ok(!effect_resolution_matches(
                parsed_resolution,
                raw,
                result_raw,
                execution.scope.plan,
                execution.scope.task,
                intent,
                signature,
              ))
            }
          }
          False -> Ok(True)
        }
      }
    }
    None, Some(_), _, _, None, _ -> Error("effect_result_without_prepared_intent")
    _, _, _, _, Some(raw), None -> {
      use prepared <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "completion_intent_json" }),
      )
      Ok(pending_completion_record_matches(
        prepared, execution.grant.digest, execution.scope.plan,
        execution.scope.task, execution.binding.worker,
        execution.binding.attempt, intent,
      ))
    }
    None, None, None, None, Some(raw), Some(result_raw) -> {
      use prepared <- result.try(
        json.parse(raw, value.decoder())
          |> result.map_error(fn(_) { "completion_intent_json" }),
      )
      let result_id =
        "uos.harness-successor-completion.v1:" <> files.digest(raw)
      use result_record <- result.try(
        json.parse(result_raw, value.decoder())
          |> result.map_error(fn(_) { "completion_result_json" }),
      )
      Ok(
        !pending_completion_record_matches(
          prepared, execution.grant.digest, execution.scope.plan,
          execution.scope.task, execution.binding.worker,
          execution.binding.attempt, intent,
        )
          || value.get(result_record, "state") != Ok(value.Text("completed"))
          || value.get(result_record, "result") != Ok(value.Text(result_id))
          || value.get(result_record, "prepared") != Ok(value.Text(raw)),
      )
    }
    _, _, _, _, None, Some(_) -> Error("completion_result_without_prepared_intent")
    _, _, _, _, _, _ -> Ok(False)
  }
}

pub fn pending_effect_record_matches(
  prepared: value.Value,
  grant_sha: String,
  plan: String,
  task: String,
  worker: String,
  attempt: Int,
  intent: String,
) -> Bool {
  let identity_matches = case value.get(prepared, "execution") {
    Ok(identity) ->
      value.get(identity, "grant_sha256") == Ok(value.Text(grant_sha))
        && value.get(identity, "plan") == Ok(value.Text(plan))
        && value.get(identity, "task") == Ok(value.Text(task))
        && value.get(identity, "worker") == Ok(value.Text(worker))
        && case value.get(identity, "attempt") {
          Ok(value.Integer(recorded)) -> recorded > 0 && recorded <= attempt
          _ -> False
        }
    _ -> False
  }
  let signature_valid = case value.get(prepared, "signature") {
    Ok(value.Text(signature)) -> a.digest_valid(signature)
    _ -> False
  }
  value.get(prepared, "schema") == Ok(value.Text("uos.harness-successor-effect.v1"))
    && value.get(prepared, "status") == Ok(value.Text("PREPARED"))
    && value.get(prepared, "kind") == Ok(value.Text("effect_intent"))
    && value.get(prepared, "intent_id") == Ok(value.Text(intent))
    && signature_valid
    && identity_matches
}

pub fn pending_completion_record_matches(
  prepared: value.Value,
  grant_sha: String,
  plan: String,
  task: String,
  worker: String,
  attempt: Int,
  intent: String,
) -> Bool {
  let identity_matches = case value.get(prepared, "execution") {
    Ok(identity) ->
      value.get(identity, "grant_sha256") == Ok(value.Text(grant_sha))
        && value.get(identity, "plan") == Ok(value.Text(plan))
        && value.get(identity, "task") == Ok(value.Text(task))
        && value.get(identity, "worker") == Ok(value.Text(worker))
        && value.get(identity, "attempt") == Ok(value.Integer(attempt))
    _ -> False
  }
  value.get(prepared, "schema") == Ok(value.Text("uos.harness-successor-completion.v1"))
    && value.get(prepared, "kind") == Ok(value.Text("completion_intent"))
    && value.get(prepared, "intent_id") == Ok(value.Text(intent))
    && identity_matches
}

pub fn reconcile(
  execution: a.Execution,
  intent: String,
) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.check(execution.grant))
  use assessment_lock <- result.try(reconcile_assessment_path_lock(
    execution, intent,
  ))
  case assessment_lock {
    Some(receipt) -> Ok(receipt)
    None -> {
      use assessment <- result.try(reconcile_initial_assessment(
        execution.grant, execution.scope, intent,
      ))
      case assessment {
        Some(receipt) -> Ok(receipt)
        None -> {
          use planning_resolution <- result.try(planning.reconcile(execution, intent))
          case planning_resolution {
            Some(receipt) -> Ok(receipt)
            None -> reconcile_effect_or_completion(execution, intent)
          }
        }
      }
    }
  }
}

fn reconcile_effect_or_completion(
  execution: a.Execution,
  intent: String,
) -> Result(json.Json, String) {
  // Dispatch on the record's DECLARED kind, never on which filename exists:
  // before the "@" encoding those two questions had the same answer for some
  // intent ids, and a filename was never evidence of a record's meaning anyway.
  use completion <- result.try(
    a.read_optional(effect_path(execution, intent, "completion-intent")),
  )
  case completion {
    None -> reconcile_effect(execution, intent)
    Some(prepared) -> reconcile_completion(execution, intent, prepared)
  }
}

/// A dangling effect intent -- written before dispatch, never resulted -- is the
/// state that previously had no exit at all. It gets quarantined, not resolved.
fn reconcile_effect(
  execution: a.Execution,
  intent: String,
) -> Result(json.Json, String) {
  use quarantined <- result.try(
    a.read_optional(effect_path(execution, intent, "quarantine")),
  )
  case quarantined {
    Some(body) -> {
      use parsed <- result.try(
        json.parse(body, value.decoder())
        |> result.map_error(fn(_) { "quarantine_json" }),
      )
      use _ <- result.try(a.require(
        value.get(parsed, "schema")
          == Ok(value.Text("uos.harness-successor-quarantine.v1"))
          && value.get(parsed, "kind") == Ok(value.Text("quarantine_record"))
          && value.get(parsed, "intent_id") == Ok(value.Text(intent)),
        "quarantine_kind_mismatch",
      ))
      Ok(value.encode(parsed))
    }
    None -> {
      use pending <- result.try(
        a.read_optional(effect_path(execution, intent, "intent")),
      )
      case pending {
        None -> Error("reconciliation_target_not_found")
        Some(intent_body) -> {
          use parsed <- result.try(
            json.parse(intent_body, value.decoder())
            |> result.map_error(fn(_) { "intent_json" }),
          )
          use _ <- result.try(a.require(
            value.get(parsed, "schema")
              == Ok(value.Text("uos.harness-successor-effect.v1"))
              && value.get(parsed, "kind") == Ok(value.Text("effect_intent"))
              && value.get(parsed, "intent_id") == Ok(value.Text(intent)),
            "effect_intent_kind_mismatch",
          ))
          use settled <- result.try(
            a.read_optional(effect_path(execution, intent, "result")),
          )
          case settled {
            // A result exists after all: the outcome is known, so there is
            // nothing to quarantine. Hand back what was recorded.
            Some(body) -> {
              use result_record <- result.try(
                json.parse(body, value.decoder())
                  |> result.map_error(fn(_) { "corrupt_result" }),
              )
              use signature <- result.try(text(parsed, "signature"))
              use _ <- result.try(a.require(
                effect_result_matches_prepared(
                  parsed, result_record, execution.scope.plan,
                  execution.scope.task, intent,
                ),
                "effect_result_binding_mismatch",
              ))
              use status <- result.try(text(result_record, "status"))
              case status {
                "EXECUTED" ->
                  replay(body, signature) |> result.map(fn(valid) { valid })
                _ -> {
                  use tool <- result.try(text(result_record, "tool"))
                  use failure <- result.try(case value.get(result_record, "failure") {
                    Ok(value.Text(s)) -> Ok(s)
                    _ -> Ok("")
                  })
                  use _ <- result.try(a.require(
                    known_no_effect_refusal(status, tool, failure),
                    "effect_outcome_unknown_requires_adjudication",
                  ))
                  use now <- result.try(clock.observe())
                  let resolution = json.object([
                    #("schema", json.string("uos.harness-effect-resolution.v1")),
                    #("state", json.string("KNOWN_NOT_APPLIED")),
                    #("intent_id", json.string(intent)),
                    #("plan", json.string(execution.scope.plan)),
                    #("task", json.string(execution.scope.task)),
                    #("request_signature", json.string(signature)),
                    #("prepared_sha256", json.string(files.digest(intent_body))),
                    #("result_sha256", json.string(files.digest(body))),
                    #("reason", json.string("source_digest_conflict")),
                    #("attribution", json.string("KNOWN_NOT_APPLIED")),
                    #("observed_at", clock.to_json(now)),
                  ])
                  use _ <- result.try(create_or_same(
                    effect_path(execution, intent, "resolution"),
                    json.to_string(resolution),
                  ))
                  Ok(resolution)
                }
              }
            }
            None ->
              record_quarantine(
                execution,
                intent,
                intent_body,
                "dangling_effect_intent",
              )
          }
        }
      }
    }
  }
}

fn reconcile_completion(
  execution: a.Execution,
  intent: String,
  prepared: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(
    json.parse(prepared, value.decoder())
    |> result.map_error(fn(_) { "prepared_completion_json" }),
  )
  use _ <- result.try(a.require(
    value.get(parsed, "schema")
      == Ok(value.Text("uos.harness-successor-completion.v1"))
      && value.get(parsed, "kind") == Ok(value.Text("completion_intent"))
      && value.get(parsed, "intent_id") == Ok(value.Text(intent)),
    "prepared_completion_kind",
  ))
  use identity <- result.try(value.get(parsed, "execution"))
  use _ <- result.try(
    list.try_each(
      [
        #("plan", value.Text(execution.scope.plan)),
        #("task", value.Text(execution.scope.task)),
        #("worker", value.Text(execution.binding.worker)),
        #("attempt", value.Integer(execution.binding.attempt)),
        #("grant_sha256", value.Text(execution.grant.digest)),
      ],
      fn(pair) {
        use actual <- result.try(value.get(identity, pair.0))
        a.require(actual == pair.1, "prepared_completion_identity")
      },
    ),
  )
  let result_id =
    "uos.harness-successor-completion.v1:" <> files.digest(prepared)
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(
    row.state == "completed"
      && row.attempt == execution.binding.attempt
      && row.result == Some(result_id)
      && row.completed_at_ns != None,
    "canonical_completion_not_matched",
  ))
  use _ <- result.try(
    a.coordinate([
      "release",
      execution.binding.session,
      dev.task_resource(execution.binding),
      int.to_string(execution.binding.epoch),
      execution.grant.id <> "-" <> intent <> "-complete-release",
    ]),
  )
  let receipt =
    json.object([
      #("state", json.string("completed")),
      #("result", json.string(result_id)),
      #("prepared", json.string(prepared)),
      #("system_admission", json.bool(False)),
    ])
  let result_path = effect_path(execution, intent, "completion-result")
  use existing <- result.try(a.read_optional(result_path))
  use _ <- result.try(case existing {
    Some(body) ->
      a.require(body == json.to_string(receipt), "completion_receipt_conflict")
    None -> files.create(dev.root, result_path, json.to_string(receipt))
  })
  // Risk state reconciliation is deterministic and never re-executes completion.
  use now <- result.try(clock.observe())
  use _ <- result.try(a.state_assessment(
    execution,
    "completed",
    intent <> "-reconcile-" <> int.to_string(now.sample.observed.utc_us),
  ))
  Ok(receipt)
}

/// Reconstruct only a terminal reconciliation context after a transport restart.
/// The canonical completion digest must still match before any cleanup occurs.
pub fn recover(grant: a.Grant, intent: String) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.check(grant))
  let path = effect_path_for(grant.id, intent, "completion-intent")
  use body <- result.try(files.read(dev.root, path))
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "prepared_json" }),
  )
  use identity <- result.try(value.get(parsed, "execution"))
  use plan <- result.try(text(identity, "plan"))
  use task <- result.try(text(identity, "task"))
  use worker <- result.try(text(identity, "worker"))
  use hash <- result.try(text(identity, "grant_sha256"))
  use attempt_value <- result.try(value.get(identity, "attempt"))
  use epoch_value <- result.try(value.get(identity, "coordinator_epoch"))
  use attempt <- result.try(case attempt_value {
    value.Integer(n) if n > 0 -> Ok(n)
    _ -> Error("prepared_attempt")
  })
  use epoch <- result.try(case epoch_value {
    value.Integer(n) if n > 0 -> Ok(n)
    _ -> Error("prepared_epoch")
  })
  use _ <- result.try(a.require(
    worker == grant.worker && hash == grant.digest,
    "prepared_grant_binding",
  ))
  use scope <- result.try(a.lookup(grant, plan, task))
  let binding =
    dev.Binding(
      "development",
      plan,
      task,
      worker,
      attempt,
      grant.session,
      epoch,
    )
  reconcile(a.Execution(grant, scope, binding, scope.portfolio), intent)
}

/// Retained diagnostic fields of an EXECUTED effect receipt.
///
/// The backend output is bounded before retention (`dev.backend_diagnostic`),
/// so the record cannot carry every byte. What it MUST carry is a digest of
/// the bytes it does retain, the digest of the full output under its own
/// name, the byte count on both sides of the bound, and an explicit statement
/// of the relationship between them.
///
/// Before this repair the only digest present hashed the FULL output while
/// `output` held a truncated tail: a verifier holding the receipt could not
/// check the bytes in front of it, and nothing disclosed that truncation had
/// happened or how many bytes were dropped. Observed 2026-10-27 on a real
/// harness_test receipt: retained 8192 bytes digesting to e019941e..., while
/// `output_sha256` read 5055476a....
///
/// `output_retention` is derived by OBSERVING the bound's result, never by
/// matching the fallback sentinel text:
///   - "full"           the retained text is the whole output
///   - "tail_truncated" the retained text is a proper suffix of the output
///   - "unavailable"    the bound returned text that is not output bytes
///
/// The integrity property holds in all three cases: `output_retained_sha256`
/// covers exactly the bytes stored in `output`. `output_sha256` keeps its
/// original name and meaning (the full output) so historical receipts remain
/// readable under one vocabulary.
pub fn effect_output_fields(output: String) -> List(#(String, json.Json)) {
  let retained = dev.backend_diagnostic(output)
  let retention = case retained == output, string.ends_with(output, retained) {
    True, _ -> "full"
    False, True -> "tail_truncated"
    False, False -> "unavailable"
  }
  [
    #("output", json.string(retained)),
    #("output_sha256", json.string(files.digest(output))),
    #("output_retained_sha256", json.string(files.digest(retained))),
    #("output_retained_bytes", json.int(string.byte_size(retained))),
    #("output_bytes", json.int(string.byte_size(output))),
    #("output_retention", json.string(retention)),
  ]
}
