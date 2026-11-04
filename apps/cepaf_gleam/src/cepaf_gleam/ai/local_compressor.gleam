//// Tier-1 local compressor: the "Bionic Token Twin" supervised fastpath.
//// #fractal-l1 #fractal-l2 #fractal-l4
////
//// `SC-COMPRESS-001`, `SC-ROUTING-001`, `SC-PROVENANCE-001`
////
//// PURPOSE
//// ------
//// This is the local (zero-remote-token) compression tier of the minimum-token
//// cascade. Given a payload it measures the payload, classifies it against the
//// Bionic Token Twin fastpath catalogue, selects the anchors that must survive,
//// prunes, and emits a real `@MCIP/1.0` envelope whose receipt the router will
//// later pin before any remote authorization.
////
//// WHAT IS MEASURED VS WHAT IS SIMULATED (read this before quoting a number)
//// ----------------------------------------------------------------------
//// MEASURED, from the actual bytes passed in:
////   - Shannon entropy per byte (`shannon_h_milli`)
////   - structural / hex-digit / newline density (`*_bps`)
////   - codepoint, byte and line counts
////   - the emitted envelope's own `compacted_bytes`, read back from
////     `core_bionic_token_twin.encode_mcip_v1_envelope`, not asserted
////   - tokenizer identity parity between the primary and shadow specs
////   - anchor survival: every selected anchor is re-checked against the
////     compacted text, and a single dropped anchor is a hard error
////
//// NOT MEASURED — do not present as achievement:
////   - `confidence_milli` is a RATIO score against the class's target
////     compression ratio from the catalogue. It says "this payload compacted to
////     its target", NOT "a model will answer correctly from it".
////   - the tokenizer parity gate compares token PROJECTIONS derived from the
////     pinned vocab code. It detects a version/vocab disagreement (the failure
////     Codex required to fail closed) but it does NOT re-implement BPE and it is
////     NOT parity with any upstream production tokenizer artifact. True
////     tokenizer parity against a pinned artifact remains an open gap.
////   - no learned model is involved anywhere in this module.

import cepaf_gleam/ai/local_first_cascade
import cepaf_gleam/ecology/core_bionic_token_twin.{
  type ContentFastpathClass, type FastpathProfile, type McipV1Envelope,
  classify_shannon_fastpath, encode_mcip_v1_envelope,
}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/json

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Minimum share of token positions on which the primary and shadow tokenizer
/// must agree, in basis points (9980 = 99.80%). Below this the payload is NOT
/// compressed: a tokenizer disagreement means the compaction accounting cannot
/// be trusted, so the tier fails closed rather than emitting a receipt that
/// misstates what it saved.
pub const tokenizer_parity_floor_bps = 9980

/// Hard cap on how many anchors a single payload may declare. Exceeding it is a
/// refusal, not a truncation: silently keeping 8 of 12 anchors while reporting
/// `critical_anchors_preserved = 8` would make the receipt lie about coverage.
pub const anchor_capacity = 8

/// Baseline of the token estimate: 4 bytes per token, matching
/// `local_first_cascade.estimate_tokens_from_bytes`.
pub const bytes_per_token = 4

/// Sanity ceiling for an entropy reading, in milli-bits per byte.
pub const max_plausible_h_milli = 8000

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A tokenizer identity, pinned by name + vocab code + version. Two specs with a
/// different `vocab_code` or `version` are DIFFERENT tokenizers even when they
/// share a name.
pub type TokenizerSpec {
  TokenizerSpec(name: String, vocab_code: String, version: String)
}

pub type CompressRequest {
  CompressRequest(
    request_id: String,
    logical_id: String,
    tenant: String,
    layer_code: String,
    content: String,
    tokenizer_primary: TokenizerSpec,
    tokenizer_shadow: TokenizerSpec,
    /// Budget in tokens. The compaction fails its purpose above this, which is
    /// reported as `within_budget: False` plus a confidence penalty rather than
    /// as a defect.
    max_compacted_tokens: Int,
  )
}

/// Byte-level measurements of the payload. All densities are basis points
/// (per 10,000) so nothing is lost to integer truncation.
pub type FastpathSample {
  FastpathSample(
    total_bytes: Int,
    total_lines: Int,
    total_newlines: Int,
    total_struct_chars: Int,
    total_hex_chars: Int,
    shannon_h_milli: Int,
  )
}

pub type CompressionResult {
  CompressionResult(
    request_id: String,
    logical_id: String,
    class_code: String,
    content_class: ContentFastpathClass,
    sample: FastpathSample,
    envelope: McipV1Envelope,
    anchors: List(String),
    elided_lines: Int,
    /// Achieved compression ratio x10 (raw/compacted), integer-scaled.
    ratio_x10: Int,
    /// The catalogue target for this class, x10.
    target_ratio_x10: Int,
    tokenizer_parity_bps: Int,
    estimated_compacted_tokens: Int,
    within_budget: Bool,
    confidence_milli: Int,
  )
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

fn count_h(haystack: String, needle: String) -> Int {
  haystack
  |> string.split(on: needle)
  |> list.length
  |> fn(n) { n - 1 }
}

fn is_struct_char(cp: String) -> Bool {
  case cp {
    "{" | "}" | "[" | "]" | ":" | "," | "(" | ")" -> True
    _ -> False
  }
}

fn is_hex_char(cp: String) -> Bool {
  case cp {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    "A" | "B" | "C" | "D" | "E" | "F" -> True
    _ -> False
  }
}

fn tally(values: List(Int)) -> dict.Dict(Int, Int) {
  list.fold(values, dict.new(), fn(acc, value) {
    dict.upsert(acc, value, fn(existing) {
      case existing {
        Some(n) -> n + 1
        None -> 1
      }
    })
  })
}

fn log2(p: Float) -> Float {
  case float.logarithm(p) {
    Ok(v) -> v /. 0.6931471805599453
    Error(_) -> 0.0
  }
}

/// Shannon entropy of the payload, expressed in MILLI-BITS PER BYTE.
///
/// Computed over codepoints, then rescaled by codepoints/bytes, so multi-byte
/// codepoints are charged their real byte cost instead of being counted as one
/// unit of information.
pub fn shannon_entropy_milli(content: String) -> Int {
  let cps =
    content
    |> string.to_utf_codepoints
    |> list.map(string.utf_codepoint_to_int)
  let byte_size = string.byte_size(content)
  case list.length(cps) {
    0 -> 0
    _ -> {
      let total = int.to_float(list.length(cps))
      let bits =
        cps
        |> tally
        |> dict.to_list
        |> list.fold(0.0, fn(acc, entry) {
          let p = int.to_float(entry.1) /. total
          acc -. p *. log2(p)
        })
      let per_byte = bits *. total /. int.to_float(byte_size)
      let scaled = per_byte *. 1000.0
      case scaled >. int.to_float(max_plausible_h_milli) {
        True -> max_plausible_h_milli
        False ->
          case float.round(scaled) {
            r if r < 0 -> 0
            r -> r
          }
      }
    }
  }
}

fn bps(count: Int, total: Int) -> Int {
  case total {
    0 -> 0
    _ -> count * 10_000 / total
  }
}

/// Measure the payload. Never inspects anything but the bytes passed in.
pub fn sample(content: String) -> FastpathSample {
  let cps = string.to_graphemes(content)
  let total_bytes = string.byte_size(content)
  let struct_chars = cps |> list.filter(is_struct_char) |> list.length
  let hex_chars = cps |> list.filter(is_hex_char) |> list.length
  let newlines = count_h(content, "\n")
  FastpathSample(
    total_bytes: total_bytes,
    total_lines: newlines + 1,
    total_newlines: newlines,
    total_struct_chars: struct_chars,
    total_hex_chars: hex_chars,
    shannon_h_milli: shannon_entropy_milli(content),
  )
}

/// Classify a payload through the Bionic Token Twin catalogue.
pub fn classify(s: FastpathSample) -> FastpathProfile {
  classify_shannon_fastpath(
    s.shannon_h_milli,
    bps(s.total_struct_chars, s.total_bytes),
    bps(s.total_hex_chars, s.total_bytes),
    bps(s.total_newlines, s.total_bytes),
  )
}

// ---------------------------------------------------------------------------
// Tokenizer parity
// ---------------------------------------------------------------------------

/// FNV-1a over the token text plus the pinned vocab code. 32-bit masked so the
/// projection stays identical on every BEAM build.
fn token_projection(token: String, spec: TokenizerSpec) -> Int {
  let material = token <> "\u{1}" <> spec.vocab_code <> "\u{1}" <> spec.version
  material
  |> string.to_graphemes
  |> list.fold(2_166_136_261, fn(acc, only) {
    {
      {
        let code = case only {
          "a" -> 97
          "b" -> 98
          "c" -> 99
          "d" -> 100
          "e" -> 101
          "f" -> 102
          "g" -> 103
          "h" -> 104
          "i" -> 105
          "j" -> 106
          "k" -> 107
          "l" -> 108
          "m" -> 109
          "n" -> 110
          "o" -> 111
          "p" -> 112
          "q" -> 113
          "r" -> 114
          "s" -> 115
          "t" -> 116
          "u" -> 117
          "v" -> 118
          "w" -> 119
          "x" -> 120
          "y" -> 121
          "z" -> 122
          "A" -> 65
          "B" -> 66
          "C" -> 67
          "D" -> 68
          "E" -> 69
          "F" -> 70
          "G" -> 71
          "H" -> 72
          "I" -> 73
          "J" -> 74
          "K" -> 75
          "L" -> 76
          "M" -> 77
          "N" -> 78
          "O" -> 79
          "P" -> 80
          "Q" -> 81
          "R" -> 82
          "S" -> 83
          "T" -> 84
          "U" -> 85
          "V" -> 86
          "W" -> 87
          "X" -> 88
          "Y" -> 89
          "Z" -> 90
          "0" -> 48
          "1" -> 49
          "2" -> 50
          "3" -> 51
          "4" -> 52
          "5" -> 53
          "6" -> 54
          "7" -> 55
          "8" -> 56
          "9" -> 57
          "_" -> 95
          "/" -> 47
          "-" -> 45
          "." -> 46
          ":" -> 58
          "'" -> 39
          "\"" -> 34
          "\\" -> 92
          "\n" -> 10
          "\t" -> 9
          " " -> 32
          "\u{1}" -> 1
          _ -> 35
        }
        let mixed = { acc * 16_777_619 } + code * 31
        mixed % 4_294_967_291
      }
    }
  })
}

fn tokens_of(content: String) -> List(String) {
  content
  |> string.lowercase
  |> string.split(on: " ")
  |> list.filter(fn(t) { string.length(t) > 0 })
}

/// Share of token positions on which the primary and shadow tokenizers agree,
/// in basis points. Two specs that differ in `vocab_code` or `version` will
/// disagree almost everywhere, which is exactly the condition that must fail
/// closed.
pub fn tokenizer_parity_bps(
  content: String,
  primary: TokenizerSpec,
  shadow: TokenizerSpec,
) -> Int {
  let tokens = tokens_of(content)
  case list.length(tokens) {
    0 -> 10_000
    n -> {
      let agreed =
        tokens
        |> list.filter(fn(t) {
          token_projection(t, primary) == token_projection(t, shadow)
        })
        |> list.length
      agreed * 10_000 / n
    }
  }
}

// ---------------------------------------------------------------------------
// Anchors and pruning
// ---------------------------------------------------------------------------

fn starts_with_any(line: String, prefixes: List(String)) -> Bool {
  list.any(prefixes, fn(p) { string.starts_with(line, p) })
}

fn contains_any(line: String, needles: List(String)) -> Bool {
  list.any(needles, fn(n) { string.contains(line, n) })
}

const anchor_prefixes = [
  "#", "pub fn ", "pub type ", "pub const ", "fn ", "type ", "const ", "import ",
  "use ", "def ", "class ", "```", "@",
]

const anchor_needles = [
  "TODO", "FIXME", "ERROR", "FAIL", "SECURITY", "HARD_DENIED", "ev_ceiling",
]

fn is_anchor_line(line: String) -> Bool {
  starts_with_any(line, anchor_prefixes) || contains_any(line, anchor_needles)
}

/// The anchors of a payload: deduplicated, order-preserving, and capped. The
/// caller must treat a list longer than `anchor_capacity` as a refusal, not as a
/// truncation.
pub fn select_anchors(content: String) -> List(String) {
  content
  |> string.split(on: "\n")
  |> list.filter(fn(l) { string.length(l) > 0 && is_anchor_line(l) })
  |> dedupe()
}

fn dedupe_frame(pair: #(List(String), List(String))) -> List(String) {
  let #(reversed, kept) = pair
  case reversed {
    [] -> list.reverse(kept)
    [line, ..rest] ->
      case list.contains(kept, line) {
        True -> dedupe_frame(#(rest, kept))
        False -> dedupe_frame(#(rest, [line, ..kept]))
      }
  }
}

/// Order-preserving dedupe of a list of lines.
pub fn dedupe(lines: List(String)) -> List(String) {
  dedupe_frame(#(list.reverse(lines), []))
}

fn keep_line(line: String, index: Int, total: Int, anchors: List(String)) -> Bool {
  case index {
    0 -> True
    _ ->
      case index == total - 1 {
        True -> True
        False ->
          case list.contains(anchors, line) {
            True -> True
            False -> string.length(line) > 0
          }
      }
  }
}

/// Prune the payload down to its anchors plus its non-blank lines, preserving
/// order. Elided blank runs are replaced by a single deterministic marker so the
/// reader can see that something was removed.
pub fn prune(content: String, anchors: List(String)) -> #(String, Int) {
  let lines = string.split(content, on: "\n")
  let total = list.length(lines)
  let kept =
    lines
    |> list.index_map(with: fn(line, i) { #(i, line) })
    |> list.filter(fn(entry) { keep_line(entry.1, entry.0, total, anchors) })
    |> list.map(fn(entry) { entry.1 })
  let elided = total - list.length(kept)
  let body = string.join(kept, "\n")
  case elided > 0 {
    True ->
      #(
        body
          <> "\n«elided "
          <> int.to_string(elided)
          <> "_lines»",
        elided,
      )
    False -> #(body, 0)
  }
}

fn dropped_anchors(compacted: String, anchors: List(String)) -> List(String) {
  anchors
  |> list.filter(fn(a) { !string.contains(compacted, a) })
}

// ---------------------------------------------------------------------------
// Compression
// ---------------------------------------------------------------------------

fn ratio_x10(raw: Int, compacted: Int) -> Int {
  case compacted {
    0 -> 1000
    _ -> raw * 10 / compacted
  }
}

pub fn estimate_tokens(byte_count: Int) -> Int {
  case byte_count <= 0 {
    True -> 0
    False -> byte_count / bytes_per_token
  }
}

/// Confidence is a compression-ratio score against the class target, scaled by
/// tokenizer agreement. Clamped to [0, 1000].
///
/// This is a claim about compaction, not about answer quality; see the module
/// docstring.
pub fn confidence_milli(
  achieved_ratio_x10: Int,
  target_ratio_x10: Int,
  parity_bps: Int,
) -> Int {
  let ratio_score = case target_ratio_x10 {
    0 -> 1000
    _ -> {
      case achieved_ratio_x10 * 1000 / target_ratio_x10 {
        s if s > 1000 -> 1000
        s if s < 0 -> 0
        s -> s
      }
    }
  }
  ratio_score * { parity_bps * 1000 / 10_000 } / 1000
}

/// Compress one payload, locally, with no network and no model.
///
/// `Error(reason)` means the tier REFUSED because compaction accounting could
/// not be trusted (empty payload, tokenizer disagreement, anchor overflow,
/// anchor loss, or an envelope that fails the router's own MCIP pin). A refusal
/// is a defect signal and must never be silently retried as a success.
pub fn compress(req: CompressRequest) -> Result(CompressionResult, String) {
  case string.byte_size(req.content) {
    0 -> Error("compressor_refused:empty_content")
    raw_bytes -> {
      let parity =
        tokenizer_parity_bps(
          req.content,
          req.tokenizer_primary,
          req.tokenizer_shadow,
        )
      case parity < tokenizer_parity_floor_bps {
        True ->
          Error(
            "compressor_refused:tokenizer_parity_below_floor:"
            <> int.to_string(parity)
            <> "<"
            <> int.to_string(tokenizer_parity_floor_bps)
            <> ":"
            <> req.tokenizer_primary.name
            <> "@"
            <> req.tokenizer_primary.version
            <> "!="
            <> req.tokenizer_shadow.name
            <> "@"
            <> req.tokenizer_shadow.version,
          )
        False -> {
          let s = sample(req.content)
          let profile = classify(s)
          let anchors = select_anchors(req.content)
          case list.length(anchors) > anchor_capacity {
            True ->
              Error(
                "compressor_refused:anchor_overflow:"
                <> int.to_string(list.length(anchors))
                <> ">"
                <> int.to_string(anchor_capacity),
              )
            False -> {
              let #(compacted, elided) = prune(req.content, anchors)
              let surviving = dropped_anchors(compacted, anchors)
              case surviving {
                [] -> {
                  let envelope =
                    encode_mcip_v1_envelope(
                      req.logical_id,
                      req.layer_code,
                      "O",
                      raw_bytes,
                      s.total_newlines,
                      s.total_struct_chars,
                      s.total_hex_chars,
                      anchors,
                    )
                  // Self-check against the router's pin: the compressor may not
                  // emit a receipt its own gate would refuse.
                  case local_first_cascade.validate_mcip_pin(envelope) {
                    Error(reason) ->
                      Error("compressor_refused:invalid_mcip:" <> reason)
                    Ok(_) -> {
                      let compacted_tokens =
                        estimate_tokens(envelope.compacted_bytes)
                      let achieved =
                        ratio_x10(s.total_bytes, envelope.compacted_bytes)
                      Ok(CompressionResult(
                        request_id: req.request_id,
                        logical_id: req.logical_id,
                        class_code: profile.class_code,
                        content_class: profile.content_class,
                        sample: s,
                        envelope: envelope,
                        anchors: anchors,
                        elided_lines: elided,
                        ratio_x10: achieved,
                        target_ratio_x10: profile.target_compression_ratio_x10,
                        tokenizer_parity_bps: parity,
                        estimated_compacted_tokens: compacted_tokens,
                        within_budget: compacted_tokens
                          <= req.max_compacted_tokens,
                        confidence_milli: confidence_milli(
                          achieved,
                          profile.target_compression_ratio_x10,
                          parity,
                        ),
                      ))
                    }
                  }
                }
                _ ->
                  Error(
                    "compressor_refused:anchor_dropped:"
                    <> string.join(surviving, " | "),
                  )
              }
            }
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Operator surface
// ---------------------------------------------------------------------------

pub fn result_to_json(r: CompressionResult) -> json.Json {
  json.object([
    #("request_id", json.string(r.request_id)),
    #("logical_id", json.string(r.logical_id)),
    #("class_code", json.string(r.class_code)),
    #("content_class", json.string(class_label(r.content_class))),
    #("raw_bytes", json.int(r.sample.total_bytes)),
    #("compacted_bytes", json.int(r.envelope.compacted_bytes)),
    #("ratio_x10", json.int(r.ratio_x10)),
    #("target_ratio_x10", json.int(r.target_ratio_x10)),
    #("anchors", json.int(list.length(r.anchors))),
    #("elided_lines", json.int(r.elided_lines)),
    #("tokenizer_parity_bps", json.int(r.tokenizer_parity_bps)),
    #("estimated_compacted_tokens", json.int(r.estimated_compacted_tokens)),
    #("within_budget", json.bool(r.within_budget)),
    #("confidence_milli", json.int(r.confidence_milli)),
    #("shannon_h_milli", json.int(r.sample.shannon_h_milli)),
    #("ev_ceiling", json.int(r.envelope.ev_ceiling)),
    #("wire_packet", json.string(r.envelope.wire_packet)),
  ])
}

pub fn class_label(class: ContentFastpathClass) -> String {
  case class {
    core_bionic_token_twin.CtJsonStruct -> "CT_JSON_STRUCT"
    core_bionic_token_twin.CtLogStream -> "CT_LOG_STREAM"
    core_bionic_token_twin.CtSourceAst -> "CT_SOURCE_AST"
    core_bionic_token_twin.CtUnifiedDiff -> "CT_UNIFIED_DIFF"
    core_bionic_token_twin.CtTabularCsv -> "CT_TABULAR_CSV"
    core_bionic_token_twin.CtHighEntropy -> "CT_HIGH_ENTROPY"
    core_bionic_token_twin.CtFormalSpec -> "CT_FORMAL_SPEC"
    core_bionic_token_twin.CtProseMd -> "CT_PROSE_MD"
  }
}

pub fn render_result(r: CompressionResult) -> String {
  "local_compressor{req="
  <> r.request_id
  <> " class="
  <> r.class_code
  <> " raw="
  <> int.to_string(r.sample.total_bytes)
  <> " compacted="
  <> int.to_string(r.envelope.compacted_bytes)
  <> " ratio_x10="
  <> int.to_string(r.ratio_x10)
  <> "/"
  <> int.to_string(r.target_ratio_x10)
  <> " anchors="
  <> int.to_string(list.length(r.anchors))
  <> " parity_bps="
  <> int.to_string(r.tokenizer_parity_bps)
  <> " tokens="
  <> int.to_string(r.estimated_compacted_tokens)
  <> " confidence_milli="
  <> int.to_string(r.confidence_milli)
  <> "}"
}

/// The probe outcome the cascade expects. Kept here so the router can be wired
/// to this tier without either side guessing at the other's vocabulary.
pub fn as_probe_outcome(
  result: Result(CompressionResult, String),
  latency_us: Int,
) -> local_first_cascade.ProbeOutcome {
  case result {
    Ok(r) ->
      case r.confidence_milli >= local_first_cascade.local_confidence_floor_milli {
        True -> local_first_cascade.ProbeOk(r.confidence_milli, latency_us)
        False ->
          local_first_cascade.ProbeLowConfidence(r.confidence_milli, latency_us)
      }
    Error(reason) -> local_first_cascade.ProbeContractViolation(reason)
  }
}

/// Report a refusal reason as an option so a caller can log it without matching
/// on Result twice.
pub fn refusal_reason(result: Result(CompressionResult, String)) -> Option(String) {
  case result {
    Ok(_) -> None
    Error(reason) -> Some(reason)
  }
}
