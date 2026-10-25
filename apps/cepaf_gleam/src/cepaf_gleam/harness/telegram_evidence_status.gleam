//// Candidate-bound Telegram evidence status validation for /checklist and /aspects.
//// This state NEVER asserts evidence bytes were checked; integration emits
//// evidence_bytes_verified=false,authority=observation_only,runtime_admission=NOT_GRANTED.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Record {
  Record(
    id: String,
    outcome: String,
    runtime_sha256: Option(String),
    formal_sha256: Option(String),
    reason: String,
  )
}

fn is_hex_char(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
    | "a" | "b" | "c" | "d" | "e" | "f" -> True
    _ -> False
  }
}

fn is_id_char(c: String) -> Bool {
  case c {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m"
    | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z"
    | "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M"
    | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z"
    | "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
    | "-" | "_" -> True
    _ -> False
  }
}

fn is_reason_char(c: String) -> Bool {
  is_id_char(c) || c == " " || c == "."
}

pub fn valid_hex(s: String, length: Int) -> Bool {
  length >= 0
  && string.byte_size(s) == length
  && list.all(string.to_graphemes(s), is_hex_char)
}

fn valid_id(id: String) -> Bool {
  let len = string.byte_size(id)
  len > 0 && len <= 32 && list.all(string.to_graphemes(id), is_id_char)
}

fn valid_reason(reason: String) -> Bool {
  let len = string.byte_size(reason)
  len > 0 && len <= 96 && string.trim(reason) == reason && list.all(string.to_graphemes(reason), is_reason_char)
}

fn valid_outcome_and_digests(
  outcome: String,
  runtime_sha256: Option(String),
  formal_sha256: Option(String),
) -> Bool {
  case outcome, runtime_sha256, formal_sha256 {
    "PASS", Some(r), Some(f) -> valid_hex(r, 64) && valid_hex(f, 64)
    "FAIL", Some(r), Some(f) -> valid_hex(r, 64) && valid_hex(f, 64)
    "FAIL", Some(r), None -> valid_hex(r, 64)
    "FAIL", None, Some(f) -> valid_hex(f, 64)
    "PARTIAL", Some(r), Some(f) -> valid_hex(r, 64) && valid_hex(f, 64)
    "PARTIAL", Some(r), None -> valid_hex(r, 64)
    "PARTIAL", None, Some(f) -> valid_hex(f, 64)
    "UNRUN", None, None -> True
    "UNKNOWN", None, None -> True
    "NOT_APPLICABLE", None, None -> True
    _, _, _ -> False
  }
}

pub fn valid_record(r: Record) -> Bool {
  valid_id(r.id)
  && valid_reason(r.reason)
  && valid_outcome_and_digests(r.outcome, r.runtime_sha256, r.formal_sha256)
}

pub fn state(r: Record, stale: Bool) -> String {
  case valid_record(r) {
    False -> "REJECTED"
    True ->
      case stale {
        True -> "STALE"
        False ->
          case r.outcome {
            "PASS" -> "RECORDED_PASS"
            "FAIL" -> "RECORDED_FAIL"
            "PARTIAL" -> "RECORDED_PARTIAL"
            "NOT_APPLICABLE" -> "RECORDED_NOT_APPLICABLE"
            other -> other
          }
      }
  }
}
