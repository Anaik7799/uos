//// Fixed local Podman observations for the authenticated Mini App.
//// No command/label/environment export and no mutating verb is reachable here.

import cepaf_gleam/harness/observer_policy as policy
import cepaf_gleam/telegram/mini_api as api
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Query {
  Containers
  Images
  Info
}

pub type Io {
  Io(
    read: fn(Query, Int) -> Result(String, String),
    monotonic_ms: fn() -> Int,
    unix_seconds: fn() -> Int,
  )
}

type Unit {
  Millisecond
  Second
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic(unit: Unit) -> Int

@external(erlang, "erlang", "system_time")
fn system(unit: Unit) -> Int

@external(erlang, "sa_plan_observer_ffi", "observe_checked")
fn invoke(
  guardian: String,
  sha: String,
  args: List(String),
  deadline: Int,
  max_bytes: Int,
) -> Result(policy.Observation, String)

pub fn arguments(query: Query) -> List(String) {
  case query {
    Containers -> [
      "--remote=false",
      "ps",
      "--all",
      "--no-trunc",
      "--format",
      "{\"id\":{{json .ID}},\"name\":{{json .Names}},\"image\":{{json .Image}},\"state\":{{json .State}}}",
    ]
    Images -> [
      "--remote=false",
      "images",
      "--no-trunc",
      "--format",
      "{\"id\":{{json .ID}},\"repository\":{{json .Repository}},\"tag\":{{json .Tag}},\"size\":{{json .Size}}}",
    ]
    Info -> [
      "--remote=false",
      "info",
      "--format",
      "{\"rootless\":{{json .Host.Security.Rootless}},\"version\":{{json .Version.Version}}}",
    ]
  }
}

fn require(valid: Bool) -> Result(Nil, String) {
  case valid {
    True -> Ok(Nil)
    False -> Error("podman_observation_refused")
  }
}

fn read(query: Query, deadline: Int, sha: String) -> Result(String, String) {
  use _ <- result.try(require(
    policy.valid_digest(sha) && deadline >= 100 && deadline <= 1500,
  ))
  use receipt <- result.try(
    invoke(
      "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe",
      "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be",
      [
        "--exe",
        "/usr/bin/podman",
        "--sha256",
        sha,
        "--deadline-ms",
        int.to_string(deadline),
        "--max-bytes",
        "32768",
        "--",
        ..arguments(query)
      ],
      deadline,
      32_768,
    )
    |> result.replace_error("podman_worker_unavailable"),
  )
  use _ <- result.try(require(
    receipt.guardian_result == "child_exited"
    && receipt.cleanup == "confirmed"
    && receipt.child_exit == 0
    && bit_array.byte_size(receipt.payload) <= 32_768,
  ))
  bit_array.to_string(receipt.payload)
  |> result.replace_error("podman_encoding_refused")
}

pub fn live_io(sha: String) -> Io {
  Io(
    fn(q, timeout) { read(q, timeout, sha) },
    fn() { monotonic(Millisecond) },
    fn() { system(Second) },
  )
}

fn one(io: Io, query: Query, last: Int, deadline: Int) -> Result(#(String, Int), String) {
  let before = io.monotonic_ms()
  use _ <- result.try(require(before >= last && deadline - before >= 100))
  use raw <- result.try(io.read(query, int.min(1500, deadline - before)))
  let after = io.monotonic_ms()
  use _ <- result.try(require(after >= before && after < deadline))
  Ok(#(raw, after))
}
pub fn observe(io: Io) -> Result(api.Observation, String) {
  observe_with_budget(io, 4000)
}

pub fn observe_with_budget(io: Io, budget_ms: Int) -> Result(api.Observation, String) {
  use _ <- result.try(require(budget_ms >= 100 && budget_ms <= 4000))
  let started = io.monotonic_ms()
  let deadline = started + budget_ms
  use #(containers, after_containers) <- result.try(one(io, Containers, started, deadline))
  use #(images, after_images) <- result.try(one(io, Images, after_containers, deadline))
  use #(info, _) <- result.try(one(io, Info, after_images, deadline))
  project(containers, images, info, io.unix_seconds())
}

type Container {
  Container(id: String, name: String, image: String, state: String)
}

type Image {
  Image(id: String, repository: String, tag: String, size: String)
}

fn container_decoder() -> decode.Decoder(Container) {
  use id <- decode.field("id", decode.string)
  use name <- decode.field("name", decode.string)
  use image <- decode.field("image", decode.string)
  use state <- decode.field("state", decode.string)
  decode.success(Container(id, name, image, state))
}

fn image_decoder() -> decode.Decoder(Image) {
  use id <- decode.field("id", decode.string)
  use repository <- decode.field("repository", decode.string)
  use tag <- decode.field("tag", decode.string)
  use size <- decode.field("size", decode.string)
  decode.success(Image(id, repository, tag, size))
}

fn text(value: String, max: Int) -> Bool {
  value != ""
  && string.byte_size(value) <= max
  && !list.any(["\u{0}", "\n", "\r", "\t", "\u{1b}", "\u{7f}"], fn(c) {
    string.contains(value, c)
  })
}

fn lines(raw: String, decoder: decode.Decoder(a)) -> Result(List(a), String) {
  use _ <- result.try(require(string.byte_size(raw) <= 32_768))
  let rows = case string.trim(raw) {
    "" -> []
    other -> string.split(other, "\n")
  }
  use _ <- result.try(require(list.length(rows) <= 128))
  list.try_map(rows, fn(row) {
    json.parse(row, decoder) |> result.replace_error("podman_row_refused")
  })
}

fn image_id(value: String) -> Bool {
  case value {
    "sha256:" <> digest -> policy.valid_digest(digest)
    _ -> policy.valid_digest(value)
  }
}

pub fn project(
  containers: String,
  images: String,
  info: String,
  at: Int,
) -> Result(api.Observation, String) {
  use _ <- result.try(require(at > 0 && string.byte_size(info) <= 32_768))
  use cs <- result.try(lines(containers, container_decoder()))
  use imgs <- result.try(lines(images, image_decoder()))
  let decoder = {
    use rootless <- decode.field("rootless", decode.bool)
    use version <- decode.field("version", decode.string)
    decode.success(#(rootless, version))
  }
  use #(rootless, version) <- result.try(
    json.parse(info, decoder) |> result.replace_error("podman_info_refused"),
  )
  use _ <- result.try(require(
    text(version, 64)
    && list.length(list.unique(list.map(cs, fn(c) { c.id }))) == list.length(cs)
    && list.all(cs, fn(c) {
      policy.valid_digest(c.id)
      && text(c.name, 128)
      && text(c.image, 512)
      && list.contains(
        [
          "configured",
          "created",
          "initialized",
          "running",
          "paused",
          "stopped",
          "exited",
          "removing",
          "stopping",
          "unknown",
        ],
        c.state,
      )
    })
    && list.all(imgs, fn(i) {
      image_id(i.id)
      && text(i.repository, 512)
      && text(i.tag, 128)
      && text(i.size, 64)
    })
    && list.length(
      list.unique(list.map(imgs, fn(i) { #(i.id, i.repository, i.tag) })),
    )
    == list.length(imgs),
  ))
  let selected_cs =
    list.sort(cs, fn(a, b) { string.compare(a.id, b.id) }) |> list.take(40)
  let selected_imgs =
    list.sort(imgs, fn(a, b) {
      string.compare(
        a.id <> ":" <> a.repository <> ":" <> a.tag,
        b.id <> ":" <> b.repository <> ":" <> b.tag,
      )
    })
    |> list.take(40)
  let fields = [
    #(
      "Scope",
      "Local Podman inventory of the service account; not a fleet or application-health assertion",
    ),
    #("Rootless", case rootless {
      True -> "true"
      False -> "false"
    }),
    #("Podman version", version),
    #("Container count", int.to_string(list.length(cs))),
    #(
      "Running containers",
      int.to_string(list.count(cs, fn(c) { c.state == "running" })),
    ),
    #("Image references", int.to_string(list.length(imgs))),
    #(
      "Shown",
      int.to_string(list.length(selected_cs))
        <> " of "
        <> int.to_string(list.length(cs))
        <> " containers; "
        <> int.to_string(list.length(selected_imgs))
        <> " of "
        <> int.to_string(list.length(imgs))
        <> " image references",
    ),
    #("Runtime admission", "NOT_GRANTED"),
    #("Actions", "Read-only inventory; no start, stop or removal is executed"),
    ..list.map(selected_cs, fn(c) {
      #("Container " <> c.id, c.name <> " | " <> c.state <> " | " <> c.image)
    })
  ]
  let fields =
    list.append(
      fields,
      list.index_map(selected_imgs, fn(i, n) {
        #(
          "Image " <> int.to_string(n + 1),
          i.id <> " | " <> i.repository <> ":" <> i.tag <> " | " <> i.size,
        )
      }),
    )
  Ok(api.Observed(at, "local_podman_cli", dict.from_list(fields)))
}
