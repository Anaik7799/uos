//// Authenticated projection of the shared declared mesh configuration.

import cepaf_gleam/config/mesh_config as mesh
import cepaf_gleam/config/mesh_source
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string

fn row(kind: String, index: Int, value: String) {
  #(kind <> " " <> string.pad_start(int.to_string(index + 1), 2, "0"), value)
}

fn groups(
  kind: String,
  rows: List(#(String, String)),
  index: Int,
) -> List(#(String, String)) {
  case rows {
    [] -> []
    _ -> {
      let #(chunk, rest) = list.split(rows, 8)
      [
        row(
          kind <> " group",
          index,
          string.join(list.map(chunk, fn(x) { x.1 }), "\n"),
        ),
        ..groups(kind, rest, index + 1)
      ]
    }
  }
}

pub fn observe(raw: Option(String), at: Int) -> api.Observation {
  project(mesh_source.from_environment(raw), at)
}

pub fn project(
  value: Result(mesh_source.Declaration, String),
  at: Int,
) -> api.Observation {
  case value {
    Error(_) -> api.Unavailable("mesh_configuration_invalid")
    Ok(d) -> {
      let c = mesh_source.configuration(d)
      let fields = [
        #("Configuration source", mesh_source.source(d)),
        #("Scope", "Declared configuration only"),
        #("Deployment", "Not confirmed"),
        #("Runtime admission", "NOT_GRANTED"),
        #("Validation", "Structural checks passed"),
        #("Containers", int.to_string(list.length(c.containers))),
        #("Networks", int.to_string(list.length(c.networks))),
        #("Volumes", int.to_string(list.length(c.volumes))),
        #("Quorum", int.to_string(c.quorum_size)),
        #("Declared CPU cores", float.to_string(mesh.total_cpu_allocation(c))),
        #("Declared memory MiB", int.to_string(mesh.total_memory_allocation(c))),
      ]
      let containers =
        list.index_map(
          list.sort(c.containers, fn(a, b) { string.compare(a.name, b.name) }),
          fn(x, i) {
            row(
              "Container",
              i,
              x.name
                <> " · port "
                <> int.to_string(x.port)
                <> " · CPU "
                <> float.to_string(x.cpu_limit)
                <> " · "
                <> int.to_string(x.memory_mb)
                <> " MiB",
            )
          },
        )
      let networks =
        list.index_map(
          list.sort(c.networks, fn(a, b) { string.compare(a.name, b.name) }),
          fn(x, i) {
            row("Network", i, x.name <> " · " <> x.subnet <> " · " <> x.driver)
          },
        )
      let volumes =
        list.index_map(
          list.sort(c.volumes, fn(a, b) { string.compare(a.name, b.name) }),
          fn(x, i) {
            row(
              "Volume",
              i,
              x.name <> " · " <> int.to_string(x.size_mb) <> " MiB",
            )
          },
        )
      api.Observed(
        at,
        "declared_mesh_configuration",
        dict.from_list(
          list.flatten([
            fields,
            groups("Container", containers, 0),
            groups("Network", networks, 0),
            groups("Volume", volumes, 0),
          ]),
        ),
      )
    }
  }
}
