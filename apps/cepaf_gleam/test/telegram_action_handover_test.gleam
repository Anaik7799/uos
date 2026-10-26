import cepaf_gleam/harness/telegram_action_handover as handover
import gleam/int
import gleam/list
import gleam/regexp
import gleam/string
import gleeunit/should
import simplifile

const base = "/tmp/claude-1000/-home-an-NAS-setup-uos/35600f5c-f8c9-4312-b1e0-07fde55d77cc/scratchpad/w3-handover-"

fn fresh(name: String) -> String {
  let dir = base <> name
  let _ = simplifile.delete(dir)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn req(args: String) {
  let assert Ok(r) = handover.parse(args)
  r
}

fn markdown_files(dir: String) -> List(String) {
  let assert Ok(names) = simplifile.read_directory(dir)
  list.filter(names, fn(n) { string.ends_with(n, ".md") })
}

fn filename_ok(name: String) -> Bool {
  let assert Ok(re) =
    regexp.from_string("^[0-9]{8}-[0-9]{4}-handover-[a-z0-9-]+\\.md$")
  regexp.check(re, name)
}

// 2026-10-26T01:02:03.123456Z
const t1 = 1_792_976_523_123_456_000

const t2 = 1_792_980_000_000_000_000

pub fn literal_and_parse_positive_test() {
  handover.literal() |> should.equal("/handover")
  handover.slug(req("Release Notes")) |> should.equal("release-notes")
  handover.slug(req("  wave2-w3  ")) |> should.equal("wave2-w3")
  handover.slug(req("a")) |> should.equal("a")
  handover.slug(req(string.repeat("a", 40)))
  |> should.equal(string.repeat("a", 40))
}

pub fn parse_negative_test() {
  list.each(
    [
      "",
      "   ",
      "-x",
      "x-",
      "a--b",
      "a_b",
      "a/b",
      "../x",
      "caf\u{e9}",
      "a.b",
      "a\nb",
      string.repeat("a", 41),
      string.repeat("a ", 129),
    ],
    fn(input) {
      case handover.parse(input) {
        Error(message) ->
          string.starts_with(message, "usage:") |> should.equal(True)
        Ok(_) -> should.fail()
      }
    },
  )
}

pub fn effect_id_is_stable_digest_of_the_slug_test() {
  let a = handover.effect_id(req("alpha"))
  string.length(a) |> should.equal(64)
  a |> should.equal(handover.effect_id(req("Alpha")))
  { a == handover.effect_id(req("beta")) } |> should.equal(False)
}

pub fn preview_shape_and_confidence_label_test() {
  let text = handover.preview(req("alpha"))
  string.contains(text, "\"status\":\"preview\"") |> should.equal(True)
  string.contains(text, "\"confidence\":\"observed\"") |> should.equal(True)
  string.contains(text, "\"authority\":\"NONE\"") |> should.equal(True)
  string.contains(text, "\"sections\":13") |> should.equal(True)
  string.contains(text, "-handover-alpha.md") |> should.equal(True)
  string.contains(
    text,
    "\"effect_id\":\"" <> handover.effect_id(req("alpha")) <> "\"",
  )
  |> should.equal(True)
  { string.byte_size(text) <= 3500 } |> should.equal(True)
}

pub fn prefix_uses_hour_and_seconds_test() {
  handover.prefix_from_iso("2026-10-26T01:02:03.123456Z")
  |> should.equal(Ok("20261026-0103"))
  handover.prefix_from_iso("2026-12-31T23:59:58Z")
  |> should.equal(Ok("20261231-2358"))
  list.each(
    [
      "",
      "2026-10-26",
      "2026-10-26 01:02:03",
      "20261026T010203Z",
      "2026-1a-26T01:02:03Z",
    ],
    fn(bad) {
      handover.prefix_from_iso(bad)
      |> should.equal(Error("clock_format_invalid"))
    },
  )
}

pub fn execute_writes_receipt_and_skeleton_then_duplicates_test() {
  let dir = fresh("exec")
  let r = req("wave two")
  let assert Ok(first) = handover.execute_at(r, dir, t1)
  string.contains(first, "\"status\":\"executed\"") |> should.equal(True)
  string.contains(first, "\"literal\":\"/handover\"") |> should.equal(True)
  let assert [name] = markdown_files(dir)
  filename_ok(name) |> should.equal(True)
  string.ends_with(name, "-handover-wave-two.md") |> should.equal(True)
  string.starts_with(name, "20261026-0103-") |> should.equal(True)
  let assert Ok(receipt) =
    simplifile.read(dir <> "/" <> handover.effect_id(r) <> ".json")
  receipt |> should.equal(first)
  // Repeat, even at a different clock reading: stored receipt, no second file.
  let assert Ok(second) = handover.execute_at(r, dir, t2)
  string.contains(second, "\"status\":\"duplicate\"") |> should.equal(True)
  string.contains(second, name) |> should.equal(True)
  markdown_files(dir) |> should.equal([name])
  let assert Ok(names) = simplifile.read_directory(dir)
  list.length(names) |> should.equal(2)
}

pub fn skeleton_has_all_13_headings_in_order_test() {
  let dir = fresh("headings")
  let assert Ok(_) = handover.execute_at(req("order"), dir, t1)
  let assert [name] = markdown_files(dir)
  let assert Ok(body) = simplifile.read(dir <> "/" <> name)
  let expected = [
    "## 1. Scope & Trigger", "## 2. Pre-State Assessment",
    "## 3. Execution Detail", "## 4. Root Cause Analysis", "## 5. Fix Taxonomy",
    "## 6. Patterns & Anti-Patterns Discovered", "## 7. Verification Matrix",
    "## 8. Files Modified", "## 9. Architectural Observations",
    "## 10. Remaining Gaps", "## 11. Metrics Summary",
    "## 12. STAMP & Constitutional Alignment", "## 13. Conclusion",
  ]
  let found =
    string.split(body, "\n")
    |> list.filter(fn(line) { string.starts_with(line, "## ") })
  found |> should.equal(expected)
  string.contains(body, "NOT a completed journal") |> should.equal(True)
  list.length(handover.section_titles()) |> should.equal(13)
}

pub fn execute_with_real_clock_names_file_correctly_test() {
  let dir = fresh("clock")
  let assert Ok(_) = handover.execute(req("live-clock"), dir)
  let assert [name] = markdown_files(dir)
  filename_ok(name) |> should.equal(True)
  // Not the epoch: the prefix came from the real host clock.
  string.starts_with(name, "20") |> should.equal(True)
  let assert Ok(year) = int.parse(string.slice(name, 0, 4))
  { year >= 2026 } |> should.equal(True)
}

pub fn execute_refuses_missing_evidence_dir_test() {
  let dir = base <> "does-not-exist"
  let _ = simplifile.delete(dir)
  handover.execute_at(req("alpha"), dir, t1)
  |> should.equal(Error("evidence_dir_unavailable"))
  handover.execute(req("alpha"), dir)
  |> should.equal(Error("evidence_dir_unavailable"))
  // A file is not a directory.
  let file = fresh("filecheck") <> "/f"
  let assert Ok(_) = simplifile.write(file, "x")
  handover.execute_at(req("alpha"), file, t1)
  |> should.equal(Error("evidence_dir_unavailable"))
  simplifile.is_directory(dir) |> should.equal(Ok(False))
}

pub fn execute_never_writes_outside_the_evidence_dir_test() {
  let dir = fresh("contained")
  let assert Ok(_) = handover.execute_at(req("contained"), dir, t1)
  let assert Ok(parent) = simplifile.read_directory(base <> "contained/..")
  list.any(parent, fn(n) { string.contains(n, "handover-contained.md") })
  |> should.equal(False)
}
