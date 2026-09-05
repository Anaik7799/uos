//// Pass-24 — owner_parent_picker MVU tests.
////
//// Anti-Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): each test exercises
//// the *real* update() state machine and assertion is on substantive state
//// fields (not Bool stubs). Filter test seeds candidates and checks
//// substring matching is case-insensitive.

import cepaf_gleam/ui/lustre/owner_parent_picker.{
  type PickerModel, Candidate, CandidatesLoaded, ClosePicker, OpenPicker,
  OwnerKind, ParentKind, Reset, SelectOwner, SelectParent, Submit, UpdateQuery,
  filtered, init, kind_to_string, render_ansi, render_html, submittable, update,
  visible_count,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// ── §1. init ─────────────────────────────────────────────────────────────

pub fn init_returns_closed_test() {
  let m = init()
  m.open |> should.equal(False)
  m.query |> should.equal("")
  m.candidates |> should.equal([])
  m.submitted |> should.equal(False)
}

pub fn init_default_kind_is_owner_test() {
  let m = init()
  m.kind |> should.equal(OwnerKind)
}

// ── §2. open / close ─────────────────────────────────────────────────────

pub fn open_picker_owner_test() {
  let m = update(init(), OpenPicker(OwnerKind))
  m.open |> should.equal(True)
  m.kind |> should.equal(OwnerKind)
  m.submitted |> should.equal(False)
}

pub fn open_picker_parent_test() {
  let m = update(init(), OpenPicker(ParentKind))
  m.open |> should.equal(True)
  m.kind |> should.equal(ParentKind)
}

pub fn close_picker_clears_query_test() {
  let m =
    init()
    |> update(OpenPicker(OwnerKind))
    |> update(UpdateQuery("alice"))
    |> update(ClosePicker)
  m.open |> should.equal(False)
  m.query |> should.equal("")
}

// ── §3. query + filter ───────────────────────────────────────────────────

fn seeded() -> PickerModel {
  init()
  |> update(OpenPicker(OwnerKind))
  |> update(
    CandidatesLoaded([
      Candidate("alice", "Alice Smith"),
      Candidate("bob", "Bob Jones"),
      Candidate("carol", "Carol Anderson"),
      Candidate("alice2", "Alice Wonderland"),
    ]),
  )
}

pub fn empty_query_returns_all_test() {
  let m = seeded()
  visible_count(m) |> should.equal(4)
}

pub fn query_filters_substring_test() {
  let m = update(seeded(), UpdateQuery("alice"))
  visible_count(m) |> should.equal(2)
}

pub fn query_filter_case_insensitive_test() {
  let m = update(seeded(), UpdateQuery("ALICE"))
  visible_count(m) |> should.equal(2)
}

pub fn query_filters_by_id_test() {
  let m = update(seeded(), UpdateQuery("bob"))
  let found = filtered(m)
  list.length(found) |> should.equal(1)
}

pub fn query_no_match_returns_empty_test() {
  let m = update(seeded(), UpdateQuery("xyz_no_match"))
  visible_count(m) |> should.equal(0)
}

// ── §4. selection ────────────────────────────────────────────────────────

pub fn select_owner_records_id_test() {
  let m = update(init(), SelectOwner("alice"))
  m.selected_owner |> should.equal(Some("alice"))
  m.selected_parent |> should.equal(None)
}

pub fn select_parent_records_id_test() {
  let m = update(init(), SelectParent("task-123"))
  m.selected_parent |> should.equal(Some("task-123"))
}

pub fn submittable_requires_at_least_one_selection_test() {
  init() |> submittable |> should.equal(False)
  init() |> update(SelectOwner("alice")) |> submittable |> should.equal(True)
  init() |> update(SelectParent("p1")) |> submittable |> should.equal(True)
}

// ── §5. submit / reset ───────────────────────────────────────────────────

pub fn submit_closes_and_marks_submitted_test() {
  let m =
    init()
    |> update(OpenPicker(OwnerKind))
    |> update(SelectOwner("alice"))
    |> update(Submit)
  m.open |> should.equal(False)
  m.submitted |> should.equal(True)
  // Selection persists past submit
  m.selected_owner |> should.equal(Some("alice"))
}

pub fn reset_returns_to_init_test() {
  let m =
    init()
    |> update(OpenPicker(OwnerKind))
    |> update(SelectOwner("alice"))
    |> update(SelectParent("p1"))
    |> update(Submit)
    |> update(Reset)
  m |> should.equal(init())
}

// ── §6. render ───────────────────────────────────────────────────────────

pub fn render_html_closed_minimal_test() {
  let html = render_html(init())
  string.contains(html, "data-open=\"false\"") |> should.be_true()
  string.contains(html, "picker-modal") |> should.equal(False)
}

pub fn render_html_open_includes_query_test() {
  let m =
    init()
    |> update(OpenPicker(OwnerKind))
    |> update(UpdateQuery("alice"))
  let html = render_html(m)
  string.contains(html, "data-open=\"true\"") |> should.be_true()
  string.contains(html, "data-kind=\"owner\"") |> should.be_true()
  string.contains(html, "value=\"alice\"") |> should.be_true()
}

pub fn render_html_includes_candidates_test() {
  let html = render_html(seeded())
  string.contains(html, "Alice Smith") |> should.be_true()
  string.contains(html, "Bob Jones") |> should.be_true()
  string.contains(html, "data-id=\"alice\"") |> should.be_true()
}

pub fn render_html_disables_submit_when_no_selection_test() {
  let m = update(init(), OpenPicker(OwnerKind))
  let html = render_html(m)
  string.contains(html, "picker-submit\" disabled") |> should.be_true()
}

pub fn render_html_enables_submit_when_owner_selected_test() {
  let m =
    init()
    |> update(OpenPicker(OwnerKind))
    |> update(SelectOwner("alice"))
  let html = render_html(m)
  string.contains(html, "picker-submit\" disabled") |> should.equal(False)
  string.contains(html, "picker-submit\">Submit") |> should.be_true()
}

// ── §7. ANSI render (TUI) ────────────────────────────────────────────────

pub fn render_ansi_closed_empty_test() {
  render_ansi(init()) |> should.equal("")
}

pub fn render_ansi_open_includes_kind_test() {
  let m = update(init(), OpenPicker(ParentKind))
  let ansi = render_ansi(m)
  string.contains(ansi, "PICKER (parent)") |> should.be_true()
}

pub fn render_ansi_lists_candidates_test() {
  let ansi = render_ansi(seeded())
  string.contains(ansi, "Alice Smith") |> should.be_true()
  string.contains(ansi, "Carol Anderson") |> should.be_true()
}

// ── §8. kind helpers ─────────────────────────────────────────────────────

pub fn kind_to_string_owner_test() {
  kind_to_string(OwnerKind) |> should.equal("owner")
}

pub fn kind_to_string_parent_test() {
  kind_to_string(ParentKind) |> should.equal("parent")
}
