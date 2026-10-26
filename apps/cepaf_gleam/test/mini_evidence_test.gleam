import cepaf_gleam/harness/telegram_fmea_report as fmea
import cepaf_gleam/harness/telegram_verification_report as verify
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_evidence as mini
import cepaf_gleam/telegram/mini_runtime as runtime
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const now = 1_792_890_000

const hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const candidate = "cccccccccccccccccccccccccccccccccccccccc"

fn fmea_output(at: Int) -> String {
  fmea.project(fmea_source, hash, "test/mini", None, at) |> should.be_ok
}

fn verification_output(at: Int) -> String {
  verify.project(
    verification_source,
    hash,
    hash,
    candidate,
    "checklist",
    "",
    at,
  )
  |> should.be_ok
}

fn fields(observation: api.Observation) -> List(#(String, String)) {
  let assert api.Observed(_, _, values) = observation
  { dict.size(values) <= 100 } |> should.equal(True)
  let pairs = dict.to_list(values)
  list.all(pairs, fn(p) {
    string.byte_size(p.0) <= 128 && string.byte_size(p.1) <= 2048
  })
  |> should.equal(True)
  pairs
}

fn rendered(observation: api.Observation) -> String {
  fields(observation)
  |> list.map(fn(p) { p.0 <> ": " <> p.1 })
  |> string.join("\n")
}

pub fn fmea_real_report_and_bounds_test() {
  let text =
    mini.fmea(fmea_output(now * 1000), "test/mini", now)
    |> should.be_ok
    |> rendered
  string.contains(text, "test/mini") |> should.equal(True)
  string.contains(text, "NOT_GRANTED") |> should.equal(True)
  string.contains(text, "Counterfeit healthy result") |> should.equal(True)
  string.contains(text, "32") |> should.equal(True)
}

pub fn fmea_stale_record_remains_labelled_test() {
  let text =
    mini.fmea(fmea_output(now * 1000 + 2000), "test/mini", now + 2)
    |> should.be_ok
    |> rendered
  string.contains(text, "stale") |> should.equal(True)
}

pub fn fmea_wrong_scope_and_admission_refused_test() {
  let raw = fmea_output(now * 1000)
  mini.fmea(raw, "other/plan", now) |> should.be_error
  mini.fmea(string.replace(raw, "NOT_GRANTED", "GRANTED"), "test/mini", now)
  |> should.be_error
  mini.fmea(
    string.replace(raw, "observation_only", "execution"),
    "test/mini",
    now,
  )
  |> should.be_error
}

pub fn fmea_transport_age_refused_test() {
  mini.fmea(fmea_output(now * 1000), "test/mini", now + 31) |> should.be_error
  mini.fmea(fmea_output({ now + 1 } * 1000), "test/mini", now)
  |> should.be_error
}

pub fn verification_missing_and_recorded_states_test() {
  let text =
    mini.verification(verification_output(now * 1000), candidate, now)
    |> should.be_ok
    |> rendered
  string.contains(text, "RECORDED_PASS") |> should.equal(True)
  string.contains(text, "UNKNOWN") |> should.equal(True)
  string.contains(text, "NOT_GRANTED") |> should.equal(True)
  string.contains(text, candidate) |> should.equal(True)
}

pub fn verification_stale_does_not_become_pass_test() {
  let text =
    mini.verification(
      verification_output(now * 1000 + 2000),
      candidate,
      now + 2,
    )
    |> should.be_ok
    |> rendered
  string.contains(text, "STALE") |> should.equal(True)
  string.contains(text, "RECORDED_PASS") |> should.equal(False)
}

pub fn verification_wrong_binding_refused_test() {
  let raw = verification_output(now * 1000)
  mini.verification(raw, "dddddddddddddddddddddddddddddddddddddddd", now)
  |> should.be_error
  mini.verification(
    string.replace(raw, "NOT_GRANTED", "GRANTED"),
    candidate,
    now,
  )
  |> should.be_error
  mini.verification(
    string.replace(raw, "\"gates_executed\":false", "\"gates_executed\":true"),
    candidate,
    now,
  )
  |> should.be_error
}

pub fn verification_transport_age_refused_test() {
  mini.verification(verification_output(now * 1000), candidate, now + 31)
  |> should.be_error
  mini.verification(verification_output({ now + 1 } * 1000), candidate, now)
  |> should.be_error
}

pub fn malformed_and_oversize_refused_test() {
  list.each(["{}", "[]", "{", string.repeat("x", 32_769)], fn(raw) {
    mini.fmea(raw, "test/mini", now) |> should.be_error
    mini.verification(raw, candidate, now) |> should.be_error
  })
}

const fmea_source = "[{\"assessment_id\":\"assessment-0\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK0\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]},{\"assessment_id\":\"assessment-1\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK1\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]},{\"assessment_id\":\"assessment-2\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK2\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]},{\"assessment_id\":\"assessment-3\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK3\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]},{\"assessment_id\":\"assessment-4\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK4\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]},{\"assessment_id\":\"assessment-5\",\"plan_id\":\"test/mini\",\"task_id\":\"TASK5\",\"observed_at\":\"2026-10-25T00:59:59Z\",\"valid_until\":\"2026-10-25T01:00:01Z\",\"task_state\":\"available\",\"fmea_modes\":[{\"id\":\"a\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":1,\"rpn\":8,\"band\":4},{\"id\":\"b\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":2,\"rpn\":16,\"band\":4},{\"id\":\"c\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":3,\"rpn\":24,\"band\":4},{\"id\":\"d\",\"cause\":\"Counterfeit healthy result <script>alert(1)</script>\",\"effect\":\"Unsafe release\",\"controls\":\"Independent evidence\",\"s\":4,\"o\":2,\"det\":4,\"rpn\":32,\"band\":4}]}]"

const verification_source = "{\"schema\":\"uos.telegram.verification-record.v1\",\"candidate\":\"cccccccccccccccccccccccccccccccccccccccc\",\"observed_at_ms\":1792889999000,\"expires_at_ms\":1792890001000,\"checkpoints\":[{\"id\":\"CHK-01-TIME\",\"outcome\":\"PASS\",\"runtime_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"formal_sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"reason\":\"Recorded fixture only\"}],\"aspects\":[]}"

pub fn task_lease_exact_nanosecond_boundary_test() {
  runtime.task_state("executing", Some("1000000001"), 1_000_000_000)
  |> should.equal("executing")
  runtime.task_state("executing", Some("1000000001"), 1_000_000_001)
  |> should.equal("executing (lease expired)")
  runtime.task_state("executing", Some("1000000001"), 1_000_000_002)
  |> should.equal("executing (lease expired)")
  runtime.task_state("executing", None, 1_000_000_002)
  |> should.equal("executing (lease unknown)")
  runtime.task_state("executing", Some("invalid"), 1_000_000_002)
  |> should.equal("executing (lease unknown)")
  runtime.task_state("completed", None, 1_000_000_002)
  |> should.equal("completed")
}

/// Rewrite one integer JSON field of a record, for horizon tests.
fn with_int_field(raw: String, key: String, value: Int) -> String {
  case string.split(raw, "\"" <> key <> "\":") {
    [head, tail] -> {
      let rest = case string.split_once(tail, ",") {
        Ok(#(_, after)) -> "," <> after
        Error(_) -> tail
      }
      head <> "\"" <> key <> "\":" <> int.to_string(value) <> rest
    }
    _ -> raw
  }
}

/// Review A-02 (wave 6l): a record whose own horizon has passed is rendered
/// expired and stale with no passes, whatever the worker wrote.
pub fn verification_expired_record_is_stale_with_zero_credit_test() {
  let fresh = verification_output(now * 1000)
  let expired =
    fresh
    |> with_int_field("record_observed_at_ms", now * 1000 - 100_000)
    |> with_int_field("record_expires_at_ms", now * 1000 - 50_000)
  let text =
    mini.verification(expired, candidate, now)
    |> should.be_ok
    |> rendered
  string.contains(text, "Record expired: true") |> should.equal(True)
  string.contains(text, "Record stale: true") |> should.equal(True)
  string.contains(text, "Recorded passes: 0 (expired)") |> should.equal(True)
  // the fresh record is unchanged by the law
  let live =
    mini.verification(fresh, candidate, now) |> should.be_ok |> rendered
  string.contains(live, "Record expired: false") |> should.equal(True)
  string.contains(live, "Record stale: false") |> should.equal(True)
}
