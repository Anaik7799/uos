//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/eventsource/chain</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ULTRA-001, SC-HASH-001, SC-SAFETY-003</stamp-controls></compliance>
//// </c3i-module>
////
//// Cryptographically verifiable event sourcing log with SHA-256 hash chain.

import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/string

/// A single event in the hash chain
pub type EventEntry {
  EventEntry(
    sequence: Int,
    timestamp: Int,
    event_type: String,
    payload: String,
    prev_hash: String,
    hash: String,
    node_id: String,
  )
}

/// The event log — append-only chain with head hash
pub type EventLog {
  EventLog(entries: List(EventEntry), head_hash: String, chain_length: Int)
}

/// Create empty event log
pub fn new_log() -> EventLog {
  EventLog(entries: [], head_hash: "genesis", chain_length: 0)
}

/// Append an event — computes hash from payload + timestamp + prev_hash
pub fn append(
  log: EventLog,
  event_type: String,
  payload: String,
  node_id: String,
  timestamp: Int,
) -> EventLog {
  let prev = log.head_hash
  let seq = log.chain_length + 1
  let hash_input = payload <> "|" <> int.to_string(timestamp) <> "|" <> prev
  let hash = compute_sha256(hash_input)

  let entry =
    EventEntry(
      sequence: seq,
      timestamp: timestamp,
      event_type: event_type,
      payload: payload,
      prev_hash: prev,
      hash: hash,
      node_id: node_id,
    )

  EventLog(entries: [entry, ..log.entries], head_hash: hash, chain_length: seq)
}

/// Verify the entire chain — returns True if all hashes are valid
pub fn verify(log: EventLog) -> Bool {
  let reversed = list.reverse(log.entries)
  verify_chain(reversed, "genesis")
}

fn verify_chain(entries: List(EventEntry), expected_prev: String) -> Bool {
  case entries {
    [] -> True
    [entry, ..rest] -> {
      let hash_input =
        entry.payload
        <> "|"
        <> int.to_string(entry.timestamp)
        <> "|"
        <> expected_prev
      let computed = compute_sha256(hash_input)
      case computed == entry.hash && entry.prev_hash == expected_prev {
        True -> verify_chain(rest, entry.hash)
        False -> False
      }
    }
  }
}

/// Detect tampering — returns list of tampered sequence numbers
pub fn detect_tampering(log: EventLog) -> List(Int) {
  let reversed = list.reverse(log.entries)
  find_tampered(reversed, "genesis", [])
}

fn find_tampered(
  entries: List(EventEntry),
  expected_prev: String,
  tampered: List(Int),
) -> List(Int) {
  case entries {
    [] -> list.reverse(tampered)
    [entry, ..rest] -> {
      let hash_input =
        entry.payload
        <> "|"
        <> int.to_string(entry.timestamp)
        <> "|"
        <> expected_prev
      let computed = compute_sha256(hash_input)
      case computed == entry.hash {
        True -> find_tampered(rest, entry.hash, tampered)
        False -> find_tampered(rest, entry.hash, [entry.sequence, ..tampered])
      }
    }
  }
}

/// Get last N events
pub fn recent(log: EventLog, n: Int) -> List(EventEntry) {
  list.take(log.entries, n)
}

/// SHA-256 hash computation
fn compute_sha256(input: String) -> String {
  let bytes = bit_array.from_string(input)
  let hash = crypto.hash(crypto.Sha256, bytes)
  bit_array_to_hex(hash)
}

fn bit_array_to_hex(bits: BitArray) -> String {
  bit_array.base16_encode(bits)
  |> string.lowercase
}
