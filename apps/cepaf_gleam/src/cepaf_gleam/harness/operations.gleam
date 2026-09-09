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
pub fn capture(scope: a.Scope) -> Result(String, String) {
  use sources <- result.try(list.try_map(scope.sources, fn(path) {
    use content <- result.try(a.read_optional(path))
    let digest = case content { Some(body) -> json.string(files.digest(body)) None -> json.null() }
    Ok(json.object([#("path", json.string(path)), #("sha256", digest)]))
  }))
  Ok(json.array(sources, fn(x) { x }) |> json.to_string)
}
fn effect_path(execution: a.Execution, intent: String, suffix: String) -> String {
  "var/harness/effects/" <> execution.grant.id <> "-" <> intent <> "-" <> suffix <> ".json"
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
pub fn effect(execution: a.Execution, name: String, args: value.Value) -> Result(json.Json, String) {
  use intent <- result.try(text(args, "intent_id"))
  use _ <- result.try(a.require(a.intent_valid(intent), "intent_id"))
  use _ <- result.try(a.fence(execution, 1000))
  let sig = signature(execution, name, args)
  let result_path = effect_path(execution, intent, "result")
  use saved <- result.try(a.read_optional(result_path))
  case saved {
    Some(body) -> replay(body, sig)
    None -> {
      use pending <- result.try(a.read_optional(effect_path(execution, intent, "intent")))
      use _ <- result.try(a.require(pending == None, "unknown_effect_outcome_requires_reconciliation"))
      use risk <- result.try(a.risk_check(execution.risk_path, execution.scope, execution.binding.worker, execution.binding.attempt, True))
      use before <- result.try(capture(execution.scope))
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
        json.object([#("status", json.string("PREPARED")), ..base]) |> json.to_string))
      let outcome = perform(execution, name, args, 60_000)
      let verified = {
        use output <- result.try(outcome)
        use after <- result.try(capture(execution.scope))
        use _ <- result.try(a.require(name == "harness_write_file" || before == after, "source_changed_during_effect"))
        use final <- result.try(a.fence(execution, 0))
        use _ <- result.try(clock.continuity(proof.clock, final.clock))
        Ok(#(output, after, final.clock))
      }
      let record = case verified {
        Ok(#(output, after, final)) -> json.object([
          #("status", json.string("EXECUTED")), #("output", json.string(dev.backend_diagnostic(output))),
          #("output_sha256", json.string(files.digest(output))), #("output_manifest", json.string(after)),
          #("finished", clock.to_json(final)), ..base])
        Error(e) -> json.object([#("status", json.string("FAILED_OR_UNVERIFIED")),
          #("failure", json.string(e)), ..base])
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
    #("execution", a.observe_execution(execution)), #("candidate_sha256", json.string(files.digest(candidate))),
    #("build_receipt_sha256", json.string(build_hash)), #("test_receipt_sha256", json.string(test_hash)),
    #("journal_path", json.string(journal_path)), #("journal_sha256", json.string(files.digest(journal))),
    #("verification_path", json.string(verification_path)), #("verification_sha256", json.string(files.digest(verification)))])
    |> json.to_string
  use _ <- result.try(a.fence(execution, 10_000))
  use current <- result.try(capture(execution.scope))
  use _ <- result.try(a.require(current == candidate, "source_changed_before_completion"))
  use _ <- result.try(files.create(dev.root, effect_path(execution, intent, "completion-intent"), prepared))
  let result_id = "uos.harness-successor-completion.v1:" <> files.digest(prepared)
  use _ <- result.try(sa.complete_sa_task(execution.scope.plan, execution.scope.task, execution.binding.worker,
    execution.binding.attempt, result_id))
  use row <- result.try(dev.read_task(execution.binding))
  use _ <- result.try(a.require(row.state == "completed" && row.attempt == execution.binding.attempt
    && row.result == Some(result_id) && row.completed_at_ns != None, "completion_outcome_unknown"))
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
  use prepared <- result.try(files.read(dev.root, effect_path(execution, intent, "completion-intent")))
  use parsed <- result.try(json.parse(prepared, value.decoder()) |> result.map_error(fn(_) { "prepared_completion_json" }))
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
  let path = "var/harness/effects/" <> grant.id <> "-" <> intent <> "-completion-intent.json"
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
