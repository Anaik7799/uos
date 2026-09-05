import cepaf_gleam/podman/domain.{type Volume, type VolumeSpec, Volume}
import cepaf_gleam/podman/http_client.{type PodmanClient}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

pub fn list_volumes(client: PodmanClient) -> Result(List(Volume), String) {
  case http_client.get(client, "/volumes/json") {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      // Podman returns { Volumes: [...], Warnings: [...] }
      case json.parse(from: body_str, using: decode_volumes_response()) {
        Ok(volumes) -> Ok(volumes)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn inspect(client: PodmanClient, name: String) -> Result(Volume, String) {
  case http_client.get(client, "/volumes/" <> name <> "/json") {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      case json.parse(from: body_str, using: decode_volume()) {
        Ok(volume) -> Ok(volume)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn create(client: PodmanClient, spec: VolumeSpec) -> Result(Volume, String) {
  let body = encode_volume_spec(spec)
  case
    http_client.post(
      client,
      "/volumes/create",
      bit_array.from_string(json.to_string(body)),
    )
  {
    Ok(resp) if resp.status == 201 -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }
      case json.parse(from: body_str, using: decode_volume()) {
        Ok(volume) -> Ok(volume)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Ok(resp) -> Error("Unexpected status code: " <> int_to_string(resp.status))
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

fn decode_volumes_response() -> decode.Decoder(List(Volume)) {
  use volumes <- decode.field("Volumes", decode.list(decode_volume()))
  decode.success(volumes)
}

fn decode_volume() -> decode.Decoder(Volume) {
  use name <- decode.field("Name", decode.string)
  use driver <- decode.field("Driver", decode.string)
  use mountpoint <- decode.field("Mountpoint", decode.string)
  use created_at <- decode.field("CreatedAt", decode.string)
  use labels <- decode.optional_field(
    "Labels",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  use options <- decode.optional_field(
    "Options",
    dict.new(),
    decode.dict(decode.string, decode.string),
  )
  use scope <- decode.field("Scope", decode.string)

  decode.success(Volume(
    name: name,
    driver: driver,
    mountpoint: mountpoint,
    created_at: created_at,
    labels: labels,
    options: options,
    scope: scope,
  ))
}

fn encode_volume_spec(spec: VolumeSpec) -> json.Json {
  json.object([
    #("Name", json.string(spec.name)),
    #("Driver", json.string(spec.driver)),
    #(
      "Labels",
      json.object(
        list.map(dict.to_list(spec.labels), fn(pair) {
          #(pair.0, json.string(pair.1))
        }),
      ),
    ),
    #(
      "Options",
      json.object(
        list.map(dict.to_list(spec.options), fn(pair) {
          #(pair.0, json.string(pair.1))
        }),
      ),
    ),
  ])
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String
