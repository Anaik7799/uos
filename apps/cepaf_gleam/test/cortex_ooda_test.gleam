// =============================================================================
// [C3I-SIL6-MSTS] UOS CORTEX OODA & SA-PLAN INTEGRATION TESTS
// =============================================================================

import cepaf_gleam/cortex/circuit_breaker_pool.{
  init_pool, is_tier_allowed, record_tier_failure,
}
import cepaf_gleam/cortex/cortex_nif
import cepaf_gleam/cortex/cortex_sup
import cepaf_gleam/cortex/cortex_types.{
  PhaseCompleted, SourceWebCockpit, TaskIntent, Tier1GeminiDirect,
  Tier6ReteUlRules, Tier7StaticAck,
}
import cepaf_gleam/cortex/ooda_actor
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn ooda_pure_query_test() {
  let intent =
    TaskIntent(
      id: "intent-test-01",
      raw_text: "Hello UOS, report system state",
      source: SourceWebCockpit,
      chat_id: None,
      user_id: None,
      timestamp_ms: 1_700_000_000,
      intent_type: "query",
      stress_level: 0.1,
    )
  let pool = init_pool()
  let #(decision, _updated_pool) =
    ooda_actor.execute_pure_ooda(intent, pool, 1_700_000_000)

  decision.phase |> should.equal(PhaseCompleted)
  decision.sa_plan_authorized |> should.be_true()
  string.contains(decision.footer, "Pipeline:") |> should.be_true()
  string.contains(decision.footer, "observe") |> should.be_true()
  string.contains(decision.footer, "orient") |> should.be_true()
  string.contains(decision.footer, "decide") |> should.be_true()
  string.contains(decision.footer, "act") |> should.be_true()
}

pub fn ooda_pure_status_ping_test() {
  let intent =
    TaskIntent(
      id: "intent-test-02",
      raw_text: "ping",
      source: SourceWebCockpit,
      chat_id: None,
      user_id: None,
      timestamp_ms: 1_700_000_000,
      intent_type: "query",
      stress_level: 0.0,
    )
  let pool = init_pool()
  let #(decision, _updated_pool) =
    ooda_actor.execute_pure_ooda(intent, pool, 1_700_000_000)

  decision.sa_plan_authorized |> should.be_true()
  case decision.inference_result {
    Some(res) -> {
      res.tier |> should.equal(Tier6ReteUlRules)
      string.contains(res.response_text, "Cluster status nominal")
      |> should.be_true()
    }
    None -> panic as "expected tier6 inference result"
  }
}

pub fn ooda_andon_stop_line_unledgered_test() {
  let intent =
    TaskIntent(
      id: "intent-test-03",
      raw_text: "run tool unledgered bypass sa-plan shadow task",
      source: SourceWebCockpit,
      chat_id: None,
      user_id: None,
      timestamp_ms: 1_700_000_000,
      intent_type: "tool_execution",
      stress_level: 0.8,
    )
  let pool = init_pool()
  let #(decision, _updated_pool) =
    ooda_actor.execute_pure_ooda(intent, pool, 1_700_000_000)

  decision.sa_plan_authorized |> should.be_false()
  string.contains(decision.reasoning, "Fractal Jidoka Andon Halt")
  |> should.be_true()
  string.contains(decision.reply_markdown, "ANDON STOP LINE HALT (-32002)")
  |> should.be_true()
}

pub fn ooda_storage_interlock_hard_denied_test() {
  let intent =
    TaskIntent(
      id: "intent-test-04",
      raw_text: "format /dev/nvme0n1 with serial 25503L801736",
      source: SourceWebCockpit,
      chat_id: None,
      user_id: None,
      timestamp_ms: 1_700_000_000,
      intent_type: "query",
      stress_level: 1.0,
    )
  let pool = init_pool()
  let #(decision, _updated_pool) =
    ooda_actor.execute_pure_ooda(intent, pool, 1_700_000_000)

  decision.sa_plan_authorized |> should.be_false()
  string.contains(decision.reasoning, "HARD_DENIED") |> should.be_true()
  string.contains(decision.reply_markdown, "HARD_DENIED INTERLOCK TRIGGERED")
  |> should.be_true()
}

pub fn cortex_supervisor_spec_test() {
  let s = cortex_sup.spec()
  s.name |> should.equal("CortexSupervisor")
  s.intensity |> should.equal(3)
  s.period_seconds |> should.equal(60)
}

pub fn circuit_breaker_pool_trip_test() {
  let pool0 = init_pool()
  is_tier_allowed(pool0, Tier1GeminiDirect, 1000) |> should.be_true()

  let pool1 = record_tier_failure(pool0, Tier1GeminiDirect, 1000)
  let pool2 = record_tier_failure(pool1, Tier1GeminiDirect, 1001)
  let pool3 = record_tier_failure(pool2, Tier1GeminiDirect, 1002)

  // Breaker should now be Open
  is_tier_allowed(pool3, Tier1GeminiDirect, 1003) |> should.be_false()

  // Tier7StaticAck is always allowed even if others fail
  is_tier_allowed(pool3, Tier7StaticAck, 1003) |> should.be_true()
}

pub fn cortex_nif_ping_test() {
  let reply = cortex_nif.ping()
  string.contains(reply, "pong:cortex_nif") |> should.be_true()
}

pub fn cortex_nif_pii_scrubbing_test() {
  let dirty = "Operator token: sk-live1234567890abcdef123456 and email user@example.com"
  let clean = cortex_nif.scrub_pii(dirty)
  string.contains(clean, "sk-live") |> should.be_false()
  string.contains(clean, "user@example.com") |> should.be_false()
}

pub fn cortex_nif_storage_interlock_test() {
  // Hard-denied serial must return False
  cortex_nif.check_storage_safety("Target drive serial 25503L801736")
  |> should.be_false()

  // Safe drive serial must return True
  cortex_nif.check_storage_safety("Target drive serial SAFE_DRIVE_OSD_01")
  |> should.be_true()
}
