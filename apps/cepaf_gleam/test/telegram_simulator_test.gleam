import cepaf_gleam/harness/telegram
import cepaf_gleam/harness/telegram_simulator
import gleam/bit_array
import gleam/string
import gleeunit/should

pub fn telegram_domain_a_simulation_test() {
  let msg = telegram_simulator.simulate_text_directive(1, "/status")
  let resp = telegram.handle_message(msg)
  resp.chat_id |> should.equal(msg.chat_id)
  resp.intent_id |> should.equal("tg-1")
  resp.parse_mode |> should.equal("Markdown")
  string.contains(resp.text, "Cluster Telemetry") |> should.equal(True)

  let storage_msg = telegram_simulator.simulate_text_directive(2, "/storage")
  let storage_resp = telegram.handle_message(storage_msg)
  string.contains(storage_resp.text, "[REDACTED_SYSTEM_OS_SERIAL]")
  |> should.equal(True)
  string.contains(storage_resp.text, "HARD-DENIED") |> should.equal(True)

  let help_msg = telegram_simulator.simulate_text_directive(3, "/help")
  let help_resp = telegram.handle_message(help_msg)
  string.contains(help_resp.text, "Domain A: Foundational SRE") |> should.equal(True)
  string.contains(help_resp.text, "Domain B: Advanced SRE") |> should.equal(True)
  string.contains(help_resp.text, "Domain C: Creative Cybernetics") |> should.equal(True)
  string.contains(help_resp.text, "Domain D: Team Collaboration") |> should.equal(True)
}

pub fn telegram_domain_b_simulation_test() {
  let resuscitate_msg =
    telegram_simulator.simulate_text_directive(11, "/resuscitate vm-1")
  let resp = telegram.handle_message(resuscitate_msg)
  string.contains(resp.text, "Disaster Recovery Resuscitation")
  |> should.equal(True)
  string.contains(resp.text, "[REDACTED_SYSTEM_OS_SERIAL]") |> should.equal(True)

  let chaos_msg =
    telegram_simulator.simulate_text_directive(12, "/chaos inject zenoh-peer")
  let resp2 = telegram.handle_message(chaos_msg)
  string.contains(resp2.text, "Controlled Chaos Injection")
  |> should.equal(True)

  let repro_msg =
    telegram_simulator.simulate_text_directive(13, "/repro trace-9901")
  let resp3 = telegram.handle_message(repro_msg)
  string.contains(resp3.text, "Sandbox Bug Reproduction Engine")
  |> should.equal(True)

  let merge_msg =
    telegram_simulator.simulate_text_directive(14, "/merge feat/prajna-window")
  let resp4 = telegram.handle_message(merge_msg)
  string.contains(resp4.text, "Mobile Jujutsu PR Merge")
  |> should.equal(True)

  let bisect_msg =
    telegram_simulator.simulate_text_directive(15, "/bisect test_flaky_timeout")
  let resp5 = telegram.handle_message(bisect_msg)
  string.contains(resp5.text, "Autonomous Flaky Test Bisection")
  |> should.equal(True)

  let mesh_msg =
    telegram_simulator.simulate_text_directive(16, "/mesh reconcile")
  let resp6 = telegram.handle_message(mesh_msg)
  string.contains(resp6.text, "Tailscale Mesh CRDT Reconciliation")
  |> should.equal(True)
}

pub fn telegram_domain_c_simulation_test() {
  let pacing_msg =
    telegram_simulator.simulate_text_directive(21, "/pacing nap")
  let resp1 = telegram.handle_message(pacing_msg)
  string.contains(resp1.text, "Autonomous Operator Guard Engaged")
  |> should.equal(True)

  let whatif_msg =
    telegram_simulator.simulate_text_directive(22, "/whatif drain nas-1")
  let resp2 = telegram.handle_message(whatif_msg)
  string.contains(resp2.text, "Digital-Twin Shadow Simulation")
  |> should.equal(True)

  let rack_msg =
    telegram_simulator.simulate_text_directive(23, "/rack-cv chassis-01")
  let resp3 = telegram.handle_message(rack_msg)
  string.contains(resp3.text, "Computer Vision Server Rack Diagnostic")
  |> should.equal(True)
  string.contains(resp3.text, "[REDACTED_SYSTEM_OS_SERIAL]") |> should.equal(True)

  let acoustic_msg =
    telegram_simulator.simulate_text_directive(24, "/acoustic fan-02")
  let resp4 = telegram.handle_message(acoustic_msg)
  string.contains(resp4.text, "Acoustic Bearing Degradation Diagnostic")
  |> should.equal(True)

  let rewind_msg =
    telegram_simulator.simulate_text_directive(25, "/rewind 10m")
  let resp5 = telegram.handle_message(rewind_msg)
  string.contains(resp5.text, "Time-Machine Historical State Scrubbing")
  |> should.equal(True)

  let radar_msg =
    telegram_simulator.simulate_text_directive(26, "/radar")
  let resp6 = telegram.handle_message(radar_msg)
  string.contains(resp6.text, "ASCII Heatmap Radar")
  |> should.equal(True)

  let eco_msg =
    telegram_simulator.simulate_text_directive(27, "/eco-schedule run")
  let resp7 = telegram.handle_message(eco_msg)
  string.contains(resp7.text, "Green Energy Batch Execution Launched")
  |> should.equal(True)
}

pub fn telegram_domain_d_simulation_test() {
  let sidecar_msg =
    telegram_simulator.simulate_text_directive(31, "/sidecar listen")
  let resp1 = telegram.handle_message(sidecar_msg)
  string.contains(resp1.text, "Whisper-to-Ear Private Telemetry Sidecar")
  |> should.equal(True)

  let voice_msg =
    telegram_simulator.simulate_text_directive(32, "/voice-roll-call verify prop-drain")
  let resp2 = telegram.handle_message(voice_msg)
  string.contains(resp2.text, "Multi-Party Voice Biometric Quorum Roll Call")
  |> should.equal(True)
  string.contains(resp2.text, "25503L801736") |> should.equal(True)

  let babel_msg =
    telegram_simulator.simulate_text_directive(33, "/babel start ja en")
  let resp3 = telegram.handle_message(babel_msg)
  string.contains(resp3.text, "Live Technical Speech Babel Bridge Active")
  |> should.equal(True)

  let wb_msg =
    telegram_simulator.simulate_text_directive(34, "/whiteboard session-fsm")
  let resp4 = telegram.handle_message(wb_msg)
  string.contains(resp4.text, "Whiteboard-to-Code Collaborative Synthesis")
  |> should.equal(True)

  let socratic_msg =
    telegram_simulator.simulate_text_directive(35, "/socratic network stall")
  let resp5 = telegram.handle_message(socratic_msg)
  string.contains(resp5.text, "Socratic Referee & Conflict Resolution Card")
  |> should.equal(True)

  let handover_msg =
    telegram_simulator.simulate_text_directive(36, "/handover generate")
  let resp6 = telegram.handle_message(handover_msg)
  string.contains(resp6.text, "Shift Handover Dossier & Podcast Minted")
  |> should.equal(True)

  let gameday_msg =
    telegram_simulator.simulate_text_directive(37, "/gameday start partition-nas1")
  let resp7 = telegram.handle_message(gameday_msg)
  string.contains(resp7.text, "Synthetic Adversary GameDay Chaos Drill")
  |> should.equal(True)
}

pub fn telegram_multimodal_vision_and_audio_simulation_test() {
  // Acoustic FFT test
  let empty_sample = bit_array.from_string("")
  let spec_empty = telegram_simulator.simulate_acoustic_fft(empty_sample)
  spec_empty.anomaly_detected |> should.equal(False)

  let raw_pcm = bit_array.from_string("simulated-pcm-waveform-data-bytes-1024")
  let spec_active = telegram_simulator.simulate_acoustic_fft(raw_pcm)
  spec_active.anomaly_detected |> should.equal(True)
  spec_active.fundamental_hz |> should.equal(1240)
  spec_active.flutter_hz |> should.equal(14)

  // Computer Vision Rack test
  let raw_img = bit_array.from_string("simulated-jpeg-bay-image-bytes")
  let inspection_bay3 = telegram_simulator.simulate_vision_inspection(raw_img, 3)
  inspection_bay3.amber_led |> should.equal(True)
  inspection_bay3.safe_to_pull |> should.equal(True)
  inspection_bay3.serial_number |> should.equal("S439NX0M819234")

  let inspection_bay0 = telegram_simulator.simulate_vision_inspection(raw_img, 0)
  inspection_bay0.safe_to_pull |> should.equal(False)
  inspection_bay0.serial_number
  |> should.equal(telegram_simulator.hard_denied_system_os_serial)

  // Voice memo simulation
  let voice_memo =
    telegram_simulator.simulate_voice_memo(
      880,
      "an",
      5.2,
      "/voice-roll-call verify prop-drain",
    )
  let voice_resp = telegram.handle_message(voice_memo)
  voice_resp.chat_id |> should.equal("voice-room-sim")
  string.contains(voice_resp.text, "Quorum Roll Call") |> should.equal(True)

  // Photo upload simulation
  let photo_memo =
    telegram_simulator.simulate_photo_upload(881, "/rack-cv bay-3", "file-9912")
  let photo_resp = telegram.handle_message(photo_memo)
  photo_resp.chat_id |> should.equal("field-ops-sim")
  string.contains(photo_resp.text, "Bay 3 (SAFE TO PULL)") |> should.equal(True)
}

pub fn telegram_full_simulation_sweep_test() {
  let report = telegram_simulator.run_full_simulation_sweep()

  report.failed_simulated |> should.equal(0)
  { report.passed_simulated >= 50 } |> should.equal(True)
  report.hardware_lock_verified |> should.equal(True)
  report.domain_a_count |> should.equal(13)
  report.domain_b_count |> should.equal(11)
  report.domain_c_count |> should.equal(12)
  report.domain_d_count |> should.equal(12)
  report.multimodal_count |> should.equal(4)
}
