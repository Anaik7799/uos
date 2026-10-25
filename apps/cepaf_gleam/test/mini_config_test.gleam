import cepaf_gleam/config/mesh_config as mesh
import cepaf_gleam/config/mesh_source as source
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_config as mini
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

fn raw(c) {
  mesh.config_to_json(c) |> json.to_string
}

fn default() {
  mesh.default_mesh_config()
}

fn configured(c) {
  source.from_environment(Some(raw(c)))
}

pub fn default_is_declared_not_deployed_test() {
  let assert Ok(d) = source.from_environment(None)
  source.source(d) |> should.equal("compiled_default")
  let assert api.Observed(1000, "declared_mesh_configuration", f) =
    mini.project(Ok(d), 1000)
  dict.get(f, "Deployment") |> should.equal(Ok("Not confirmed"))
  dict.get(f, "Containers") |> should.equal(Ok("7"))
  string.contains(
    json.to_string(source.summary(Ok(d))),
    "\"deployment_confirmed\":false",
  )
  |> should.be_true
}

pub fn explicit_configuration_not_default_test() {
  let c = default()
  let c =
    mesh.MeshConfig(..c, containers: list.take(c.containers, 1), quorum_size: 1)
  let assert Ok(d) = configured(c)
  source.source(d) |> should.equal("configured")
  let assert api.Observed(_, _, f) = mini.project(Ok(d), 1000)
  dict.get(f, "Containers") |> should.equal(Ok("1"))
}

pub fn malformed_configuration_never_defaults_test() {
  list.each(
    [
      "",
      "null",
      "{}",
      "[]",
      raw(default()) <> " trailing",
      string.repeat("x", 65_537),
    ],
    fn(s) {
      source.from_environment(Some(s)) |> should.be_error
      mini.observe(Some(s), 1000)
      |> should.equal(api.Unavailable("mesh_configuration_invalid"))
    },
  )
}

pub fn duplicate_and_escaped_duplicate_keys_refused_test() {
  let s = raw(default())
  source.from_environment(
    Some(string.replace(
      s,
      "\"quorum_size\":4",
      "\"quorum_size\":4,\"quorum_size\":4",
    )),
  )
  |> should.be_error
  source.from_environment(
    Some(string.replace(
      s,
      "\"quorum_size\":4",
      "\"quorum_size\":4,\"quorum_\\u0073ize\":4",
    )),
  )
  |> should.be_error
  source.from_environment(
    Some(string.replace(s, "\"quorum_size\":4", "\"quorum_size\":4,\"extra\":0")),
  )
  |> should.be_error
}

pub fn invalid_network_cidr_refused_test() {
  list.each(
    [
      "10.0.0.1/24",
      "010.0.0.0/24",
      "10.0.0.0/33",
      "256.0.0.0/8",
      "10.0.0/8",
      "10.0.0.0/-1",
    ],
    fn(s) { source.subnet_valid(s) |> should.be_false },
  )
  list.each(
    ["0.0.0.0/0", "10.0.0.0/8", "192.168.1.0/24", "192.168.1.1/32"],
    fn(s) { source.subnet_valid(s) |> should.be_true },
  )
}

pub fn duplicate_names_and_ports_refused_test() {
  let c = default()
  let assert [a, b, ..rest] = c.containers
  configured(
    mesh.MeshConfig(..c, containers: [
      a,
      mesh.ContainerSpec(..b, name: a.name),
      ..rest
    ]),
  )
  |> should.be_error
  configured(
    mesh.MeshConfig(..c, containers: [
      a,
      mesh.ContainerSpec(..b, port: a.port),
      ..rest
    ]),
  )
  |> should.be_error
}

pub fn invalid_numeric_bounds_refused_test() {
  let c = default()
  let assert [a, ..rest] = c.containers
  list.each([0, 65_536], fn(port) {
    configured(
      mesh.MeshConfig(..c, containers: [
        mesh.ContainerSpec(..a, port: port),
        ..rest
      ]),
    )
    |> should.be_error
  })
  list.each([0, 65_537], fn(memory) {
    configured(
      mesh.MeshConfig(..c, containers: [
        mesh.ContainerSpec(..a, memory_mb: memory),
        ..rest
      ]),
    )
    |> should.be_error
  })
  configured(
    mesh.MeshConfig(..c, containers: [
      mesh.ContainerSpec(..a, cpu_limit: 0.0),
      ..rest
    ]),
  )
  |> should.be_error
  configured(mesh.MeshConfig(..c, quorum_size: 0)) |> should.be_error
  configured(mesh.MeshConfig(..c, quorum_size: 8)) |> should.be_error
  configured(mesh.MeshConfig(..c, quorum_size: 3)) |> should.be_error
}

pub fn malformed_volume_path_refused_test() {
  let c = default()
  list.each(["relative", "/data/../private", "/data\nprivate"], fn(p) {
    configured(mesh.MeshConfig(..c, volumes: [mesh.VolumeSpec("state", p, 1)]))
    |> should.be_error
  })
}

pub fn sensitive_configuration_fields_not_projected_test() {
  let c = default()
  let assert [a, ..rest] = c.containers
  let c =
    mesh.MeshConfig(
      ..c,
      containers: [
        mesh.ContainerSpec(
          ..a,
          image: "PRIVATE_IMAGE_MARKER",
          health_check: "PRIVATE_HEALTH_MARKER",
        ),
        ..rest
      ],
      volumes: [mesh.VolumeSpec("state", "/PRIVATE_PATH_MARKER", 1)],
    )
  let assert api.Observed(_, _, f) = mini.observe(Some(raw(c)), 1000)
  let s = string.join(dict.values(f), " ")
  list.each(
    ["PRIVATE_IMAGE_MARKER", "PRIVATE_HEALTH_MARKER", "PRIVATE_PATH_MARKER"],
    fn(marker) { string.contains(s, marker) |> should.be_false },
  )
}

pub fn maximum_valid_configuration_fits_api_without_data_loss_test() {
  let containers =
    list.map(range(1, 64), fn(i) {
      mesh.ContainerSpec(
        "c" <> int.to_string(i),
        "image",
        10_000 + i,
        "/health",
        0.125,
        1,
      )
    })
  let networks =
    list.map(range(1, 16), fn(i) {
      mesh.NetworkSpec(
        "n" <> int.to_string(i),
        "10." <> int.to_string(i) <> ".0.0/16",
        "bridge",
      )
    })
  let volumes =
    list.map(range(1, 64), fn(i) {
      mesh.VolumeSpec("v" <> int.to_string(i), "/v" <> int.to_string(i), 1)
    })
  let c = mesh.MeshConfig(containers, networks, volumes, 33)
  let assert Ok(d) = configured(c)
  let assert api.Observed(_, _, f) = mini.project(Ok(d), 1000)
  { dict.size(f) <= 100 } |> should.be_true
  list.all(dict.to_list(f), fn(p) {
    string.byte_size(p.0) <= 128 && string.byte_size(p.1) <= 2048
  })
  |> should.be_true
  let text = string.join(dict.values(f), "\n")
  list.each(containers, fn(c) {
    string.contains(text, c.name <> " · port ") |> should.be_true
  })
  list.each(networks, fn(n) {
    string.contains(text, n.name <> " · " <> n.subnet) |> should.be_true
  })
  list.each(volumes, fn(v) {
    string.contains(text, v.name <> " · 1 MiB") |> should.be_true
  })
}

pub fn ordering_independent_of_input_test() {
  let c = default()
  let d =
    mesh.MeshConfig(
      ..c,
      containers: list.reverse(c.containers),
      networks: list.reverse(c.networks),
      volumes: list.reverse(c.volumes),
    )
  mini.observe(Some(raw(c)), 1000)
  |> should.equal(mini.observe(Some(raw(d)), 1000))
}

pub fn summary_keeps_router_page_contract_on_success_and_failure_test() {
  list.each([source.from_environment(None),source.from_environment(Some("{}"))],fn(value) {
    string.contains(json.to_string(source.summary(value)),"\"page\":\"Mesh Configuration\"") |> should.be_true
  })
}
