// STAMP: SC-SMRITI-001, SC-GLM-CORE-002, SC-ARCH-SPLIT-003
// AOR: AOR-SMRITI-001, AOR-GLM-005

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type CatalogEntry {
  CatalogEntry(
    id: String,
    name: String,
    category: String,
    description: String,
    tags: List(String),
    created_at: String,
  )
}

pub type CatalogQuery {
  CatalogQuery(
    category: Option(String),
    tags: List(String),
    search_text: Option(String),
    limit: Int,
  )
}

pub type CatalogResult {
  CatalogResult(
    entries: List(CatalogEntry),
    total_count: Int,
    query_time_ms: Int,
  )
}

pub fn search(query: CatalogQuery) -> Result(CatalogResult, String) {
  let search_term = build_search_term(query)
  let raw_json = nif.knowledge_search(search_term)

  let decoder = decode.string
  case json.parse(raw_json, decoder) {
    Ok(_) | Error(_) -> {
      let entries = parse_nif_results(raw_json, query)
      Ok(CatalogResult(
        entries: entries,
        total_count: list.length(entries),
        query_time_ms: 0,
      ))
    }
  }
}

pub fn index_entry(entry: CatalogEntry) -> Result(Nil, String) {
  let payload =
    entry.category <> ": " <> entry.name <> " — " <> entry.description
  let raw = nif.plan_add_task(payload, "P2")
  case string.contains(raw, "error") {
    True -> Error("Index failed: " <> raw)
    False -> Ok(Nil)
  }
}

pub fn delete_entry(id: String) -> Result(Nil, String) {
  let raw = nif.plan_update_task(id, "completed")
  case string.contains(raw, "error") {
    True -> Error("Delete failed: " <> raw)
    False -> Ok(Nil)
  }
}

pub fn ingest(_path: String) -> Result(Int, String) {
  Error("Ingest failed: No NIF for read_file")
}

fn build_search_term(query: CatalogQuery) -> String {
  let parts = []
  let parts = case query.search_text {
    Some(text) -> [text, ..parts]
    None -> parts
  }
  let parts = case query.category {
    Some(cat) -> [cat, ..parts]
    None -> parts
  }
  let parts = case query.tags {
    [] -> parts
    tags -> [string.join(tags, " "), ..parts]
  }
  case parts {
    [] -> "*"
    _ -> string.join(parts, " ")
  }
}

fn parse_nif_results(
  raw_json: String,
  query: CatalogQuery,
) -> List(CatalogEntry) {
  let entries = extract_entries_from_json(raw_json)
  let filtered = case query.category {
    Some(cat) -> list.filter(entries, fn(e) { e.category == cat })
    None -> entries
  }
  let filtered = case query.tags {
    [] -> filtered
    required ->
      list.filter(filtered, fn(e) {
        list.all(required, fn(t) { list.contains(e.tags, t) })
      })
  }
  list.take(filtered, query.limit)
}

fn extract_entries_from_json(raw: String) -> List(CatalogEntry) {
  let lines =
    string.split(raw, "\n") |> list.filter(fn(l) { string.length(l) > 2 })
  list.filter_map(lines, fn(line) {
    case json.parse(line, entry_decoder()) {
      Ok(entry) -> Ok(entry)
      Error(_) -> Error(Nil)
    }
  })
}

fn entry_decoder() -> decode.Decoder(CatalogEntry) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use category <- decode.optional_field("category", "general", decode.string)
  use content <- decode.optional_field("content", "", decode.string)
  use created_at <- decode.optional_field("created_at", "", decode.string)
  decode.success(CatalogEntry(
    id: id,
    name: title,
    category: category,
    description: content,
    tags: [],
    created_at: created_at,
  ))
}

pub fn new_entry(
  id: String,
  name: String,
  category: String,
  description: String,
) -> CatalogEntry {
  CatalogEntry(id, name, category, description, [], "")
}

pub fn matches_query(entry: CatalogEntry, query: CatalogQuery) -> Bool {
  let category_match = case query.category {
    None -> True
    Some(cat) -> entry.category == cat
  }
  let tags_match = case query.tags {
    [] -> True
    required_tags ->
      list.all(required_tags, fn(tag) { list.contains(entry.tags, tag) })
  }
  let text_match = case query.search_text {
    None -> True
    Some(text) -> {
      let lower_text = string.lowercase(text)
      string.contains(string.lowercase(entry.name), lower_text)
      || string.contains(string.lowercase(entry.description), lower_text)
    }
  }
  category_match && tags_match && text_match
}

pub fn entry_to_json(e: CatalogEntry) -> json.Json {
  json.object([
    #("id", json.string(e.id)),
    #("name", json.string(e.name)),
    #("category", json.string(e.category)),
    #("description", json.string(e.description)),
    #("tags", json.array(e.tags, json.string)),
    #("created_at", json.string(e.created_at)),
  ])
}

pub fn query_to_json(q: CatalogQuery) -> json.Json {
  json.object([
    #("category", case q.category {
      None -> json.null()
      Some(c) -> json.string(c)
    }),
    #("tags", json.array(q.tags, json.string)),
    #("search_text", case q.search_text {
      None -> json.null()
      Some(t) -> json.string(t)
    }),
    #("limit", json.int(q.limit)),
  ])
}

pub fn result_to_json(r: CatalogResult) -> json.Json {
  json.object([
    #("entries", json.array(r.entries, entry_to_json)),
    #("total_count", json.int(r.total_count)),
    #("query_time_ms", json.int(r.query_time_ms)),
  ])
}
