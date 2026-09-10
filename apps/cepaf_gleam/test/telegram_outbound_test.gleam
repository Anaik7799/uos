import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_outbound.{
  build_send_payload, chunk_text, find_cut_index, find_last_char_offset,
  get_default_chat_id, get_telegram_token, max_message_length,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn chunk_text_short_test() {
  let msg = "Short message under 4096 chars"
  let chunks = chunk_text(msg, max_message_length)
  chunks
  |> should.equal([msg])
}

pub fn chunk_text_exact_length_test() {
  let msg = string.repeat("a", 4096)
  let chunks = chunk_text(msg, 4096)
  list.length(chunks)
  |> should.equal(1)
  chunks
  |> should.equal([msg])
}

pub fn chunk_text_with_newline_boundary_test() {
  let prefix = string.repeat("a", 3800)
  let suffix = string.repeat("b", 1000)
  let full = prefix <> "\n" <> suffix
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      // First chunk should end with the newline
      string.ends_with(first, "\n")
      |> should.be_true
      string.length(first)
      |> should.equal(3801)
      first
      |> should.equal(prefix <> "\n")
      second
      |> should.equal(suffix)
    }
    _ -> should.fail()
  }
}

pub fn chunk_text_with_space_boundary_test() {
  let prefix = string.repeat("x", 3900)
  let suffix = string.repeat("y", 500)
  let full = prefix <> " " <> suffix
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      string.ends_with(first, " ")
      |> should.be_true
      string.length(first)
      |> should.equal(3901)
      first
      |> should.equal(prefix <> " ")
      second
      |> should.equal(suffix)
    }
    _ -> should.fail()
  }
}

pub fn chunk_text_hard_cut_no_delimiter_test() {
  let full = string.repeat("z", 5000)
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      string.length(first)
      |> should.equal(4096)
      string.length(second)
      |> should.equal(904)
    }
    _ -> should.fail()
  }
}

pub fn find_last_char_offset_test() {
  let str = "alpha\nbeta\ngamma"
  find_last_char_offset(str, "\n")
  |> should.equal(Some(10))

  let str_space = "one two three"
  find_last_char_offset(str_space, " ")
  |> should.equal(Some(7))

  let str_none = "singleword"
  find_last_char_offset(str_none, "\n")
  |> should.equal(option.None)
}

pub fn find_cut_index_newline_test() {
  let str = string.repeat("a", 3800) <> "\n" <> string.repeat("b", 1000)
  let idx = find_cut_index(str, 4096)
  idx
  |> should.equal(3801)
}

pub fn token_resolution_test() {
  case get_telegram_token() {
    Ok(token) -> {
      string.starts_with(token, "8660817750:")
      |> should.be_true
    }
    Error(err) -> {
      // In isolated CI environment without db, verify error is cleanly typed
      string.is_empty(err)
      |> should.be_false
    }
  }
}

pub fn chat_id_resolution_test() {
  case get_default_chat_id() {
    Ok(cid) -> {
      cid
      |> should.equal("6249174059")
    }
    Error(err) -> {
      string.is_empty(err)
      |> should.be_false
    }
  }
}

// --- egress: what may not leave for api.telegram.org ------------------------
//
// The falsifier for each law below is the guard removed from
// build_send_payload. Before it was wired, all three failed.

/// The measured defect: a message body carrying the denied host OS NVMe serial
/// reached the transport with the serial intact.
pub fn outbound_payload_never_carries_the_denied_serial_test() {
  let payload =
    build_send_payload(
      "6249174059",
      "OSD candidate report: bay 0 serial 25503L801736 skipped",
      Some("Markdown"),
    )
  payload
  |> string.contains(egress_redactor.denied_os_nvme_serial)
  |> should.be_false

  // Redacted, not dropped: the operator still sees that a serial was there.
  payload
  |> string.contains(egress_redactor.redacted_serial_placeholder)
  |> should.be_true
}

/// The plaintext fallback path builds its body from the same `text`, so a
/// guard that covered only the Markdown send would leak on every retry.
pub fn plaintext_fallback_payload_is_guarded_too_test() {
  build_send_payload("6249174059", "serial 25503L801736", None)
  |> string.contains(egress_redactor.denied_os_nvme_serial)
  |> should.be_false
}

/// A check that mangles healthy traffic is an outage, not a check.
pub fn ordinary_message_passes_through_unchanged_test() {
  let msg = "Ceph OSD rebalance complete: 3 up, 0 down"
  build_send_payload("6249174059", msg, None)
  |> string.contains(msg)
  |> should.be_true
}
