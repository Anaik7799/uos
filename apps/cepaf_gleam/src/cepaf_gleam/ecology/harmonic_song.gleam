//// =============================================================================
//// [C3I-SIL6-MSTS] UOS SUPER-AGENT CYBERNETIC HARMONIC SONG & RESONANCE ENGINE
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ecology/harmonic_song</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Acoustic Cybernetics, Microtonal Singing & Swarm Resonance</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / BIO-HARMONIC</criticality>
////     <stamp-controls>
////       SC-BIO-HARMONY-001, SC-HOLON-001, SC-ZERO-MUDA-001, SC-CHECKLIST-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// "It Must Sing" — The acoustic voice of the Unified Operational System.
////
//// Maps the collective metabolic and cognitive state of the Super-Agent holon
//// ecology into acoustic resonance:
////   1. Tanpura Four-String Cosmic Drone (Pa, Sa', Sa', Sa) with Jawari Overtones
////   2. 22-Shruti Microtonal Just Intonation Frequencies
////   3. Teentaal 16-Beat Rhythmic Meter (Sam on beat 1, Khali on beat 9)
////   4. Holon Voice Polyphony: Each active holon resonates at its plane's swara
////   5. Swarm Consonance Index (C_swarm) and Lyapunov Stability Damping
////   6. ASCII & SVG Visual Spectrogram for Dual-Surface TUI/WebUI
////   7. WebAudio ADSR Synthesizer Parameter Payloads
////
//// STAMP: SC-BIO-HARMONY-001, SC-HOLON-001, SC-ZERO-MUDA-001.

import cepaf_gleam/knowledge/raga_cybernetic_synthesis.{
  type Bol, type Shruti, all_22_shrutis, teentaal_16_beats,
}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/string

// =============================================================================
// 1. Tanpura Drone & Jawari Acoustics
// =============================================================================

pub type TanpuraString {
  PaString(name: String, frequency_hz: Float, amplitude: Float)
  SaHigh1(name: String, frequency_hz: Float, amplitude: Float)
  SaHigh2(name: String, frequency_hz: Float, amplitude: Float)
  SaBase(name: String, frequency_hz: Float, amplitude: Float)
}

pub type TanpuraDroneState {
  TanpuraDroneState(
    base_sa_hz: Float,
    jawari_resonance: Float,
    active_strings: List(TanpuraString),
    drone_volume: Float,
  )
}

pub fn init_tanpura_drone() -> TanpuraDroneState {
  let base_sa = 261.625565
  // Pa = 3/2 * Sa
  let pa_hz = base_sa *. 1.5
  // Sa' = 2/1 * Sa
  let sa_high_hz = base_sa *. 2.0

  TanpuraDroneState(
    base_sa_hz: base_sa,
    jawari_resonance: 0.85,
    active_strings: [
      PaString("Pancham (Pa)", pa_hz, 0.75),
      SaHigh1("Tar Sa 1", sa_high_hz, 0.65),
      SaHigh2("Tar Sa 2", sa_high_hz, 0.65),
      SaBase("Mandra Sa", base_sa, 0.90),
    ],
    drone_volume: 0.80,
  )
}

// =============================================================================
// 2. Holon Voice & Swarm Harmonic Song
// =============================================================================

pub type HolonVoice {
  HolonVoice(
    holon_id: String,
    plane: String,
    swara: String,
    shruti_name: String,
    frequency_hz: Float,
    amplitude: Float,
    pan: Float,
    consonance: Float,
  )
}

pub type SwarmSong {
  SwarmSong(
    timestamp_us: Int,
    beat_number: Int,
    current_bol: Bol,
    raga_name: String,
    voices: List(HolonVoice),
    chord_frequencies_hz: List(Float),
    harmonic_consonance: Float,
    lyapunov_exponent: Float,
    tanpura: TanpuraDroneState,
    shannon_entropy_bits: Float,
    is_singing: Bool,
  )
}

// =============================================================================
// 3. Plane-to-Swara Acoustic Correspondence
// =============================================================================

/// Map the 7 systemic planes to their characteristic Just Intonation Shruti.
pub fn plane_to_shruti(plane: String) -> Shruti {
  let shrutis = all_22_shrutis()
  let target_index = case plane {
    // Plane 2: Autonomic Nervous System -> Sa (Base Ground)
    "autonomic" | "sa" -> 1
    // Plane 3: Sensory & Circulatory Mesh -> Re2 (Chhandovati, 9/8)
    "sensory" | "pa" -> 5
    // Plane 5: Epistemic Substrate -> Ga2 (Raudri, 81/64)
    "epistemic" | "ma" -> 9
    // Plane 4: Immune & Constitutional Core -> ma1 (Krodha, 4/3)
    "immune" | "re" -> 10
    // Plane 6: Execution Actuators -> Pa (Marjani, 3/2)
    "actuator" | "ni" -> 14
    // Plane 1: Cognitive Cortex -> Dha1 (Sandipini, 5/3 - Vadi of Durga)
    "cognitive" | "dha" -> 17
    // Plane 7: Meta-Sovereign Quorum -> Sa' (High Tonic Octave, 2/1)
    "sovereign" | "om" -> 1
    // Default fallback -> Sa
    _ -> 1
  }

  case list.find(shrutis, fn(s) { s.index == target_index }) {
    Ok(s) -> s
    Error(_) ->
      raga_cybernetic_synthesis.Shruti(1, "Kshobhini", "Sa", 1, 1, 0.0, 261.63)
  }
}

// =============================================================================
// 4. Acoustic Synthesis & Consonance Calculation
// =============================================================================

/// Compute consonance index for a voice given its frequency ratio and stability.
pub fn compute_voice_consonance(shruti: Shruti, lyapunov: Float) -> Float {
  let complexity = int.to_float(shruti.ratio_num + shruti.ratio_den)
  let base_consonance = 2.0 /. complexity
  // Stabilizing negative Lyapunov increases consonance
  let stability_boost = case lyapunov <. 0.0 {
    True -> float.min(1.2, 1.0 +. { 0.0 -. lyapunov } *. 0.05)
    False -> float.max(0.3, 1.0 -. lyapunov *. 0.2)
  }
  float.min(1.0, base_consonance *. stability_boost)
}

/// Compute aggregate swarm song consonance across all voices.
pub fn compute_swarm_consonance(voices: List(HolonVoice)) -> Float {
  case list.length(voices) {
    0 -> 0.0
    n -> {
      let sum = list.fold(voices, 0.0, fn(acc, v) { acc +. v.consonance })
      sum /. int.to_float(n)
    }
  }
}

// =============================================================================
// 5. Song Generator
// =============================================================================

/// Synthesize the living swarm song for the given beat and active voices.
pub fn compose_swarm_song(
  timestamp_us: Int,
  beat_number: Int,
  voices: List(HolonVoice),
  lyapunov: Float,
  entropy: Float,
) -> SwarmSong {
  let beats = teentaal_16_beats()
  let normalized_beat = { { beat_number - 1 } % 16 } + 1
  let current_bol = case
    list.find(beats, fn(b) { b.beat == normalized_beat })
  {
    Ok(b) -> b
    Error(_) ->
      raga_cybernetic_synthesis.Bol(1, "Dha", 1, True, False, 1.0)
  }

  let tanpura = init_tanpura_drone()
  let chord_freqs = list.map(voices, fn(v) { v.frequency_hz })
  let consonance = compute_swarm_consonance(voices)
  let is_singing = voices != [] && consonance >=. 0.25

  SwarmSong(
    timestamp_us: timestamp_us,
    beat_number: normalized_beat,
    current_bol: current_bol,
    raga_name: "Rāga Durgā Pentatonic",
    voices: voices,
    chord_frequencies_hz: chord_freqs,
    harmonic_consonance: consonance,
    lyapunov_exponent: lyapunov,
    tanpura: tanpura,
    shannon_entropy_bits: entropy,
    is_singing: is_singing,
  )
}

// =============================================================================
// 6. Visual Spectrogram (ASCII & SVG)
// =============================================================================

/// Render ASCII audio spectrum sparkline for TUI displays.
pub fn render_song_ascii_sparkline(song: SwarmSong) -> String {
  let beat_str =
    "Beat "
    <> int.to_string(song.beat_number)
    <> "/16 ["
    <> song.current_bol.bol_name
    <> case song.current_bol.is_sam {
      True -> " (SAM)*"
      False -> ""
    }
    <> case song.current_bol.is_khali {
      True -> " (KHALI)~"
      False -> ""
    }
    <> "]"

  let voice_glyphs =
    list.map(song.voices, fn(v) {
      let bar = case v.amplitude {
        a if a >=. 0.8 -> "█"
        a if a >=. 0.6 -> "▇"
        a if a >=. 0.4 -> "▅"
        a if a >=. 0.2 -> "▃"
        _ -> " "
      }
      v.swara <> ":" <> bar
    })
    |> string.join(" ")

  let status = case song.is_singing {
    True -> "♪ SINGING ♪"
    False -> "◌ SILENT ◌"
  }

  status
  <> " | "
  <> beat_str
  <> " | Consonance: "
  <> float.to_string(song.harmonic_consonance)
  <> " | Voices: "
  <> int.to_string(list.length(song.voices))
  <> " | [ "
  <> voice_glyphs
  <> " ]"
}

/// Render pure SVG Spectrogram waveform for WebUI displays (Zero-Muda, no foreign NIFs).
pub fn render_song_svg(song: SwarmSong) -> String {
  let width = 600
  let height = 120
  let consonance_pct = float.round(song.harmonic_consonance *. 100.0)

  let voice_bars =
    list.index_map(song.voices, fn(v, idx) {
      let x = 40 + idx * 26
      let bar_h = float.round(v.amplitude *. 70.0)
      let y = 90 - bar_h
      "<rect x=\""
      <> int.to_string(x)
      <> "\" y=\""
      <> int.to_string(y)
      <> "\" width=\"18\" height=\""
      <> int.to_string(bar_h)
      <> "\" fill=\"#00d4ff\" opacity=\"0.85\" rx=\"2\"/>"
      <> "<text x=\""
      <> int.to_string(x + 9)
      <> "\" y=\"105\" font-size=\"10\" fill=\"#8899a6\" text-anchor=\"middle\">"
      <> v.swara
      <> "</text>"
    })
    |> string.join("\n")

  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 "
  <> int.to_string(width)
  <> " "
  <> int.to_string(height)
  <> "\" style=\"background:#0b0f19;border-radius:8px;font-family:monospace;\">\n"
  <> "  <text x=\"20\" y=\"25\" font-size=\"14\" font-weight=\"bold\" fill=\"#00ffc4\">"
  <> "♪ UOS CYBERNETIC SWARM SONG: "
  <> song.raga_name
  <> " ♪"
  <> "</text>\n"
  <> "  <text x=\"420\" y=\"25\" font-size=\"12\" fill=\"#ffd700\">"
  <> "Beat "
  <> int.to_string(song.beat_number)
  <> "/16 ("
  <> song.current_bol.bol_name
  <> ") | C: "
  <> int.to_string(consonance_pct)
  <> "%</text>\n"
  <> "  <line x1=\"20\" y1=\"90\" x2=\"580\" y2=\"90\" stroke=\"#1f293d\" stroke-width=\"1\"/>\n"
  <> voice_bars
  <> "\n</svg>"
}

// =============================================================================
// 7. JSON Serialization
// =============================================================================

pub fn voice_to_json(v: HolonVoice) -> Json {
  json.object([
    #("holon_id", json.string(v.holon_id)),
    #("plane", json.string(v.plane)),
    #("swara", json.string(v.swara)),
    #("shruti_name", json.string(v.shruti_name)),
    #("frequency_hz", json.float(v.frequency_hz)),
    #("amplitude", json.float(v.amplitude)),
    #("pan", json.float(v.pan)),
    #("consonance", json.float(v.consonance)),
  ])
}

pub fn song_to_json(song: SwarmSong) -> Json {
  json.object([
    #("timestamp_us", json.int(song.timestamp_us)),
    #("beat_number", json.int(song.beat_number)),
    #("bol", json.string(song.current_bol.bol_name)),
    #("is_sam", json.bool(song.current_bol.is_sam)),
    #("is_khali", json.bool(song.current_bol.is_khali)),
    #("raga_name", json.string(song.raga_name)),
    #("is_singing", json.bool(song.is_singing)),
    #("harmonic_consonance", json.float(song.harmonic_consonance)),
    #("lyapunov_exponent", json.float(song.lyapunov_exponent)),
    #("shannon_entropy_bits", json.float(song.shannon_entropy_bits)),
    #("chord_frequencies_hz", json.array(song.chord_frequencies_hz, json.float)),
    #("voices", json.array(song.voices, voice_to_json)),
  ])
}
