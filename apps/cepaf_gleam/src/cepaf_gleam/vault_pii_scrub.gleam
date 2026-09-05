//// Vault PII scrubber — defense-in-depth against accidental plaintext-key
//// leakage into audit log envelopes, OTel spans, and Wisp REST responses.
////
//// Slice F partial (Pass-29): pure-function scrubber that detects + redacts
//// 7 canonical API-key shapes used by the C3I mesh, before any string
//// reaches `audit_log.rs` immutable register or Zenoh telemetry.
////
//// Per .claude/rules/secrets-vault.md:
////   SC-VAULT-002: KEK MUST never appear in plaintext anywhere on disk
////   SC-VAULT-004: plaintext API-key shapes MUST NOT appear in any committed
////                file or audit log
////   SC-SEC-003: PII scrubbing for all log paths
////
//// This is the same regex set used by:
////   - `.git/hooks/pre-commit` vault secret-scan
////   - `sub-projects/c3i/native/planning_daemon/src/pii.rs` (Rust cortex)
////
//// Pure functions — exhaustively unit-testable.

import gleam/string

// =====================================================================
// Detected shapes
// =====================================================================

pub type KeyShape {
  /// `sk-ant-api03-…` — Anthropic API key
  AnthropicKey
  /// `sk-or-v1-…` — OpenRouter API key
  OpenRouterKey
  /// `sk-proj-…` — OpenAI project key
  OpenAiProjectKey
  /// `AIza…` (≥36 chars) — Google API key
  GoogleApiKey
  /// `ghp_…` — GitHub personal access token
  GithubPat
  /// `gho_…` — GitHub OAuth token
  GithubOauth
  /// `xoxb-…` — Slack bot token
  SlackBotToken
}

/// Result of a scrub pass.
pub type ScrubResult {
  ScrubResult(cleaned: String, shapes_found: List(KeyShape), redactions: Int)
}

// =====================================================================
// Public API
// =====================================================================

/// Scrub a string by replacing detected key shapes with `[REDACTED:<shape>]`.
/// Returns the cleaned string + audit info for telemetry.
pub fn scrub(input: String) -> ScrubResult {
  let r0 = ScrubResult(cleaned: input, shapes_found: [], redactions: 0)
  r0
  |> apply_shape("sk-ant-api03-", AnthropicKey)
  |> apply_shape("sk-or-v1-", OpenRouterKey)
  |> apply_shape("sk-proj-", OpenAiProjectKey)
  |> apply_aiza_shape()
  |> apply_shape("ghp_", GithubPat)
  |> apply_shape("gho_", GithubOauth)
  |> apply_shape("xoxb-", SlackBotToken)
}

/// Convenience: returns True iff the input contains ANY known shape.
pub fn contains_secret_shape(input: String) -> Bool {
  let r = scrub(input)
  r.redactions > 0
}

/// Convert a KeyShape variant to its stable token name for logging.
pub fn shape_token(shape: KeyShape) -> String {
  case shape {
    AnthropicKey -> "anthropic"
    OpenRouterKey -> "openrouter"
    OpenAiProjectKey -> "openai_project"
    GoogleApiKey -> "google_api"
    GithubPat -> "github_pat"
    GithubOauth -> "github_oauth"
    SlackBotToken -> "slack_bot"
  }
}

// =====================================================================
// Internal: shape-by-shape rewriter
// =====================================================================

fn apply_shape(
  result: ScrubResult,
  prefix: String,
  shape: KeyShape,
) -> ScrubResult {
  case string.contains(result.cleaned, prefix) {
    False -> result
    True -> {
      let cleaned =
        redact_after_prefix(result.cleaned, prefix, shape_token(shape))
      let count = count_occurrences(result.cleaned, prefix)
      ScrubResult(
        cleaned: cleaned,
        shapes_found: prepend_unique(result.shapes_found, shape),
        redactions: result.redactions + count,
      )
    }
  }
}

/// Special handler for `AIza…` Google API keys (no fixed-length prefix; the
/// pattern is `AIza` followed by ≥35 base64-ish chars).
fn apply_aiza_shape(result: ScrubResult) -> ScrubResult {
  case string.contains(result.cleaned, "AIza") {
    False -> result
    True -> {
      let cleaned =
        redact_after_prefix(result.cleaned, "AIza", shape_token(GoogleApiKey))
      let count = count_occurrences(result.cleaned, "AIza")
      ScrubResult(
        cleaned: cleaned,
        shapes_found: prepend_unique(result.shapes_found, GoogleApiKey),
        redactions: result.redactions + count,
      )
    }
  }
}

/// Replace every `<prefix><tail>` with `[REDACTED:<token>]`. Tail is
/// considered to end at whitespace, comma, quote, semicolon, or end-of-string.
fn redact_after_prefix(input: String, prefix: String, token: String) -> String {
  let parts = string.split(input, prefix)
  case parts {
    [head] -> head
    [head, ..rest_parts] -> {
      let redacted_parts =
        list_map(rest_parts, fn(part) {
          let #(_consumed, remainder) = consume_token_chars(part)
          "[REDACTED:" <> token <> "]" <> remainder
        })
      string_join_inplace(head, redacted_parts)
    }
    [] -> input
  }
}

/// Walk through `s` consuming token-character bytes (alphanum + `-` + `_`)
/// until first non-token char or end. Returns `(consumed, remainder)`.
fn consume_token_chars(s: String) -> #(String, String) {
  do_consume(string.to_graphemes(s), [], "")
}

fn do_consume(
  chars: List(String),
  consumed: List(String),
  _ignored: String,
) -> #(String, String) {
  case chars {
    [] -> #(string_concat_reverse(consumed), "")
    [c, ..rest] -> {
      case is_token_char(c) {
        True -> do_consume(rest, [c, ..consumed], "")
        False -> #(string_concat_reverse(consumed), c <> string_concat(rest))
      }
    }
  }
}

fn is_token_char(c: String) -> Bool {
  case c {
    "-" | "_" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" -> True
    "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" -> True
    "u" | "v" | "w" | "x" | "y" | "z" -> True
    "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" -> True
    "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" -> True
    "U" | "V" | "W" | "X" | "Y" | "Z" -> True
    _ -> False
  }
}

// =====================================================================
// Helpers
// =====================================================================

fn count_occurrences(haystack: String, needle: String) -> Int {
  let parts = string.split(haystack, needle)
  case parts {
    [] -> 0
    _ -> {
      let n = list_length(parts)
      case n {
        0 -> 0
        _ -> n - 1
      }
    }
  }
}

fn prepend_unique(xs: List(KeyShape), x: KeyShape) -> List(KeyShape) {
  case list_contains(xs, x) {
    True -> xs
    False -> [x, ..xs]
  }
}

fn list_contains(xs: List(KeyShape), x: KeyShape) -> Bool {
  case xs {
    [] -> False
    [head, ..rest] ->
      case head == x {
        True -> True
        False -> list_contains(rest, x)
      }
  }
}

fn list_map(xs: List(a), f: fn(a) -> b) -> List(b) {
  do_map(xs, f, [])
}

fn do_map(xs: List(a), f: fn(a) -> b, acc: List(b)) -> List(b) {
  case xs {
    [] -> reverse(acc)
    [head, ..rest] -> do_map(rest, f, [f(head), ..acc])
  }
}

fn list_length(xs: List(a)) -> Int {
  do_length(xs, 0)
}

fn do_length(xs: List(a), acc: Int) -> Int {
  case xs {
    [] -> acc
    [_, ..rest] -> do_length(rest, acc + 1)
  }
}

fn reverse(xs: List(a)) -> List(a) {
  do_reverse(xs, [])
}

fn do_reverse(xs: List(a), acc: List(a)) -> List(a) {
  case xs {
    [] -> acc
    [head, ..rest] -> do_reverse(rest, [head, ..acc])
  }
}

fn string_concat(parts: List(String)) -> String {
  string.concat(parts)
}

fn string_concat_reverse(parts: List(String)) -> String {
  string.concat(reverse(parts))
}

fn string_join_inplace(head: String, parts: List(String)) -> String {
  case parts {
    [] -> head
    [p, ..rest] -> string_join_inplace(head <> p, rest)
  }
}
