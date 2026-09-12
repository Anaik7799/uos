//// Pass-24 — CP5 P1 #12 Owner + Parent-ID Picker
////
//// Lustre MVU component for selecting an owner (string) and parent task ID
//// when creating or editing a planning task.
////
//// Triple-interface mandate (SC-GLM-UI-001): the same Model/Msg surface is
//// reused by:
////   - Lustre SSR (this file's `view`)
////   - Wisp REST (`ui/wisp/router.gleam` `/api/v1/picker/options`)
////   - TUI ANSI (`ui/tui/owner_parent_picker_view.gleam`)
////
//// Anti-pattern guarded: [zk-3346fc607a1ef9e6] Stub-That-Lies — every
//// transition tested with real Model values, not stubbed inputs. The
//// `Submit` Msg sets a `submitted` flag the test asserts on rather than a
//// boolean stub.
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009, SC-AGUI-UI-001

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ── §1. Types ────────────────────────────────────────────────────────────

/// A candidate value the operator can pick from the autocomplete list.
pub type Candidate {
  Candidate(id: String, label: String)
}

/// Picker mode.
pub type PickerKind {
  OwnerKind
  ParentKind
}

/// MVU model.
pub type PickerModel {
  PickerModel(
    open: Bool,
    kind: PickerKind,
    /// Currently typed filter text.
    query: String,
    /// Candidate list (loaded from /api/v1/picker/options).
    candidates: List(Candidate),
    /// Currently committed selection.
    selected_owner: Option(String),
    selected_parent: Option(String),
    /// Set on Submit — UI side-effect signal.
    submitted: Bool,
  )
}

/// MVU message variants.
pub type PickerMsg {
  OpenPicker(PickerKind)
  ClosePicker
  UpdateQuery(String)
  CandidatesLoaded(List(Candidate))
  SelectOwner(String)
  SelectParent(String)
  Submit
  Reset
}

// ── §2. init ─────────────────────────────────────────────────────────────

pub fn init() -> PickerModel {
  PickerModel(
    open: False,
    kind: OwnerKind,
    query: "",
    candidates: [],
    selected_owner: None,
    selected_parent: None,
    submitted: False,
  )
}

// ── §3. update — pure state machine ──────────────────────────────────────

pub fn update(model: PickerModel, msg: PickerMsg) -> PickerModel {
  case msg {
    OpenPicker(kind) ->
      PickerModel(
        ..model,
        open: True,
        kind: kind,
        query: "",
        // Clear submitted flag so the UI knows this is a fresh interaction.
        submitted: False,
      )
    ClosePicker ->
      PickerModel(..model, open: False, query: "", candidates: [])
    UpdateQuery(q) -> PickerModel(..model, query: q)
    CandidatesLoaded(cs) -> PickerModel(..model, candidates: cs)
    SelectOwner(id) ->
      PickerModel(..model, selected_owner: Some(id))
    SelectParent(id) ->
      PickerModel(..model, selected_parent: Some(id))
    Submit -> PickerModel(..model, open: False, submitted: True)
    Reset -> init()
  }
}

// ── §4. Query helpers (filter candidates client-side) ────────────────────

/// Filter candidates by case-insensitive substring on label OR id.
pub fn filtered(model: PickerModel) -> List(Candidate) {
  case model.query {
    "" -> model.candidates
    q ->
      list.filter(model.candidates, fn(c) {
        let qlow = string.lowercase(q)
        string.contains(string.lowercase(c.label), qlow)
        || string.contains(string.lowercase(c.id), qlow)
      })
  }
}

/// Number of candidates currently visible (after filtering).
pub fn visible_count(model: PickerModel) -> Int {
  list.length(filtered(model))
}

/// Whether the picker is in a state ready to submit.
/// (At least one of owner/parent must be selected.)
pub fn submittable(model: PickerModel) -> Bool {
  case model.selected_owner, model.selected_parent {
    None, None -> False
    _, _ -> True
  }
}

// ── §5. Render — pure HTML string for SSR + TUI text ─────────────────────
//
// Rendered as raw HTML string (not lustre/element) to keep this module
// dependency-light; the full Lustre `view` lives in a thin wrapper that
// imports lustre/element. The HTML output is the same.

pub fn render_html(model: PickerModel) -> String {
  case model.open {
    False -> "<div class=\"picker-closed\" data-open=\"false\"></div>"
    True ->
      "<div class=\"picker-modal\" data-open=\"true\" data-kind=\""
      <> kind_to_string(model.kind)
      <> "\">"
      <> "<input class=\"picker-query\" value=\""
      <> model.query
      <> "\" placeholder=\"Search "
      <> kind_to_string(model.kind)
      <> "...\"/>"
      <> "<ul class=\"picker-candidates\">"
      <> render_candidates(filtered(model))
      <> "</ul>"
      <> "<div class=\"picker-actions\"><button class=\"picker-cancel\">Cancel</button>"
      <> render_submit_button(submittable(model))
      <> "</div></div>"
  }
}

fn render_submit_button(enabled: Bool) -> String {
  case enabled {
    True -> "<button class=\"picker-submit\">Submit</button>"
    False -> "<button class=\"picker-submit\" disabled>Submit</button>"
  }
}

fn render_candidates(cs: List(Candidate)) -> String {
  list.fold(cs, "", fn(acc, c) {
    acc
    <> "<li data-id=\""
    <> c.id
    <> "\" class=\"picker-candidate\">"
    <> c.label
    <> "</li>"
  })
}

pub fn kind_to_string(k: PickerKind) -> String {
  case k {
    OwnerKind -> "owner"
    ParentKind -> "parent"
  }
}

// ── §6. ANSI render for TUI ──────────────────────────────────────────────

pub fn render_ansi(model: PickerModel) -> String {
  case model.open {
    False -> ""
    True -> {
      let header = "── PICKER (" <> kind_to_string(model.kind) <> ") ──\n"
      let q_line = "  query: " <> model.query <> "\n"
      let count_line =
        "  candidates: "
        <> int_to_str(visible_count(model))
        <> " visible\n"
      let candidate_lines =
        list.fold(filtered(model), "", fn(acc, c) {
          acc <> "    • " <> c.label <> " (" <> c.id <> ")\n"
        })
      let footer = case submittable(model) {
        True -> "  [Enter] Submit · [Esc] Cancel\n"
        False -> "  [Esc] Cancel (no selection yet)\n"
      }
      header <> q_line <> count_line <> candidate_lines <> footer
    }
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_str(n: Int) -> String
