// =============================================================================
// [C3I-SIL6-MSTS] UOS CYBERNETIC RĀGA & 22-SHRUTI HARMONY TEST SUITE
// =============================================================================
// Verifies 22 Shrutis mathematical ratios, Rāga Durgā pentatonic structures,
// Teentaal 16-beat rhythmic cycle, and Lyapunov acoustic stability.
// =============================================================================

import cepaf_gleam/knowledge/raga_cybernetic_synthesis as raga
import gleam/list
import gleeunit/should

pub fn shruti_count_and_frequencies_test() {
  let shrutis = raga.all_22_shrutis()
  list.length(shrutis) |> should.equal(22)

  // Verify first shruti is Shadja (1/1)
  let assert Ok(s1) = list.first(shrutis)
  s1.name |> should.equal("Kshobhini")
  s1.swara |> should.equal("Sa")
  s1.ratio_num |> should.equal(1)
  s1.ratio_den |> should.equal(1)

  // Verify last shruti is Ugra (Ni2, 243/128)
  let assert Ok(s22) = list.last(shrutis)
  s22.name |> should.equal("Ugra")
  s22.swara |> should.equal("Ni2")
  s22.ratio_num |> should.equal(243)
  s22.ratio_den |> should.equal(128)
}

pub fn raga_durga_scale_and_invariants_test() {
  let durga = raga.raga_durga()
  durga.name |> should.equal("Rāga Durgā")
  durga.thaat |> should.equal("Bilawal")
  durga.jati |> should.equal("Audav-Audav (Pentatonic)")

  list.length(durga.arohana) |> should.equal(6)
  list.length(durga.avarohana) |> should.equal(6)
  list.length(durga.varjita) |> should.equal(2)

  // Vadi must be Dha (5/3) and Samvadi must be Re (9/8)
  durga.vadi |> should.equal("Dha (Shuddha Dhaivat, 5/3)")
  durga.samvadi |> should.equal("Re (Shuddha Rishabh, 9/8)")

  // Math gates
  should.be_true(durga.shannon_entropy >=. 2.50)
  should.be_true(durga.lyapunov_exponent <. 0.0)
}

pub fn teentaal_16_beats_cycle_test() {
  let beats = raga.teentaal_16_beats()
  list.length(beats) |> should.equal(16)

  // Beat 1 must be Sam (Dha)
  let assert Ok(b1) = list.first(beats)
  b1.beat |> should.equal(1)
  b1.bol_name |> should.equal("Dha")
  b1.is_sam |> should.be_true
  b1.is_khali |> should.be_false

  // Beat 9 must be Khali (Dha)
  let assert Ok(b9) = list.drop(beats, 8) |> list.first
  b9.beat |> should.equal(9)
  b9.is_khali |> should.be_true

  // Beat 16 must be last beat
  let assert Ok(b16) = list.last(beats)
  b16.beat |> should.equal(16)
  b16.bol_name |> should.equal("Dha")
}

pub fn acoustic_audit_verification_test() {
  let audit = raga.verify_acoustic_harmony()
  audit.total_shrutis |> should.equal(22)
  audit.durga_swaras_count |> should.equal(6)
  audit.teentaal_beats_count |> should.equal(16)
  audit.lyapunov_stable |> should.be_true
  audit.entropy_sufficient |> should.be_true
  audit.just_intonation_verified |> should.be_true

  let str = raga.audit_to_string(audit)
  should.be_true(str != "")
}
