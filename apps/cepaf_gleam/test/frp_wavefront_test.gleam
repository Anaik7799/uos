/// FRP OODA Wavefront tests — 13 domain actors, decision fusion
/// SC-ULTRA-001 Focus 12: FRP OODA Wavefront
import cepaf_gleam/rules/engine.{Fact}
import cepaf_gleam/rules/stream
import gleeunit/should

pub fn init_wavefront_has_13_domains_test() {
  let wf = stream.init_wavefront()
  wf.cycle_count |> should.equal(0)
  wf.fused_decision |> should.equal("NoAction")
}

pub fn evaluate_domain_updates_stream_test() {
  let wf =
    stream.init_wavefront()
    |> stream.evaluate_domain("governor", [
      Fact("Governor.OverLimit", "false"),
      Fact("Governor.HighLoad", "false"),
    ])
  wf.cycle_count |> should.equal(0)
}

pub fn fuse_decisions_produces_result_test() {
  let wf =
    stream.init_wavefront()
    |> stream.evaluate_domain("governor", [
      Fact("Governor.OverLimit", "false"),
      Fact("Governor.HighLoad", "false"),
    ])
    |> stream.fuse_decisions()
  wf.cycle_count |> should.equal(1)
}

pub fn current_decision_returns_fused_test() {
  let wf = stream.init_wavefront() |> stream.fuse_decisions()
  let result = stream.current_decision(wf)
  { result.decision != "" } |> should.be_true()
}
