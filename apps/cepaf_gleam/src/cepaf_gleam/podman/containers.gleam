import cepaf_gleam/podman/domain.{
  type ContainerSummary, ContainerSummary, string_to_status,
}
import cepaf_gleam/podman/http_client.{type PodmanClient}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "os_cmd")
fn erl_os_cmd(cmd: String) -> Result(BitArray, String)

pub fn list_containers(
  client: PodmanClient,
  all: Bool,
) -> Result(List(ContainerSummary), String) {
  case list_containers_rest(client, all) {
    Ok(containers) -> Ok(containers)
    Error(_) -> list_containers_cli(all)
  }
}

fn list_containers_cli(all: Bool) -> Result(List(ContainerSummary), String) {
  let format =
    "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}|{{.Created}}"
  let cmd =
    "podman ps --format \""
    <> format
    <> "\""
    <> case all {
      True -> " --all"
      False -> ""
    }
  case erl_os_cmd(cmd) {
    Ok(output_binary) -> {
      case bit_array.to_string(output_binary) {
        Ok(output_str) -> {
          let containers = parse_containers_pipe(output_str)
          Ok(containers)
        }
        Error(_) -> Error("Failed to read podman output as UTF-8")
      }
    }
    Error(e) -> Error("podman cmd failed: " <> e)
  }
}

fn parse_containers_pipe(content: String) -> List(ContainerSummary) {
  let lines = string.split(content, "\n")
  list.filter_map(lines, fn(line) {
    case string.split(line, "|") {
      [id, names_str, image, status, state_str, created_str] -> {
        let names = string.split(names_str, ",") |> list.map(string.trim)
        let created = case int.parse(created_str) {
          Ok(i) -> i
          Error(_) -> 0
        }
        Ok(
          ContainerSummary(
            id: id,
            names: names,
            image: image,
            image_id: "",
            command: "",
            created: created,
            state: domain.string_to_status(state_str),
            status: status,
            ports: [],
            labels: dict.new(),
            mounts: [],
            networks: [],
          ),
        )
      }
      _ -> Error(Nil)
    }
  })
}

fn list_containers_rest(
  client: PodmanClient,
  all: Bool,
) -> Result(List(ContainerSummary), String) {
  let query = case all {
    True -> "/containers/json?all=true"
    False -> "/containers/json"
  }

  case http_client.get(client, query) {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      case json.parse(from: body_str, using: decode_container_list()) {
        Ok(containers) -> Ok(containers)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn start(client: PodmanClient, name: String) -> Result(Nil, String) {
  case start_rest(client, name) {
    Ok(_) -> Ok(Nil)
    Error(_) -> start_cli(name)
  }
}

fn start_rest(client: PodmanClient, name: String) -> Result(Nil, String) {
  case http_client.post(client, "/containers/" <> name <> "/start", <<>>) {
    Ok(resp) if resp.status == 204 || resp.status == 304 -> Ok(Nil)
    Ok(resp) -> Error("Unexpected status code: " <> int.to_string(resp.status))
    Error(e) -> Error(e)
  }
}

fn start_cli(name: String) -> Result(Nil, String) {
  let cmd = "podman start " <> name
  case erl_os_cmd(cmd) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error("podman start failed: " <> e)
  }
}

pub fn stop(
  client: PodmanClient,
  name: String,
  timeout: option.Option(Int),
) -> Result(Nil, String) {
  case stop_rest(client, name, timeout) {
    Ok(_) -> Ok(Nil)
    Error(_) -> stop_cli(name)
  }
}

fn stop_rest(
  client: PodmanClient,
  name: String,
  timeout: option.Option(Int),
) -> Result(Nil, String) {
  let query = case timeout {
    option.Some(t) -> "?t=" <> int.to_string(t)
    option.None -> ""
  }
  case
    http_client.post(client, "/containers/" <> name <> "/stop" <> query, <<>>)
  {
    Ok(resp) if resp.status == 204 || resp.status == 304 -> Ok(Nil)
    Ok(resp) -> Error("Unexpected status code: " <> int.to_string(resp.status))
    Error(e) -> Error(e)
  }
}

fn stop_cli(name: String) -> Result(Nil, String) {
  let cmd = "podman stop " <> name
  case erl_os_cmd(cmd) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error("podman stop failed: " <> e)
  }
}

pub fn restart(client: PodmanClient, name: String) -> Result(Nil, String) {
  case restart_rest(client, name) {
    Ok(_) -> Ok(Nil)
    Error(_) -> restart_cli(name)
  }
}

fn restart_rest(client: PodmanClient, name: String) -> Result(Nil, String) {
  case http_client.post(client, "/containers/" <> name <> "/restart", <<>>) {
    Ok(resp) if resp.status == 204 -> Ok(Nil)
    Ok(resp) -> Error("Unexpected status code: " <> int.to_string(resp.status))
    Error(e) -> Error(e)
  }
}

fn restart_cli(name: String) -> Result(Nil, String) {
  let cmd = "podman restart " <> name
  case erl_os_cmd(cmd) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error("podman restart failed: " <> e)
  }
}

pub fn remove(
  client: PodmanClient,
  name: String,
  force: Bool,
) -> Result(Nil, String) {
  let query = case force {
    True -> "?force=true"
    False -> ""
  }
  case
    http_client.send_request(
      client,
      http.Delete,
      "/containers/" <> name <> query,
      <<>>,
    )
  {
    Ok(resp) if resp.status == 204 -> Ok(Nil)
    Ok(resp) -> Error("Unexpected status code: " <> int.to_string(resp.status))
    Error(e) -> Error(e)
  }
}

pub fn inspect(
  client: PodmanClient,
  name: String,
) -> Result(domain.ContainerInspect, String) {
  case http_client.get(client, "/containers/" <> name <> "/json") {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      case json.parse(from: body_str, using: decode_container_inspect()) {
        Ok(container) -> Ok(container)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

fn string_of_json_error(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(b) -> "Unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "Unexpected sequence: " <> s
    json.UnableToDecode(errors) -> {
      list.map(errors, fn(e) {
        e.expected
        <> " at "
        <> list.fold(e.path, "", fn(acc, p) { acc <> "/" <> p })
      })
      |> list.first
      |> result.unwrap("Unable to decode")
    }
  }
}

fn decode_container_list() -> decode.Decoder(List(ContainerSummary)) {
  decode.list(of: decode_container_summary())
}

fn decode_container_summary() -> decode.Decoder(ContainerSummary) {
  use id <- decode.field("Id", decode.string)
  use names <- decode.field("Names", decode.list(decode.string))
  use image <- decode.field("Image", decode.string)
  use image_id <- decode.field("ImageID", decode.string)
  use command <- decode.field("Command", decode.string)
  use created <- decode.field("Created", decode.int)
  use state <- decode.field(
    "State",
    decode.string |> decode.map(string_to_status),
  )
  use status <- decode.field("Status", decode.string)
  use ports <- decode.field("Ports", decode.list(decode_port_mapping()))
  use labels <- decode.field(
    "Labels",
    decode.dict(decode.string, decode.string),
  )
  use mounts <- decode.field("Mounts", decode.list(decode_mount()))
  use networks <- decode.field("Networks", decode.list(decode.string))

  decode.success(ContainerSummary(
    id: id,
    names: names,
    image: image,
    image_id: image_id,
    command: command,
    created: created,
    state: state,
    status: status,
    ports: ports,
    labels: labels,
    mounts: mounts,
    networks: networks,
  ))
}

fn decode_port_mapping() -> decode.Decoder(domain.PortMapping) {
  use container_port <- decode.field("container_port", decode.int)
  use host_port <- decode.optional_field(
    "host_port",
    Error(Nil),
    decode.int |> decode.map(Ok),
  )
  use host_ip <- decode.optional_field(
    "host_ip",
    Error(Nil),
    decode.string |> decode.map(Ok),
  )
  use protocol <- decode.field(
    "protocol",
    decode.string |> decode.map(fn(_) { domain.Tcp }),
  )
  use range <- decode.optional_field(
    "range",
    Error(Nil),
    decode.int |> decode.map(Ok),
  )

  decode.success(domain.PortMapping(
    container_port: container_port,
    host_port: host_port |> option.from_result,
    host_ip: host_ip |> option.from_result,
    protocol: protocol,
    range: range |> option.from_result,
  ))
}

fn decode_mount() -> decode.Decoder(domain.Mount) {
  use mount_type <- decode.field(
    "Type",
    decode.string |> decode.map(fn(_) { domain.MountVolume }),
  )
  use source <- decode.field("Source", decode.string)
  use target <- decode.field("Destination", decode.string)
  use read_only <- decode.field("RW", decode.bool |> decode.map(fn(rw) { !rw }))
  use options <- decode.optional_field(
    "Options",
    [],
    decode.list(decode.string),
  )

  decode.success(domain.Mount(
    mount_type: mount_type,
    source: source,
    target: target,
    read_only: read_only,
    options: options,
  ))
}

fn decode_container_inspect() -> decode.Decoder(domain.ContainerInspect) {
  use id <- decode.field("Id", decode.string)
  use created <- decode.field("Created", decode.string)
  use path <- decode.field("Path", decode.string)
  use args <- decode.field("Args", decode.list(decode.string))
  use state <- decode.field("State", decode_container_state_detail())
  use image <- decode.field("Image", decode.string)
  use image_name <- decode.field("ImageName", decode.string)
  use name <- decode.field("Name", decode.string)
  use restart_count <- decode.field("RestartCount", decode.int)
  use platform <- decode.field("Platform", decode.string)
  use mount_label <- decode.field("MountLabel", decode.string)
  use process_label <- decode.field("ProcessLabel", decode.string)
  use mounts <- decode.field("Mounts", decode.list(decode_mount()))
  use labels <- decode.field(
    "Labels",
    decode.dict(decode.string, decode.string),
  )
  use env <- decode.field(
    "Config",
    decode.at(["Env"], decode.list(decode.string)),
  )

  decode.success(domain.ContainerInspect(
    id: id,
    created: created,
    path: path,
    args: args,
    state: state,
    image: image,
    image_name: image_name,
    name: name,
    restart_count: restart_count,
    platform: platform,
    mount_label: mount_label,
    process_label: process_label,
    mounts: mounts,
    labels: labels,
    env: env,
  ))
}

fn decode_container_state_detail() -> decode.Decoder(
  domain.ContainerStateDetail,
) {
  use status <- decode.field(
    "Status",
    decode.string |> decode.map(domain.string_to_status),
  )
  use running <- decode.field("Running", decode.bool)
  use paused <- decode.field("Paused", decode.bool)
  use restarting <- decode.field("Restarting", decode.bool)
  use oom_killed <- decode.field("OOMKilled", decode.bool)
  use dead <- decode.field("Dead", decode.bool)
  use pid <- decode.field("Pid", decode.int)
  use exit_code <- decode.field("ExitCode", decode.int)
  use error <- decode.field("Error", decode.string)
  use started_at <- decode.field("StartedAt", decode.string)
  use finished_at <- decode.field("FinishedAt", decode.string)
  use health <- decode.optional_field(
    "Health",
    option.None,
    decode_health_check_result() |> decode.map(option.Some),
  )

  decode.success(domain.ContainerStateDetail(
    status: status,
    running: running,
    paused: paused,
    restarting: restarting,
    oom_killed: oom_killed,
    dead: dead,
    pid: pid,
    exit_code: exit_code,
    error: error,
    started_at: started_at,
    finished_at: finished_at,
    health: health,
  ))
}

fn decode_health_check_result() -> decode.Decoder(domain.HealthCheckResult) {
  use status <- decode.field(
    "Status",
    decode.string |> decode.map(domain.string_to_health_status),
  )
  use failing_streak <- decode.field("FailingStreak", decode.int)
  use log <- decode.field("Log", decode.list(decode_health_check_log()))

  decode.success(domain.HealthCheckResult(
    status: status,
    failing_streak: failing_streak,
    log: log,
  ))
}

fn decode_health_check_log() -> decode.Decoder(domain.HealthCheckLog) {
  use start <- decode.field("Start", decode.string)
  use end <- decode.field("End", decode.string)
  use exit_code <- decode.field("ExitCode", decode.int)
  use output <- decode.field("Output", decode.string)

  decode.success(domain.HealthCheckLog(
    start: start,
    end: end,
    exit_code: exit_code,
    output: output,
  ))
}
