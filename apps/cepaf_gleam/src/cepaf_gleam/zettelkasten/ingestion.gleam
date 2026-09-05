//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/ingestion</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-IKE-001, SC-SMRITI-131, SC-SMRITI-140</stamp-controls></compliance>
//// </c3i-module>
////
//// Document ingestion pipeline for Zettelkasten.
//// Parses markdown files into holons, splits on ## headers, assigns levels.
//// STAMP: SC-IKE-001 (ingestion pipeline), SC-SMRITI-131 (FTS5), SC-SMRITI-140 (evolution recorded)

import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/types.{
  type DecayRate, type Holon, type HolonLevel, type KnowledgeSource,
  type RhetoricalFunction, DocumentSource, Holon,
}
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{None}
import gleam/string

/// Ingestion result for a single document.
pub type IngestionResult {
  IngestionResult(
    source_path: String,
    holons_created: Int,
    stamp_refs_found: Int,
    errors: List(String),
  )
}

/// Parse a markdown document into one or more holons.
/// Large files (> 100 lines) are split on ## headers into atomic zettels.
/// Small files become a single holon.
pub fn parse_document(
  path: String,
  content: String,
  uuid_prefix: String,
  timestamp: String,
) -> List(Holon) {
  let level = types.level_for_path(path)
  let rhetorical = types.rhetorical_for_path(path)
  let decay = types.decay_for_level(level)
  let source = DocumentSource(path: path)

  let lines = string.split(content, "\n")
  let line_count = list.length(lines)

  case line_count > 100 {
    True ->
      split_on_headers(
        path,
        content,
        uuid_prefix,
        timestamp,
        level,
        rhetorical,
        decay,
        source,
      )
    False -> [
      make_holon(
        uuid_prefix <> "-0",
        extract_title(content, path),
        content,
        path,
        level,
        rhetorical,
        decay,
        source,
        timestamp,
      ),
    ]
  }
}

/// Split content on ## headers into separate holons.
fn split_on_headers(
  path: String,
  content: String,
  uuid_prefix: String,
  timestamp: String,
  level: HolonLevel,
  rhetorical: RhetoricalFunction,
  decay: DecayRate,
  source: KnowledgeSource,
) -> List(Holon) {
  let sections = split_by_h2(content)
  case sections {
    [] -> [
      make_holon(
        uuid_prefix <> "-0",
        extract_title(content, path),
        content,
        path,
        level,
        rhetorical,
        decay,
        source,
        timestamp,
      ),
    ]
    _ ->
      list.index_map(sections, fn(section, idx) {
        let uuid = uuid_prefix <> "-" <> int_to_string(idx)
        let title = extract_title(section, path <> "#" <> int_to_string(idx))
        make_holon(
          uuid,
          title,
          section,
          path,
          level,
          rhetorical,
          decay,
          source,
          timestamp,
        )
      })
  }
}

/// Create a holon from parsed content.
fn make_holon(
  uuid: String,
  title: String,
  content: String,
  path: String,
  level: HolonLevel,
  rhetorical: RhetoricalFunction,
  decay: DecayRate,
  source: KnowledgeSource,
  timestamp: String,
) -> Holon {
  let hash = compute_content_hash(content)
  let stamps = linker.extract_stamp_refs(content)
  let tags = extract_tags(path)

  Holon(
    uuid: uuid,
    title: title,
    content: content,
    tags: tags,
    level: level,
    rhetorical: rhetorical,
    entropy: 0.0,
    decay_rate: decay,
    source: source,
    content_hash: hash,
    cluster: classify_cluster(path),
    stamp_refs: stamps,
    created_at: timestamp,
    updated_at: timestamp,
    verified_at: None,
  )
}

/// Extract title from first line (# heading) or use path as fallback.
pub fn extract_title(content: String, fallback: String) -> String {
  case string.split(content, "\n") {
    [first, ..] -> {
      let trimmed = string.trim(first)
      case string.starts_with(trimmed, "# ") {
        True -> string.drop_start(trimmed, 2) |> string.trim
        False ->
          case string.starts_with(trimmed, "## ") {
            True -> string.drop_start(trimmed, 3) |> string.trim
            False ->
              case string.starts_with(trimmed, "-- ") {
                True -> string.drop_start(trimmed, 3) |> string.trim
                False ->
                  case string.starts_with(trimmed, "////") {
                    True -> string.drop_start(trimmed, 4) |> string.trim
                    False ->
                      case trimmed == "" {
                        True -> fallback
                        False -> string.slice(trimmed, 0, 80)
                      }
                  }
              }
          }
      }
    }
    [] -> fallback
  }
}

/// Compute SHA-256 hash of content for dedup.
pub fn compute_content_hash(content: String) -> String {
  crypto.hash(crypto.Sha256, <<content:utf8>>)
  |> bit_array.base16_encode
  |> string.lowercase
  |> string.slice(0, 16)
}

/// Extract tags from file path.
fn extract_tags(path: String) -> List(String) {
  let parts = string.split(path, "/")
  case parts {
    [] -> []
    [single] -> [single]
    _ -> list.take(parts, 3)
  }
}

/// Classify into knowledge cluster based on path.
fn classify_cluster(path: String) -> option.Option(String) {
  case path {
    "docs/journal/" <> _ -> option.Some("journal")
    "docs/architecture/" <> _ -> option.Some("architecture")
    "docs/plans/" <> _ -> option.Some("plans")
    "specs/allium/" <> _ -> option.Some("allium")
    "specs/tla/" <> _ -> option.Some("formal")
    "specs/wolfram/" <> _ -> option.Some("formal")
    "specs/formal/" <> _ -> option.Some("formal")
    ".claude/rules/" <> _ -> option.Some("constraints")
    _ -> None
  }
}

/// Split content by ## headers (keep header with its section).
fn split_by_h2(content: String) -> List(String) {
  let lines = string.split(content, "\n")
  split_lines_by_h2(lines, [], [])
}

fn split_lines_by_h2(
  lines: List(String),
  current_section: List(String),
  sections: List(String),
) -> List(String) {
  case lines {
    [] ->
      case current_section {
        [] -> list.reverse(sections)
        _ ->
          list.reverse([
            string.join(list.reverse(current_section), "\n"),
            ..sections
          ])
      }
    [line, ..rest] ->
      case string.starts_with(line, "## ") {
        True ->
          case current_section {
            [] -> split_lines_by_h2(rest, [line], sections)
            _ -> {
              let section = string.join(list.reverse(current_section), "\n")
              split_lines_by_h2(rest, [line], [section, ..sections])
            }
          }
        False -> split_lines_by_h2(rest, [line, ..current_section], sections)
      }
  }
}

/// Summarize ingestion results.
pub fn summarize(results: List(IngestionResult)) -> String {
  let total_holons =
    list.fold(results, 0, fn(acc, r) { acc + r.holons_created })
  let total_stamps =
    list.fold(results, 0, fn(acc, r) { acc + r.stamp_refs_found })
  let total_errors =
    list.fold(results, 0, fn(acc, r) { acc + list.length(r.errors) })

  "Ingested "
  <> int_to_string(list.length(results))
  <> " documents → "
  <> int_to_string(total_holons)
  <> " holons, "
  <> int_to_string(total_stamps)
  <> " STAMP refs, "
  <> int_to_string(total_errors)
  <> " errors"
}

fn int_to_string(n: Int) -> String {
  case n < 0 {
    True -> "-" <> int_to_string(-n)
    False ->
      case n < 10 {
        True ->
          case n {
            0 -> "0"
            1 -> "1"
            2 -> "2"
            3 -> "3"
            4 -> "4"
            5 -> "5"
            6 -> "6"
            7 -> "7"
            8 -> "8"
            _ -> "9"
          }
        False -> int_to_string(n / 10) <> int_to_string(n % 10)
      }
  }
}
