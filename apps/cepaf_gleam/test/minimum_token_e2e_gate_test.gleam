import cepaf_gleam/ai/local_first_cascade.{
  type LocalProbe, type RouteRequest, Ingress, LocalProbe, LowLatencyLocalFirst,
  ProbeNotAttempted, ProbeOk, RouteRequest, check_local_resolution_gate,
  empty_ledger, record, route, summarize,
}
import gleam/list
import gleam/option.{None}
import gleeunit/should

fn make_request(id: String) -> RouteRequest {
  RouteRequest(
    request_id: id,
    logical_id: "e2e-bench-" <> id,
    tenant: "tenant-e2e",
    layer_code: "L1",
    origin: Ingress,
    strategy: LowLatencyLocalFirst,
    prompt_bytes: 256,
    max_completion_tokens: 128,
    allow_paid: False,
  )
}

fn make_probe() -> LocalProbe {
  LocalProbe(
    simd: ProbeOk(confidence_milli: 850, latency_us: 100),
    compress: ProbeNotAttempted,
    max: ProbeNotAttempted,
  )
}

pub fn e2e_gate_achieves_80_percent_local_resolution_test() {
  let ids = [
    "req-1", "req-2", "req-3", "req-4", "req-5", "req-6", "req-7", "req-8",
    "req-9", "req-10",
  ]
  let probe = make_probe()

  let final_ledger =
    list.fold(ids, empty_ledger(), fn(ledger, id) {
      let req = make_request(id)
      let dec = route(req, probe, None, 1000)
      let assert Ok(updated) = record(ledger, dec)
      updated
    })

  let summary = summarize(final_ledger)
  summary.local_resolved
  |> should.equal(10)
  summary.local_resolution_bps
  |> should.equal(10_000)

  let gate_pass = check_local_resolution_gate(summary, 8000)
  gate_pass
  |> should.equal(Ok(Nil))

  summary.remote_prompt_tokens
  |> should.equal(0)
  summary.remote_completion_tokens
  |> should.equal(0)
}
