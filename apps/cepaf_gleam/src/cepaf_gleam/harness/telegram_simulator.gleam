//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_simulator</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-HARNESS-SIM-001, SC-AUDIO-001, SC-DRIVE-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Pure Gleam/OTP 29 Multimodal Telegram Simulator.
//// Simulates inbound messages, voice memos, rack photos, whiteboard photos,
//// ambient telemetry, and runs comprehensive sweep across all 48 directives.

import cepaf_gleam/harness/telegram.{type InboundMessage, type OutboundResponse, InboundMessage}
import gleam/bit_array
import gleam/list
import gleam/string

pub const hard_denied_system_os_serial: String = "25503L801736"

pub type SimulationReport {
  SimulationReport(
    total_simulated: Int,
    passed_simulated: Int,
    failed_simulated: Int,
    domain_a_count: Int,
    domain_b_count: Int,
    domain_c_count: Int,
    domain_d_count: Int,
    multimodal_count: Int,
    hardware_lock_verified: Bool,
  )
}

pub type AcousticSpectrum {
  AcousticSpectrum(
    fundamental_hz: Int,
    flutter_hz: Int,
    snr_db: Float,
    anomaly_detected: Bool,
  )
}

pub type VisionInspection {
  VisionInspection(
    bay_number: Int,
    amber_led: Bool,
    serial_number: String,
    safe_to_pull: Bool,
  )
}

/// Construct simulated text directive message.
pub fn simulate_text_directive(update_id: Int, cmd: String) -> InboundMessage {
  InboundMessage(
    update_id: update_id,
    message_id: 1000 + update_id,
    chat_id: "chat-sim-01",
    from_user: "operator_sim",
    text: cmd,
    timestamp_ms: 1_700_000_000 + update_id,
  )
}

/// Construct simulated voice memo message with Whisper transcription.
pub fn simulate_voice_memo(
  update_id: Int,
  speaker: String,
  _duration_s: Float,
  speech_text: String,
) -> InboundMessage {
  InboundMessage(
    update_id: update_id,
    message_id: 2000 + update_id,
    chat_id: "voice-room-sim",
    from_user: speaker,
    text: speech_text,
    timestamp_ms: 1_700_000_000 + update_id,
  )
}

/// Construct simulated photo upload message with caption.
pub fn simulate_photo_upload(
  update_id: Int,
  caption: String,
  _file_id: String,
) -> InboundMessage {
  InboundMessage(
    update_id: update_id,
    message_id: 3000 + update_id,
    chat_id: "field-ops-sim",
    from_user: "field_technician",
    text: caption,
    timestamp_ms: 1_700_000_000 + update_id,
  )
}

/// Simulate acoustic 1024-point Fourier FFT analysis on audio stream.
pub fn simulate_acoustic_fft(sample_bytes: BitArray) -> AcousticSpectrum {
  let size = bit_array.byte_size(sample_bytes)
  case size > 0 {
    True ->
      AcousticSpectrum(
        fundamental_hz: 1240,
        flutter_hz: 14,
        snr_db: 42.5,
        anomaly_detected: True,
      )
    False ->
      AcousticSpectrum(
        fundamental_hz: 0,
        flutter_hz: 0,
        snr_db: 0.0,
        anomaly_detected: False,
      )
  }
}

/// Simulate computer vision chassis inspection on rack image.
pub fn simulate_vision_inspection(
  image_bytes: BitArray,
  target_bay: Int,
) -> VisionInspection {
  let _ = bit_array.byte_size(image_bytes)
  case target_bay {
    0 ->
      VisionInspection(
        bay_number: 0,
        amber_led: False,
        serial_number: hard_denied_system_os_serial,
        safe_to_pull: False,
      )
    3 ->
      VisionInspection(
        bay_number: 3,
        amber_led: True,
        serial_number: "S439NX0M819234",
        safe_to_pull: True,
      )
    b ->
      VisionInspection(
        bay_number: b,
        amber_led: False,
        serial_number: "GENERIC-NVME-000",
        safe_to_pull: False,
      )
  }
}

/// Run full simulation sweep across all 48 directives across all 4 domains.
pub fn run_full_simulation_sweep() -> SimulationReport {
  let domain_a_cmds = [
    "/start", "/help", "/status", "/storage", "/dark", "/andon",
    "/zigvm version", "/plan", "/sutra", "/zk", "/checklist", "/cockpit",
    "/approval uos/plan-1 task-101 Verify-Rollout",
  ]

  let domain_b_cmds = [
    "/resuscitate vm-1", "/chaos inject zenoh-peer", "/repro trace-1234",
    "/merge feat/prajna-window", "/bisect comprehensive_ui_regression_test",
    "/escalate cluster-admin", "/rotate-keys all", "/mesh reconcile",
    "/migrate auth-service", "/adr draft Emergency Storage Quorum",
    "/blast-radius apps/cepaf_gleam/src/cepaf_gleam/harness/telegram.gleam",
  ]

  let domain_c_cmds = [
    "/pacing nap", "/whatif drain nas-1 worker pool", "/rack-cv chassis-01",
    "/acoustic fan-bearing-02", "/rewind 15m", "/postmortem inc-5501",
    "/finops", "/eco-schedule run", "/radar", "/canvas", "/lockbox engage",
    "/export-audit SOC2-TypeII",
  ]

  let domain_d_cmds = [
    "/sidecar listen", "/voice-roll-call verify prop-drain",
    "/babel start ja en", "/whiteboard session-fsm",
    "/socratic packet drop root cause", "/handover generate",
    "/pair-voice start", "/exec-brief inc-active",
    "/commitments list", "/acoustic-hud engage",
    "/retro export retro-incident-99", "/gameday start partition-nas1",
  ]

  let multimodal_cmds = [
    simulate_voice_memo(801, "an", 4.5, "/voice-roll-call verify prop-drain"),
    simulate_photo_upload(802, "/rack-cv bay-3", "file-chassis-bay3"),
    simulate_photo_upload(803, "/whiteboard state-machine", "file-wb-fsm"),
    simulate_voice_memo(804, "operator_jp", 12.0, "/socratic memory pressure"),
  ]

  let evaluate_cmd = fn(cmd: String, idx: Int) -> Bool {
    let msg = simulate_text_directive(idx, cmd)
    let resp = telegram.handle_message(msg)
    validate_response(resp, msg)
  }

  let count_passed = fn(cmds: List(String), start_idx: Int) -> #(Int, Int) {
    list.index_fold(cmds, #(0, 0), fn(acc, cmd, i) {
      let #(passed, failed) = acc
      case evaluate_cmd(cmd, start_idx + i) {
        True -> #(passed + 1, failed)
        False -> #(passed, failed + 1)
      }
    })
  }

  let #(passed_a, failed_a) = count_passed(domain_a_cmds, 100)
  let #(passed_b, failed_b) = count_passed(domain_b_cmds, 200)
  let #(passed_c, failed_c) = count_passed(domain_c_cmds, 300)
  let #(passed_d, failed_d) = count_passed(domain_d_cmds, 400)

  let #(passed_multi, failed_multi) =
    list.fold(multimodal_cmds, #(0, 0), fn(acc, msg) {
      let #(passed, failed) = acc
      let resp = telegram.handle_message(msg)
      case validate_response(resp, msg) {
        True -> #(passed + 1, failed)
        False -> #(passed, failed + 1)
      }
    })

  let total_passed =
    passed_a + passed_b + passed_c + passed_d + passed_multi
  let total_failed =
    failed_a + failed_b + failed_c + failed_d + failed_multi
  let total_sim = total_passed + total_failed

  // Hardware lock validation
  let storage_msg = simulate_text_directive(999, "/storage")
  let storage_resp = telegram.handle_message(storage_msg)
  let lock_ok =
    {
      string.contains(storage_resp.text, "[REDACTED_SYSTEM_OS_SERIAL]")
      || string.contains(storage_resp.text, hard_denied_system_os_serial)
    }
    && {
      string.contains(storage_resp.text, "HARD-DENIED")
      || string.contains(storage_resp.text, "ENFORCED")
      || string.contains(storage_resp.text, "LOCKED")
      || string.contains(storage_resp.text, "Locked")
    }

  SimulationReport(
    total_simulated: total_sim,
    passed_simulated: total_passed,
    failed_simulated: total_failed,
    domain_a_count: list.length(domain_a_cmds),
    domain_b_count: list.length(domain_b_cmds),
    domain_c_count: list.length(domain_c_cmds),
    domain_d_count: list.length(domain_d_cmds),
    multimodal_count: list.length(multimodal_cmds),
    hardware_lock_verified: lock_ok,
  )
}

fn validate_response(resp: OutboundResponse, msg: InboundMessage) -> Bool {
  let has_chat_id = resp.chat_id == msg.chat_id
  let has_text = string.length(resp.text) > 20
  let is_markdown = resp.parse_mode == "Markdown"
  let has_intent = string.starts_with(resp.intent_id, "tg-")

  has_chat_id && has_text && is_markdown && has_intent
}
