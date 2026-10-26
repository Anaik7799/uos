//// Media design T0: the eleven legacy media arms report MediaUnsupported and
//// assert no measurement, detection, extraction or latency.

import cepaf_gleam/harness/telegram_collab as collab
import cepaf_gleam/harness/telegram_creative as creative
import cepaf_gleam/harness/telegram_media_unsupported as unsup
import gleam/list
import gleam/string
import gleeunit/should

/// The eleven literals whose legacy-route reply was changed (for the integrator).
pub const eleven_arm_literals = [
  "/rack-cv", "/acoustic", "/whiteboard", "/sidecar", "/voice-roll-call",
  "/babel", "/pair-voice", "/acoustic-hud", "/handover", "/retro", "/gameday",
]

const hostile = "`*_[evil](x)\u{0}../../etc"

/// literal, capability, reply produced with an argument shape that used to fabricate.
fn arms() -> List(#(String, String, String)) {
  [
    #("/rack-cv", "media.photo.rack_cv", creative.handle_rack_cv([hostile])),
    #(
      "/acoustic",
      "media.audio.acoustic_fft",
      creative.handle_acoustic([hostile]),
    ),
    #(
      "/whiteboard",
      "media.photo.whiteboard_synthesis",
      collab.handle_whiteboard([hostile]),
    ),
    #("/sidecar", "media.voice.sidecar", collab.handle_sidecar(["listen"])),
    #(
      "/voice-roll-call",
      "media.voice.biometric_roll_call",
      collab.handle_voice_roll_call(["verify", hostile]),
    ),
    #(
      "/babel",
      "media.voice.speech_translation",
      collab.handle_babel(["start", "ja", "en"]),
    ),
    #(
      "/pair-voice",
      "media.voice.pair_programming",
      collab.handle_pair_voice(["start"]),
    ),
    #(
      "/acoustic-hud",
      "media.audio.spatial_hud",
      collab.handle_acoustic_hud(["engage"]),
    ),
    #(
      "/handover",
      "media.audio.handover_podcast",
      collab.handle_handover(["generate"]),
    ),
    #(
      "/retro",
      "media.voice.retro_scribe",
      collab.handle_retro(["export", hostile]),
    ),
    #(
      "/gameday",
      "media.voice.gameday_drill",
      collab.handle_gameday(["start", hostile]),
    ),
  ]
}

fn prefix(literal: String, capability: String) -> String {
  "⚠️ *"
  <> literal
  <> "* media capability is not implemented\n\n```json\n"
  <> "{\"status\":\"UNSUPPORTED\",\"capability\":\""
  <> capability
  <> "\",\"backend\":\"NOT_IMPLEMENTED\",\"observed\":false,\"reason\":\"No"
}

pub fn eleven_literals_listed_test() {
  list.length(eleven_arm_literals) |> should.equal(11)
  arms()
  |> list.map(fn(a) { a.0 })
  |> should.equal(eleven_arm_literals)
}

pub fn each_arm_returns_media_unsupported_shape_test() {
  list.each(arms(), fn(a) {
    let #(literal, capability, reply) = a
    string.starts_with(reply, prefix(literal, capability)) |> should.be_true
    string.ends_with(reply, "\"}\n```") |> should.be_true
  })
}

pub fn render_is_exactly_the_record_test() {
  let u = unsup.unsupported("media.x.y", "because")
  unsup.to_json(u)
  |> should.equal(
    "{\"status\":\"UNSUPPORTED\",\"capability\":\"media.x.y\",\"backend\":\"NOT_IMPLEMENTED\",\"observed\":false,\"reason\":\"because\"}",
  )
  u.backend |> should.equal("NOT_IMPLEMENTED")
  u.observed |> should.equal(False)
  unsup.render("/x", u)
  |> should.equal(
    "⚠️ */x* media capability is not implemented\n\n```json\n"
    <> unsup.to_json(u)
    <> "\n```",
  )
}

pub fn reason_is_escaped_not_interpolated_test() {
  unsup.to_json(unsup.unsupported("c", "say \"hi\"\n"))
  |> should.equal(
    "{\"status\":\"UNSUPPORTED\",\"capability\":\"c\",\"backend\":\"NOT_IMPLEMENTED\",\"observed\":false,\"reason\":\"say \\\"hi\\\"\\n\"}",
  )
}

pub fn no_arm_asserts_a_measurement_test() {
  list.each(arms(), fn(a) {
    let reply = a.2
    // P-2: no digit anywhere in the reply, so no confidence, RUL, latency or count.
    string.to_graphemes(reply)
    |> list.any(fn(g) { string.contains("0123456789", g) })
    |> should.be_false
    let lower = string.lowercase(reply)
    list.each(
      [
        "%", "±", "confidence", "rul", "chassis", "detected", "acoustic match",
        "vote:", "ms)", "extracted", "vit ", "spectrogram", "whisper", "kokoro",
        "consensus reached", "committed", "latency",
      ],
      fn(bad) { string.contains(lower, bad) |> should.be_false },
    )
  })
}

pub fn sender_argument_is_never_echoed_test() {
  list.each(arms(), fn(a) {
    string.contains(a.2, "evil") |> should.be_false
    string.contains(a.2, "etc") |> should.be_false
  })
}

pub fn help_text_is_kept_test() {
  string.contains(collab.handle_sidecar([]), "`/sidecar listen`")
  |> should.be_true
  string.contains(collab.handle_babel([]), "`/babel start <lang1> <lang2>`")
  |> should.be_true
  string.contains(collab.handle_pair_voice([]), "`/pair-voice start`")
  |> should.be_true
  string.contains(collab.handle_acoustic_hud([]), "`/acoustic-hud engage`")
  |> should.be_true
  string.contains(collab.handle_handover([]), "`/handover generate`")
  |> should.be_true
  string.contains(collab.handle_retro([]), "`/retro export <session_id>`")
  |> should.be_true
  string.contains(collab.handle_gameday([]), "`/gameday start <scenario>`")
  |> should.be_true
  string.contains(
    collab.handle_voice_roll_call([]),
    "`/voice-roll-call verify <proposal_id>`",
  )
  |> should.be_true
}

pub fn voice_roll_call_help_also_reports_unsupported_test() {
  let reply = collab.handle_voice_roll_call([])
  string.contains(
    reply,
    "\"capability\":\"media.voice.biometric_roll_call\",\"backend\":\"NOT_IMPLEMENTED\",\"observed\":false",
  )
  |> should.be_true
}

pub fn subcommand_arms_without_media_flag_stay_help_only_test() {
  // Argument-less calls keep the usage text; they never assert a result.
  list.each(
    [
      collab.handle_sidecar([]),
      collab.handle_babel([]),
      collab.handle_pair_voice([]),
      collab.handle_acoustic_hud([]),
      collab.handle_handover([]),
      collab.handle_retro([]),
      collab.handle_gameday([]),
    ],
    fn(r) { string.contains(r, "\"observed\":false") |> should.be_false },
  )
}
