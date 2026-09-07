import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleeunit/should
import uos_swarm/board.{Agent, Causality, Draft}
import uos_swarm/raga
import uos_swarm/sangita

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn agent(id: String, layer: String) -> board.Agent {
  Agent(id, layer, "model")
}

fn draft(
  from: board.Agent,
  kind: board.Kind,
  to: String,
  payload: List(#(String, String)),
) -> board.Draft {
  Draft(
    from,
    to,
    kind,
    payload,
    board.no_semantics,
    Causality(None, []),
    None,
    None,
  )
}

fn msg(
  from: board.Agent,
  kind: board.Kind,
  lamport: Int,
  payload: List(#(String, String)),
) -> board.Message {
  board.seal(
    draft(from, kind, "broadcast", payload),
    "test",
    1_700_000_000_000_000 + lamport,
    lamport,
    string.pad_start(int.to_string(lamport), 16, "0"),
    board.genesis_digest,
  )
}

/// One message per board kind (Andon appears twice, once green once red;
/// Progress appears twice to exercise its rotating cursor), all from
/// `sender`, in increasing Lamport order.
fn all_kind_messages(sender: board.Agent) -> List(board.Message) {
  let specs = [
    #(board.Plan, []),
    #(board.Dispatch, []),
    #(board.Claim, []),
    #(board.Progress, []),
    #(board.Progress, []),
    #(board.Question, []),
    #(board.Answer, []),
    #(board.Report, []),
    #(board.Verdict, []),
    #(board.Andon, [#("color", "green")]),
    #(board.Andon, [#("color", "red")]),
    #(board.Jidoka, []),
    #(board.Integrate, []),
    #(board.Heartbeat, []),
    #(board.Intent, []),
    #(board.LeaseGrant, []),
    #(board.LeaseRelease, []),
    #(board.Ack, []),
    #(board.DeadLetter, []),
  ]
  list.index_map(specs, fn(spec, i) { msg(sender, spec.0, i + 1, spec.1) })
}

fn note_of(notes: List(sangita.Note), source: String) -> sangita.Note {
  notes |> list.find(fn(n) { n.source == source }) |> should.be_ok
}

fn at(xs: List(a), i: Int) -> a {
  list.drop(xs, i) |> list.first |> should.be_ok
}

fn tiny_bandish(
  r: sangita.Raga,
  t: sangita.Tala,
  tempo: Int,
) -> sangita.Bandish {
  let note = sangita.Note(raga.Sa, raga.Shuddha, 0, 1, 1, "test")
  sangita.bandish_of_notes(r, t, tempo, [note], sangita.neutral_harmony(r))
}

fn max_abs_sample(wav: BitArray) -> Int {
  let assert <<_header:bytes-size(44), pcm:bytes>> = wav
  scan_samples(pcm, 0)
}

fn scan_samples(pcm: BitArray, acc: Int) -> Int {
  case pcm {
    <<sample:16-little-signed, rest:bytes>> ->
      scan_samples(rest, int.max(acc, int.absolute_value(sample)))
    _ -> acc
  }
}

fn read_vlq(bytes: BitArray) -> #(Int, BitArray) {
  read_vlq_loop(bytes, 0)
}

fn read_vlq_loop(bytes: BitArray, acc: Int) -> #(Int, BitArray) {
  case bytes {
    <<1:1, low7:7, rest:bits>> -> read_vlq_loop(rest, acc * 128 + low7)
    <<0:1, low7:7, rest:bits>> -> #(acc * 128 + low7, rest)
    _ -> #(acc, bytes)
  }
}

/// Count Note On (0x9x), Note Off (0x8x) and "other" (program change, meta)
/// events in a raw MTrk event stream by walking delta-time-VLQ + event
/// pairs — a minimal structural MIDI reader, just enough to verify
/// `sangita.to_midi`'s own event shapes.
fn count_events(
  bytes: BitArray,
  on: Int,
  off: Int,
  other: Int,
) -> #(Int, Int, Int) {
  case bytes {
    <<>> -> #(on, off, other)
    _ -> {
      let #(_, after_vlq) = read_vlq(bytes)
      case after_vlq {
        <<0xFF:8, _meta_type:8, len:8, _data:bytes-size(len), rest:bytes>> ->
          count_events(rest, on, off, other + 1)
        <<status:8, rest:bytes>> ->
          case int.bitwise_and(status, 0xF0) {
            0x90 -> {
              let assert <<_:8, _:8, rest2:bytes>> = rest
              count_events(rest2, on + 1, off, other)
            }
            0x80 -> {
              let assert <<_:8, _:8, rest2:bytes>> = rest
              count_events(rest2, on, off + 1, other)
            }
            0xC0 -> {
              let assert <<_:8, rest2:bytes>> = rest
              count_events(rest2, on, off, other + 1)
            }
            _ -> #(on, off, other)
          }
        _ -> #(on, off, other)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 1. Saṅgīta — composition, unified with the real raga.gleam catalogue
// ---------------------------------------------------------------------------

pub fn catalogue_ragas_all_singable_test() {
  list.each(raga.ragas(), fn(r) {
    let sender = agent("w", "L2")
    let b =
      sangita.compose(all_kind_messages(sender), r, raga.teentaal(), 80, 8)
    let scale = sangita.scale_of(r)
    list.each(b.notes, fn(n) {
      should.be_true(list.contains(scale, #(n.swara, n.variant)))
    })
  })
}

pub fn sam_carries_vadi_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L1")
  let b = sangita.compose(all_kind_messages(sender), r, t, 80, 8)
  let sam_notes = list.filter(b.notes, fn(n) { n.matra == t.sam })
  should.be_true(sam_notes != [])
  let vadi_pitch = sangita.pitch_of(r, r.vadi)
  list.each(sam_notes, fn(n) { should.equal(#(n.swara, n.variant), vadi_pitch) })
}

pub fn khali_never_carries_a_strong_note_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L1")
  let b = sangita.compose(all_kind_messages(sender), r, t, 80, 8)
  let khali_notes =
    list.filter(b.notes, fn(n) { list.contains(t.khali, n.matra) })
  should.be_true(khali_notes != [])
  list.each(khali_notes, fn(n) {
    should.equal(n.swara, raga.Sa)
    should.equal(n.duration, 1)
  })
}

pub fn octave_follows_sender_layer_test() {
  let l0 = agent("l0", "L0")
  let l1 = agent("l1", "L1")
  let l2 = agent("l2", "L2")
  let l3 = agent("l3", "L3")
  let m0 = msg(l0, board.Ack, 1, [])
  let m1 = msg(l1, board.Ack, 2, [])
  let m2 = msg(l2, board.Ack, 3, [])
  let m3 = msg(l3, board.Ack, 4, [])
  let b =
    sangita.compose([m0, m1, m2, m3], raga.yaman(), raga.teentaal(), 80, 4)
  should.equal(note_of(b.notes, m0.id).octave, 1)
  should.equal(note_of(b.notes, m1.id).octave, 0)
  should.equal(note_of(b.notes, m2.id).octave, -1)
  should.equal(note_of(b.notes, m3.id).octave, -1)
}

pub fn sthayi_is_first_cycle_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L1")
  let b = sangita.compose(all_kind_messages(sender), r, t, 80, 8)
  should.be_true(b.sthayi != [])
  let first = at(b.sthayi, 0)
  should.equal(first.matra, 1)
}

pub fn sargam_contains_devanagari_and_sam_marker_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L0")
  let b = sangita.compose(all_kind_messages(sender), r, t, 80, 4)
  let text = sangita.to_sargam(b)
  should.be_true(string.contains(text, "स"))
  should.be_true(string.contains(text, "X"))
  should.be_true(string.contains(text, "Yaman"))
}

pub fn compose_is_deterministic_test() {
  let r = raga.bhairav()
  let t = raga.teentaal()
  let sender = agent("w", "L2")
  let messages = all_kind_messages(sender)
  let b1 = sangita.compose(messages, r, t, 80, 4)
  let b2 = sangita.compose(messages, r, t, 80, 4)
  should.equal(b1.notes, b2.notes)
  should.equal(b1.sthayi, b2.sthayi)
  should.equal(b1.antara, b2.antara)
  should.equal(sangita.to_sargam(b1), sangita.to_sargam(b2))
}

pub fn compose_respects_max_cycles_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L1")
  let messages =
    list.repeat(Nil, 40)
    |> list.index_map(fn(_, i) { msg(sender, board.Ack, i + 1, []) })
  let b = sangita.compose(messages, r, t, 80, 1)
  should.be_true(list.length(b.notes) <= t.matras)
}

pub fn tala_selection_by_name_test() {
  should.equal(sangita.tala_by_name("Jhaptaal").matras, 10)
  should.equal(sangita.tala_by_name("teentaal").matras, 16)
  should.equal(sangita.tala_by_name("Rupak").matras, 7)
  should.equal(sangita.tala_by_name("Ektaal").matras, 12)
  should.be_true(result.is_error(sangita.tala_by_name_strict("nope-tala")))
}

pub fn raga_by_name_strict_positive_test() {
  let r = sangita.raga_by_name_strict("Kafi") |> should.be_ok
  should.equal(r.thaat, raga.Kafi)
  let r2 = sangita.raga_by_name_strict("darbari") |> should.be_ok
  should.equal(r2.vadi, raga.Re)
}

pub fn raga_by_name_strict_negative_test() {
  should.be_true(result.is_error(sangita.raga_by_name_strict("not-a-raga")))
}

// ---------------------------------------------------------------------------
// 2. Sound — frequencies, MIDI mapping, three-voice WAV mix
// ---------------------------------------------------------------------------

pub fn frequency_pa_is_1_5x_sa_test() {
  let sa = sangita.frequency(raga.Sa, raga.Shuddha, 0, 240.0)
  let pa = sangita.frequency(raga.Pa, raga.Shuddha, 0, 240.0)
  should.equal(pa, sa *. 1.5)
}

pub fn frequency_tara_sa_is_2x_sa_test() {
  let sa = sangita.frequency(raga.Sa, raga.Shuddha, 0, 240.0)
  let tara_sa = sangita.frequency(raga.Sa, raga.Shuddha, 1, 240.0)
  should.equal(tara_sa, sa *. 2.0)
}

pub fn midi_note_number_test() {
  should.equal(sangita.midi_note_number(raga.Sa, raga.Shuddha, 0, 60), 60)
  should.equal(sangita.midi_note_number(raga.Pa, raga.Shuddha, 0, 60), 67)
  should.equal(sangita.midi_note_number(raga.Re, raga.Komal, 0, 60), 61)
  should.equal(sangita.midi_note_number(raga.Ma, raga.Tivra, 0, 60), 66)
  should.equal(sangita.midi_note_number(raga.Sa, raga.Shuddha, 1, 60), 72)
}

pub fn wav_header_and_sample_count_test() {
  // Rupak: 7 mātrās; at 420bpm one mātrā is exactly 1/7 s, so one cycle is
  // exactly 1.0 s — keeps the generated sample count (and test runtime)
  // small while still exercising the full three-voice mix.
  let b = tiny_bandish(raga.yaman(), raga.rupak(), 420)
  let wav = sangita.to_wav(b, 8000, 240.0)
  let assert <<
    riff:bytes-size(4),
    riff_chunk_size:32-little,
    wave:bytes-size(4),
    fmt_tag:bytes-size(4),
    subchunk1_size:32-little,
    audio_format:16-little,
    channels:16-little,
    sample_rate:32-little,
    byte_rate:32-little,
    block_align:16-little,
    bits_per_sample:16-little,
    data_tag:bytes-size(4),
    data_size:32-little,
    _pcm:bytes,
  >> = wav
  should.equal(riff, <<"RIFF":utf8>>)
  should.equal(wave, <<"WAVE":utf8>>)
  should.equal(fmt_tag, <<"fmt ":utf8>>)
  should.equal(data_tag, <<"data":utf8>>)
  should.equal(subchunk1_size, 16)
  should.equal(audio_format, 1)
  should.equal(channels, 1)
  should.equal(sample_rate, 8000)
  should.equal(byte_rate, 8000 * 2)
  should.equal(block_align, 2)
  should.equal(bits_per_sample, 16)
  should.equal(data_size, 8000 * 2)
  should.equal(riff_chunk_size, 36 + 8000 * 2)
}

pub fn wav_caps_to_sixty_seconds_test() {
  let r = raga.yaman()
  let t = raga.dadra()
  let sender = agent("w", "L1")
  let messages =
    list.repeat(Nil, 60)
    |> list.index_map(fn(_, i) { msg(sender, board.Ack, i + 1, []) })
  // dadra = 6 matras/cycle, 60 Ack notes -> 10 cycles; at 6bpm one matra is
  // 10s, so 10 cycles is 600s of nominal audio -- must be capped to 60s.
  let b = sangita.compose(messages, r, t, 6, 20)
  let wav = sangita.to_wav(b, 1000, 240.0)
  let max_bytes = 44 + 60 * 1000 * 2
  should.be_true(bit_array.byte_size(wav) <= max_bytes)
}

pub fn mix_within_16bit_range_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let sender = agent("w", "L1")
  // tempo 240 + max_cycles 1 keeps this to one 16-matra cycle -- fast to
  // synthesize while still exercising melody+drone+percussion together.
  let b = sangita.compose(all_kind_messages(sender), r, t, 240, 1)
  let wav = sangita.to_wav(b, 8000, 240.0)
  should.be_true(max_abs_sample(wav) <= 26_214)
}

pub fn drone_present_in_first_second_test() {
  // Isolate the tānpūrā drone from the full mix (which also carries
  // percussion on every mātrā, so "energy in the mix" would not by itself
  // distinguish the drone's own continuity) and confirm it has energy in
  // the piece's opening second, regardless of what the melody is doing.
  let r = raga.yaman()
  let samples = sangita.drone_samples(r, 1.0, 8000, 240.0, 1.0)
  should.equal(list.length(samples), 8000)
  let energy = list.fold(samples, 0.0, fn(acc, x) { acc +. float_abs(x) })
  should.be_true(energy >. 0.0)
}

fn float_abs(x: Float) -> Float {
  case x <. 0.0 {
    True -> -1.0 *. x
    False -> x
  }
}

pub fn midi_header_bytes_test() {
  let b = tiny_bandish(raga.yaman(), raga.teentaal(), 90)
  let midi = sangita.to_midi(b, 60)
  let assert <<
    mthd:bytes-size(4),
    hdr_len:32,
    format:16,
    ntrks:16,
    division:16,
    mtrk:bytes-size(4),
    track_len:32,
    track_data:bytes,
  >> = midi
  should.equal(mthd, <<"MThd":utf8>>)
  should.equal(hdr_len, 6)
  should.equal(format, 0)
  should.equal(ntrks, 1)
  should.equal(division, 120)
  should.equal(mtrk, <<"MTrk":utf8>>)
  should.equal(track_len, bit_array.byte_size(track_data))
}

pub fn midi_event_count_test() {
  // One melody note, one cycle of Teentaal (16 matras): melody=1 pair,
  // drone plucks = ceil(16/2)=8 pairs, percussion = 16 pairs (one per
  // matra) -> 25 Note On / 25 Note Off, plus tempo + program-change +
  // end-of-track = 3 "other" events.
  let b = tiny_bandish(raga.yaman(), raga.teentaal(), 90)
  let midi = sangita.to_midi(b, 60)
  // 14-byte MThd chunk + 8-byte "MTrk"+length prefix before the actual
  // track event bytes begin.
  let assert <<_header:bytes-size(22), track_data:bytes>> = midi
  let #(on, off, other) = count_events(track_data, 0, 0, 0)
  should.equal(on, 25)
  should.equal(off, 25)
  should.equal(other, 3)
}

// ---------------------------------------------------------------------------
// 1b. Compose and sing your own rāga
// ---------------------------------------------------------------------------

pub fn raga_json_define_positive_test() {
  let text =
    "{\"name\":\"Test Raga\",\"thaat\":\"Kalyan\","
    <> "\"aroha\":[\"sa\",\"re\",\"ga\",\"ma+\",\"pa\",\"dha\",\"ni\",\"sa'\"],"
    <> "\"avaroha\":[\"sa'\",\"ni\",\"dha\",\"pa\",\"ma+\",\"ga\",\"re\",\"sa\"],"
    <> "\"vadi\":\"ga\",\"samvadi\":\"ni\",\"time\":\"evening\",\"mood\":\"testing\"}"
  let r = sangita.parse_raga_json(text) |> should.be_ok
  should.equal(r.name, "Test Raga")
  should.equal(r.thaat, raga.Kalyan)
  should.equal(r.vadi, raga.Ga)
  should.equal(r.samvadi, raga.Ni)
}

pub fn raga_json_define_negative_out_of_thaat_test() {
  // Bilawal is all-shuddha; komal Re ("re_") is outside its note set.
  let text =
    "{\"name\":\"Bad\",\"thaat\":\"Bilawal\","
    <> "\"aroha\":[\"sa\",\"re_\",\"ga\",\"ma\",\"pa\",\"dha\",\"ni\",\"sa'\"],"
    <> "\"avaroha\":[\"sa'\",\"ni\",\"dha\",\"pa\",\"ma\",\"ga\",\"re_\",\"sa\"],"
    <> "\"vadi\":\"sa\",\"samvadi\":\"pa\",\"time\":\"morning\",\"mood\":\"x\"}"
  should.be_true(result.is_error(sangita.parse_raga_json(text)))
}

pub fn raga_json_define_negative_empty_name_test() {
  let text =
    "{\"name\":\"\",\"thaat\":\"Bilawal\",\"aroha\":[\"sa\",\"pa\"],"
    <> "\"avaroha\":[\"pa\",\"sa\"],\"vadi\":\"sa\",\"samvadi\":\"pa\","
    <> "\"time\":\"morning\",\"mood\":\"x\"}"
  should.be_true(result.is_error(sangita.parse_raga_json(text)))
}

pub fn raga_json_define_negative_bad_vadi_test() {
  // Durga's own def, but vadi "ga" is not in the pentatonic set.
  let text =
    "{\"name\":\"Bad Vadi\",\"thaat\":\"Bilawal\","
    <> "\"aroha\":[\"sa\",\"re\",\"ma\",\"pa\",\"dha\",\"sa'\"],"
    <> "\"avaroha\":[\"sa'\",\"dha\",\"pa\",\"ma\",\"re\",\"sa\"],"
    <> "\"vadi\":\"ga\",\"samvadi\":\"sa\",\"time\":\"evening\",\"mood\":\"x\"}"
  should.be_true(result.is_error(sangita.parse_raga_json(text)))
}

pub fn sargam_parse_rests_and_ties_test() {
  let r = raga.yaman()
  let text = "sa - re ~"
  let notes = sangita.parse_sargam(text, r) |> should.be_ok
  should.equal(list.length(notes), 2)
  let first = at(notes, 0)
  should.equal(first.swara, raga.Sa)
  should.equal(first.matra, 1)
  should.equal(first.duration, 1)
  let second = at(notes, 1)
  should.equal(second.swara, raga.Re)
  should.equal(second.matra, 3)
  should.equal(second.duration, 2)
}

pub fn sargam_parse_out_of_scale_error_test() {
  // Malkauns has no Pa.
  should.be_true(result.is_error(sangita.parse_sargam("pa", raga.malkauns())))
}

pub fn sargam_tie_without_preceding_note_error_test() {
  should.be_true(result.is_error(sangita.parse_sargam("~", raga.yaman())))
}

pub fn sing_sargam_renders_expected_note_count_test() {
  let r = raga.yaman()
  let t = raga.teentaal()
  let text = "sa re ga ma+ pa dha ni sa'\nsa' ni dha pa ma+ ga re sa"
  let notes = sangita.parse_sargam(text, r) |> should.be_ok
  should.equal(list.length(notes), 16)
  let b = sangita.bandish_of_notes(r, t, 80, notes, sangita.neutral_harmony(r))
  should.equal(list.length(b.notes), 16)
  should.equal(list.length(b.sthayi), 8)
  should.equal(sangita.cycles_used(b.notes), 2)
}

pub fn harmony_modulation_changes_drone_gain_test() {
  let low = sangita.Harmony(0.2, [], [], 1, "test")
  let mid = sangita.Harmony(0.65, [], [], 1, "test")
  let #(low_raga, low_mix) = sangita.raga_and_mix_for_state(low)
  let #(_mid_raga, mid_mix) = sangita.raga_and_mix_for_state(mid)
  should.be_true(low_mix.drone >. mid_mix.drone)
  should.be_true(low_mix.melody <. mid_mix.melody)
  should.equal(mid_mix, sangita.default_mix())
  should.equal(low_raga.name, raga.malkauns().name)
}

// ---------------------------------------------------------------------------
// 3. Harmony with the universe
// ---------------------------------------------------------------------------

pub fn harmony_index_is_bounded_test() {
  let sender = agent("w", "L1")
  let h = sangita.harmony(all_kind_messages(sender), 1_700_000_000_000_000)
  should.be_true(h.index >=. 0.0)
  should.be_true(h.index <=. 1.0)
}

pub fn harmony_empty_board_is_fully_consonant_test() {
  let h = sangita.harmony([], 0)
  should.equal(h.index, 1.0)
  should.equal(h.dissonant, [])
}

pub fn harmony_consonant_dissonant_partition_test() {
  let sender = agent("w", "L1")
  let q = msg(sender, board.Question, 1, [])
  let dead = msg(sender, board.DeadLetter, 2, [])
  let dead2 = msg(sender, board.DeadLetter, 3, [])
  let dead3 = msg(sender, board.DeadLetter, 4, [])
  let h = sangita.harmony([q, dead, dead2, dead3], 1_700_000_000_000_000)
  should.be_true(list.contains(h.dissonant, "questions_answered"))
  should.be_true(list.contains(h.dissonant, "dead_letter_absence"))
  should.be_true(h.consonant != [])
}

pub fn prahar_and_raga_for_hour_5_test() {
  should.equal(sangita.prahar_of_hour(5), 2)
  should.equal(sangita.raga_name_for_hour(5), raga.bhairav().name)
}

pub fn prahar_and_raga_for_hour_10_test() {
  should.equal(sangita.prahar_of_hour(10), 4)
  should.equal(sangita.raga_name_for_hour(10), raga.durga().name)
}

pub fn prahar_and_raga_for_hour_18_test() {
  should.equal(sangita.prahar_of_hour(18), 7)
  should.equal(sangita.raga_name_for_hour(18), raga.yaman().name)
}

pub fn prahar_and_raga_for_hour_23_test() {
  should.equal(sangita.prahar_of_hour(23), 8)
  should.equal(sangita.raga_name_for_hour(23), raga.malkauns().name)
}

pub fn raga_for_harmony_emergency_is_bhairavi_test() {
  let h = sangita.Harmony(1.0, [], [], 7, "Yaman")
  should.equal(
    sangita.raga_for_harmony(h, "Emergency").name,
    raga.bhairavi().name,
  )
}

pub fn raga_for_harmony_low_index_is_malkauns_test() {
  let h = sangita.Harmony(0.2, [], [], 7, "Yaman")
  should.equal(
    sangita.raga_for_harmony(h, "Nominal").name,
    raga.malkauns().name,
  )
}

pub fn raga_for_harmony_otherwise_follows_the_hour_test() {
  let h = sangita.Harmony(0.9, [], [], 7, raga.yaman().name)
  should.equal(sangita.raga_for_harmony(h, "Nominal").name, raga.yaman().name)
}

// ---------------------------------------------------------------------------
// 4. Growth in harmony
// ---------------------------------------------------------------------------

pub fn harmony_gate_passes_for_equal_test() {
  let h = sangita.Harmony(0.7, [], [], 1, "test")
  should.be_ok(sangita.harmony_gate(h, h))
}

pub fn harmony_gate_fails_for_a_drop_test() {
  let before = sangita.Harmony(0.8, [], [], 1, "test")
  let after = sangita.Harmony(0.6, [], [], 1, "test")
  should.be_error(sangita.harmony_gate(before, after))
}

pub fn harmony_gate_passes_within_tolerance_test() {
  let before = sangita.Harmony(0.8, [], [], 1, "test")
  let after = sangita.Harmony(0.76, [], [], 1, "test")
  should.be_ok(sangita.harmony_gate(before, after))
}

pub fn growth_record_test() {
  let before = sangita.Harmony(0.7, [], [], 1, "test")
  let after = sangita.Harmony(0.75, [], [], 1, "test")
  let g = sangita.growth(before, after, 3, 42, 2, 8, 10)
  should.equal(g.modules, 3)
  should.equal(g.tests, 42)
  should.equal(g.adopted_proposals, 2)
  should.equal(g.verified_ratio, 0.8)
  should.equal(g.harmony_before, 0.7)
  should.equal(g.harmony_after, 0.75)
  should.be_true(g.in_harmony)
}

pub fn growth_out_of_harmony_test() {
  let before = sangita.Harmony(0.9, [], [], 1, "test")
  let after = sangita.Harmony(0.5, [], [], 1, "test")
  let g = sangita.growth(before, after, 1, 1, 1, 1, 1)
  should.be_false(g.in_harmony)
}
