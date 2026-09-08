import cepaf_gleam/ecology/living_swarm_actor.{
  get_song, get_sparkline, get_spectrogram, get_swarm, start_actor,
}
import gleeunit/should

pub fn living_swarm_actor_lifecycle_test() {
  // Start the living swarm actor with a fast 50ms tick interval
  let res = start_actor(50)
  res |> should.be_ok
  let assert Ok(started) = res
  let subj = started.data

  // Query swarm state
  let swarm_res = get_swarm(subj, 500)
  swarm_res |> should.be_ok
  let assert Ok(swarm) = swarm_res
  swarm.holons |> should.not_equal([])

  // Query cybernetic swarm song
  let song_res = get_song(subj, 500)
  song_res |> should.be_ok
  let assert Ok(song) = song_res
  song.raga_name |> should.equal("Bhairav")

  // Query ASCII sparkline
  let sparkline_res = get_sparkline(subj, 500)
  sparkline_res |> should.be_ok
  let assert Ok(sparkline) = sparkline_res
  sparkline |> should.not_equal("")

  // Query SVG spectrogram
  let svg_res = get_spectrogram(subj, 500)
  svg_res |> should.be_ok
  let assert Ok(svg) = svg_res
  svg |> should.not_equal("")
}
