import envoy
import gleam/bit_array
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import ocaml_test_inventory/files
import ocaml_test_inventory/inventory.{
  type Finding, Changed, Entry, InvalidInventory, Missing, Unreadable,
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

fn entry_decoder() {
  use path <- decode.field("source_path", decode.string)
  use sha256 <- decode.field("source_sha256", decode.string)
  decode.success(Entry(path, sha256))
}

fn finding_json(finding: Finding) -> json.Json {
  let #(kind, detail) = case finding {
    Changed(path) -> #("changed", path)
    Missing(path) -> #("missing", path)
    Unreadable(path) -> #("unreadable", path)
    InvalidInventory(reason) -> #("invalid_inventory", reason)
  }
  json.object([#("kind", json.string(kind)), #("detail", json.string(detail))])
}

fn emit(root: String, count: Int, findings: List(Finding)) {
  io.println(
    json.to_string(
      json.object([
        #("source_root", json.string(root)),
        #("candidate_entries", json.int(count)),
        #("preserved", json.bool(list.is_empty(findings))),
        #("case_coverage", json.null()),
        #("findings", json.array(findings, finding_json)),
      ]),
    ),
  )
  case findings {
    [] -> Nil
    _ -> halt(1)
  }
}

pub fn main() {
  let assert Ok(root) = envoy.get("UOS_INVENTORY_ROOT")
  let assert Ok(path) = envoy.get("UOS_INVENTORY_FILE")
  let decoder = {
    use version <- decode.field("schema_version", decode.int)
    use entries <- decode.field("candidates", decode.list(entry_decoder()))
    decode.success(#(version, entries))
  }
  case files.read_checked(path) {
    Error(_) ->
      emit(root, 0, [InvalidInventory("inventory unreadable or unsafe")])
    Ok(bytes) ->
      case bit_array.to_string(bytes) {
        Error(_) -> emit(root, 0, [InvalidInventory("inventory is not UTF8")])
        Ok(text) ->
          case json.parse(text, decoder) {
            Ok(#(1, entries)) ->
              emit(root, list.length(entries), files.verify(root, entries))
            _ ->
              emit(root, 0, [
                InvalidInventory(
                  "schema_version 1 and typed candidates required",
                ),
              ])
          }
      }
  }
}
