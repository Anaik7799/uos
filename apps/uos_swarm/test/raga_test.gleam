import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_swarm/ooda
import uos_swarm/raga

pub fn all_swaras_has_seven_test() {
  list.length(raga.all_swaras()) |> should.equal(7)
  list.unique(raga.all_swaras()) |> should.equal(raga.all_swaras())
}

pub fn swara_labels_are_non_empty_test() {
  list.each(raga.all_swaras(), fn(s) {
    { raga.swara_label(s) != "" } |> should.be_true
  })
}

// Sa and Pa are the two achala (immovable) svara-s: every thaat carries them shuddha.
pub fn sa_and_pa_are_always_shuddha_test() {
  list.each(raga.thaats, fn(t) {
    let set = raga.thaat_swaras(t)
    list.contains(set, #(raga.Sa, raga.Shuddha)) |> should.be_true
    list.contains(set, #(raga.Pa, raga.Shuddha)) |> should.be_true
  })
}

pub fn every_thaat_has_seven_swaras_test() {
  list.each(raga.thaats, fn(t) {
    list.length(raga.thaat_swaras(t)) |> should.equal(7)
  })
  list.length(raga.thaats) |> should.equal(10)
}

pub fn thaat_of_layer_matches_canonical_order_test() {
  raga.thaat_of_layer(0) |> should.equal(raga.Bilawal)
  raga.thaat_of_layer(1) |> should.equal(raga.Kalyan)
  raga.thaat_of_layer(2) |> should.equal(raga.Khamaj)
  raga.thaat_of_layer(3) |> should.equal(raga.Bhairav)
  raga.thaat_of_layer(4) |> should.equal(raga.Poorvi)
  raga.thaat_of_layer(5) |> should.equal(raga.Marwa)
  raga.thaat_of_layer(6) |> should.equal(raga.Kafi)
  raga.thaat_of_layer(7) |> should.equal(raga.Asavari)
  raga.thaat_of_layer(8) |> should.equal(raga.Bhairavi)
  raga.thaat_of_layer(9) |> should.equal(raga.Todi)
  // Out-of-range layers fail closed onto Todi rather than crashing.
  raga.thaat_of_layer(42) |> should.equal(raga.Todi)
  raga.thaat_of_layer(-1) |> should.equal(raga.Todi)
}

pub fn at_least_eight_ragas_defined_test() {
  { list.length(raga.ragas()) >= 8 } |> should.be_true
}

pub fn raga_of_mode_covers_every_mode_test() {
  raga.raga_of_mode(ooda.Dark, 10).name |> should.equal(raga.malkauns().name)
  raga.raga_of_mode(ooda.Dim, 10).name |> should.equal(raga.bhairav().name)
  raga.raga_of_mode(ooda.Normal, 10).name |> should.equal(raga.yaman().name)
  raga.raga_of_mode(ooda.Emergency, 10).name
  |> should.equal(raga.bhairavi().name)
}

pub fn raga_of_mode_bright_depends_on_hour_test() {
  raga.raga_of_mode(ooda.Bright, 9).name |> should.equal(raga.bilawal().name)
  raga.raga_of_mode(ooda.Bright, 21).name |> should.equal(raga.durga().name)
}

pub fn beat_of_cycle_teentaal_test() {
  let t = raga.teentaal()
  raga.beat_of_cycle(t, 1) |> should.equal(raga.Beat(1, 1, raga.Sam))
  raga.beat_of_cycle(t, 5) |> should.equal(raga.Beat(5, 2, raga.Tali))
  raga.beat_of_cycle(t, 9) |> should.equal(raga.Beat(9, 3, raga.Khali))
  raga.beat_of_cycle(t, 13) |> should.equal(raga.Beat(13, 4, raga.Tali))
  raga.beat_of_cycle(t, 17) |> should.equal(raga.Beat(1, 1, raga.Sam))
  raga.beat_of_cycle(t, 2).kind |> should.equal(raga.Ordinary)
}

pub fn beat_of_cycle_rupak_sam_is_khali_test() {
  let t = raga.rupak()
  // Rupak famously opens on a wave, not a clap: sam and khali coincide at matra 1.
  raga.beat_of_cycle(t, 1).kind |> should.equal(raga.Sam)
  t.khali |> should.equal([1])
}

pub fn tala_names_are_distinct_test() {
  let names = list.map(raga.talas(), fn(t) { t.name })
  list.length(list.unique(names)) |> should.equal(list.length(names))
  list.length(raga.talas()) |> should.equal(6)
}

pub fn phase_of_swarm_covers_known_steps_test() {
  string.contains(raga.phase_of_swarm("plan"), "alap") |> should.be_true
  string.contains(raga.phase_of_swarm("dispatch"), "jor") |> should.be_true
  string.contains(raga.phase_of_swarm("verify"), "jhala") |> should.be_true
  string.contains(raga.phase_of_swarm("integrate"), "bandish")
  |> should.be_true
  string.contains(raga.phase_of_swarm("nonsense"), "unknown swarm step")
  |> should.be_true
}

pub fn gharana_of_provider_covers_known_providers_test() {
  string.starts_with(raga.gharana_of_provider("claude"), "gharānā: claude")
  |> should.be_true
  string.starts_with(raga.gharana_of_provider("codex"), "gharānā: codex")
  |> should.be_true
  string.starts_with(raga.gharana_of_provider("agy"), "gharānā: agy")
  |> should.be_true
  string.starts_with(
    raga.gharana_of_provider("openrouter"),
    "gharānā: openrouter",
  )
  |> should.be_true
  string.contains(raga.gharana_of_provider("someone-else"), "unclassified")
  |> should.be_true
}

pub fn validate_register_passes_test() {
  raga.validate_register() |> should.equal(Ok(Nil))
}

pub fn to_markdown_renders_all_four_tables_test() {
  let md = raga.to_markdown()
  string.contains(md, "svara") |> should.be_true
  string.contains(md, "thaat") |> should.be_true
  string.contains(md, raga.yaman().name) |> should.be_true
  string.contains(md, "Teentaal") |> should.be_true
}

pub fn to_json_contains_all_sections_test() {
  let s = raga.to_json() |> json.to_string()
  string.contains(s, "swaras") |> should.be_true
  string.contains(s, "thaats") |> should.be_true
  string.contains(s, "ragas") |> should.be_true
  string.contains(s, "talas") |> should.be_true
}

// Property: beat_of_cycle never crashes and always returns a matra within 1..matras, for any
// tala and any cycle (including 0 and negative cycles).
pub fn property_beat_of_cycle_always_in_range_test() {
  list.each(prng.seeds(30), fn(seed) {
    let #(cycle, _) = prng.int_between(seed, -50, 500)
    list.each(raga.talas(), fn(t) {
      let beat = raga.beat_of_cycle(t, cycle)
      { beat.matra >= 1 && beat.matra <= t.matras } |> should.be_true
      { beat.vibhag >= 1 && beat.vibhag <= list.length(t.vibhags) }
      |> should.be_true
    })
  })
}
