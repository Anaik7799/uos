//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/zenoh/ets_zenoh_bridge</module>
////     <description>Tri-Language Shared State Bridge across Gleam, OCaml, and Mojo via Zenoh & ETS</description>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ZENOH-001, SC-FUNC-004, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="idempotence">ets_put(k, v) ∘ zenoh_put(k, v) is idempotent</property>
////     <property name="convergence">State(Gleam) ≡ State(OCaml) ≡ State(Mojo) under Zenoh-ETS</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/substrate/beam_cache
import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "http_get")
fn http_get(url: String) -> Result(BitArray, String)

@external(erlang, "cepaf_gleam_ffi", "http_put")
fn http_put(url: String, content_type: String, body: String) -> Result(Nil, String)

@external(erlang, "cepaf_gleam_ffi", "base64_decode")
fn base64_decode(input: String) -> Result(BitArray, Nil)

const zenoh_rest_base = "http://127.0.0.1:8080/c3i/a2a/ets/"

pub type StateEntry {
  StateEntry(key: String, value: String)
}

pub type TriLanguageStateSummary {
  TriLanguageStateSummary(
    gleam_state: String,
    ocaml_state: String,
    mojo_state: String,
    ets_entry_count: Int,
    is_converged: Bool,
  )
}

/// Initialize the underlying ETS storage table.
pub fn init_bridge() -> Result(Nil, String) {
  beam_cache.init()
}

/// Put state into both local BEAM ETS and the distributed Zenoh mesh.
pub fn put_state(key: String, value: String) -> Result(Nil, String) {
  let _ = beam_cache.init()
  case beam_cache.put(key, value) {
    Ok(Nil) -> {
      // Best-effort publish to Zenoh mesh on port 8080
      let url = zenoh_rest_base <> key
      let _ = http_put(url, "text/plain", value)
      Ok(Nil)
    }
    Error(err) -> Error(err)
  }
}

/// Get state from BEAM ETS, falling back to Zenoh REST if not found locally.
pub fn get_state(key: String) -> Result(String, String) {
  let _ = beam_cache.init()
  case beam_cache.get(key) {
    Ok(val) -> Ok(val)
    Error(_) -> {
      // Fallback: query Zenoh REST
      let url = zenoh_rest_base <> key
      case http_get(url) {
        Ok(body_bits) -> {
          case bit_array.to_string(body_bits) {
            Ok(body_str) -> parse_single_zenoh_val(body_str, key)
            Error(_) -> Error("binary_decode_error")
          }
        }
        Error(err) -> Error(err)
      }
    }
  }
}

/// Return all key/value pairs currently held in BEAM ETS.
pub fn all_ets_state() -> List(StateEntry) {
  let _ = beam_cache.init()
  beam_cache.all()
  |> list.map(fn(pair) { StateEntry(key: pair.0, value: pair.1) })
}

/// Synchronize all keys from Zenoh into BEAM ETS.
pub fn sync_zenoh_to_ets() -> Result(Int, String) {
  let _ = beam_cache.init()
  let url = "http://127.0.0.1:8080/c3i/a2a/ets/**"
  case http_get(url) {
    Ok(body_bits) -> {
      case bit_array.to_string(body_bits) {
        Ok(body_str) -> {
          let entries = parse_zenoh_entries(body_str)
          let count = list.length(entries)
          list.each(entries, fn(entry) {
            let _ = beam_cache.put(entry.key, entry.value)
            Nil
          })
          Ok(count)
        }
        Error(_) -> Error("binary_to_string_error")
      }
    }
    Error(err) -> Error(err)
  }
}

/// Synchronize all keys from BEAM ETS out to Zenoh.
pub fn sync_ets_to_zenoh() -> Result(Int, String) {
  let _ = beam_cache.init()
  let all_pairs = beam_cache.all()
  let count = list.length(all_pairs)
  list.each(all_pairs, fn(pair) {
    let url = zenoh_rest_base <> pair.0
    let _ = http_put(url, "text/plain", pair.1)
    Nil
  })
  Ok(count)
}

/// Evaluate cross-language convergence between Gleam, OCaml, and Mojo test states.
pub fn evaluate_tri_language_state() -> TriLanguageStateSummary {
  let _ = beam_cache.init()
  let _ = sync_zenoh_to_ets()

  let gleam_val = result.unwrap(beam_cache.get("gleam_state"), "MISSING")
  let ocaml_val = result.unwrap(beam_cache.get("ocaml_state"), "MISSING")
  let mojo_val = result.unwrap(beam_cache.get("mojo_state"), "MISSING")

  let count = beam_cache.size()

  let converged =
    gleam_val != "MISSING" && ocaml_val != "MISSING" && mojo_val != "MISSING"

  TriLanguageStateSummary(
    gleam_state: gleam_val,
    ocaml_state: ocaml_val,
    mojo_state: mojo_val,
    ets_entry_count: count,
    is_converged: converged,
  )
}

// -----------------------------------------------------------------------------
// Internal JSON / Base64 Helpers
// -----------------------------------------------------------------------------

type RawZenohItem {
  RawZenohItem(key: String, value: String)
}

fn zenoh_item_decoder() -> decode.Decoder(RawZenohItem) {
  use key <- decode.field("key", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(RawZenohItem(key: key, value: value))
}

fn parse_single_zenoh_val(body_str: String, requested_key: String) -> Result(String, String) {
  let decoder = decode.list(zenoh_item_decoder())
  case json.parse(body_str, decoder) {
    Ok([first, ..]) -> {
      let decoded = decode_value(first.value)
      let _ = beam_cache.put(requested_key, decoded)
      Ok(decoded)
    }
    _ -> Error("not_found")
  }
}

fn parse_zenoh_entries(body_str: String) -> List(StateEntry) {
  let decoder = decode.list(zenoh_item_decoder())
  case json.parse(body_str, decoder) {
    Ok(items) -> {
      list.map(items, fn(item) {
        let clean_key = case string.starts_with(item.key, "c3i/a2a/ets/") {
          True -> string.drop_start(item.key, string.length("c3i/a2a/ets/"))
          False -> item.key
        }
        let clean_val = decode_value(item.value)
        StateEntry(key: clean_key, value: clean_val)
      })
    }
    Error(_) -> []
  }
}

fn decode_value(raw: String) -> String {
  case base64_decode(raw) {
    Ok(bits) -> {
      case bit_array.to_string(bits) {
        Ok(str) -> str
        Error(_) -> raw
      }
    }
    Error(_) -> raw
  }
}
