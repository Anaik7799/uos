import cepaf_gleam/ecology/capability_port.{Masked, Unavailable}
import cepaf_gleam/ecology/harmonic_song.{
  init_tanpura_drone, render_song_ascii_sparkline, render_song_svg,
}
import cepaf_gleam/ecology/living_swarm.{
  all_21_holon_specs, init_living_swarm, invoke_capability, step_swarm_cycle,
  swarm_to_json,
}
import cepaf_gleam/ecology/super_agent.{Active}
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn init_living_swarm_test() {
  let ecology = init_living_swarm()
  let specs = all_21_holon_specs()

  // Verify total holon count matches specification
  list.length(ecology.holons)
  |> should.equal(list.length(specs))

  // Verify all holons are active
  let all_active = list.all(ecology.holons, fn(h) { h.lifecycle == Active })
  should.be_true(all_active)

  // No observations or proofs are prefilled at initialization.
  should.be_false(ecology.is_harmonic)
  ecology.beat_number
  |> should.equal(1)
  ecology.shannon_entropy
  |> should.equal(0.0)
  ecology.receipts |> should.equal([])
  list.find(ecology.holons, fn(h) { h.id == "ucon" }) |> should.be_ok
  list.find(ecology.holons, fn(h) { h.id == "indrajaal" }) |> should.be_ok
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

  let sixteen_beats = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

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

pub fn real_local_capability_invocation_test() {
  let ecology = init_living_swarm()

  // 1. Find sovereign agent (all 11 capabilities active)
  let agy_opt = list.find(ecology.holons, fn(h) { h.id == "agy-agent" })
  should.be_ok(agy_opt)

  let assert Ok(agy) = agy_opt

  // Each invocation must now obtain a real outcome; backend availability is
  // not inferred from a sovereign mode or a capability name.
  let capabilities = ["bayesian", "fprime", "ruliad", "formal_twin"]

  let invoked_agy =
    list.fold(capabilities, agy, fn(acc, cap) {
      case invoke_capability(acc, cap) {
        Ok(updated) -> updated
        Error(err) -> panic as err
      }
    })

  invoked_agy.successful_invocations |> should.equal(4)
  invoked_agy.rete_ul.rules_fired |> should.equal(0)
  invoked_agy.openrouter_free.advisory_tokens_spent |> should.equal(0)
  invoked_agy.formal_twin.lean4_theorems_proved |> should.equal(0)

  // 2. Fail-closed test: Reflex agent cannot invoke openrouter_free
  let prajna_opt =
    list.find(ecology.holons, fn(h) { h.id == "prajna-homeostasis" })
  should.be_ok(prajna_opt)
  let assert Ok(prajna) = prajna_opt

  should.be_error(invoke_capability(prajna, "openrouter_free"))
}

pub fn common_catalog_matches_backend_catalog_test() {
  super_agent.all_capability_names
  |> should.equal(capability_port.all_capabilities)
  list.each(init_living_swarm().holons, fn(h) {
    let encoded = super_agent.to_json(h) |> json.to_string
    string.contains(encoded, "\"capability_catalog\"") |> should.be_true
    list.each(super_agent.all_capability_names, fn(name) {
      string.contains(encoded, name) |> should.be_true
    })
  })
}

pub fn unavailable_and_masked_work_earns_no_success_test() {
  let original = init_living_swarm()
  let observed =
    original
    |> living_swarm.record_outcome("ucon", Unavailable("modular_max", "absent"))
    |> living_swarm.record_outcome("ucon", Masked("formal_twin"))
  let assert Ok(h) = list.find(observed.holons, fn(h) { h.id == "ucon" })
  h.successful_invocations |> should.equal(0)
  h.unavailable_invocations |> should.equal(1)
  h.masked_invocations |> should.equal(1)
}

pub fn receipt_retention_is_bounded_test() {
  let observed =
    list.fold(list.repeat(Nil, 200), init_living_swarm(), fn(s, _) {
      living_swarm.record_outcome(
        s,
        "ucon",
        Unavailable("bayesian", "bounded negative case"),
      )
    })
  observed.invocation_sequence |> should.equal(200)
  list.length(observed.receipts) |> should.equal(living_swarm.receipt_limit)
  let assert [latest, ..] = observed.receipts
  latest.sequence |> should.equal(200)
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
