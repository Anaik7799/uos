//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Conversation Memory Unit Tests (SC-COG-001, SC-STATE-001)
//// =============================================================================

import cepaf_gleam/harness/conversation_memory.{
  clear_history, count_turns, default_db_path, get_recent_history, init_schema,
  record_turn,
}
import cepaf_gleam/harness/egress_redactor
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn conversation_memory_lifecycle_test() {
  let chat_id = "test_chat_unit_42"

  // 1. Initialize schema
  let init_res = init_schema(default_db_path)
  should.be_ok(init_res)

  // Clear any existing state for test chat
  let _ = clear_history(default_db_path, chat_id)
  should.equal(0, count_turns(default_db_path, chat_id))

  // 2. Record Turn 1 (User asks generic query)
  let r1 =
    record_turn(
      default_db_path,
      chat_id,
      "user",
      "show me what is happening in the uos system",
      None,
      1_700_000_001_000,
    )
  should.be_ok(r1)

  // 3. Record Turn 2 (Assistant responds)
  let r2 =
    record_turn(
      default_db_path,
      chat_id,
      "assistant",
      "All 16 Podman containers nominal. Zero-Muda verified.",
      None,
      1_700_000_002_000,
    )
  should.be_ok(r2)

  // 4. Record Turn 3 with raw NVMe serial (must be redacted upon persistence)
  let r3 =
    record_turn(
      default_db_path,
      chat_id,
      "assistant",
      "Root drive serial is " <> egress_redactor.denied_os_nvme_serial <> " and is locked.",
      Some("tool_storage_inspect"),
      1_700_000_003_000,
    )
  should.be_ok(r3)

  should.equal(3, count_turns(default_db_path, chat_id))

  // 5. Fetch recent history
  let history = get_recent_history(default_db_path, chat_id, 10)
  should.equal(3, list.length(history))

  // Verify chronological ordering
  case history {
    [m1, m2, m3] -> {
      should.equal("user", m1.role)
      should.equal("show me what is happening in the uos system", m1.content)

      should.equal("assistant", m2.role)

      should.equal("assistant", m3.role)
      // Verify redaction took effect!
      should.be_false(string.contains(m3.content, egress_redactor.denied_os_nvme_serial))
      should.be_true(string.contains(m3.content, egress_redactor.redacted_serial_placeholder))
    }
    _ -> should.fail()
  }

  // 6. Clear history
  let clear_res = clear_history(default_db_path, chat_id)
  should.be_ok(clear_res)
  should.equal(0, count_turns(default_db_path, chat_id))
}
