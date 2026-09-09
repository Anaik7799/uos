//// Task-scoped development effects with durable intent/result receipts.
//// Sa-plan remains the task authority. Receipts are evidence, never grants.
import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge as sa
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub fn text(args: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(args, key))
  case found { value.Text(s) -> Ok(s) _ -> Error("string_field:" <> key) }
}
pub fn fields(name: String) -> List(String) {
  case name {
    "harness_claim" | "harness_attach" -> ["plan", "task", "intent_id"]
    "harness_read_file" -> ["path"]
    "harness_write_file" -> ["intent_id", "path", "content", "expected_sha256"]
    "harness_build" | "harness_test" | "harness_release" | "harness_reconcile" -> ["intent_id"]
    "harness_assess" -> ["intent_id", "assessment_json", "reason"]
    "harness_finish" -> ["intent_id", "journal_path", "build_intent_id", "test_intent_id", "verification_path"]
    _ -> []
  }
}
pub const names = ["harness_status", "harness_clock", "harness_heartbeat", "harness_claim",
  "harness_attach", "harness_release", "harness_read_file", "harness_write_file",
  "harness_build", "harness_test", "harness_assess", "harness_finish", "harness_reconcile"]

pub fn validate_args(name: String, args: value.Value) -> Result(Nil, String) {
  use _ <- result.try(a.require(list.contains(names, name), "unknown_tool"))
  case args {
    value.Object(actual) -> {
      let required = fields(name)
      use _ <- result.try(a.require(list.length(actual) == list.length(required)
        && list.all(actual, fn(field) { list.contains(required, field.0) }), "unexpected_or_missing_fields"))
      list.try_each(required, fn(key) { text(args, key) |> result.map(fn(_) { Nil }) })
    }
    _ -> Error("arguments_object_required")
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
  use entries <- result.try(list.try_map(paths, fn(path) {
    use content <- result.try(a.read_optional(path))
    let digest = case content { Some(body) -> json.string(files.digest(body)) None -> json.null() }
    Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
  }))
  Ok(json.array(entries, fn(x) { x }) |> json.to_string)
}

/// Everything the grant authorizes to change: sources plus writes, sorted and
/// deduplicated so the manifest is a function of the SET, not of declaration order.
pub fn guard_capture(scope: a.Scope) -> Result(String, String) {
  manifest_of(list.sort(list.unique(list.append(scope.sources, scope.writes)), string.compare))
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
  use before <- result.try(json.parse(before_json, value.decoder()) |> result.map_error(fn(_) { "manifest_json" }))
  use after <- result.try(json.parse(after_json, value.decoder()) |> result.map_error(fn(_) { "manifest_json" }))
  case before, after {
    value.Array(b), value.Array(c) -> {
      use _ <- result.try(a.require(list.length(b) == list.length(c), "manifest_structure_mismatch"))
      list.try_each(list.zip(b, c), fn(pair) {
        use before_path <- result.try(text(pair.0, "path"))
        use after_path <- result.try(text(pair.1, "path"))
        use _ <- result.try(a.require(before_path == after_path, "manifest_path_mismatch"))
        use before_sha <- result.try(value.get(pair.0, "sha256"))
        use after_sha <- result.try(value.get(pair.1, "sha256"))
        case before_path == target_path {
          True -> a.require(after_sha == value.Text(expected_digest), "write_target_digest_mismatch")
          False -> a.require(before_sha == after_sha, "unauthorized_concurrent_modification:" <> before_path)
        }
      })
    }
    _, _ -> Error("manifest_array_required")
  }
}

pub fn capture(scope: a.Scope) -> Result(String, String) {
  use sources <- result.try(list.try_map(scope.sources, fn(path) {
    use content <- result.try(a.read_optional(path))
    let digest = case content { Some(body) -> json.string(files.digest(body)) None -> json.null() }
    Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
  }))
  Ok(json.array(sources, fn(x) { x }) |> json.to_string)
}
// C2: the old encoding was "<grant>-<intent>-<suffix>.json". "-" is inside the
// admission.component charset, so intent "x-completion" with suffix "intent" and
// intent "x" with suffix "completion-intent" produced THE SAME PATH. "@" is
// outside that charset, so the ambiguity is gone by construction rather than by
// convention. Pre-existing v9 effect files are deliberately unreadable under the
// new scheme: they carry no `kind` tag, so reading them would reinstate exactly
// the untyped observable this fix removes. Grant ids are fresh per session.
pub fn effect_path_for(grant_id: String, intent: String, suffix: String) -> String {
  "var/harness/effects/" <> grant_id <> "@" <> intent <> "@" <> suffix <> ".json"
}

fn effect_path(execution: a.Execution, intent: String, suffix: String) -> String {
  effect_path_for(execution.grant.id, intent, suffix)
}
fn signature(execution: a.Execution, tool: String, args: value.Value) -> String {
  json.object([
    #("grant", json.string(execution.grant.digest)), #("plan", json.string(execution.scope.plan)),
    #("task", json.string(execution.scope.task)), #("attempt", json.int(execution.binding.attempt)),
    #("worker", json.string(execution.binding.worker)), #("tool", json.string(tool)),
    #("args", value.encode(args)),
  ]) |> json.to_string |> files.digest
}
pub fn replay(saved: String, expected_signature: String) -> Result(json.Json, String) {
  use parsed <- result.try(json.parse(saved, value.decoder()) |> result.map_error(fn(_) { "corrupt_result" }))
  use sig <- result.try(value.get(parsed, "signature"))
  use status <- result.try(value.get(parsed, "status"))
  // Meaning comes from the record, never from where the record was found.
  use _ <- result.try(a.require(value.get(parsed, "schema")
    == Ok(value.Text("uos.harness-successor-effect.v1"))
    && value.get(parsed, "kind") == Ok(value.Text("effect_result")), "replay_kind_mismatch"))
  use _ <- result.try(a.require(sig == value.Text(expected_signature), "replay_binding_mismatch"))
  use _ <- result.try(a.require(status == value.Text("EXECUTED"), "saved_effect_failed_or_unverified_no_retry"))
  Ok(value.encode(parsed))
}
fn perform(execution: a.Execution, name: String, args: value.Value, timeout: Int) -> Result(String, String) {
  case name {
    "harness_write_file" -> {
      use path <- result.try(text(args, "path"))
      use body <- result.try(text(args, "content"))
      use expected <- result.try(text(args, "expected_sha256"))
      use _ <- result.try(a.require(list.contains(execution.scope.writes, path), "write_scope_refused"))
      use _ <- result.try(case expected {
        "ABSENT" -> files.create(dev.root, path, body)
        _ -> files.replace(dev.root, path, expected, body)
      })
      use readback <- result.try(files.read(dev.root, path))
      use _ <- result.try(a.require(readback == body, "write_readback_mismatch"))
      Ok(files.digest(readback))
    }
    "harness_build" -> dev.bounded(dev.root <> "/toolchains/nix-profile/bin/env", build_args(["build"]), timeout)
    "harness_test" -> dev.bounded(dev.root <> "/toolchains/nix-profile/bin/env",
      build_args(["run", "-m", "harness_task_verification", "--", ..execution.scope.tests]), timeout)
    _ -> Error("effect_not_admitted")
  }
}
pub fn build_args(args: List(String)) -> List(String) {
  ["--chdir=" <> dev.root <> "/apps/cepaf_gleam",
    "PATH=" <> dev.root <> "/toolchains/nix-profile/bin:" <> dev.root <> "/toolchains/gleam-1.16.0/bin:" <> dev.root <> "/toolchains/opam-ocaml/bin",
    "ERL_FLAGS=+S 2:2 +A 2", "ERL_CRASH_DUMP_SECONDS=0",
    dev.root <> "/toolchains/gleam-1.16.0/bin/gleam", ..args]
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
pub fn check_not_burned(execution: a.Execution, intent: String, signature: String) -> Result(Nil, String) {
  use by_intent <- result.try(a.read_optional(burned_intent_path(intent)))
  use _ <- result.try(a.require(by_intent == None, "intent_permanently_quarantined_no_retry"))
  use by_signature <- result.try(a.read_optional(burned_signature_path(signature)))
  use _ <- result.try(a.require(by_signature == None, "logical_effect_permanently_quarantined_no_retry"))
  use by_grant <- result.try(a.read_optional(effect_path(execution, intent, "quarantine")))
  a.require(by_grant == None, "intent_permanently_quarantined_no_retry")
}

pub fn record_quarantine(
  execution: a.Execution,
  intent: String,
  intent_body: String,
  reason: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(json.parse(intent_body, value.decoder()) |> result.map_error(fn(_) { "intent_json" }))
  use signature <- result.try(text(parsed, "signature"))
  use tool <- result.try(text(parsed, "tool"))
  use original_input <- result.try(text(parsed, "input_sha256"))
  use now <- result.try(clock.observe())
  use observed <- result.try(guard_capture(execution.scope))
  let record = json.object([
    #("schema", json.string("uos.harness-successor-quarantine.v1")),
    #("kind", json.string("quarantine_record")),
    #("status", json.string("QUARANTINED_OUTCOME_UNKNOWN")),
    #("disposition", json.string("PERMANENT_NO_RETRY")),
    #("statement", json.string(
      "No success, failure or rollback has been established for this effect. "
      <> "The outcome is unknown and remains unknown. This record retires the "
      <> "logical effect; it does not resolve it.")),
    #("reason", json.string(reason)),
    #("intent_id", json.string(intent)),
    #("tool", json.string(tool)),
    #("signature", json.string(signature)),
    #("original_intent_path", json.string(effect_path(execution, intent, "intent"))),
    #("original_intent_sha256", json.string(files.digest(intent_body))),
    #("original_input_sha256_observation", json.string(original_input)),
    #("execution", a.observe_execution(execution)),
    #("original_clock", case value.get(parsed, "started") { Ok(v) -> value.encode(v) Error(_) -> json.null() }),
    #("manifest_observation_at_quarantine", json.string(observed)),
    #("manifest_sha256_at_quarantine", json.string(files.digest(observed))),
    // Labelled observations, NOT proof. A manifest that matches says the files
    // look the same right now; it says nothing about who can still write them.
    #("observation_disclaimer", json.string(
      "Manifest fields are point-in-time OBSERVATIONS, not evidence of quiescence "
      <> "and not evidence about the effect's outcome.")),
    #("quiescence_grade", json.string("NO_SUFFICIENT_SAME_BOOT_EVIDENCE_IN_THIS_SUBSTRATE")),
    #("resumption", json.string("REFUSED")),
    #("missing_evidence", json.array([
      "no cgroup or equivalent containment was bound to the original dispatch, so "
        <> "the descendant population cannot be enumerated",
      "tools/ecology_process.ml reaps only its owned process group; its own header "
        <> "states it does not contain children that create new sessions, so its "
        <> "return is not evidence of descendant death",
      "a changed boot_id would prove the old executor is gone, but it also fails "
        <> "validate_window, so it is not a resumption path",
      "no evidence whether the effect succeeded, failed, or partially applied",
    ], json.string)),
    #("quarantined_at", clock.to_json(now)),
    #("system_admission", json.bool(False)),
  ])
  let path = effect_path(execution, intent, "quarantine")
  use _ <- result.try(files.create(dev.root, path, json.to_string(record)))
  let tombstone = json.object([
    #("intent_id", json.string(intent)), #("signature", json.string(signature)),
    #("quarantine_receipt", json.string(path)),
  ]) |> json.to_string
  use _ <- result.try(files.create(dev.root, burned_intent_path(intent), tombstone))
  use _ <- result.try(files.create(dev.root, burned_signature_path(signature), tombstone))
  Ok(record)
}

pub fn effect(execution: a.Execution, name: String, args: value.Value) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.fence(execution, 1000))
  let sig = signature(execution, name, args)
  use _ <- result.try(check_not_burned(execution, intent, sig))
  let result_path = effect_path(execution, intent, "result")
  use saved <- result.try(a.read_optional(result_path))
  case saved {
    Some(body) -> replay(body, sig)
    None -> {
      use pending <- result.try(a.read_optional(effect_path(execution, intent, "intent")))
      use _ <- result.try(a.require(pending == None, "unknown_effect_outcome_requires_reconciliation"))
      use risk <- result.try(a.risk_check(execution.risk_path, execution.scope, execution.binding.worker, execution.binding.attempt, True))
      use before <- result.try(capture(execution.scope))
      // The wider manifest guards concurrent modification; `before` above stays
      // the narrow candidate identity that the receipt binds.
      use guard_before <- result.try(guard_capture(execution.scope))
      use proof <- result.try(a.fence(execution, 60_000))
      let trace = crypto.strong_random_bytes(16) |> bit_array.base16_encode |> string.lowercase
      let span = crypto.strong_random_bytes(8) |> bit_array.base16_encode |> string.lowercase
      let base = [#("schema", json.string("uos.harness-successor-effect.v1")),
        #("intent_id", json.string(intent)), #("tool", json.string(name)),
        #("signature", json.string(sig)), #("execution", a.observe_execution(execution)),
        #("trace_id", json.string(trace)), #("span_id", json.string(span)),
        #("input_manifest", json.string(before)), #("input_sha256", json.string(files.digest(before))),
        #("risk_receipt", json.string(risk)), #("started", clock.to_json(proof.clock))]
      use _ <- result.try(files.create(dev.root, effect_path(execution, intent, "intent"),
        json.object([#("status", json.string("PREPARED")),
          #("kind", json.string("effect_intent")), ..base]) |> json.to_string))
      let outcome = perform(execution, name, args, 60_000)
      let verified = {
        use output <- result.try(outcome)
        use after <- result.try(capture(execution.scope))
        use guard_after <- result.try(guard_capture(execution.scope))
        use _ <- result.try(case name {
          // Was: `name == "harness_write_file" || before == after`, which let ANY
          // file move underneath a write. Now the write target must carry exactly
          // the digest claimed and everything else must be untouched.
          "harness_write_file" -> {
            use target <- result.try(text(args, "path"))
            use content <- result.try(text(args, "content"))
            write_manifest_clean(guard_before, guard_after, target, files.digest(content))
          }
          _ -> a.require(guard_before == guard_after, "scope_changed_during_effect")
        })
        use final <- result.try(a.fence(execution, 0))
        use _ <- result.try(clock.continuity(proof.clock, final.clock))
        Ok(#(output, after, final.clock))
      }
      let record = case verified {
        Ok(#(output, after, final)) -> json.object([
          #("status", json.string("EXECUTED")), #("kind", json.string("effect_result")),
          #("output", json.string(dev.backend_diagnostic(output))),
          #("output_sha256", json.string(files.digest(output))), #("output_manifest", json.string(after)),
          #("finished", clock.to_json(final)), ..base])
        Error(e) -> json.object([#("status", json.string("FAILED_OR_UNVERIFIED")),
          #("kind", json.string("effect_result")), #("failure", json.string(e)), ..base])
      }
      use _ <- result.try(files.create(dev.root, result_path, json.to_string(record)))
      case verified {
        Ok(_) -> Ok(record)
        Error(e) -> {
          let known_exit = case outcome {
            Error(cause) -> string.starts_with(cause, "backend_exit:") && name != "harness_write_file"
            Ok(_) -> False
          }
          let label = case known_exit { True -> "effect_failed:" False -> "effect_unverified:" }
          Error(label <> e <> ";receipt:" <> result_path)
        }
      }
    }
  }
}
pub fn read_file(execution: a.Execution, path: String) -> Result(json.Json, String) {
  use _ <- result.try(a.fence(execution, 1000))
  use _ <- result.try(a.require(list.contains(execution.scope.reads, path)
    || list.contains(execution.scope.writes, path) || list.contains(execution.scope.sources, path), "read_scope_refused"))
  use body <- result.try(files.read(dev.root, path))
  use _ <- result.try(a.fence(execution, 0))
  Ok(json.object([#("path", json.string(path)), #("content", json.string(body)),
    #("sha256", json.string(files.digest(body))), #("execution", a.observe_execution(execution))]))
}
pub fn assessment_paths_allowed(grant: a.Grant, body: String) -> Result(Nil, String) {
  use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "assessment_json" }))
  use records <- result.try(case parsed { value.Array(xs) -> Ok(xs) _ -> Error("assessment_array") })
  let allowed = list.flatten(list.map(grant.scopes, fn(scope) { list.append(scope.sources, scope.reads) }))
  list.try_each(records, fn(record) {
    use snapshot <- result.try(value.get(record, "snapshot"))
    use entries <- result.try(value.get(snapshot, "evidence"))
    use entries <- result.try(case entries { value.Array(xs) -> Ok(xs) _ -> Error("assessment_evidence_array") })
    list.try_each(entries, fn(entry) {
      use path <- result.try(text(entry, "path"))
      a.require(a.public_path(path) && list.contains(allowed, path), "assessment_source_outside_grant")
    })
  })
}
pub fn assess(execution: a.Execution, args: value.Value) -> Result(a.Execution, String) {
  // Repairing an assessment needs the live task fence, not a passing old
  // assessment. This does not execute source/backend effects or grant admission.
  use _ <- result.try(a.fence(execution, 15_000))
  use intent <- result.try(text(args, "intent_id"))
  use body <- result.try(text(args, "assessment_json"))
  use reason <- result.try(text(args, "reason"))
  use _ <- result.try(a.require(a.intent_valid(intent) && string.byte_size(reason) >= 16
    && string.byte_size(reason) <= 2048, "qualified_assessment_reason_required"))
  use _ <- result.try(assessment_paths_allowed(execution.grant, body))
  let path = "var/harness/" <> execution.grant.id <> "-" <> intent <> "-assessment.json"
  use _ <- result.try(files.create(dev.root, path, body))
  use _ <- result.try(a.risk_check(path, execution.scope, execution.binding.worker, execution.binding.attempt, True))
  use _ <- result.try(files.create(dev.root, "var/harness/" <> execution.grant.id <> "-" <> intent <> "-assessment-reason.json",
    json.object([#("reason", json.string(reason)), #("assessment", json.string(path)),
      #("execution", a.observe_execution(execution))]) |> json.to_string))
  use original <- result.try(files.read(dev.root, execution.scope.portfolio))
  use _ <- result.try(files.create(dev.root, path <> ".before.json", original))
  use _ <- result.try(a.fence(execution, 0))
  use _ <- result.try(files.replace(dev.root, execution.scope.portfolio, files.digest(original), body))
  Ok(a.Execution(..execution, risk_path: execution.scope.portfolio))
}
pub fn release(execution: a.Execution, intent: String) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.fence(execution, 5000))
  release_after_fence(execution, intent) |> result.map_error(fn(e) { "release_outcome_unknown:" <> e })
}
fn release_after_fence(execution: a.Execution, intent: String) -> Result(json.Json, String) {
  use _ <- result.try(sa.run_sa_plan_cli(["task", "release", execution.scope.plan, execution.scope.task,
    execution.binding.worker, int.to_string(execution.binding.attempt)]))
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(row.state == "available" && row.worker == None
    && row.attempt == execution.binding.attempt, "release_outcome_unknown"))
  use _ <- result.try(a.coordinate(["release", execution.binding.session, dev.task_resource(execution.binding),
    int.to_string(execution.binding.epoch), execution.grant.id <> "-" <> intent <> "-release"]))
  use _ <- result.try(a.state_assessment(execution, "available", intent <> "-release"))
  Ok(json.object([#("state", json.string("available")), #("released", a.observe_execution(execution)),
    #("next_task", json.string("READY_AFTER_FRESH_FULL_PLAN_ASSESSMENT"))]))
}
fn successful_check(execution: a.Execution, id: String, tool: String, candidate: String) -> Result(String, String) {
  use _ <- result.try(a.require(a.intent_valid(id), "check_intent"))
  let path = effect_path(execution, id, "result")
  use body <- result.try(files.read(dev.root, path))
  use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "check_receipt_json" }))
  let sig = signature(execution, tool, value.Object([#("intent_id", value.Text(id))]))
  use _ <- result.try(replay(body, sig))
  use source <- result.try(value.get(parsed, "input_manifest"))
  use _ <- result.try(a.require(source == value.Text(candidate), "verification_candidate_mismatch"))
  Ok(files.digest(body))
}
pub fn finish(execution: a.Execution, args: value.Value) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  use journal_path <- result.try(text(args, "journal_path"))
  use verification_path <- result.try(text(args, "verification_path"))
  use build <- result.try(text(args, "build_intent_id"))
  use test_id <- result.try(text(args, "test_intent_id"))
  use _ <- result.try(a.require(a.intent_valid(intent) && list.contains(execution.scope.reads, journal_path)
    && list.contains(execution.scope.reads, verification_path), "completion_scope"))
  use _ <- result.try(a.fence(execution, 20_000))
  use _ <- result.try(a.risk_check(execution.risk_path, execution.scope, execution.binding.worker, execution.binding.attempt, True))
  use candidate <- result.try(capture(execution.scope))
  use build_hash <- result.try(successful_check(execution, build, "harness_build", candidate))
  use test_hash <- result.try(successful_check(execution, test_id, "harness_test", candidate))
  use journal <- result.try(files.read(dev.root, journal_path))
  use _ <- result.try(a.require(dev.journal_sections_valid(journal), "thirteen_journal_sections_required"))
  use verification <- result.try(files.read(dev.root, verification_path))
  use attestation <- result.try(json.parse(verification, value.decoder()) |> result.map_error(fn(_) { "verification_json" }))
  use _ <- result.try(list.try_each([
    #("schema", value.Text("uos.harness-task-verification.v1")),
    #("plan", value.Text(execution.scope.plan)), #("task", value.Text(execution.scope.task)),
    #("attempt", value.Integer(execution.binding.attempt)),
    #("candidate_sha256", value.Text(files.digest(candidate))),
    #("build_receipt_sha256", value.Text(build_hash)), #("test_receipt_sha256", value.Text(test_hash)),
    #("verdict", value.Text("VERIFIED")),
  ], fn(pair) {
    use actual <- result.try(value.get(attestation, pair.0))
    a.require(actual == pair.1, "verification_binding:" <> pair.0)
  }))
  // Exact source/evidence peer acknowledgement is required as a file reference.
  // Its qualified authorship remains the cooperative local review boundary.
  use peer_path <- result.try(text(attestation, "peer_review_path"))
  use peer_digest <- result.try(text(attestation, "peer_review_sha256"))
  use formal_path <- result.try(text(attestation, "formal_evidence_path"))
  use formal_digest <- result.try(text(attestation, "formal_evidence_sha256"))
  use _ <- result.try(list.try_each([#(peer_path, peer_digest), #(formal_path, formal_digest)], fn(pair) {
    use _ <- result.try(a.require(list.contains(execution.scope.reads, pair.0) && a.digest_valid(pair.1), "evidence_scope"))
    use evidence <- result.try(files.read(dev.root, pair.0))
    a.require(files.digest(evidence) == pair.1, "evidence_digest_mismatch")
  }))
  let prepared = json.object([#("schema", json.string("uos.harness-successor-completion.v1")),
    #("kind", json.string("completion_intent")), #("intent_id", json.string(intent)),
    #("execution", a.observe_execution(execution)), #("candidate_sha256", json.string(files.digest(candidate))),
    #("build_receipt_sha256", json.string(build_hash)), #("test_receipt_sha256", json.string(test_hash)),
    #("journal_path", json.string(journal_path)), #("journal_sha256", json.string(files.digest(journal))),
    #("verification_path", json.string(verification_path)), #("verification_sha256", json.string(files.digest(verification)))])
    |> json.to_string
  use _ <- result.try(a.fence(execution, 10_000))
  use current <- result.try(capture(execution.scope))
  use _ <- result.try(a.require(current == candidate, "source_changed_before_completion"))
  use _ <- result.try(files.create(dev.root, effect_path(execution, intent, "completion-intent"), prepared)
    |> result.map_error(fn(e) { "completion_outcome_unknown:prepared:" <> e }))
  finish_after_prepare(execution, intent, prepared)
    |> result.map_error(fn(e) { "completion_outcome_unknown:" <> e })
}
fn finish_after_prepare(execution: a.Execution, intent: String, prepared: String) -> Result(json.Json, String) {
  let result_id = "uos.harness-successor-completion.v1:" <> files.digest(prepared)
  use _ <- result.try(sa.complete_sa_task(execution.scope.plan, execution.scope.task, execution.binding.worker,
    execution.binding.attempt, result_id))
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(row.state == "completed" && row.attempt == execution.binding.attempt
    && row.result == Some(result_id) && row.completed_at_ns != None, "completion_outcome_unknown"))
  use _ <- result.try(a.check(execution.grant))
  use _ <- result.try(a.coordinate(["release", execution.binding.session, dev.task_resource(execution.binding),
    int.to_string(execution.binding.epoch), execution.grant.id <> "-" <> intent <> "-complete-release"]))
  let receipt = json.object([#("state", json.string("completed")), #("result", json.string(result_id)),
    #("prepared", json.string(prepared)), #("system_admission", json.bool(False))])
  use _ <- result.try(files.create(dev.root, effect_path(execution, intent, "completion-result"), json.to_string(receipt)))
  use _ <- result.try(a.state_assessment(execution, "completed", intent <> "-complete"))
  Ok(receipt)
}

/// Recover a committed completion by exact canonical result digest. This is a
/// terminal read/reconciliation path and grants no ordinary source effects.
pub fn reconcile(execution: a.Execution, intent: String) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.check(execution.grant))
  // Dispatch on the record's DECLARED kind, never on which filename exists:
  // before the "@" encoding those two questions had the same answer for some
  // intent ids, and a filename was never evidence of a record's meaning anyway.
  use completion <- result.try(a.read_optional(effect_path(execution, intent, "completion-intent")))
  case completion {
    None -> reconcile_effect(execution, intent)
    Some(prepared) -> reconcile_completion(execution, intent, prepared)
  }
}

/// A dangling effect intent -- written before dispatch, never resulted -- is the
/// state that previously had no exit at all. It gets quarantined, not resolved.
fn reconcile_effect(execution: a.Execution, intent: String) -> Result(json.Json, String) {
  use quarantined <- result.try(a.read_optional(effect_path(execution, intent, "quarantine")))
  case quarantined {
    Some(body) -> {
      use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "quarantine_json" }))
      use _ <- result.try(a.require(value.get(parsed, "schema")
        == Ok(value.Text("uos.harness-successor-quarantine.v1"))
        && value.get(parsed, "kind") == Ok(value.Text("quarantine_record"))
        && value.get(parsed, "intent_id") == Ok(value.Text(intent)), "quarantine_kind_mismatch"))
      Ok(value.encode(parsed))
    }
    None -> {
      use pending <- result.try(a.read_optional(effect_path(execution, intent, "intent")))
      case pending {
        None -> Error("reconciliation_target_not_found")
        Some(intent_body) -> {
          use parsed <- result.try(json.parse(intent_body, value.decoder())
            |> result.map_error(fn(_) { "intent_json" }))
          use _ <- result.try(a.require(value.get(parsed, "schema")
            == Ok(value.Text("uos.harness-successor-effect.v1"))
            && value.get(parsed, "kind") == Ok(value.Text("effect_intent"))
            && value.get(parsed, "intent_id") == Ok(value.Text(intent)), "effect_intent_kind_mismatch"))
          use settled <- result.try(a.read_optional(effect_path(execution, intent, "result")))
          case settled {
            // A result exists after all: the outcome is known, so there is
            // nothing to quarantine. Hand back what was recorded.
            Some(body) -> json.parse(body, value.decoder())
              |> result.map(value.encode) |> result.map_error(fn(_) { "corrupt_result" })
            None -> record_quarantine(execution, intent, intent_body, "dangling_effect_intent")
          }
        }
      }
    }
  }
}

fn reconcile_completion(execution: a.Execution, intent: String, prepared: String) -> Result(json.Json, String) {
  use parsed <- result.try(json.parse(prepared, value.decoder()) |> result.map_error(fn(_) { "prepared_completion_json" }))
  use _ <- result.try(a.require(value.get(parsed, "schema")
    == Ok(value.Text("uos.harness-successor-completion.v1"))
    && value.get(parsed, "kind") == Ok(value.Text("completion_intent"))
    && value.get(parsed, "intent_id") == Ok(value.Text(intent)), "prepared_completion_kind"))
  use identity <- result.try(value.get(parsed, "execution"))
  use _ <- result.try(list.try_each([
    #("plan", value.Text(execution.scope.plan)), #("task", value.Text(execution.scope.task)),
    #("worker", value.Text(execution.binding.worker)), #("attempt", value.Integer(execution.binding.attempt)),
    #("grant_sha256", value.Text(execution.grant.digest)),
  ], fn(pair) {
    use actual <- result.try(value.get(identity, pair.0))
    a.require(actual == pair.1, "prepared_completion_identity")
  }))
  let result_id = "uos.harness-successor-completion.v1:" <> files.digest(prepared)
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(row.state == "completed" && row.attempt == execution.binding.attempt
    && row.result == Some(result_id) && row.completed_at_ns != None, "canonical_completion_not_matched"))
  use _ <- result.try(a.coordinate(["release", execution.binding.session, dev.task_resource(execution.binding),
    int.to_string(execution.binding.epoch), execution.grant.id <> "-" <> intent <> "-complete-release"]))
  let receipt = json.object([#("state", json.string("completed")), #("result", json.string(result_id)),
    #("prepared", json.string(prepared)), #("system_admission", json.bool(False))])
  let result_path = effect_path(execution, intent, "completion-result")
  use existing <- result.try(a.read_optional(result_path))
  use _ <- result.try(case existing {
    Some(body) -> a.require(body == json.to_string(receipt), "completion_receipt_conflict")
    None -> files.create(dev.root, result_path, json.to_string(receipt))
  })
  // Risk state reconciliation is deterministic and never re-executes completion.
  use now <- result.try(clock.observe())
  use _ <- result.try(a.state_assessment(execution, "completed",
    intent <> "-reconcile-" <> int.to_string(now.sample.observed.utc_us)))
  Ok(receipt)
}

/// Reconstruct only a terminal reconciliation context after a transport restart.
/// The canonical completion digest must still match before any cleanup occurs.
pub fn recover(grant: a.Grant, intent: String) -> Result(json.Json, String) {
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.check(grant))
  let path = effect_path_for(grant.id, intent, "completion-intent")
  use body <- result.try(files.read(dev.root, path))
  use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "prepared_json" }))
  use identity <- result.try(value.get(parsed, "execution"))
  use plan <- result.try(text(identity, "plan"))
  use task <- result.try(text(identity, "task"))
  use worker <- result.try(text(identity, "worker"))
  use hash <- result.try(text(identity, "grant_sha256"))
  use attempt_value <- result.try(value.get(identity, "attempt"))
  use epoch_value <- result.try(value.get(identity, "coordinator_epoch"))
  use attempt <- result.try(case attempt_value { value.Integer(n) if n > 0 -> Ok(n) _ -> Error("prepared_attempt") })
  use epoch <- result.try(case epoch_value { value.Integer(n) if n > 0 -> Ok(n) _ -> Error("prepared_epoch") })
  use _ <- result.try(a.require(worker == grant.worker && hash == grant.digest, "prepared_grant_binding"))
  use scope <- result.try(a.lookup(grant, plan, task))
  let binding = dev.Binding("development", plan, task, worker, attempt, grant.session, epoch)
  reconcile(a.Execution(grant, scope, binding, scope.portfolio), intent)
}
