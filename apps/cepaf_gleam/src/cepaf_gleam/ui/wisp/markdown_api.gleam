// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-SMRITI-001
// Wisp REST endpoint for markdown/zettel rendering (JSON).
// Triple-Interface: Lustre (markdown.gleam) + Wisp (this) + TUI (markdown_view.gleam).

import cepaf_gleam/smriti/catalog.{type CatalogEntry}
import gleam/json
import gleam/list

/// Render a catalog entry as JSON with pre-parsed markdown structure.
pub fn entry_to_markdown_json(entry: CatalogEntry) -> json.Json {
  json.object([
    #("id", json.string(entry.id)),
    #("name", json.string(entry.name)),
    #("category", json.string(entry.category)),
    #("description", json.string(entry.description)),
    #("tags", json.array(entry.tags, json.string)),
    #("created_at", json.string(entry.created_at)),
    #("content_type", json.string("markdown")),
  ])
}

/// Render multiple entries as a JSON array.
pub fn entries_to_json(entries: List(CatalogEntry)) -> json.Json {
  json.object([
    #("entries", json.array(entries, entry_to_markdown_json)),
    #("count", json.int(list.length(entries))),
  ])
}
