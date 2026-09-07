import gleeunit/should
import uos_swarm/board_reader
import uos_swarm/clock_guard
import uos_swarm/clock_guard_fetch

pub fn disallowed_endpoints_never_replace_last_projection_test() {
  let projection = "/tmp/uos-clock-guard-fetch-last-good"
  clock_guard.store_floor(projection, 91) |> should.be_ok

  clock_guard_fetch.fetch("https://127.0.0.1:8080/c3i/a2a/**", projection)
  |> should.be_error
  clock_guard_fetch.fetch("http://example.com/c3i/a2a/**", projection)
  |> should.be_error
  clock_guard_fetch.fetch(
    "http://user:secret@127.0.0.1:8080/c3i/a2a/**",
    projection,
  )
  |> should.be_error

  board_reader.read_file(projection, 64) |> should.equal(Ok("91"))
}

pub fn fetch_requires_absolute_private_projection_and_unfragmented_url_test() {
  clock_guard_fetch.fetch("http://127.0.0.1:8080/c3i/a2a/**", "relative")
  |> should.be_error
  clock_guard_fetch.fetch(
    "http://127.0.0.1:8080/c3i/a2a/**#fragment",
    "/tmp/uos-clock-guard-fetch-fragment",
  )
  |> should.be_error
}
