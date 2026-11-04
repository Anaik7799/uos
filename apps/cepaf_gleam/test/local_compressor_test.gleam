import cepaf_gleam/ai/local_compressor.{
  type CompressRequest, type TokenizerSpec, CompressRequest, TokenizerSpec,
  as_probe_outcome, compress, sample, select_anchors, shannon_entropy_milli,
  tokenizer_parity_bps,
}
import cepaf_gleam/ai/local_first_cascade.{
  ProbeContractViolation, ProbeLowConfidence, ProbeOk,
}
import gleam/list
import gleam/string
import gleeunit/should

fn default_spec() -> TokenizerSpec {
  TokenizerSpec(name: "qwen-2.5-bpe", vocab_code: "v151643", version: "1.0.0")
}

fn divergent_spec() -> TokenizerSpec {
  TokenizerSpec(name: "qwen-2.5-bpe", vocab_code: "v151644", version: "1.0.0")
}

fn req(content: String) -> CompressRequest {
  CompressRequest(
    request_id: "req-c1",
    logical_id: "workload-local-c1",
    tenant: "tenant-uos",
    layer_code: "L1",
    content: content,
    tokenizer_primary: default_spec(),
    tokenizer_shadow: default_spec(),
    max_compacted_tokens: 500,
  )
}

pub fn entropy_zero_on_empty_test() {
  shannon_entropy_milli("")
  |> should.equal(0)
}

pub fn entropy_measured_positive_test() {
  let h = shannon_entropy_milli("aaaaabbbbbcccccdddddeeeee")
  // 5 distinct symbols over 25 bytes: log2(5) ~ 2.32 bits/byte = ~2322 milli-bits
  { h > 2000 && h < 2500 }
  |> should.equal(True)
}

pub fn sample_counts_structure_and_hex_test() {
  let s = sample("{\"hash\":\"0x1a2b3c\",\"count\":42}\n")
  s.total_lines
  |> should.equal(2)
  s.total_newlines
  |> should.equal(1)
  { s.total_struct_chars > 0 }
  |> should.equal(True)
  { s.total_hex_chars > 0 }
  |> should.equal(True)
}

pub fn identical_tokenizers_have_perfect_parity_test() {
  tokenizer_parity_bps("alpha beta gamma delta", default_spec(), default_spec())
  |> should.equal(10_000)
}

pub fn divergent_tokenizers_fail_parity_test() {
  let parity =
    tokenizer_parity_bps(
      "alpha beta gamma delta epsilon",
      default_spec(),
      divergent_spec(),
    )
  // Divergent vocab_code must drive parity well below floor (9980 bps)
  { parity < 9980 }
  |> should.equal(True)
}

pub fn select_anchors_finds_code_markers_test() {
  let payload =
    "// intro\npub fn calculate() -> Int {\n  42\n}\nTODO: fixme\nplain text\n"
  let anchors = select_anchors(payload)
  list.contains(anchors, "pub fn calculate() -> Int {")
  |> should.equal(True)
  list.contains(anchors, "TODO: fixme")
  |> should.equal(True)
}

pub fn empty_payload_refused_test() {
  let r = compress(req(""))
  case r {
    Error(reason) ->
      string.contains(reason, "empty_content")
      |> should.equal(True)
    Ok(_) -> should.fail()
  }
}

pub fn divergent_tokenizer_fails_closed_test() {
  let r =
    compress(
      CompressRequest(
        ..req(
          "pub fn worker() -> Nil {\n  // long enough token stream\n  let x = 1\n  let y = 2\n}\n",
        ),
        tokenizer_shadow: divergent_spec(),
      ),
    )
  case r {
    Error(reason) ->
      string.contains(reason, "tokenizer_parity_below_floor")
      |> should.equal(True)
    Ok(_) -> should.fail()
  }
}

pub fn successful_compression_preserves_anchors_test() {
  // A payload large enough (e.g. 50 lines of logs/code) that compacting down to
  // anchors + elided-marker actually strictly reduces byte size below raw_bytes,
  // satisfying validate_mcip_pin's `compacted_bytes < raw_bytes` check.
  let filler =
    list.repeat("  let ignored_trace_line_for_compaction_pad = 1234567890\n", 20)
    |> string.concat
  let content =
    "pub fn process() -> Int {\n"
    <> filler
    <> "  TODO: check bounds\n"
    <> filler
    <> "  0\n}\n"
  let r = compress(req(content))
  case r {
    Ok(res) -> {
      res.request_id
      |> should.equal("req-c1")
      list.length(res.anchors)
      |> should.equal(2)
      // Both critical anchors survived inside the envelope
      string.contains(
        res.envelope.wire_packet,
        "pub fn process() -> Int {",
      )
      |> should.equal(True)
      string.contains(res.envelope.wire_packet, "TODO: check bounds")
      |> should.equal(True)
      // Envelope satisfies MCIP pin directly
      res.envelope.ev_ceiling
      |> should.equal(93)
      res.envelope.poodavr_stage
      |> should.equal("O")
      res.within_budget
      |> should.equal(True)
    }
    Error(reason) -> {
      let _ = reason
      should.fail()
    }
  }
}

pub fn cascade_probe_outcome_mapping_test() {
  let filler =
    list.repeat("  let line = \"padded_data_to_achieve_compaction_ratio_x10\"\n", 25)
    |> string.concat
  let content =
    "pub fn ping() -> String {\n"
    <> filler
    <> "  \"pong\"\n}\n"
  let r = compress(req(content))
  let outcome = as_probe_outcome(r, 120)
  case outcome {
    ProbeOk(conf, lat) -> {
      { conf >= 700 }
      |> should.equal(True)
      lat
      |> should.equal(120)
    }
    ProbeLowConfidence(conf, _) -> {
      { conf < 700 }
      |> should.equal(True)
    }
    ProbeContractViolation(_) -> should.fail()
    _ -> should.fail()
  }
}

pub fn refusal_maps_to_contract_violation_test() {
  let outcome = as_probe_outcome(Error("empty"), 50)
  case outcome {
    ProbeContractViolation(reason) ->
      reason
      |> should.equal("empty")
    _ -> should.fail()
  }
}
