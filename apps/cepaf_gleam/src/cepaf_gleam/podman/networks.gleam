import cepaf_gleam/podman/domain.{
  type Network, type NetworkSpec, type Subnet, Network, Subnet,
}
import cepaf_gleam/podman/http_client.{type PodmanClient}
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result

pub fn list_networks(client: PodmanClient) -> Result(List(Network), String) {
  case http_client.get(client, "/networks/json") {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      case json.parse(from: body_str, using: decode.list(decode_network())) {
        Ok(networks) -> Ok(networks)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn inspect(client: PodmanClient, name: String) -> Result(Network, String) {
  case http_client.get(client, "/networks/" <> name <> "/json") {
    Ok(resp) -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }

      case json.parse(from: body_str, using: decode_network()) {
        Ok(network) -> Ok(network)
        Error(e) -> Error("JSON decode error: " <> string_of_json_error(e))
      }
    }
    Error(e) -> Error(e)
  }
}

pub fn create(
  client: PodmanClient,
  spec: NetworkSpec,
) -> Result(Network, String) {
  let body = encode_network_spec(spec)
  case
    http_client.post(
      client,
      "/networks/create",
      bit_array.from_string(json.to_string(body)),
    )
  {
    Ok(resp) if resp.status == 201 -> {
      let body_str = case bit_array.to_string(resp.body) {
        Ok(s) -> s
        Error(_) -> ""
      }
      case json.parse(from: body_str, using: decode_network()) {
        Ok(network) -> Ok(network)
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

fn decode_network() -> decode.Decoder(Network) {
  use name <- decode.field("Name", decode.string)
  use id <- decode.field("Id", decode.string)
  use driver <- decode.field("Driver", decode.string)
  use created <- decode.field("Created", decode.string)
  use subnets <- decode.optional_field(
    "Subnets",
    [],
    decode.list(decode_subnet()),
  )
  use internal <- decode.field("Internal", decode.bool)
  use dns_enabled <- decode.field("DNSEnabled", decode.bool)
  use labels <- decode.field(
    "Labels",
    decode.dict(decode.string, decode.string),
  )
  use options <- decode.field(
    "Options",
    decode.dict(decode.string, decode.string),
  )

  decode.success(Network(
    name: name,
    id: id,
    driver: driver,
    created: created,
    subnets: subnets,
    internal: internal,
    dns_enabled: dns_enabled,
    labels: labels,
    options: options,
  ))
}

fn decode_subnet() -> decode.Decoder(Subnet) {
  use subnet <- decode.field("Subnet", decode.string)
  use gateway <- decode.optional_field(
    "Gateway",
    option.None,
    decode.string |> decode.map(option.Some),
  )

  decode.success(Subnet(subnet: subnet, gateway: gateway))
}

fn encode_network_spec(spec: NetworkSpec) -> json.Json {
  json.object([
    #("Name", json.string(spec.name)),
    #("Driver", json.string(spec.driver)),
    #("Internal", json.bool(spec.internal)),
    #("DNSEnabled", json.bool(spec.dns_enabled)),
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
