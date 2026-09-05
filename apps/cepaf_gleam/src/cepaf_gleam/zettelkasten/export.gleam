//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/export</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SMRITI-082, SC-SMRITI-083, SC-SMRITI-072</stamp-controls></compliance>
//// </c3i-module>
////
//// Obsidian vault export — holons → markdown files with YAML frontmatter.
//// STAMP: SC-SMRITI-082 (Obsidian .obsidian config), SC-SMRITI-083 (YAML frontmatter)

import cepaf_gleam/zettelkasten/entropy
import cepaf_gleam/zettelkasten/types.{type Holon, type HolonEdge}
import gleam/list
import gleam/option
import gleam/string

/// Export a holon as Obsidian-compatible markdown with YAML frontmatter.
pub fn holon_to_obsidian(holon: Holon, edges: List(HolonEdge)) -> String {
  let frontmatter = build_frontmatter(holon)
  let backlinks = build_backlinks(holon.uuid, edges)
  let stamp_section = build_stamp_section(holon.stamp_refs)

  frontmatter
  <> "\n"
  <> holon.content
  <> "\n"
  <> stamp_section
  <> "\n"
  <> backlinks
}

/// Build YAML frontmatter block.
fn build_frontmatter(holon: Holon) -> String {
  "---\n"
  <> "uuid: "
  <> holon.uuid
  <> "\n"
  <> "level: "
  <> types.level_to_string(holon.level)
  <> "\n"
  <> "rhetorical: "
  <> rhetorical_to_string(holon.rhetorical)
  <> "\n"
  <> "entropy: "
  <> float_to_string_2dp(holon.entropy)
  <> "\n"
  <> "decay_rate: "
  <> types.decay_to_string(holon.decay_rate)
  <> "\n"
  <> "freshness: "
  <> entropy.entropy_label(holon.entropy)
  <> "\n"
  <> "tags: ["
  <> string.join(holon.tags, ", ")
  <> "]\n"
  <> case holon.cluster {
    option.Some(c) -> "cluster: " <> c <> "\n"
    option.None -> ""
  }
  <> "created: "
  <> holon.created_at
  <> "\n"
  <> "updated: "
  <> holon.updated_at
  <> "\n"
  <> "---\n"
}

/// Build backlinks section from edges.
fn build_backlinks(holon_id: String, edges: List(HolonEdge)) -> String {
  let inbound =
    edges
    |> list.filter(fn(e) { e.target_id == holon_id })
    |> list.map(fn(e) {
      "- [["
      <> e.source_id
      <> "]] ("
      <> types.link_type_to_string(e.link_type)
      <> ")"
    })

  case inbound {
    [] -> ""
    links -> "\n## Backlinks\n" <> string.join(links, "\n") <> "\n"
  }
}

/// Build STAMP references section.
fn build_stamp_section(refs: List(String)) -> String {
  case refs {
    [] -> ""
    stamps ->
      "\n## STAMP References\n"
      <> string.join(list.map(stamps, fn(s) { "- `" <> s <> "`" }), "\n")
      <> "\n"
  }
}

/// Generate Obsidian vault index (MOC — Map of Content).
pub fn generate_index(holons: List(Holon)) -> String {
  let ecosystem = list.filter(holons, fn(h) { h.level == types.Ecosystem })
  let molecular = list.filter(holons, fn(h) { h.level == types.Molecular })
  let organism = list.filter(holons, fn(h) { h.level == types.Organism })

  "# Indrajaal Knowledge Index\n\n"
  <> "## Architecture (Ecosystem)\n"
  <> holon_list_to_links(ecosystem)
  <> "\n## Specifications (Molecular)\n"
  <> holon_list_to_links(molecular)
  <> "\n## Sessions (Organism)\n"
  <> holon_list_to_links(list.take(organism, 20))
  <> "\n\n---\n"
  <> "Total: "
  <> int_to_string(list.length(holons))
  <> " zettels\n"
}

/// Generate .obsidian/app.json config.
pub fn obsidian_config() -> String {
  "{\"strictLineBreaks\": false, \"showFrontmatter\": true, \"defaultViewMode\": \"source\"}"
}

/// Compute vault filename from holon title.
pub fn vault_filename(holon: Holon) -> String {
  holon.title
  |> string.replace("/", "-")
  |> string.replace(":", "-")
  |> string.replace("\\", "-")
  |> string.replace("?", "")
  |> string.replace("\"", "")
  |> string.trim
  |> fn(s) { s <> ".md" }
}

// Helpers
fn holon_list_to_links(holons: List(Holon)) -> String {
  holons
  |> list.map(fn(h) { "- [[" <> h.title <> "]]" })
  |> string.join("\n")
}

fn rhetorical_to_string(r: types.RhetoricalFunction) -> String {
  case r {
    types.Axiom -> "axiom"
    types.Evidence -> "evidence"
    types.Hypothesis -> "hypothesis"
    types.Anecdote -> "anecdote"
  }
}

fn float_to_string_2dp(f: Float) -> String {
  let whole = truncate_positive(f)
  let frac = truncate_positive({ f -. int_to_float(whole) } *. 100.0)
  int_to_string(whole)
  <> "."
  <> case frac < 10 {
    True -> "0" <> int_to_string(frac)
    False -> int_to_string(frac)
  }
}

fn truncate_positive(f: Float) -> Int {
  truncate_acc(f, 0)
}

fn truncate_acc(f: Float, acc: Int) -> Int {
  case f <. 1.0 {
    True -> acc
    False -> truncate_acc(f -. 1.0, acc + 1)
  }
}

fn int_to_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    1 -> 1.0
    _ -> {
      let half = int_to_float(n / 2)
      let rem = case n % 2 {
        0 -> 0.0
        _ -> 1.0
      }
      half +. half +. rem
    }
  }
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
