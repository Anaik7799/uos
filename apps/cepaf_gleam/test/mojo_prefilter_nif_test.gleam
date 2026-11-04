import cepaf_gleam/ai/mojo_prefilter_nif.{
  MojoPrefilterConfig, PrefilterBatchResult, PrefilterScore, default_config,
  score_batch,
}
import gleam/list
import gleeunit/should

pub fn default_config_is_valid_test() {
  let cfg = default_config()
  cfg.timeout_ms
  |> should.equal(150)
  cfg.simd_width_bits
  |> should.equal(512)
}

pub fn empty_batch_fails_closed_test() {
  let cfg = default_config()
  let r = score_batch(cfg, "batch-0", [])
  case r {
    Error(err) -> err |> should.equal("empty_batch_rejected")
    Ok(_) -> should.fail()
  }
}

pub fn scoring_batch_computes_admissibility_test() {
  let cfg = default_config()
  let items = [
    #("item-1", "short"),
    #("item-2", "this is a very long text that easily passes the threshold of 70 characters and thus score is 700+"),
  ]
  let r = score_batch(cfg, "batch-1", items)
  case r {
    Ok(res) -> {
      res.batch_id |> should.equal("batch-1")
      list.length(res.scores) |> should.equal(2)
      res.reaped_cleanly |> should.equal(True)
    }
    Error(_) -> should.fail()
  }
}

pub fn calibrated_uos_domain_prompts_exceed_ninety_percent_capture_test() {
  let cfg = default_config()
  let uos_prompts = [
    #("u1", "Verify Lean 4 theorem in Traceability.lean"),
    #("u2", "Check Gospel contract in hermes_wiki"),
    #("u3", "Inspect sa-plan task state in uos.sqlite3"),
    #("u4", "Run STPA FMEA hazard analysis on L0"),
    #("u5", "Evaluate Rete rule conflict"),
    #("u6", "Check Prajna circuit breaker health"),
    #("u7", "Predict Lyapunov stability horizon"),
    #("u8", "Synthesize Shruti harmonics for Durga"),
    #("u9", "Query Razr15 Qwen 2.5 Coder 7B GGUF on port 8000"),
    #("u10", "Inspect Wisp Lustre TUI router"),
  ]
  case score_batch(cfg, "batch-uos-calibration", uos_prompts) {
    Ok(res) -> {
      let admissible_count =
        list.count(res.scores, fn(s) { s.admissible && s.confidence_milli >= 700 })
      // 10/10 (100% >= 90%) UOS domain prompts are captured locally at Tier 0 SIMD
      admissible_count |> should.equal(10)
    }
    Error(_) -> should.fail()
  }
}
