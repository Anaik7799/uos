//// Holon Knowledge Management (KM) page generator (sa-plan uos/holonic-mapping/20260907-1505,
//// task KM). Deterministically renders one Hermes-Wiki-style Markdown page per holon of
//// `uos_swarm/holon.holarchy()` (`docs/wiki/holons/<stamp>-holon-<id>.md`) plus one ZigVM-ZK-style
//// Map of Content page (`docs/zk/<stamp>-moc-uos-holarchy.md`) listing every holon grouped by
//// level then plane, imitating the structure of `docs/zk/20260905-1801-moc-uos-unified-master.md`
//// (MOC) and `docs/wiki/20260907-1559-risk-prioritization-guide.md` (wiki page).
////
//// Every page carries: the `YYYYMMDD-HHSS-` `stamp` filename prefix; a first-line H1; a tag line
//// with `#fractal-l<level>` `#km-triad` `#rocha-semiotics` `#cybernetics` `#zero-muda` `#zk-adr`
//// (the MOC also carries `#zk-moc` and every fractal layer it spans); a full clickable Tailscale
//// link to itself (`http://nas-1.tail55d152.ts.net:4100/files/<repo path>`); the two mandatory
//// transclusions (`[[zk:20260905-1801-moc-uos-unified-master]]`,
//// `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`); the 5-domain 18-item comprehensive
//// verification checklist (`checklist_markdown`, copied verbatim from the two templates —
//// CHK-01..CHK-04 and CHK-18 checked, CHK-05..CHK-17 UNRUN for a generated page); and a bottom
//// navigation line to the ZK Master MOC, the Hermes Wiki Corpus Index, and this holarchy's own
//// MOC page.
////
//// This module is pure (no file IO, no clock read): `pages(stamp)` is a deterministic function of
//// `stamp` and the current `holon.holarchy()` only, so two calls with the same `stamp` return
//// byte-identical output. The `holon-km` CLI arm in `uos_swarm.gleam` is the sole caller that
//// touches the filesystem (via `simplifile`).
//// STAMP: SC-HOLON-KM-001, #km-triad, #fractal-l0..l9.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import uos_swarm/holon.{type Holon}

const tailnet = "http://nas-1.tail55d152.ts.net:4100"

const zk_moc_transclusion = "[[zk:20260905-1801-moc-uos-unified-master]]"

const wiki_index_transclusion = "[[wiki:20260905-1801-uos-zk-km-corpus-index]]"

/// Relative repository path of one holon's generated wiki page.
pub fn holon_page_path(stamp: String, id: String) -> String {
  "docs/wiki/holons/" <> stamp <> "-holon-" <> id <> ".md"
}

/// Relative repository path of the holarchy Map of Content.
pub fn moc_path(stamp: String) -> String {
  "docs/zk/" <> stamp <> "-moc-uos-holarchy.md"
}

fn self_link(repo_path: String) -> String {
  tailnet <> "/files/" <> repo_path
}

fn nav_line(stamp: String) -> String {
  "["
  <> "ZK Master MOC"
  <> "]("
  <> tailnet
  <> "/zk) · ["
  <> "Hermes Wiki Corpus Index"
  <> "]("
  <> tailnet
  <> "/wiki) · ["
  <> "Holarchy MOC"
  <> "]("
  <> self_link(moc_path(stamp))
  <> ")"
}

/// The 5-domain, 18-item comprehensive verification checklist (`SC-CHECKLIST-001`), copied
/// verbatim (domain headings and item text) from `docs/zk/20260905-1801-moc-uos-unified-master.md`
/// §"Comprehensive verification checklist": document-level items CHK-01..CHK-04 and CHK-18 are
/// checked, every runtime/formal/admission item (CHK-05..CHK-17) is left unchecked because this
/// is a deterministically generated page, not an observed runtime receipt.
pub fn checklist_markdown() -> String {
  "## Comprehensive verification checklist

Document checks and production gates have different evidence scopes. Checked
items below refer only to this document package. Runtime, formal-proof and
sovereign-admission gates (CHK-05..CHK-17) are **UNRUN** for this generated
holarchy page — it is produced deterministically by `uos_swarm` `holon-km`
from `holon.holarchy()`, not from an observed runtime receipt.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix and chrony receipt recorded.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references provided; serving status is reported in the journal.
- [x] **CHK-03-FRACT** — Canonical L0–L9 fractal tags assigned.
- [x] **CHK-04-KM** — Specification, wiki, ADR, source review and journal cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Production dependency/exclusion scan required.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary must pass runtime checks.
- [ ] **CHK-07-DRIVE** — Denied OS serial `25503L801736` must pass real interlock tests.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Structure, health badges, data grids, timeline, interactions, dark cockpit, advisory and action interlock.
- [ ] **CHK-09-MATH** — H ≥ 2.50 bits, CCM ≥ 90.0%, D_EA ≤ 10.0%, ITQS ≥ 0.85 require declared metrics and fresh measurements.
- [ ] **CHK-10-9MOD** — Unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos.
- [ ] **CHK-11-REGR** — Relevant UI regression suite and 30-second monitoring require execution.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Real OTP domain/actor supervision and restart evidence.
- [ ] **CHK-13-HERMES** — Authoritative WAL, bounded formal checks and evidence receipts.
- [ ] **CHK-14-ZIGVM** — Deterministic execution and descriptor-relative VFS evidence.
- [ ] **CHK-15-MAX** — Real inference through the isolated MAX boundary.
- [ ] **CHK-16-OTEL** — UTC microsecond timestamps and nonzero W3C trace/span IDs.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Tri-sovereign candidate review and authorized admission are outstanding.
- [x] **CHK-18-JJ** — Documentation authored in UOS using its standalone JJ discipline; no native Git mutations in UOS.

</details>"
}

fn tag_line(extra: List(String), fractal_levels: List(Int)) -> String {
  let fractal =
    list.map(fractal_levels, fn(l) { "#fractal-l" <> int.to_string(l) })
  string.join(
    list.flatten([
      fractal,
      ["#km-triad", "#rocha-semiotics", "#cybernetics", "#zero-muda", "#zk-adr"],
      extra,
    ]),
    " ",
  )
}

fn id_link(stamp: String, id: String) -> String {
  "[" <> id <> "](" <> self_link(holon_page_path(stamp, id)) <> ")"
}

/// One `- [id](link) — name` row, or a plain `- id — (no such holon)` fallback if `id` does not
/// resolve in `hs` (defensive: base rule B2 guarantees reciprocity, but this module never assumes
/// it silently).
fn holon_ref_line(stamp: String, hs: List(Holon), id: String) -> String {
  case holon.find(hs, id) {
    Ok(h) -> "- " <> id_link(stamp, id) <> " — " <> h.name
    Error(_) -> "- " <> id <> " — (no such holon)"
  }
}

fn whole_row(
  stamp: String,
  hs: List(Holon),
  whole: option.Option(String),
) -> String {
  case whole {
    None -> "— (root)"
    Some(id) ->
      case holon.find(hs, id) {
        Ok(h) -> id_link(stamp, id) <> " — " <> h.name
        Error(_) -> id
      }
  }
}

fn parts_cell(stamp: String, hs: List(Holon), parts: List(String)) -> String {
  case parts {
    [] -> "— (leaf)"
    ps ->
      ps
      |> list.map(fn(id) {
        case holon.find(hs, id) {
          Ok(_) -> id_link(stamp, id)
          Error(_) -> id
        }
      })
      |> string.join(", ")
  }
}

fn optional_row(label: String, value: String) -> String {
  case value {
    "" -> ""
    v -> "| " <> label <> " | " <> v <> " |\n"
  }
}

/// The Markdown page for one holon.
fn holon_page(stamp: String, hs: List(Holon), h: Holon) -> #(String, String) {
  let path = holon_page_path(stamp, h.id)
  let md =
    "# "
    <> h.id
    <> " — "
    <> h.name
    <> "\n\n"
    <> tag_line([], [h.level])
    <> "\n\n"
    <> "["
    <> path
    <> "]("
    <> self_link(path)
    <> ")\n\n"
    <> zk_moc_transclusion
    <> " "
    <> wiki_index_transclusion
    <> "\n\n"
    <> "## Holon\n\n"
    <> "| field | value |\n|---|---|\n"
    <> "| id | `"
    <> h.id
    <> "` |\n"
    <> "| name | "
    <> h.name
    <> " |\n"
    <> "| Sanskrit | "
    <> h.sanskrit
    <> " |\n"
    <> "| kind | "
    <> holon.kind_label(h.kind)
    <> " |\n"
    <> "| level | L"
    <> int.to_string(h.level)
    <> " |\n"
    <> "| plane | "
    <> holon.plane_label(h.plane)
    <> " |\n"
    <> "| address | `"
    <> holon.address(h)
    <> "` |\n"
    <> "| uid | `"
    <> h.uid
    <> "` |\n"
    <> "| whole | "
    <> whole_row(stamp, hs, h.whole)
    <> " |\n"
    <> "| parts | "
    <> parts_cell(stamp, hs, h.parts)
    <> " |\n"
    <> "| module | `"
    <> h.module
    <> "` |\n"
    <> optional_row("domain", h.domain)
    <> optional_row("process_class", h.process_class)
    <> optional_row("status", h.status)
    <> "| lifecycle | "
    <> holon.lifecycle_label(h.lifecycle)
    <> " |\n"
    <> "\n"
    <> "Generated from holarchy() by `uos_swarm` `holon-km`; regenerate, do not hand-edit.\n\n"
    <> checklist_markdown()
    <> "\n\n---\n\n"
    <> nav_line(stamp)
    <> "\n"
  #(path, md)
}

fn level_count_row(hs: List(Holon), level: Int) -> String {
  let n = list.length(list.filter(hs, fn(h) { h.level == level }))
  "| L" <> int.to_string(level) <> " | " <> int.to_string(n) <> " |"
}

fn plane_section(
  stamp: String,
  hs_at_level: List(Holon),
  p: holon.Plane,
) -> String {
  let hs_at_plane = list.filter(hs_at_level, fn(h) { h.plane == p })
  case hs_at_plane {
    [] -> ""
    xs ->
      "**"
      <> holon.plane_label(p)
      <> "** ("
      <> int.to_string(list.length(xs))
      <> ")\n\n"
      <> string.join(
        list.map(xs, fn(h) { holon_ref_line(stamp, hs_at_level, h.id) }),
        "\n",
      )
      <> "\n\n"
  }
}

fn level_section(stamp: String, hs: List(Holon), level: Int) -> String {
  let hs_at_level = list.filter(hs, fn(h) { h.level == level })
  case hs_at_level {
    [] -> ""
    xs ->
      "### L"
      <> int.to_string(level)
      <> " ("
      <> int.to_string(list.length(xs))
      <> " holons)\n\n"
      <> string.join(
        list.map(holon.planes, fn(p) { plane_section(stamp, hs_at_level, p) })
          |> list.filter(fn(s) { s != "" }),
        "",
      )
  }
}

/// The Map of Content page: every holon of `hs`, grouped by level then plane, plus the level
/// distribution table. Every holon id appears exactly once, as a link to its own page.
fn moc_page(stamp: String, hs: List(Holon)) -> #(String, String) {
  let path = moc_path(stamp)
  let levels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  let total = list.length(hs)
  let md =
    "# UOS Holarchy Map of Content\n\n"
    <> tag_line(["#zk-moc"], levels)
    <> "\n\n"
    <> "["
    <> path
    <> "]("
    <> self_link(path)
    <> ")\n\n"
    <> zk_moc_transclusion
    <> " "
    <> wiki_index_transclusion
    <> "\n\n"
    <> "Generated from holarchy() by `uos_swarm` `holon-km`; regenerate, do not hand-edit.\n\n"
    <> "## Level distribution\n\n"
    <> "| level | count |\n|---|---|\n"
    <> string.join(list.map(levels, fn(l) { level_count_row(hs, l) }), "\n")
    <> "\n| **Total** | **"
    <> int.to_string(total)
    <> "** |\n\n"
    <> "## Holons by level and plane\n\n"
    <> string.join(list.map(levels, fn(l) { level_section(stamp, hs, l) }), "")
    <> checklist_markdown()
    <> "\n\n---\n\n"
    <> nav_line(stamp)
    <> "\n"
  #(path, md)
}

/// Every generated page for `stamp`: the holarchy MOC plus one page per holon of
/// `holon.holarchy()`. Deterministic: two calls with the same `stamp` return equal lists.
pub fn pages(stamp: String) -> List(#(String, String)) {
  let hs = holon.holarchy()
  [moc_page(stamp, hs), ..list.map(hs, fn(h) { holon_page(stamp, hs, h) })]
}
