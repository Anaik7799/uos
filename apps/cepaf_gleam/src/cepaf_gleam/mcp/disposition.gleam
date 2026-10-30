//// Explicit content reconciliation: ancestry alone never proves integration.

import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, ToolError}
import gleam/list
import gleam/string

pub type ContentDisposition {
  Unclassified
  Incorporated(content_sha256: String)
  Superseded(by_commit: String, rationale: String)
  Held(hold_id: String, reason: String)
  ActiveCandidate(commit_id: String)
}

pub type HeadEntry {
  HeadEntry(id: String, is_ancestor: Bool, disposition: ContentDisposition)
}

pub fn validate_reconciliation(
  expected_ids: List(String),
  held_ids: List(String),
  entries: List(HeadEntry),
) -> Result(Int, ToolError) {
  let ids = list.map(entries, fn(entry) { entry.id })
  case
    list.length(list.unique(expected_ids)) != list.length(expected_ids)
    || list.length(list.unique(ids)) != list.length(ids)
    || list.any(expected_ids, fn(id) { !list.contains(ids, id) })
    || list.any(ids, fn(id) { !list.contains(expected_ids, id) })
    || list.any(held_ids, fn(id) { !list.contains(expected_ids, id) })
    || list.any(entries, fn(entry) { !valid_entry(entry, held_ids) })
  {
    True ->
      Error(ToolError(
        "CONTENT_DISPOSITION_REQUIRED",
        "Every expected workspace/head requires one explicit valid content disposition; holds must remain held",
        NonRetryable,
      ))
    False -> Ok(list.length(entries))
  }
}

fn present(value: String) -> Bool {
  string.trim(value) != ""
}

fn valid_entry(entry: HeadEntry, held_ids: List(String)) -> Bool {
  present(entry.id)
  && case entry.disposition {
    Unclassified -> False
    Held(hold_id, reason) -> present(hold_id) && present(reason)
    Incorporated(digest) ->
      !list.contains(held_ids, entry.id) && present(digest)
    Superseded(commit, rationale) ->
      !list.contains(held_ids, entry.id)
      && present(commit)
      && present(rationale)
    ActiveCandidate(commit) ->
      !list.contains(held_ids, entry.id) && present(commit)
  }
}
