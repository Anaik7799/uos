import cepaf_gleam/ecology/harmonic_song.{
  init_tanpura_drone, render_song_ascii_sparkline, render_song_svg,
}
import cepaf_gleam/ecology/living_swarm.{
  all_21_holon_specs, init_living_swarm, invoke_capability, step_swarm_cycle,
  swarm_to_json,
}
import cepaf_gleam/ecology/super_agent.{Active}
import gleeunit/should
import gleam/json
import gleam/list
import gleam/string

pub fn init_living_swarm_test() {
  let ecology = init_living_swarm()
  let specs = all_21_holon_specs()

  // Verify total holon count matches specification
  list.length(ecology.holons)
  |> should.equal(list.length(specs))

  // Verify all holons are active
  let all_active = list.all(ecology.holons, fn(h) { h.lifecycle == Active })
  should.be_true(all_active)

  // Verify harmonic state initialized
  should.be_true(ecology.is_harmonic)
  ecology.beat_number
  |> should.equal(1)
  ecology.shannon_entropy
  |> should.equal(2.67)
}

pub fn step_swarm_cycle_test() {
  let ecology = init_living_swarm()
  let stepped = step_swarm_cycle(ecology)

  // Beat advances from 1 to 2
  stepped.beat_number
  |> should.equal(2)
  stepped.cycle_counter
  |> should.equal(1)

  // Collective singing is active
  should.be_true(stepped.current_song.is_singing)
  should.be_true(stepped.current_song.harmonic_consonance >. 0.0)

  // Verify voices are populated for active holons
  let has_voices = stepped.current_song.voices != []
  should.be_true(has_voices)
}

pub fn teentaal_16_beat_full_cycle_test() {
  let ecology = init_living_swarm()

  let sixteen_beats = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
  ]

  // Step 16 times to complete one full Teentaal cycle
  let final_ecology =
    list.fold(sixteen_beats, ecology, fn(acc, _) { step_swarm_cycle(acc) })

  // After 16 steps, beat wraps back to 1 (Sam)
  final_ecology.beat_number
  |> should.equal(1)
  final_ecology.cycle_counter
  |> should.equal(16)
  should.be_true(final_ecology.current_song.current_bol.is_sam)
}

pub fn tanpura_drone_test() {
  let drone = init_tanpura_drone()

  // Verify 4 classic strings
  list.length(drone.active_strings)
  |> should.equal(4)
  should.be_true(drone.drone_volume >. 0.0)
  should.be_true(drone.jawari_resonance >. 0.0)
}

pub fn multi_capability_invocation_test() {
  let ecology = init_living_swarm()

  // 1. Find sovereign agent (all 11 capabilities active)
  let agy_opt = list.find(ecology.holons, fn(h) { h.id == "agy-agent" })
  should.be_ok(agy_opt)

  let assert Ok(agy) = agy_opt

  // Test invoking all 11 capabilities on sovereign agent
  let capabilities = [
    "fprime", "bayesian", "rete_ul", "ets", "stm",
    "modular_max", "openrouter_free", "ruliad", "formal_twin",
    "denotational", "algebraic_atlas",
  ]

  let invoked_agy =
    list.fold(capabilities, agy, fn(acc, cap) {
      case invoke_capability(acc, cap) {
        Ok(updated) -> updated
        Error(err) -> panic as err
      }
    })

  // Verify states were mutated
  invoked_agy.rete_ul.rules_fired
  |> should.equal(1)
  invoked_agy.ets.cached_entries
  |> should.equal(1)
  invoked_agy.openrouter_free.advisory_tokens_spent
  |> should.equal(64)
  invoked_agy.denotational.aspects_satisfied
  |> should.equal(17)

  // 2. Fail-closed test: Reflex agent cannot invoke openrouter_free
  let prajna_opt = list.find(ecology.holons, fn(h) { h.id == "prajna-homeostasis" })
  should.be_ok(prajna_opt)
  let assert Ok(prajna) = prajna_opt

  should.be_error(invoke_capability(prajna, "openrouter_free"))
}

pub fn visual_spectrogram_test() {
  let ecology = init_living_swarm()
  let stepped = step_swarm_cycle(ecology)

  let ascii = render_song_ascii_sparkline(stepped.current_song)
  should.be_true(string.contains(ascii, "SINGING"))
  should.be_true(string.contains(ascii, "Beat 2/16"))

  let svg = render_song_svg(stepped.current_song)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "Rāga Durgā Pentatonic"))
  should.be_true(string.contains(svg, "fill=\"#00ffc4\""))
}

pub fn json_serialization_test() {
  let ecology = init_living_swarm()
  let stepped = step_swarm_cycle(ecology)

  let j = swarm_to_json(stepped)
  let s = json.to_string(j)

  should.be_true(string.contains(s, "epoch_us"))
  should.be_true(string.contains(s, "beat_number"))
  should.be_true(string.contains(s, "hive-mind-decider"))
  should.be_true(string.contains(s, "is_singing"))
}
