//// Saṅgīta: the swarm sings. Per operator directive — "the swarm and hive
//// must sing and be in harmony with the universe as it increases its
//// capabilities and intelligence", extended by "convert the harmony into
//// human music so that someone can listen to the swarm singing and playing
//// music, read all the ragas and create the ability to compose and sing
//// your own ragas" — this module turns a message board timeline into a
//// deterministic Hindustani classical composition (`compose`/`to_sargam`/
//// `to_json`), synthesizes it to a pure-Gleam, three-voice WAV recording
//// (melody + tānpūrā drone + tāla percussion, `to_wav`/`to_wav_mixed`) and
//// a Standard MIDI File (`to_midi`), measures the swarm's harmony with the
//// operational "universe" of the board (`harmony`), gates capability growth
//// on that harmony never regressing beyond tolerance (`growth`/
//// `harmony_gate`), and lets an operator compose and sing their own rāga
//// (`parse_raga_json`, `parse_sargam`).
////
//// STAMP: SC-SANGITA-001. Zero-Muda: pure Gleam/OTP plus Erlang stdlib
//// `math:sin/1` (allowed — not Bevy/Graphite, not a foreign NIF).
////
//// Unification note (worker O-6b): the catalogue of svara/variant/tāla/rāga
//// now comes from `uos_swarm/raga` (written by a sibling worker), which
//// this module only reads — `raga.gleam` is never edited here. `Swara`,
//// `Variant`, `Tala` and `Raga` below are type aliases onto `raga`'s own
//// types, so a caller already holding a `raga.Raga`/`raga.Tala` value can
//// pass it straight into every function in this module.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleam/order
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/raga.{
  Dha, Ga, Khali, Komal, Ma, Ni, Ordinary, Pa, Raga, Re, Sa, Sam, Shuddha, Tali,
  Tivra,
}

/// Alias onto `raga.Swara` — see the module doc.
pub type Swara =
  raga.Swara

/// Alias onto `raga.Variant`.
pub type Variant =
  raga.Variant

/// Alias onto `raga.Tala`.
pub type Tala =
  raga.Tala

/// Alias onto `raga.Raga`.
pub type Raga =
  raga.Raga

/// Every svara, in sargam order.
pub const all_swaras = [Sa, Re, Ga, Ma, Pa, Dha, Ni]

/// Every variant.
pub const all_variants = [Shuddha, Komal, Tivra]

/// Mandra (-1), madhya (0) and tāra (+1) — the three octaves `frequencies`
/// tabulates.
pub const all_octaves = [-1, 0, 1]

fn swara_ordinal(s: Swara) -> Int {
  case s {
    Sa -> 0
    Re -> 1
    Ga -> 2
    Ma -> 3
    Pa -> 4
    Dha -> 5
    Ni -> 6
  }
}

// ---------------------------------------------------------------------------
// Rāga/tāla lookup and scale helpers (built on `raga.gleam`'s catalogue).
// ---------------------------------------------------------------------------

/// Case-insensitive match on a catalogue name's IAST half (before the
/// " · " Devanagari separator every `raga.gleam` name carries), so
/// `"Yaman"`, `"yaman"` and `"Yaman · यमन"` all match the same rāga.
fn normalize_catalogue_name(s: String) -> String {
  s
  |> string.lowercase
  |> string.split(" · ")
  |> list.first
  |> result.unwrap(s)
  |> string.trim
}

/// The rāga registered in `raga.ragas()` under `name` (case-insensitive,
/// Devanagari-suffix-insensitive); the closing rāga Bhairavi for anything
/// unrecognized (a safe, always-in-tune fallback rather than an error) —
/// use `raga_by_name_strict` where an unrecognized name must fail instead.
pub fn raga_by_name(name: String) -> Raga {
  raga_by_name_strict(name) |> result.unwrap(raga.bhairavi())
}

/// As `raga_by_name`, but `Error` (naming every catalogue rāga) instead of
/// silently falling back when `name` is not recognized.
pub fn raga_by_name_strict(name: String) -> Result(Raga, String) {
  let target = normalize_catalogue_name(name)
  raga.ragas()
  |> list.find(fn(r) { normalize_catalogue_name(r.name) == target })
  |> result.replace_error(
    "unknown raga: "
    <> name
    <> " (known: "
    <> string.join(list.map(raga.ragas(), fn(r) { r.name }), ", ")
    <> ")",
  )
}

/// The tāla registered in `raga.talas()` under `name`; Teentaal (the most
/// common cycle) for anything unrecognized.
pub fn tala_by_name(name: String) -> Tala {
  tala_by_name_strict(name) |> result.unwrap(raga.teentaal())
}

pub fn tala_by_name_strict(name: String) -> Result(Tala, String) {
  let target = normalize_catalogue_name(name)
  raga.talas()
  |> list.find(fn(t) { normalize_catalogue_name(t.name) == target })
  |> result.replace_error(
    "unknown tala: "
    <> name
    <> " (known: "
    <> string.join(list.map(raga.talas(), fn(t) { t.name }), ", ")
    <> ")",
  )
}

/// Every distinct pitch the rāga uses (āroha ∪ avaroha), in āroha order. This
/// is the closed set `compose` may ever draw a swara from — the hard
/// "harmony with the scale" rule.
pub fn scale_of(r: Raga) -> List(#(Swara, Variant)) {
  list.append(r.aroha, r.avaroha) |> list.unique
}

/// The rāga's own pitch for `target`'s svara letter, ignoring variant. When
/// the rāga does not use that svara at all (Malkauns has no Pa, Durga has no
/// Ni), returns the pitch in the rāga's own scale nearest to it by
/// scale-degree distance (ties broken toward the higher degree), so callers
/// never special-case a rāga's missing pitches: the "only scale pitches are
/// ever emitted" invariant holds unconditionally for every rāga.
pub fn nearest_in_scale(r: Raga, target: Swara) -> #(Swara, Variant) {
  let scale = scale_of(r)
  case list.find(scale, fn(p) { p.0 == target }) {
    Ok(pair) -> pair
    Error(_) -> {
      let target_ord = swara_ordinal(target)
      scale
      |> list.sort(fn(a, b) {
        let da = int.absolute_value(swara_ordinal(a.0) - target_ord)
        let db = int.absolute_value(swara_ordinal(b.0) - target_ord)
        case int.compare(da, db) {
          order.Eq -> int.compare(swara_ordinal(a.0), swara_ordinal(b.0))
          other -> other
        }
      })
      |> list.first
      |> result.unwrap(#(Sa, Shuddha))
    }
  }
}

/// Resolve a bare `Swara` (as `raga.Raga.vadi`/`.samvadi` now are) to its
/// actual pitch pair within `r`'s own scale — `raga.gleam`'s
/// `validate_register` guarantees every shipped rāga's vadi/samvadi is one
/// of its own notes, so the fallback to `nearest_in_scale` here is only
/// exercised by a malformed hand-authored rāga (see `parse_raga_json`,
/// which itself validates this before `pitch_of` is ever called on it).
pub fn pitch_of(r: Raga, s: Swara) -> #(Swara, Variant) {
  case list.find(list.append(r.aroha, r.avaroha), fn(p) { p.0 == s }) {
    Ok(pair) -> pair
    Error(_) -> nearest_in_scale(r, s)
  }
}

/// The lowest komal (flattened) pitch in the rāga's scale; when the rāga has
/// no komal pitch at all (e.g. Yaman, Durga), falls back to the rāga's
/// lowest pitch overall (always Sa) — still drawn only from the rāga's own
/// scale, preserving the hard harmony rule.
fn lowest_komal_or_fallback(r: Raga) -> #(Swara, Variant) {
  let scale = scale_of(r)
  let komals = list.filter(scale, fn(p) { p.1 == Komal })
  let pool = case komals {
    [] -> scale
    _ -> komals
  }
  pool
  |> list.sort(fn(a, b) { int.compare(swara_ordinal(a.0), swara_ordinal(b.0)) })
  |> list.first
  |> result.unwrap(#(Sa, Shuddha))
}

/// The prefix of the rāga's āroha from Sa up to and including `target`
/// (matched by exact pitch; falls back to the whole āroha if `target` is not
/// literally present).
fn ascending_to(r: Raga, target: #(Swara, Variant)) -> List(#(Swara, Variant)) {
  let cut =
    r.aroha
    |> list.index_map(fn(p, i) { #(p, i) })
    |> list.find(fn(pi) { pi.0 == target })
    |> result.map(fn(pi) { pi.1 })
    |> result.unwrap(list.length(r.aroha) - 1)
  list.take(r.aroha, cut + 1)
}

fn with_unit_durations(
  pitches: List(#(Swara, Variant)),
) -> List(#(#(Swara, Variant), Int)) {
  list.map(pitches, fn(p) { #(p, 1) })
}

fn list_at(xs: List(a), i: Int, default: a) -> a {
  case list.drop(xs, i) {
    [x, ..] -> x
    [] -> default
  }
}

/// Andon colour carried in a message's payload under `color` or `state`
/// (case-insensitive); a message with neither key, or an unrecognized value,
/// fails closed to `"red"` — the UOS doctrine throughout this repository is
/// fail-closed, and an Andon signal is exactly the kind of thing that must
/// never silently read as "fine" when it isn't labelled.
fn andon_color(payload: List(#(String, String))) -> String {
  payload
  |> list.find(fn(p) { p.0 == "color" || p.0 == "state" || p.0 == "andon" })
  |> result.map(fn(p) { string.lowercase(p.1) })
  |> result.unwrap("red")
}

// ---------------------------------------------------------------------------
// 1. Saṅgīta — the hive sings.
// ---------------------------------------------------------------------------

/// One placed note (or, when `duration` covers a khālī beat, the soft Sa
/// substituted for it — see `compose`). `octave`: -1 mandra, 0 madhya, +1
/// tāra. `matra`: the 1-based beat within the tāla cycle. `duration`: how
/// many mātrās this note is held (0 is a rest — silent in `to_wav`/
/// `to_midi`, and never produced by `compose`, but produced by
/// `parse_sargam` for a `-` token... in fact `parse_sargam` skips rests
/// rather than emitting a zero-duration Note, so the timeline gap comes
/// from the note *after* it starting later — see `notes_with_cycle`).
/// `source`: the originating board message id, or `"sargam"`/`"tala"` for a
/// hand-authored or tāla-only note.
pub type Note {
  Note(
    swara: Swara,
    variant: Variant,
    octave: Int,
    matra: Int,
    duration: Int,
    source: String,
  )
}

/// One composed piece: the rāga and tāla it is set in, its tempo, the full
/// note sequence, its first cycle (`sthayi`) and its most florid cycle by
/// octave content (`antara`), and the harmony measurement it was composed
/// under (a neutral, fully-consonant `Harmony` for hand-authored pieces that
/// carry no board — see `parse_sargam`/`bandish_of_notes`).
pub type Bandish {
  Bandish(
    raga: Raga,
    tala: Tala,
    tempo_bpm: Int,
    notes: List(Note),
    sthayi: List(Note),
    antara: List(Note),
    harmony: Harmony,
  )
}

/// -1 mandra (L2/L3, and any other layer), 0 madhya (L1), +1 tāra (L0).
fn octave_of_layer(layer: String) -> Int {
  case layer {
    "L0" -> 1
    "L1" -> 0
    _ -> -1
  }
}

/// Cursor into the tāla: the next absolute beat (1-based, never resetting —
/// see `raga.beat_of_cycle`, which folds it back into `1..matras` and
/// classifies it) to place a note at.
type Cursor {
  Cursor(beat: Int)
}

fn advance(cur: Cursor, duration: Int) -> Cursor {
  Cursor(cur.beat + duration)
}

/// Snap the cursor forward to the next tālī (clap) beat at or after its
/// current position, wrapping to the first tālī beat of the next cycle if
/// none remain in this one. Used only for `Heartbeat` motifs ("the tāla's
/// tālī beat on Sa"). When a tālī beat coincides with the sam, the
/// sam-gets-the-vādi rule in `place_one` takes precedence over the
/// tālī-beat-gets-Sa placement — sam is the stronger structural rule.
fn snap_to_tali(cur: Cursor, t: Tala) -> Cursor {
  let current = raga.beat_of_cycle(t, cur.beat)
  let cycle_start = cur.beat - current.matra
  let sorted = list.sort(t.tali, int.compare)
  case list.find(sorted, fn(m) { m >= current.matra }) {
    Ok(m) -> Cursor(cycle_start + m)
    Error(_) ->
      case list.first(sorted) {
        Ok(m) -> Cursor(cycle_start + t.matras + m)
        Error(_) -> cur
      }
  }
}

/// Place one pitch/duration event at `cur`, applying the two hard placement
/// rules — the sam always carries the vādi, and the khālī never carries a
/// strong note (it is always replaced by a soft, single-mātrā Sa) — then
/// return the placed note tagged with the cycle it started in (0-based; the
/// `Note` record itself has no cycle field — `compose`/`bandish_of_notes`
/// use the tag to build `sthayi`/`antara`, then discard it) and the
/// advanced cursor. Duration is clamped to the mātrās remaining in the
/// current cycle so a note can never span a cycle boundary — the trade-off
/// that keeps "the sam gets the vādi" exactly true for every cycle (a held
/// note that would otherwise run into the next sam is shortened instead).
fn place_one(
  cur: Cursor,
  pitch: #(Swara, Variant),
  duration: Int,
  r: Raga,
  t: Tala,
  octave: Int,
  source: String,
) -> #(#(Int, Note), Cursor) {
  let beat = raga.beat_of_cycle(t, cur.beat)
  let clamped = int.min(duration, t.matras - beat.matra + 1)
  let final_pitch = case beat.kind {
    Sam -> pitch_of(r, r.vadi)
    Khali -> nearest_in_scale(r, Sa)
    Tali | Ordinary -> pitch
  }
  let final_duration = case beat.kind {
    Khali -> 1
    _ -> clamped
  }
  let cycle_index = { cur.beat - 1 } / t.matras
  let note =
    Note(
      final_pitch.0,
      final_pitch.1,
      octave,
      beat.matra,
      final_duration,
      source,
    )
  #(#(cycle_index, note), advance(cur, final_duration))
}

fn place_motif(
  cur: Cursor,
  motif: List(#(#(Swara, Variant), Int)),
  r: Raga,
  t: Tala,
  octave: Int,
  source: String,
) -> #(List(#(Int, Note)), Cursor) {
  let #(rev, final_cur) =
    list.fold(motif, #([], cur), fn(acc, pd) {
      let #(notes, c) = acc
      let #(pitch, dur) = pd
      let #(tagged, next_c) = place_one(c, pitch, dur, r, t, octave, source)
      #([tagged, ..notes], next_c)
    })
  #(list.reverse(rev), final_cur)
}

/// The motif (pitch/duration pairs, one mātrā each unless noted) for one
/// message kind, per the operator's motif table:
///
/// | kind | phrase |
/// |---|---|
/// | Plan, Intent | ascending from Sa through the vādi |
/// | Dispatch | vādi–samvādi alternation (× 2) |
/// | Progress | repeated single ascending step (rotating cursor) |
/// | Report | descending phrase to Sa |
/// | Verdict | vādi held two mātrās |
/// | Andon green | Pa–Sa cadence |
/// | Andon amber/red, Jidoka, DeadLetter | komal Dha, or the rāga's lowest komal note, held |
/// | Integrate | full āroha then avaroha |
/// | Heartbeat | the tāla's tālī beat, on Sa |
/// | Ack, LeaseRelease, Answer | short Sa |
/// | Question | phrase ending on Ni (unresolved) |
/// | Claim, LeaseGrant | Ma |
fn motif_for(
  m: board.Message,
  r: Raga,
  progress_step: Int,
) -> #(List(#(#(Swara, Variant), Int)), Int) {
  case m.kind {
    board.Plan | board.Intent -> #(
      with_unit_durations(ascending_to(r, pitch_of(r, r.vadi))),
      progress_step,
    )
    board.Dispatch -> {
      let vadi = pitch_of(r, r.vadi)
      let samvadi = pitch_of(r, r.samvadi)
      #([#(vadi, 1), #(samvadi, 1), #(vadi, 1), #(samvadi, 1)], progress_step)
    }
    board.Progress -> {
      let scale = scale_of(r)
      let n = int.max(list.length(scale), 1)
      let i0 = int.modulo(progress_step, n) |> result.unwrap(0)
      let i1 = int.modulo(progress_step + 1, n) |> result.unwrap(0)
      let fallback = #(Sa, Shuddha)
      #(
        [#(list_at(scale, i0, fallback), 1), #(list_at(scale, i1, fallback), 1)],
        progress_step + 1,
      )
    }
    board.Report -> #(
      with_unit_durations(list.reverse(ascending_to(r, pitch_of(r, r.vadi)))),
      progress_step,
    )
    board.Verdict -> #([#(pitch_of(r, r.vadi), 2)], progress_step)
    board.Andon ->
      case andon_color(m.payload) {
        "green" -> #(
          [#(nearest_in_scale(r, Pa), 1), #(nearest_in_scale(r, Sa), 1)],
          progress_step,
        )
        _ -> #([#(lowest_komal_or_fallback(r), 2)], progress_step)
      }
    board.Jidoka -> #([#(lowest_komal_or_fallback(r), 2)], progress_step)
    board.Integrate -> #(
      list.append(with_unit_durations(r.aroha), with_unit_durations(r.avaroha)),
      progress_step,
    )
    board.Heartbeat -> #([#(nearest_in_scale(r, Sa), 1)], progress_step)
    board.Ack -> #([#(nearest_in_scale(r, Sa), 1)], progress_step)
    board.Question -> #(
      with_unit_durations(ascending_to(r, nearest_in_scale(r, Ni))),
      progress_step,
    )
    board.Answer -> #([#(nearest_in_scale(r, Sa), 1)], progress_step)
    board.Claim | board.LeaseGrant -> #(
      [#(nearest_in_scale(r, Ma), 1)],
      progress_step,
    )
    board.LeaseRelease -> #([#(nearest_in_scale(r, Sa), 1)], progress_step)
    board.DeadLetter -> #([#(lowest_komal_or_fallback(r), 2)], progress_step)
  }
}

/// Compose the board timeline into a `Bandish`, deterministically. Messages
/// are walked in Lamport order; each selects a motif in the rāga (see
/// `motif_for`) drawn only from `scale_of(r)` — the hard harmony-with-the-
/// scale rule, enforced structurally by `nearest_in_scale` and `place_one`
/// rather than merely hoped for. The sender's layer selects the octave
/// (`octave_of_layer`). Notes are placed on successive mātrās; the sam
/// always carries the vādi and the khālī never carries a strong note (see
/// `place_one`). `sthayi` is the first cycle; `antara` is the cycle with
/// the highest total octave content (ties broken toward the earliest
/// cycle). Composition stops adding cycles once `max_cycles` is reached —
/// pass a generous bound and let `to_wav`/`to_midi` apply their own hard
/// caps separately.
pub fn compose(
  messages: List(board.Message),
  r: Raga,
  t: Tala,
  tempo_bpm: Int,
  max_cycles: Int,
) -> Bandish {
  let ordered =
    list.sort(messages, fn(a, b) { int.compare(a.lamport, b.lamport) })
  let start = Cursor(1)
  let #(rev_events, _final_cur, _final_step) =
    list.fold(ordered, #([], start, 0), fn(acc, m) {
      let #(events, cur, step) = acc
      let octave = octave_of_layer(m.from.layer)
      let source = m.id
      let #(motif, step2) = motif_for(m, r, step)
      let cur2 = case m.kind {
        board.Heartbeat -> snap_to_tali(cur, t)
        _ -> cur
      }
      let #(tagged, cur3) = place_motif(cur2, motif, r, t, octave, source)
      #(list.append(list.reverse(tagged), events), cur3, step2)
    })
  let cap = int.max(max_cycles, 0)
  let events =
    list.reverse(rev_events) |> list.filter(fn(e) { e.0 >= 0 && e.0 < cap })
  let notes = list.map(events, fn(e) { e.1 })
  let now = list.fold(messages, 0, fn(acc, m) { int.max(acc, m.ts_us) })
  bandish_of_notes(r, t, tempo_bpm, notes, harmony(messages, now))
}

/// Every distinct cycle (0-based) index tagged onto `notes`, robust to a
/// cycle whose first mātrā(s) are rests (no note at mātrā 1): a new cycle
/// starts wherever a note's mātrā is not strictly greater than the previous
/// note's (mātrā values strictly increase within one cycle, since every
/// placed note advances by at least one mātrā of duration, so a
/// non-increase can only mean a new cycle began).
pub fn notes_with_cycle(notes: List(Note)) -> List(#(Int, Note)) {
  split_cycles(notes)
  |> list.index_map(fn(cyc, i) { list.map(cyc, fn(n) { #(i, n) }) })
  |> list.flatten
}

fn split_cycles(notes: List(Note)) -> List(List(Note)) {
  let grouped =
    list.fold(notes, [], fn(acc: List(List(Note)), n) {
      case acc {
        [] -> [[n]]
        [cur, ..rest] -> {
          let starts_new = case cur {
            [last, ..] -> n.matra <= last.matra
            [] -> True
          }
          case starts_new {
            True -> [[n], cur, ..rest]
            False -> [[n, ..cur], ..rest]
          }
        }
      }
    })
  grouped |> list.reverse |> list.map(list.reverse)
}

/// Number of complete cycles spanned by `notes` (0 for an empty piece).
/// Known limitation: a trailing cycle that is *entirely* rests (no note at
/// all) is invisible to this count, since there is nothing in `notes` to
/// tag it with — percussion/drone for such a cycle is not rendered.
pub fn cycles_used(notes: List(Note)) -> Int {
  list.length(split_cycles(notes))
}

fn antara_of(events: List(#(Int, Note))) -> List(Note) {
  case events {
    [] -> []
    _ -> {
      let cycles = list.map(events, fn(e) { e.0 }) |> list.unique
      let scored =
        list.map(cycles, fn(c) {
          let total =
            events
            |> list.filter(fn(e) { e.0 == c })
            |> list.fold(0, fn(acc, e) { acc + e.1.octave })
          #(c, total)
        })
      let best =
        scored
        |> list.sort(fn(a, b) {
          case int.compare(b.1, a.1) {
            order.Eq -> int.compare(a.0, b.0)
            other -> other
          }
        })
        |> list.first
        |> result.map(fn(p) { p.0 })
        |> result.unwrap(0)
      events |> list.filter(fn(e) { e.0 == best }) |> list.map(fn(e) { e.1 })
    }
  }
}

/// Build a `Bandish` from an already-placed, cursor-ordered note list (used
/// by both `compose` and `parse_sargam`'s caller): `sthayi` is cycle 0,
/// `antara` is the cycle with the highest total octave content.
pub fn bandish_of_notes(
  r: Raga,
  t: Tala,
  tempo_bpm: Int,
  notes: List(Note),
  h: Harmony,
) -> Bandish {
  let tagged = notes_with_cycle(notes)
  let sthayi =
    tagged |> list.filter(fn(e) { e.0 == 0 }) |> list.map(fn(e) { e.1 })
  let antara = antara_of(tagged)
  Bandish(r, t, tempo_bpm, notes, sthayi, antara, h)
}

/// A neutral, fully-consonant `Harmony` for pieces with no board to measure
/// (hand-authored `sing-sargam` compositions).
pub fn neutral_harmony(r: Raga) -> Harmony {
  Harmony(1.0, [], [], 1, r.name)
}

fn iast_base(s: Swara) -> String {
  case s {
    Sa -> "sa"
    Re -> "re"
    Ga -> "ga"
    Ma -> "ma"
    Pa -> "pa"
    Dha -> "dha"
    Ni -> "ni"
  }
}

fn deva_base(s: Swara) -> String {
  case s {
    Sa -> "स"
    Re -> "रे"
    Ga -> "ग"
    Ma -> "म"
    Pa -> "प"
    Dha -> "ध"
    Ni -> "नि"
  }
}

fn iast_variant(s: Swara, v: Variant) -> String {
  let base = iast_base(s)
  case v {
    Shuddha -> base
    Komal -> "_" <> base
    Tivra -> "^" <> base
  }
}

fn deva_variant(s: Swara, v: Variant) -> String {
  let base = deva_base(s)
  case v {
    Shuddha -> base
    // small dot (komal marker) before the Devanagari glyph
    Komal -> "॒" <> base
    Tivra -> "^" <> base
  }
}

fn octave_wrap(text: String, octave: Int) -> String {
  case octave {
    o if o > 0 -> text <> "'"
    o if o < 0 -> "." <> text
    _ -> text
  }
}

/// IAST-and-Devanagari sargam syllable for one note: `sa स`, komal underscore
/// / dot `_re ॒रे`, tīvra caret `^ma ^म`, tāra apostrophe `sa' स'`, mandra
/// leading dot `.sa .स`.
pub fn sargam_syllable(n: Note) -> String {
  octave_wrap(iast_variant(n.swara, n.variant), n.octave)
  <> " "
  <> octave_wrap(deva_variant(n.swara, n.variant), n.octave)
}

fn beat_mark(matra: Int, t: Tala) -> String {
  case matra == t.sam {
    True -> "X"
    False ->
      case list.contains(t.khali, matra) {
        True -> "0"
        False ->
          t.tali
          |> list.index_map(fn(m, i) { #(m, i) })
          |> list.find(fn(mi) { mi.0 == matra })
          |> result.map(fn(mi) { int.to_string(mi.1 + 1) })
          |> result.unwrap("")
      }
  }
}

fn note_cell(n: Note, t: Tala) -> String {
  let mark = beat_mark(n.matra, t)
  case mark {
    "" -> sargam_syllable(n)
    _ -> mark <> ":" <> sargam_syllable(n)
  }
}

fn vibhag_boundaries(vibhags: List(Int)) -> List(Int) {
  let #(rev, _) =
    list.fold(vibhags, #([], 0), fn(acc, v) {
      let #(bs, running) = acc
      let next = running + v
      #([next, ..bs], next)
    })
  list.reverse(rev)
}

fn vibhag_index(matra: Int, boundaries: List(Int)) -> Int {
  boundaries
  |> list.index_map(fn(b, i) { #(b, i) })
  |> list.find(fn(bi) { matra <= bi.0 })
  |> result.map(fn(bi) { bi.1 })
  |> result.unwrap(int.max(list.length(boundaries) - 1, 0))
}

fn group_consecutive(pairs: List(#(Int, String))) -> List(List(String)) {
  let grouped =
    list.fold(pairs, [], fn(acc: List(#(Int, List(String))), p) {
      let #(idx, text) = p
      case acc {
        [] -> [#(idx, [text])]
        [#(prev_idx, items), ..rest] ->
          case prev_idx == idx {
            True -> [#(idx, [text, ..items]), ..rest]
            False -> [#(idx, [text]), #(prev_idx, items), ..rest]
          }
      }
    })
  grouped |> list.reverse |> list.map(fn(g) { list.reverse(g.1) })
}

fn render_cycle(notes: List(Note), t: Tala) -> String {
  let boundaries = vibhag_boundaries(t.vibhags)
  notes
  |> list.map(fn(n) { #(vibhag_index(n.matra, boundaries), note_cell(n, t)) })
  |> group_consecutive
  |> list.map(fn(g) { string.join(g, " ") })
  |> string.join(" | ")
}

/// Render the bandish's notation: a header naming rāga (with its thaat,
/// time of day and mood), tāla, tempo and harmony index, then one line per
/// cycle, each grouped per vibhāg with `|`, the sam marked `X`, khālī
/// beats `0`, and tālī beats marked with their clap number.
pub fn to_sargam(b: Bandish) -> String {
  let header =
    "Bandish · "
    <> b.raga.name
    <> " ("
    <> raga.thaat_label(b.raga.thaat)
    <> ", "
    <> raga.time_of_day_label(b.raga.time)
    <> ", "
    <> b.raga.mood
    <> ") · "
    <> b.tala.name
    <> " · "
    <> int.to_string(b.tempo_bpm)
    <> " bpm · harmony "
    <> float.to_string(b.harmony.index)
  let lines =
    split_cycles(b.notes) |> list.map(fn(cyc) { render_cycle(cyc, b.tala) })
  string.join([header, ..lines], "\n")
}

pub fn swara_label(s: Swara) -> String {
  case s {
    Sa -> "Sa"
    Re -> "Re"
    Ga -> "Ga"
    Ma -> "Ma"
    Pa -> "Pa"
    Dha -> "Dha"
    Ni -> "Ni"
  }
}

pub fn variant_label(v: Variant) -> String {
  case v {
    Shuddha -> "Shuddha"
    Komal -> "Komal"
    Tivra -> "Tivra"
  }
}

fn note_json(n: Note) -> Json {
  json.object([
    #("swara", json.string(swara_label(n.swara))),
    #("variant", json.string(variant_label(n.variant))),
    #("octave", json.int(n.octave)),
    #("matra", json.int(n.matra)),
    #("duration", json.int(n.duration)),
    #("source", json.string(n.source)),
  ])
}

/// JSON for a `Harmony` record.
pub fn harmony_to_json(h: Harmony) -> Json {
  json.object([
    #("index", json.float(h.index)),
    #("consonant", json.array(h.consonant, json.string)),
    #("dissonant", json.array(h.dissonant, json.string)),
    #("prahar", json.int(h.prahar)),
    #("raga_for_hour", json.string(h.raga_for_hour)),
  ])
}

pub fn to_json(b: Bandish) -> Json {
  json.object([
    #("raga", json.string(b.raga.name)),
    #("tala", json.string(b.tala.name)),
    #("tempo_bpm", json.int(b.tempo_bpm)),
    #("notes", json.array(b.notes, note_json)),
    #("sthayi", json.array(b.sthayi, note_json)),
    #("antara", json.array(b.antara, note_json)),
    #("harmony", harmony_to_json(b.harmony)),
  ])
}

// ---------------------------------------------------------------------------
// 1b. Compose and sing your own rāga.
// ---------------------------------------------------------------------------

fn thaat_by_name(name: String) -> Result(raga.Thaat, String) {
  case string.lowercase(string.trim(name)) {
    "bilawal" -> Ok(raga.Bilawal)
    "kalyan" -> Ok(raga.Kalyan)
    "khamaj" -> Ok(raga.Khamaj)
    "bhairav" -> Ok(raga.Bhairav)
    "poorvi" -> Ok(raga.Poorvi)
    "marwa" -> Ok(raga.Marwa)
    "kafi" -> Ok(raga.Kafi)
    "asavari" -> Ok(raga.Asavari)
    "bhairavi" -> Ok(raga.Bhairavi)
    "todi" -> Ok(raga.Todi)
    _ -> Error("unknown thaat: " <> name)
  }
}

fn time_of_day_by_name(name: String) -> raga.TimeOfDay {
  case string.lowercase(string.trim(name)) {
    "early_morning" | "earlymorning" | "dawn" -> raga.EarlyMorning
    "morning" -> raga.Morning
    "afternoon" -> raga.Afternoon
    "evening" -> raga.Evening
    "night" -> raga.Night
    "late_night" | "latenight" | "midnight" -> raga.LateNight
    _ -> raga.AnyTime
  }
}

/// Parse one sargam token: lowercase svara name (`sa`,`re`,`ga`,`ma`,`pa`,
/// `dha`,`ni`), an optional trailing `_` (komal) or `+` (tīvra), an
/// optional trailing `'` (tāra, +1 octave) applied before the variant
/// suffix is stripped, and an optional leading `.` (mandra, -1 octave).
/// E.g. `"ma+"` -> tīvra Ma madhya; `"re_'"` -> komal Re tāra; `".ni_"` ->
/// komal Ni mandra.
pub fn parse_swara_token(
  raw: String,
) -> Result(#(Swara, Variant, Int), String) {
  let #(octave, s1) = case string.starts_with(raw, ".") {
    True -> #(-1, string.drop_start(raw, 1))
    False -> #(0, raw)
  }
  let #(octave2, s2) = case string.ends_with(s1, "'") {
    True -> #(octave + 1, string.drop_end(s1, 1))
    False -> #(octave, s1)
  }
  let #(variant, core) = case string.ends_with(s2, "_") {
    True -> #(Komal, string.drop_end(s2, 1))
    False ->
      case string.ends_with(s2, "+") {
        True -> #(Tivra, string.drop_end(s2, 1))
        False -> #(Shuddha, s2)
      }
  }
  case core {
    "sa" -> Ok(#(Sa, variant, octave2))
    "re" -> Ok(#(Re, variant, octave2))
    "ga" -> Ok(#(Ga, variant, octave2))
    "ma" -> Ok(#(Ma, variant, octave2))
    "pa" -> Ok(#(Pa, variant, octave2))
    "dha" -> Ok(#(Dha, variant, octave2))
    "ni" -> Ok(#(Ni, variant, octave2))
    _ -> Error("unrecognized svara token: " <> raw)
  }
}

fn parse_bare_swara(tok: String) -> Result(Swara, String) {
  case string.lowercase(string.trim(tok)) {
    "sa" -> Ok(Sa)
    "re" -> Ok(Re)
    "ga" -> Ok(Ga)
    "ma" -> Ok(Ma)
    "pa" -> Ok(Pa)
    "dha" -> Ok(Dha)
    "ni" -> Ok(Ni)
    _ -> Error("unrecognized svara: " <> tok)
  }
}

/// Parse a list of notation tokens, keeping each one's octave marker
/// (`#(Swara, Variant, Int)`) — needed so the ascending/descending check in
/// `validate_and_build_raga` can tell a closing `"sa'"` (tāra, one octave
/// up) from a same-octave `"sa"`, since `Swara` ordinals alone wrap back to
/// 0 at the top of the scale.
fn parse_pitch_list_full(
  tokens: List(String),
) -> Result(List(#(Swara, Variant, Int)), String) {
  list.try_map(tokens, parse_swara_token)
}

fn drop_octave(pairs: List(#(Swara, Variant, Int))) -> List(#(Swara, Variant)) {
  list.map(pairs, fn(p) { #(p.0, p.1) })
}

/// Octave-aware scale-degree ordinal (`swara_ordinal` plus 7 per octave)
/// used only for the ascending/descending check.
fn octave_ordinal(p: #(Swara, Variant, Int)) -> Int {
  swara_ordinal(p.0) + p.2 * 7
}

fn is_monotonic(xs: List(Int), ascending: Bool) -> Bool {
  case xs {
    [] -> True
    [_] -> True
    [a, b, ..rest] ->
      case ascending {
        True -> a <= b && is_monotonic([b, ..rest], True)
        False -> a >= b && is_monotonic([b, ..rest], False)
      }
  }
}

type RawRagaDef {
  RawRagaDef(
    name: String,
    thaat: String,
    aroha: List(String),
    avaroha: List(String),
    vadi: String,
    samvadi: String,
    time: String,
    mood: String,
  )
}

fn raga_def_decoder() -> decode.Decoder(RawRagaDef) {
  use name <- decode.field("name", decode.string)
  use thaat <- decode.field("thaat", decode.string)
  use aroha <- decode.field("aroha", decode.list(decode.string))
  use avaroha <- decode.field("avaroha", decode.list(decode.string))
  use vadi <- decode.field("vadi", decode.string)
  use samvadi <- decode.field("samvadi", decode.string)
  use time <- decode.optional_field("time", "any", decode.string)
  use mood <- decode.optional_field("mood", "", decode.string)
  decode.success(RawRagaDef(
    name,
    thaat,
    aroha,
    avaroha,
    vadi,
    samvadi,
    time,
    mood,
  ))
}

fn require_nonempty(pairs: List(a), what: String) -> Result(Nil, String) {
  case pairs {
    [] -> Error(what <> " must not be empty")
    _ -> Ok(Nil)
  }
}

fn require_in_scale(
  pairs: List(#(Swara, Variant)),
  scale: List(#(Swara, Variant)),
  thaat_name: String,
) -> Result(Nil, String) {
  list.try_each(pairs, fn(p) {
    case list.contains(scale, p) {
      True -> Ok(Nil)
      False ->
        Error(
          swara_label(p.0)
          <> " "
          <> variant_label(p.1)
          <> " is not in "
          <> thaat_name
          <> "'s note set",
        )
    }
  })
}

fn validate_and_build_raga(raw: RawRagaDef) -> Result(Raga, String) {
  case string.trim(raw.name) {
    "" -> Error("name must not be empty")
    _ -> {
      use thaat <- result.try(thaat_by_name(raw.thaat))
      use aroha_full <- result.try(parse_pitch_list_full(raw.aroha))
      use avaroha_full <- result.try(parse_pitch_list_full(raw.avaroha))
      use vadi <- result.try(parse_bare_swara(raw.vadi))
      use samvadi <- result.try(parse_bare_swara(raw.samvadi))
      let aroha = drop_octave(aroha_full)
      let avaroha = drop_octave(avaroha_full)
      let scale = raga.thaat_swaras(thaat)
      let thaat_name = raga.thaat_label(thaat)
      use _ <- result.try(require_nonempty(aroha, "aroha"))
      use _ <- result.try(require_nonempty(avaroha, "avaroha"))
      use _ <- result.try(require_in_scale(aroha, scale, thaat_name))
      use _ <- result.try(require_in_scale(avaroha, scale, thaat_name))
      use _ <- result.try(
        case is_monotonic(list.map(aroha_full, octave_ordinal), True) {
          True -> Ok(Nil)
          False -> Error("aroha must be ascending")
        },
      )
      use _ <- result.try(
        case is_monotonic(list.map(avaroha_full, octave_ordinal), False) {
          True -> Ok(Nil)
          False -> Error("avaroha must be descending")
        },
      )
      let all_notes = list.append(aroha, avaroha)
      use _ <- result.try(case list.any(all_notes, fn(p) { p.0 == vadi }) {
        True -> Ok(Nil)
        False -> Error("vadi is not one of the raga's own notes")
      })
      use _ <- result.try(case list.any(all_notes, fn(p) { p.0 == samvadi }) {
        True -> Ok(Nil)
        False -> Error("samvadi is not one of the raga's own notes")
      })
      Ok(Raga(
        raw.name,
        thaat,
        aroha,
        avaroha,
        vadi,
        samvadi,
        time_of_day_by_name(raw.time),
        raw.mood,
      ))
    }
  }
}

/// Parse and validate a hand-authored rāga definition:
/// `{"name","thaat","aroha":[...],"avaroha":[...],"vadi","samvadi","time","mood"}`
/// (notation per `parse_swara_token`). Validates every note is in the
/// named thaat's note set, that āroha is ascending and avaroha descending
/// (by scale degree), that vādi/samvādi are among the rāga's own notes, and
/// that `name` is non-empty — `Error` names exactly which rule failed.
pub fn parse_raga_json(text: String) -> Result(Raga, String) {
  use raw <- result.try(
    json.parse(text, raga_def_decoder())
    |> result.map_error(fn(e) { "JSON parse error: " <> string.inspect(e) }),
  )
  validate_and_build_raga(raw)
}

/// One line of `parse_sargam` — one tāla cycle: tokens are swara notation
/// (see `parse_swara_token`; octave markers apply), `-` for a rest (skips
/// one mātrā, emits nothing), or `~` to extend the immediately preceding
/// note's duration by one more mātrā. Every emitted swara is checked
/// against `scale_of(r)`; the first violation fails the whole parse.
fn parse_sargam_line(
  line: String,
  cycle_no: Int,
  r: Raga,
) -> Result(List(Note), String) {
  let tokens =
    line |> string.trim |> string.split(" ") |> list.filter(fn(t) { t != "" })
  let scale = scale_of(r)
  use #(_, rev_notes) <- result.try(
    list.try_fold(tokens, #(1, []), fn(acc, tok) {
      let #(matra, notes) = acc
      case tok {
        "-" -> Ok(#(matra + 1, notes))
        "~" ->
          case notes {
            [] ->
              Error(
                "cycle "
                <> int.to_string(cycle_no + 1)
                <> ": '~' with no preceding note",
              )
            [last, ..rest] ->
              Ok(
                #(matra + 1, [Note(..last, duration: last.duration + 1), ..rest]),
              )
          }
        _ -> {
          use #(swara, variant, octave) <- result.try(parse_swara_token(tok))
          case list.contains(scale, #(swara, variant)) {
            False ->
              Error(
                "cycle "
                <> int.to_string(cycle_no + 1)
                <> ": "
                <> tok
                <> " is not in "
                <> r.name
                <> "'s scale",
              )
            True ->
              Ok(
                #(matra + 1, [
                  Note(swara, variant, octave, matra, 1, "sargam"),
                  ..notes
                ]),
              )
          }
        }
      }
    }),
  )
  Ok(list.reverse(rev_notes))
}

/// Parse a whole sargam-notation composition (one tāla cycle per non-blank
/// line) against rāga `r`, returning the flat, cursor-ordered note list
/// ready for `bandish_of_notes`.
pub fn parse_sargam(text: String, r: Raga) -> Result(List(Note), String) {
  let lines =
    string.split(text, "\n") |> list.filter(fn(l) { string.trim(l) != "" })
  use grouped <- result.try(
    list.index_map(lines, fn(l, i) { #(l, i) })
    |> list.try_map(fn(li) { parse_sargam_line(li.0, li.1, r) }),
  )
  Ok(list.flatten(grouped))
}

// ---------------------------------------------------------------------------
// 2. Sound — pure Gleam, three-voice WAV.
// ---------------------------------------------------------------------------

/// Just-intonation ratio of `swara`/`variant` relative to Sa (at octave 0).
pub fn ratio(swara: Swara, variant: Variant) -> Float {
  case swara, variant {
    Sa, _ -> 1.0
    Re, Komal -> 16.0 /. 15.0
    Re, _ -> 9.0 /. 8.0
    Ga, Komal -> 6.0 /. 5.0
    Ga, _ -> 5.0 /. 4.0
    Ma, Tivra -> 45.0 /. 32.0
    Ma, _ -> 4.0 /. 3.0
    Pa, _ -> 3.0 /. 2.0
    Dha, Komal -> 8.0 /. 5.0
    Dha, _ -> 5.0 /. 3.0
    Ni, Komal -> 9.0 /. 5.0
    Ni, _ -> 15.0 /. 8.0
  }
}

fn power_of_two(n: Int) -> Float {
  case n {
    0 -> 1.0
    n if n > 0 -> 2.0 *. power_of_two(n - 1)
    n -> power_of_two(n + 1) /. 2.0
  }
}

/// The frequency, in Hz, of `swara`/`variant` at `octave` (-1 mandra, 0
/// madhya, +1 tāra, ...) given a tonic (Sa) of `sa_hz`.
pub fn frequency(
  swara: Swara,
  variant: Variant,
  octave: Int,
  sa_hz: Float,
) -> Float {
  ratio(swara, variant) *. sa_hz *. power_of_two(octave)
}

/// `sin`, via Erlang's `math` module. Not a foreign NIF and not
/// Bevy/Graphite: pure Erlang/OTP standard library, permitted by the
/// Zero-Muda rule the same way `crypto`/`math` externals are used elsewhere
/// in this codebase (see `uos_swarm_ffi.erl`'s `sha256_hex`/`hmac_hex`).
@external(erlang, "math", "sin")
fn erl_sin(x: Float) -> Float

const pi = 3.141592653589793

fn db_to_gain(db: Float) -> Float {
  float.power(10.0, db /. 20.0) |> result.unwrap(1.0)
}

/// Per-voice dynamics multiplier applied before the final mix (see
/// `to_wav_mixed`).
pub type MixLevels {
  MixLevels(melody: Float, drone: Float, percussion: Float)
}

pub fn default_mix() -> MixLevels {
  MixLevels(1.0, 1.0, 1.0)
}

/// Harmony-modulated dynamics: `index < 0.5` -> drone louder, melody
/// softer (a swarm out of tune with itself sings quietly, under a heavier
/// drone); `index >= 0.8` -> brighter (melody and percussion lifted); the
/// nominal band in between uses `default_mix`.
pub fn mix_for_harmony(h: Harmony) -> MixLevels {
  case h.index <. 0.5 {
    True -> MixLevels(0.7, 1.4, 1.0)
    False ->
      case h.index >=. 0.8 {
        True -> MixLevels(1.15, 0.9, 1.1)
        False -> default_mix()
      }
  }
}

/// For `sing-state`: the rāga and dynamics to sing the current board
/// harmony in — `index < 0.5` -> Malkauns, drone louder, melody softer;
/// `index >= 0.8` -> brighter, Bilawal by day / Durga by night (day
/// approximated as prahar 3..6, i.e. UTC hours 6..17); otherwise the
/// ordinary rāga-for-the-hour at default dynamics.
pub fn raga_and_mix_for_state(h: Harmony) -> #(Raga, MixLevels) {
  case h.index <. 0.5 {
    True -> #(raga.malkauns(), MixLevels(0.7, 1.4, 1.0))
    False ->
      case h.index >=. 0.8 {
        True -> {
          let daytime = h.prahar >= 3 && h.prahar <= 6
          let bright = case daytime {
            True -> raga.bilawal()
            False -> raga.durga()
          }
          #(bright, MixLevels(1.15, 0.9, 1.1))
        }
        False -> #(raga_for_harmony(h, "Nominal"), default_mix())
      }
  }
}

fn envelope(i: Int, total: Int, attack: Int, release: Int) -> Float {
  let attack_f = case i < attack {
    True -> int.to_float(i) /. int.to_float(attack)
    False -> 1.0
  }
  let remaining = total - i - 1
  let release_f = case remaining < release {
    True -> int.to_float(remaining) /. int.to_float(release)
    False -> 1.0
  }
  float.min(attack_f, release_f) |> float.max(0.0) |> float.min(1.0)
}

/// Melody timbre: fundamental + 0.35×2nd + 0.15×3rd harmonic (softer than a
/// bare sine), normalized to unit peak.
fn melody_wave(freq: Float, t: Float) -> Float {
  let w = 2.0 *. pi *. freq *. t
  { erl_sin(w) +. 0.35 *. erl_sin(2.0 *. w) +. 0.15 *. erl_sin(3.0 *. w) }
  /. 1.5
}

fn melody_loop(
  i: Int,
  dur: Int,
  freq: Float,
  sample_rate: Int,
  attack: Int,
  release: Int,
  acc: List(Float),
) -> List(Float) {
  case i >= dur {
    True -> list.reverse(acc)
    False -> {
      let t = int.to_float(i) /. int.to_float(sample_rate)
      let env = envelope(i, dur, attack, release)
      melody_loop(i + 1, dur, freq, sample_rate, attack, release, [
        melody_wave(freq, t) *. env,
        ..acc
      ])
    }
  }
}

/// Melody voice samples for one note: silence for a non-positive duration
/// (a rest), otherwise `melody_wave` with a 15ms attack / 40ms release.
fn melody_note_samples(
  n: Note,
  dur_samples: Int,
  sample_rate: Int,
  sa_hz: Float,
) -> List(Float) {
  case dur_samples <= 0 {
    True -> []
    False -> {
      let freq = frequency(n.swara, n.variant, n.octave, sa_hz)
      let attack = int.max(float.round(0.015 *. int.to_float(sample_rate)), 1)
      let release = int.max(float.round(0.04 *. int.to_float(sample_rate)), 1)
      melody_loop(0, dur_samples, freq, sample_rate, attack, release, [])
    }
  }
}

fn pad_or_trim(xs: List(Float), n: Int) -> List(Float) {
  let len = list.length(xs)
  case len >= n {
    True -> list.take(xs, n)
    False -> list.append(xs, list.repeat(0.0, n - len))
  }
}

/// The melody voice for the whole piece: each `(cycle, Note)` placed at its
/// exact mātrā offset — a rest (no `Note` at some mātrā) simply leaves a
/// silent gap, so this correctly renders both `compose`d pieces (which
/// never have gaps) and `parse_sargam` pieces (which may).
fn melody_floats(
  tagged: List(#(Int, Note)),
  t: Tala,
  matra_samples_f: Float,
  sample_rate: Int,
  sa_hz: Float,
  total_samples: Int,
) -> List(Float) {
  let #(rev_chunks, _cursor) =
    list.fold(tagged, #([], 0), fn(acc, ev) {
      let #(chunks, cursor) = acc
      let #(cycle, note) = ev
      let start =
        float.round(
          int.to_float(cycle * t.matras + note.matra - 1) *. matra_samples_f,
        )
      let dur =
        int.max(float.round(int.to_float(note.duration) *. matra_samples_f), 0)
      let gap = int.max(start - cursor, 0)
      let note_chunk = melody_note_samples(note, dur, sample_rate, sa_hz)
      #([note_chunk, list.repeat(0.0, gap), ..chunks], start + dur)
    })
  list.reverse(rev_chunks) |> list.flatten |> pad_or_trim(total_samples)
}

/// Tānpūrā drone: a continuous Pa–Sa–Sa–Sa pluck pattern one octave below
/// madhya, each pluck a 1.5s-decaying tone with 0.5×2nd/0.3×3rd string
/// harmonics, at -12dB (before `gain`).
fn pluck_loop(
  i: Int,
  n: Int,
  freq: Float,
  sample_rate: Int,
  gain: Float,
  acc: List(Float),
) -> List(Float) {
  case i >= n {
    True -> list.reverse(acc)
    False -> {
      let t = int.to_float(i) /. int.to_float(sample_rate)
      let w = 2.0 *. pi *. freq *. t
      let raw =
        { erl_sin(w) +. 0.5 *. erl_sin(2.0 *. w) +. 0.3 *. erl_sin(3.0 *. w) }
        /. 1.8
      let env = float.exponential(-1.0 *. t /. 1.5)
      pluck_loop(i + 1, n, freq, sample_rate, gain, [raw *. env *. gain, ..acc])
    }
  }
}

fn drone_floats(
  r: Raga,
  total_samples: Int,
  sample_rate: Int,
  sa_hz: Float,
  gain_mult: Float,
) -> List(Float) {
  let gain = gain_mult *. db_to_gain(-12.0)
  let pluck_seconds = 2.0
  let pluck_samples =
    int.max(float.round(pluck_seconds *. int.to_float(sample_rate)), 1)
  let pattern = [Pa, Sa, Sa, Sa]
  let n_plucks = { total_samples + pluck_samples - 1 } / pluck_samples
  let hits =
    list.repeat(Nil, int.max(n_plucks, 0))
    |> list.index_map(fn(_, i) { i })
    |> list.map(fn(i) {
      let s = list_at(pattern, int.modulo(i, 4) |> result.unwrap(0), Sa)
      let pitch = nearest_in_scale(r, s)
      let freq = frequency(pitch.0, pitch.1, -1, sa_hz)
      pluck_loop(0, pluck_samples, freq, sample_rate, gain, [])
    })
  hits |> list.flatten |> pad_or_trim(total_samples)
}

/// The tānpūrā drone alone, `seconds` long, at `sample_rate`/`sa_hz`/
/// `gain` — exposed so the drone's continuous presence can be verified
/// directly, independent of the full melody+drone+percussion mix in
/// `to_wav_mixed` (percussion alone also fills every mātrā, so "energy in
/// the mix" would not by itself isolate the drone).
pub fn drone_samples(
  r: Raga,
  seconds: Float,
  sample_rate: Int,
  sa_hz: Float,
  gain: Float,
) -> List(Float) {
  let total_samples = float.round(seconds *. int.to_float(sample_rate))
  drone_floats(r, total_samples, sample_rate, sa_hz, gain)
}

/// (decay time constant τ (s), one-pole lowpass coefficient α, base gain)
/// per beat kind: a low resonant thump on sam (long τ, heavy lowpass,
/// loudest), a mid hit on tālī, and a soft high tick on khālī/ordinary
/// beats (short τ, minimal lowpass, quietest).
fn percussion_params(kind: raga.BeatKind) -> #(Float, Float, Float) {
  case kind {
    Sam -> #(0.25, 0.85, 1.0)
    Tali -> #(0.15, 0.5, 0.7)
    Khali | Ordinary -> #(0.05, 0.05, 0.4)
  }
}

fn lcg_next(seed: Int) -> Int {
  int.modulo(1_103_515_245 * seed + 12_345, 2_147_483_648) |> result.unwrap(0)
}

fn perc_loop(
  i: Int,
  n: Int,
  tau: Float,
  alpha: Float,
  gain: Float,
  sample_rate: Int,
  seed: Int,
  y_prev: Float,
  acc: List(Float),
) -> List(Float) {
  case i >= n {
    True -> list.reverse(acc)
    False -> {
      let seed2 = lcg_next(seed)
      let x = int.to_float(seed2) /. 1_073_741_824.0 -. 1.0
      let y = alpha *. y_prev +. { 1.0 -. alpha } *. x
      let t = int.to_float(i) /. int.to_float(sample_rate)
      let env = float.exponential(-1.0 *. t /. tau)
      perc_loop(i + 1, n, tau, alpha, gain, sample_rate, seed2, y, [
        y *. env *. gain,
        ..acc
      ])
    }
  }
}

fn percussion_hit(
  n: Int,
  tau: Float,
  alpha: Float,
  gain: Float,
  sample_rate: Int,
  seed: Int,
) -> List(Float) {
  perc_loop(0, n, tau, alpha, gain, sample_rate, seed, 0.0, [])
}

/// Tāla percussion: one decaying LCG-noise hit per mātrā across every
/// complete cycle `notes` spans (`cycles_used`), shaped per `beat_of_cycle`
/// classification (see `percussion_params`).
fn percussion_floats(
  t: Tala,
  cycles: Int,
  matra_samples_f: Float,
  sample_rate: Int,
  total_samples: Int,
) -> List(Float) {
  let matra_samples = int.max(float.round(matra_samples_f), 1)
  let total_matras = cycles * t.matras
  let hits =
    list.repeat(Nil, int.max(total_matras, 0))
    |> list.index_map(fn(_, i) { i + 1 })
    |> list.map(fn(beat) {
      let kind = raga.beat_of_cycle(t, beat).kind
      let #(tau, alpha, gain) = percussion_params(kind)
      let seed = 7919 * beat + 104_729
      percussion_hit(matra_samples, tau, alpha, gain, sample_rate, seed)
    })
  hits |> list.flatten |> pad_or_trim(total_samples)
}

/// 44-byte canonical RIFF/WAVE header for 16-bit mono PCM at `sample_rate`,
/// followed by `data_size` bytes of sample data.
fn wav_header(sample_rate: Int, data_size: Int) -> BitArray {
  let byte_rate = sample_rate * 1 * 16 / 8
  let block_align = 1 * 16 / 8
  <<
    "RIFF":utf8,
    { 36 + data_size }:32-little,
    "WAVE":utf8,
    "fmt ":utf8,
    16:32-little,
    1:16-little,
    1:16-little,
    sample_rate:32-little,
    byte_rate:32-little,
    block_align:16-little,
    16:16-little,
    "data":utf8,
    data_size:32-little,
  >>
}

/// Render the bandish as a 16-bit mono PCM WAV file, mixing three voices —
/// melody (softer harmonic timbre, 15/40ms attack/release), a continuous
/// tānpūrā drone (Pa-Sa-Sa-Sa, -12dB, decaying plucks), and tāla percussion
/// (a resonant thump on sam, a mid hit on tālī, a soft tick on khālī and
/// ordinary beats) — each independently gain-scaled by `mix`, summed, then
/// peak-normalized to 0.8 full scale (clip-safe: the loudest sample in the
/// output is always exactly `0.8 * 32767 ≈ 26214`, never more). Capped to
/// at most 60 seconds of audio regardless of how many cycles the piece
/// spans.
pub fn to_wav_mixed(
  b: Bandish,
  sample_rate: Int,
  sa_hz: Float,
  mix: MixLevels,
) -> BitArray {
  let tagged = notes_with_cycle(b.notes)
  let cycles = cycles_used(b.notes)
  let matra_seconds = 60.0 /. int.to_float(int.max(b.tempo_bpm, 1))
  let matra_samples_f = matra_seconds *. int.to_float(sample_rate)
  let piece_seconds =
    float.min(
      int.to_float(cycles) *. int.to_float(b.tala.matras) *. matra_seconds,
      60.0,
    )
  let total_samples = float.round(piece_seconds *. int.to_float(sample_rate))
  case total_samples <= 0 {
    True -> wav_header(sample_rate, 0)
    False -> {
      let melody =
        melody_floats(
          tagged,
          b.tala,
          matra_samples_f,
          sample_rate,
          sa_hz,
          total_samples,
        )
        |> list.map(fn(x) { x *. mix.melody })
      let drone =
        drone_floats(b.raga, total_samples, sample_rate, sa_hz, mix.drone)
      let perc =
        percussion_floats(
          b.tala,
          cycles,
          matra_samples_f,
          sample_rate,
          total_samples,
        )
        |> list.map(fn(x) { x *. mix.percussion })
      let mixed =
        list.map2(list.map2(melody, drone, fn(a, c) { a +. c }), perc, fn(a, c) {
          a +. c
        })
      let peak =
        list.fold(mixed, 0.0, fn(acc, x) {
          float.max(acc, float.absolute_value(x))
        })
      let scale = case peak <=. 0.0 {
        True -> 0.0
        False -> 0.8 *. 32_767.0 /. peak
      }
      let pcm_chunks =
        list.map(mixed, fn(x) {
          let clamped = int.clamp(float.round(x *. scale), -32_768, 32_767)
          <<clamped:16-little>>
        })
      let pcm = bit_array.concat(pcm_chunks)
      bit_array.append(wav_header(sample_rate, bit_array.byte_size(pcm)), pcm)
    }
  }
}

/// `to_wav_mixed` at `default_mix` — melody, drone and percussion all at
/// unity gain.
pub fn to_wav(b: Bandish, sample_rate: Int, sa_hz: Float) -> BitArray {
  to_wav_mixed(b, sample_rate, sa_hz, default_mix())
}

// ---------------------------------------------------------------------------
// 2b. MIDI export (Standard MIDI File, format 0).
// ---------------------------------------------------------------------------

const ticks_per_matra = 120

fn semitone_offset(s: Swara, v: Variant) -> Int {
  let base = case s {
    Sa -> 0
    Re -> 2
    Ga -> 4
    Ma -> 5
    Pa -> 7
    Dha -> 9
    Ni -> 11
  }
  case v {
    Shuddha -> base
    Komal -> base - 1
    Tivra -> base + 1
  }
}

/// MIDI note number for `swara`/`variant`/`octave` relative to `sa_midi`
/// (the note number for madhya Sa), 12-TET approximation: komal = -1
/// semitone, tīvra = +1, clamped to the valid MIDI range 0..127.
pub fn midi_note_number(
  swara: Swara,
  variant: Variant,
  octave: Int,
  sa_midi: Int,
) -> Int {
  int.clamp(sa_midi + semitone_offset(swara, variant) + octave * 12, 0, 127)
}

fn vlq_digits(n: Int, acc: List(Int)) -> List(Int) {
  let digit = int.bitwise_and(n, 0x7F)
  let rest = int.bitwise_shift_right(n, 7)
  case rest <= 0 {
    True -> [digit, ..acc]
    False -> vlq_digits(rest, [digit, ..acc])
  }
}

fn set_continuation(digits: List(Int)) -> List(Int) {
  case digits {
    [] -> []
    [last] -> [last]
    [d, ..rest] -> [int.bitwise_or(d, 0x80), ..set_continuation(rest)]
  }
}

/// MIDI variable-length quantity encoding of a non-negative delta-time.
fn vlq(n: Int) -> BitArray {
  vlq_digits(int.max(n, 0), [])
  |> set_continuation
  |> list.map(fn(b) { <<b:8>> })
  |> bit_array.concat
}

type MidiEvent {
  MidiEvent(tick: Int, bytes: BitArray)
}

fn note_on(tick: Int, channel: Int, note: Int, velocity: Int) -> MidiEvent {
  MidiEvent(tick, <<{ 0x90 + channel }:8, note:8, velocity:8>>)
}

fn note_off(tick: Int, channel: Int, note: Int) -> MidiEvent {
  MidiEvent(tick, <<{ 0x80 + channel }:8, note:8, 0:8>>)
}

fn melody_events(
  tagged: List(#(Int, Note)),
  t: Tala,
  sa_midi: Int,
) -> List(MidiEvent) {
  list.flat_map(tagged, fn(ev) {
    let #(cycle, n) = ev
    let start = { cycle * t.matras + n.matra - 1 } * ticks_per_matra
    let dur = int.max(n.duration * ticks_per_matra, 1)
    let pitch = midi_note_number(n.swara, n.variant, n.octave, sa_midi)
    [note_on(start, 0, pitch, 90), note_off(start + dur, 0, pitch)]
  })
}

fn drone_events(r: Raga, total_matras: Int, sa_midi: Int) -> List(MidiEvent) {
  let pluck_matras = 2
  let n_plucks = { total_matras + pluck_matras - 1 } / pluck_matras
  let pattern = [Pa, Sa, Sa, Sa]
  list.repeat(Nil, int.max(n_plucks, 0))
  |> list.index_map(fn(_, i) { i })
  |> list.flat_map(fn(i) {
    let s = list_at(pattern, int.modulo(i, 4) |> result.unwrap(0), Sa)
    let pitch_pair = nearest_in_scale(r, s)
    let pitch = midi_note_number(pitch_pair.0, pitch_pair.1, -1, sa_midi)
    let start = i * pluck_matras * ticks_per_matra
    let dur = pluck_matras * ticks_per_matra
    [note_on(start, 1, pitch, 70), note_off(start + dur, 1, pitch)]
  })
}

fn percussion_note_number(kind: raga.BeatKind) -> Int {
  case kind {
    Sam -> 36
    Tali -> 38
    Khali | Ordinary -> 42
  }
}

fn percussion_events(t: Tala, total_matras: Int) -> List(MidiEvent) {
  list.repeat(Nil, int.max(total_matras, 0))
  |> list.index_map(fn(_, i) { i + 1 })
  |> list.flat_map(fn(beat) {
    let kind = raga.beat_of_cycle(t, beat).kind
    let pitch = percussion_note_number(kind)
    let start = { beat - 1 } * ticks_per_matra
    let dur = int.max(ticks_per_matra / 4, 1)
    [note_on(start, 9, pitch, 100), note_off(start + dur, 9, pitch)]
  })
}

fn tempo_event(tempo_bpm: Int) -> MidiEvent {
  let usec = 60_000_000 / int.max(tempo_bpm, 1)
  MidiEvent(0, <<0xFF:8, 0x51:8, 0x03:8, usec:24>>)
}

fn program_change_event(channel: Int, program: Int) -> MidiEvent {
  MidiEvent(0, <<{ 0xC0 + channel }:8, program:8>>)
}

fn end_of_track_event(tick: Int) -> MidiEvent {
  MidiEvent(tick, <<0xFF:8, 0x2F:8, 0x00:8>>)
}

fn track_bytes(events: List(MidiEvent)) -> BitArray {
  let sorted = list.sort(events, fn(a, b) { int.compare(a.tick, b.tick) })
  let #(chunks, _last_tick) =
    list.fold(sorted, #([], 0), fn(acc, ev) {
      let #(chunks, last) = acc
      let delta = int.max(ev.tick - last, 0)
      #([bit_array.append(vlq(delta), ev.bytes), ..chunks], ev.tick)
    })
  bit_array.concat(list.reverse(chunks))
}

/// Standard MIDI File, format 0, one track, `ticks_per_matra` (120) ticks
/// per mātrā: a tempo meta event (from `b.tempo_bpm`), a program-change to
/// 104 on channel 1 (the tānpūrā drone), then note-on/note-off pairs for
/// melody (channel 0), drone (channel 1, one octave below madhya, Pa-Sa-
/// Sa-Sa), and tāla percussion (channel 9/10, GM notes 36/38/42 for
/// sam/tālī/khālī-and-ordinary beats) — pitches are just-intonation
/// approximated to 12-TET relative to `sa_midi_note` (`midi_note_number`:
/// komal -1 semitone, tīvra +1).
pub fn to_midi(b: Bandish, sa_midi_note: Int) -> BitArray {
  let tagged = notes_with_cycle(b.notes)
  let cycles = cycles_used(b.notes)
  let total_matras = cycles * b.tala.matras
  let events =
    [tempo_event(b.tempo_bpm), program_change_event(1, 104)]
    |> list.append(melody_events(tagged, b.tala, sa_midi_note))
    |> list.append(drone_events(b.raga, total_matras, sa_midi_note))
    |> list.append(percussion_events(b.tala, total_matras))
  let last_tick = list.fold(events, 0, fn(acc, ev) { int.max(acc, ev.tick) })
  let all_events =
    list.append(events, [end_of_track_event(last_tick + ticks_per_matra)])
  let track = track_bytes(all_events)
  let header = <<"MThd":utf8, 6:32, 0:16, 1:16, ticks_per_matra:16>>
  let track_header = <<"MTrk":utf8, bit_array.byte_size(track):32>>
  bit_array.append(bit_array.append(header, track_header), track)
}

// ---------------------------------------------------------------------------
// 3. Harmony with the universe (sāmañjasya).
// ---------------------------------------------------------------------------

/// A measurement of how well the swarm's own board activity is in harmony
/// with itself and with the time of day: `index` in `0..1`, the mean of the
/// seven bounded consonance measures listed on `harmony`; `consonant`/
/// `dissonant` name which of those measures scored `>= 0.8` / `< 0.5`;
/// `prahar` is the 3-hour watch of the day (1..8); `raga_for_hour` is the
/// name of the rāga traditionally sung at that hour.
pub type Harmony {
  Harmony(
    index: Float,
    consonant: List(String),
    dissonant: List(String),
    prahar: Int,
    raga_for_hour: String,
  )
}

fn utc_hour(now_us: Int) -> Int {
  let hours_since_epoch = now_us / 1_000_000 / 3600
  int.modulo(hours_since_epoch, 24) |> result.unwrap(0)
}

/// The 3-hour prahar (1..8) that UTC `hour` (0..23) falls in.
pub fn prahar_of_hour(hour: Int) -> Int {
  hour / 3 + 1
}

/// The rāga traditionally sung at `hour` (0..23, UTC): Bhairav 4–7,
/// Bilawal/Durga 7–13 (rendered here as Durga, per `raga.raga_of_mode`'s
/// own night-vs-day split), Yaman 16–22, Malkauns 22–4 (wraps past
/// midnight), Bhairavi otherwise as the closing rāga.
pub fn raga_for_hour(hour: Int) -> Raga {
  case hour >= 4 && hour < 7 {
    True -> raga.bhairav()
    False ->
      case hour >= 7 && hour < 13 {
        True -> raga.durga()
        False ->
          case hour >= 16 && hour < 22 {
            True -> raga.yaman()
            False ->
              case hour >= 22 || hour < 4 {
                True -> raga.malkauns()
                False -> raga.bhairavi()
              }
          }
      }
  }
}

pub fn raga_name_for_hour(hour: Int) -> String {
  raga_for_hour(hour).name
}

/// The 3-hour prahar (1..8) that `now_us` (microseconds since the Unix
/// epoch, UTC) falls in.
pub fn prahar(now_us: Int) -> Int {
  prahar_of_hour(utc_hour(now_us))
}

fn questions_answered_ratio(messages: List(board.Message)) -> Float {
  let questions = list.filter(messages, fn(m) { m.kind == board.Question })
  case questions {
    [] -> 1.0
    _ -> {
      let answered =
        list.count(questions, fn(q) {
          list.any(messages, fn(m) {
            { m.kind == board.Answer || m.kind == board.Report }
            && m.causality.in_reply_to == Some(q.id)
          })
        })
      int.to_float(answered) /. int.to_float(list.length(questions))
    }
  }
}

fn ack_ratio(messages: List(board.Message)) -> Float {
  let addressed =
    list.filter(messages, fn(m) { m.to != "broadcast" && m.kind != board.Ack })
  case addressed {
    [] -> 1.0
    _ -> {
      let acked_ids =
        messages
        |> list.filter(fn(m) { m.kind == board.Ack })
        |> list.filter_map(fn(m) {
          option.to_result(m.causality.in_reply_to, Nil)
        })
      let acked_count =
        list.count(addressed, fn(m) { list.contains(acked_ids, m.id) })
      int.to_float(acked_count) /. int.to_float(list.length(addressed))
    }
  }
}

fn andon_green_ratio(messages: List(board.Message)) -> Float {
  let andons = list.filter(messages, fn(m) { m.kind == board.Andon })
  case andons {
    [] -> 1.0
    _ -> {
      let green =
        list.count(andons, fn(m) { andon_color(m.payload) == "green" })
      int.to_float(green) /. int.to_float(list.length(andons))
    }
  }
}

fn dead_letter_absence(messages: List(board.Message)) -> Float {
  let dead = list.count(messages, fn(m) { m.kind == board.DeadLetter })
  case dead {
    0 -> 1.0
    _ -> float.max(0.0, 1.0 -. int.to_float(dead) *. 0.2)
  }
}

fn heartbeat_presence(messages: List(board.Message)) -> Float {
  let senders = messages |> list.map(fn(m) { m.from.id }) |> list.unique
  case senders {
    [] -> 1.0
    _ -> {
      let beating =
        messages
        |> list.filter(fn(m) { m.kind == board.Heartbeat })
        |> list.map(fn(m) { m.from.id })
        |> list.unique
      let present = list.count(senders, fn(s) { list.contains(beating, s) })
      int.to_float(present) /. int.to_float(list.length(senders))
    }
  }
}

fn causal_gap_measure(messages: List(board.Message)) -> Float {
  let ids = list.map(messages, fn(m) { m.id })
  let gaps = board.causal_gaps(messages)
  let unresolved =
    messages
    |> list.filter_map(fn(m) { option.to_result(m.causality.in_reply_to, Nil) })
    |> list.filter(fn(target) {
      !list.contains(ids, target) && !list.contains(gaps, target)
    })
  let documented = list.length(gaps)
  let bad = list.length(unresolved)
  case documented + bad {
    0 -> 1.0
    total -> int.to_float(documented) /. int.to_float(total)
  }
}

/// Fraction of messages posted in the same prahar as `now_us` — a bounded
/// measure of how temporally clustered ("in tune with the hour") the
/// swarm's recent chatter is.
fn time_alignment(messages: List(board.Message), now_us: Int) -> Float {
  case messages {
    [] -> 1.0
    _ -> {
      let now_prahar = prahar(now_us)
      let aligned =
        list.count(messages, fn(m) { prahar(m.ts_us) == now_prahar })
      int.to_float(aligned) /. int.to_float(list.length(messages))
    }
  }
}

/// Measure the board's harmony at `now_us`: `index` is the mean of seven
/// bounded `0..1` consonance measures — `questions_answered` (Answer/Report
/// in reply to a Question), `acknowledgement` (Ack ratio for messages
/// addressed to a specific agent), `andon_green_share` (share of Andon
/// states that are green), `dead_letter_absence`, `heartbeat_presence` (per
/// active sender), `causal_gaps_documented` (documented `causal_gap`
/// payloads versus replies to unknown ids), and `time_alignment` (messages
/// posted in the current prahar). `consonant`/`dissonant` list which of
/// those seven measures were `>= 0.8` / `< 0.5` by name.
pub fn harmony(messages: List(board.Message), now_us: Int) -> Harmony {
  let measures = [
    #("questions_answered", questions_answered_ratio(messages)),
    #("acknowledgement", ack_ratio(messages)),
    #("andon_green_share", andon_green_ratio(messages)),
    #("dead_letter_absence", dead_letter_absence(messages)),
    #("heartbeat_presence", heartbeat_presence(messages)),
    #("causal_gaps_documented", causal_gap_measure(messages)),
    #("time_alignment", time_alignment(messages, now_us)),
  ]
  let total = list.fold(measures, 0.0, fn(acc, m) { acc +. m.1 })
  let index = total /. int.to_float(list.length(measures))
  let consonant =
    measures |> list.filter(fn(m) { m.1 >=. 0.8 }) |> list.map(fn(m) { m.0 })
  let dissonant =
    measures |> list.filter(fn(m) { m.1 <. 0.5 }) |> list.map(fn(m) { m.0 })
  let hour = utc_hour(now_us)
  Harmony(
    index,
    consonant,
    dissonant,
    prahar_of_hour(hour),
    raga_name_for_hour(hour),
  )
}

/// The rāga to compose in, given a measured `Harmony` and an operating
/// `mode`: `"Emergency"` always gets Bhairavi (the closing rāga, sung to
/// calm); an index under 0.5 gets Malkauns (the deep-night rāga, for a
/// swarm badly out of tune with itself); otherwise the rāga for the hour
/// the harmony was measured at.
pub fn raga_for_harmony(h: Harmony, mode: String) -> Raga {
  case mode {
    "Emergency" -> raga.bhairavi()
    _ ->
      case h.index <. 0.5 {
        True -> raga.malkauns()
        False -> raga_by_name(h.raga_for_hour)
      }
  }
}

// ---------------------------------------------------------------------------
// 4. Growth in harmony (capabilities and intelligence).
// ---------------------------------------------------------------------------

/// A record of one capability-growth step: how many modules/tests/adopted
/// proposals it represents, the fraction of `trials` that were verified,
/// the harmony index before and after, and whether growth stayed `in_harmony`
/// (did not lower harmony beyond tolerance).
pub type Growth {
  Growth(
    modules: Int,
    tests: Int,
    adopted_proposals: Int,
    verified_ratio: Float,
    harmony_before: Float,
    harmony_after: Float,
    in_harmony: Bool,
  )
}

/// Build a `Growth` record from a before/after harmony pair and the raw
/// counts of the step. `in_harmony` is `after.index >= before.index - 0.05`
/// — growth must not lower harmony beyond a small tolerance.
pub fn growth(
  before: Harmony,
  after: Harmony,
  modules: Int,
  tests: Int,
  adopted: Int,
  verified: Int,
  trials: Int,
) -> Growth {
  let verified_ratio = case trials <= 0 {
    True -> 0.0
    False -> int.to_float(verified) /. int.to_float(trials)
  }
  Growth(
    modules,
    tests,
    adopted,
    verified_ratio,
    before.index,
    after.index,
    after.index >=. before.index -. 0.05,
  )
}

/// The evolve loop (`evolve.record`, wired in by the integrator) is
/// expected to adopt a growth proposal only when this gate passes: `Ok(Nil)`
/// when `after.index >= before.index - 0.05`, `Error` with an explanation
/// otherwise.
pub fn harmony_gate(before: Harmony, after: Harmony) -> Result(Nil, String) {
  case after.index >=. before.index -. 0.05 {
    True -> Ok(Nil)
    False ->
      Error(
        "harmony gate failed: index dropped from "
        <> float.to_string(before.index)
        <> " to "
        <> float.to_string(after.index)
        <> " (tolerance 0.05) — the evolve loop must not adopt this proposal",
      )
  }
}
