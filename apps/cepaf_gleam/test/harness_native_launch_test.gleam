import cepaf_gleam/harness/native_launch as launch
import cepaf_gleam/harness/telegram_store_transport as legacy
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

const hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn configuration(path: String, digest: String) {
  launch.reviewed_configuration(
    launch.LinuxX8664,
    launch.NativeStorageV1,
    path,
    digest,
    "/private/guardian",
    hash,
    "/private/worker",
    hash,
    "/private/config",
  )
}

pub fn fixed_environment_matches_independent_profile_test() {
  // Independent reference: complete set equality, not an LD_* subset check.
  launch.environment(launch.NativeStorageV1)
  |> should.equal([
    #("PATH", "/nonexistent"),
    #("LANG", "C"),
    #("LC_ALL", "C"),
    #("TZ", "UTC"),
  ])
}

pub fn unsupported_architecture_has_no_configuration_test() {
  launch.reviewed_configuration(
    launch.UnsupportedArchitecture,
    launch.NativeStorageV1,
    "/private/launcher",
    hash,
    "/private/guardian",
    hash,
    "/private/worker",
    hash,
    "/private/config",
  )
  |> should.equal(Error(launch.UnsupportedHost))
}

pub fn unsafe_paths_refuse_test() {
  list.each(
    [
      "",
      "/",
      "relative",
      "/private/../launcher",
      "/private/./launcher",
      "/private//launcher",
      "/private/launcher/",
      "/private/\u{0000}launcher",
      "/" <> string.repeat("x", 4096),
    ],
    fn(path) {
      configuration(path, hash) |> should.equal(Error(launch.InvalidPath))
    },
  )
  configuration("/private/launcher", hash) |> should.be_ok
}

pub fn invalid_digest_never_yields_configuration_test() {
  list.each(
    ["", "a", string.repeat("A", 64), string.repeat("a", 65)],
    fn(digest) {
      configuration("/private/launcher", digest)
      |> should.equal(Error(launch.InvalidDigest))
    },
  )
}

pub fn body_bounds_are_pure_and_never_dispatch_test() {
  let config = configuration("/does/not/exist", hash) |> should.be_ok
  launch.exchange_with_cleanup(config, "")
  |> should.equal(#(Error(legacy.InputBound), None))
  launch.exchange_with_cleanup(config, string.repeat("x", 1_048_573))
  |> should.equal(#(Error(legacy.InputBound), None))
}
