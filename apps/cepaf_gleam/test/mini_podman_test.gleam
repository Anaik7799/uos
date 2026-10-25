import cepaf_gleam/telegram/mini_podman as podman
import cepaf_gleam/telegram/mini_api as api
import gleam/int
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

@external(erlang, "mini_boundary_test_ffi", "set_clock")
fn set_clock(times: List(Int)) -> Nil
@external(erlang, "mini_boundary_test_ffi", "clock")
fn clock() -> Int

const container = "{\"id\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"name\":\"test-app\",\"image\":\"local/test:1\",\"state\":\"created\"}"
const image = "{\"id\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"repository\":\"local/test\",\"tag\":\"1\",\"size\":\"4 MB\"}"
const info = "{\"rootless\":true,\"version\":\"5.7.0\"}"
fn value(observed: api.Observation, key: String) -> String {
  let assert api.Observed(_, "local_podman_cli", fields) = observed
  dict.get(fields, key) |> should.be_ok
}
fn io() -> podman.Io {
  podman.Io(fn(query, deadline) {
    {deadline >= 100 && deadline <= 1500} |> should.equal(True)
    Ok(case query { podman.Containers -> container podman.Images -> image podman.Info -> info })
  }, clock, fn() { 2000 })
}
pub fn actual_values_and_state_change_test() {
  let first = podman.project(container, image, info, 2000) |> should.be_ok
  value(first, "Container count") |> should.equal("1")
  value(first, "Running containers") |> should.equal("0")
  value(first, "Rootless") |> should.equal("true")
  value(first, "Runtime admission") |> should.equal("NOT_GRANTED")
  let second = podman.project(string.replace(container, "created", "running"), image, info, 2001) |> should.be_ok
  value(second, "Running containers") |> should.equal("1")
  {first != second} |> should.equal(True)
}
pub fn empty_requires_successful_info_test() {
  let observed = podman.project("", "", info, 2000) |> should.be_ok
  value(observed, "Container count") |> should.equal("0")
  value(observed, "Image references") |> should.equal("0")
  podman.project("", "", "", 2000) |> should.be_error
  podman.project("", "", "{}", 2000) |> should.be_error
}
pub fn malformed_rows_are_not_dropped_test() {
  list.each(["{}", container <> "\n{}", container <> "\n\n" <> container, "[]", "{\"id\":1}"], fn(raw) {
    podman.project(raw, image, info, 2000) |> should.be_error
  })
  podman.project(container, image <> "\n{}", info, 2000) |> should.be_error
}
pub fn duplicates_are_refused_test() {
  podman.project(container <> "\n" <> container, image, info, 2000) |> should.be_error
  podman.project(container, image <> "\n" <> image, info, 2000) |> should.be_error
}
pub fn invalid_identity_state_and_text_refused_test() {
  list.each([
    string.replace(container, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bad"),
    string.replace(container, "created", "healthy"),
    string.replace(container, "test-app", string.repeat("x", 129)),
    string.replace(container, "test-app", "line\\ncontrol"),
  ], fn(raw) { podman.project(raw, image, info, 2000) |> should.be_error })
  podman.project(container, string.replace(image, "sha256:bbbb", "wrong:bbbb"), info, 2000) |> should.be_error
  podman.project(container, image, "{\"rootless\":\"true\",\"version\":\"5\"}", 2000) |> should.be_error
}
pub fn output_and_row_bounds_test() {
  podman.project(string.repeat("x", 32769), image, info, 2000) |> should.be_error
  podman.project(container, image, string.repeat("x", 32769), 2000) |> should.be_error
  podman.project(container, image, info, 0) |> should.be_error
}
pub fn fixed_read_only_query_arguments_test() {
  list.each([podman.Containers, podman.Images, podman.Info], fn(query) {
    podman.arguments(query) |> list.first |> should.equal(Ok("--remote=false"))
    list.any(podman.arguments(query), fn(arg) {
      list.contains(["start", "stop", "rm", "run", "create", "inspect", "exec"], arg)
    }) |> should.equal(False)
  })
  podman.arguments(podman.Containers) |> list.last |> result.unwrap("")
  |> string.contains(".Command") |> should.equal(False)
}
pub fn monotonic_success_test() {
  set_clock([1000,1001,1100,1101,1200,1201,1300])
  let observed = podman.observe(io()) |> should.be_ok
  value(observed, "Container count") |> should.equal("1")
}
pub fn whole_observation_deadline_and_clock_test() {
  list.each([
    [1000,900],
    [1000,1001,900],
    [1000,1001,1100,1050],
    [1000,1001,1100,1101,1200,1150],
    [1000,1001,5000],
    [1000,4950],
  ], fn(times) { set_clock(times) podman.observe(io()) |> should.be_error })
}
pub fn backend_error_is_not_empty_test() {
  let failing = podman.Io(fn(_, _) { Error("denied") }, fn() { 1000 }, fn() { 2000 })
  podman.observe(failing) |> should.be_error
}

fn rows(count: Int) -> String {
  list.repeat(container, count)
  |> list.index_map(fn(raw, i) {
    let suffix = int.to_string(i)
    string.replace(raw, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      string.repeat("0", 64 - string.length(suffix)) <> suffix)
  })
  |> string.join("\n")
}
pub fn pagination_counts_and_row_limit_test() {
  let observed = podman.project(rows(41), image, info, 2000) |> should.be_ok
  value(observed, "Container count") |> should.equal("41")
  value(observed, "Shown") |> should.equal("40 of 41 containers; 1 of 1 image references")
  let assert api.Observed(_, _, fields) = observed
  {dict.size(fields) <= 100} |> should.equal(True)
  podman.project(rows(129), image, info, 2000) |> should.be_error
}
