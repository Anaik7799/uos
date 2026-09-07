import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/layout.{Cells, Fraction, Horizontal, Vertical}
import uos_tui/render
import uos_tui/style
import uos_tui/widget.{Column, TreeNode}

type M {
  Press
  Change(String)
  Move(Int)
}

fn sample() -> widget.Widget(M) {
  widget.Container(
    "root",
    Vertical,
    [
      #(Cells(1), widget.Header("h", "Title", "sub", style.none)),
      #(
        Fraction(1),
        widget.Container(
          "mid",
          Horizontal,
          [
            #(
              Cells(10),
              widget.ListView("l", ["one", "two", "three"], 1, Some(Move), None),
            ),
            #(
              Fraction(1),
              widget.DataTable(
                "t",
                [Column("a", Fraction(1)), Column("b", Cells(4))],
                [["x", "1"], ["y", "2"]],
                0,
                Some(Move),
                None,
              ),
            ),
          ],
          True,
          "Box",
        ),
      ),
      #(Cells(1), widget.Input("i", "abc", 1, "type", Change, None)),
      #(Cells(1), widget.Button("b", "Go", Press)),
      #(Cells(1), widget.ProgressBar("p", 0.5, "L0 ")),
      #(Cells(1), widget.Sparkline("s", [1.0, 3.0, 2.0], style.none)),
      #(Cells(1), widget.Tabs("tabs", ["A", "B"], 1, None)),
      #(Cells(2), widget.Log("log", ["l1", "l2", "l3"], 0)),
      #(Cells(1), widget.Rule("r", "rule")),
      #(
        Cells(3),
        widget.Tree(
          "tree",
          TreeNode("root", True, [
            TreeNode("kid", False, [TreeNode("grand", False, [])]),
          ]),
          0,
          None,
        ),
      ),
    ],
    False,
    "",
  )
}

pub fn compose_is_well_formed_test() {
  let f = render.compose(sample(), Size(40, 16), Some("l"), render.dark)
  frame.is_well_formed(f) |> should.be_true
}

pub fn header_and_border_visible_test() {
  let t =
    render.compose(sample(), Size(40, 16), None, render.dark) |> frame.to_text
  string.contains(t, "Title") |> should.be_true
  string.contains(t, "┌") |> should.be_true
  string.contains(t, " Box ") |> should.be_true
}

pub fn focused_list_marks_cursor_test() {
  let t =
    render.compose(sample(), Size(40, 16), Some("l"), render.dark)
    |> frame.to_text
  string.contains(t, "› two") |> should.be_true
}

pub fn progress_bar_percent_test() {
  let t =
    render.compose(
      widget.ProgressBar("p", 0.5, "L0 "),
      Size(30, 1),
      None,
      render.dark,
    )
    |> frame.to_text
  string.contains(t, " 50%") |> should.be_true
}

pub fn sparkline_scales_test() {
  render.sparkline([0.0, 1.0], 10) |> should.equal("▁█")
  render.sparkline([], 10) |> should.equal("")
  render.sparkline([2.0, 2.0], 10) |> should.equal("▁▁")
}

pub fn log_shows_tail_test() {
  let t =
    render.compose(
      widget.Log("log", ["a", "b", "c", "d"], 0),
      Size(5, 2),
      None,
      render.dark,
    )
    |> frame.to_text
  t |> should.equal("c    \nd    ")
}

pub fn static_wraps_test() {
  let t =
    render.compose(
      widget.Static("s", "abcdefgh", style.none),
      Size(3, 3),
      None,
      render.dark,
    )
    |> frame.to_text
  t |> should.equal("abc\ndef\ngh ")
}

pub fn tree_glyphs_test() {
  let t =
    render.compose(
      widget.Tree(
        "tree",
        TreeNode("root", True, [
          TreeNode("kid", False, [TreeNode("g", False, [])]),
        ]),
        0,
        None,
      ),
      Size(20, 3),
      None,
      render.dark,
    )
    |> frame.to_text
  string.contains(t, "▾ root") |> should.be_true
  string.contains(t, "  ▸ kid") |> should.be_true
}

pub fn checklist_counts_test() {
  let w =
    widget.Checklist(
      "c",
      [
        widget.ChecklistDomain("D1", [
          widget.ChecklistItem("A", "a", True),
          widget.ChecklistItem("B", "b", False),
        ]),
      ],
      [0],
      None,
    )
  let t = render.compose(w, Size(30, 3), None, render.dark) |> frame.to_text
  string.contains(t, "▾ D1 1/2") |> should.be_true
  string.contains(t, "[ ] B b") |> should.be_true
}

// Chaos: every widget at every size in [0..60]x[0..30] yields a well-formed frame.
pub fn chaos_compose_any_size_test() {
  list.each(prng.seeds(200), fn(seed) {
    let #(w, seed) = prng.int_between(seed, 0, 60)
    let #(h, _) = prng.int_between(seed, 0, 30)
    render.compose(sample(), Size(w, h), Some("i"), render.dark)
    |> frame.is_well_formed
    |> should.be_true
  })
}
