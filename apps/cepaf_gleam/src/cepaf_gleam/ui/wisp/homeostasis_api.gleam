//// Shared pure-router adapter. Effects are explicit in data.read, not rendering.
import cepaf_gleam/ui/homeostasis_data as data
import cepaf_gleam/ui/homeostasis_status as status
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

pub fn response(path: String) -> Option(String) {
  let split = string.split_once(path,"?") |> result.unwrap(#(path,""))
  case split.0 {
    "/api/v1/homeostasis" | "/api/v1/homeostasis/evolution" -> {
      let query = uri.parse_query(split.1) |> result.unwrap([#("mode","invalid")])
      case data.parse(query) {
        Error(_) -> Some("{\"error\":\"invalid_homeostasis_selection\"}")
        Ok(selection) -> {
          let #(snapshot,now) = data.read(selection)
          Some(status.to_json(snapshot,now))
        }
      }
    }
    _ -> None
  }
}
