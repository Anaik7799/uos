//// Pass-25 — status_filter_chips component tests.
////
//// Anti-Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): tests assert real
//// arithmetic on `StatusCounts` records, real HTML/ANSI output strings
//// containing the expected counts, and the All-chip == sum invariant.

import cepaf_gleam/ui/lustre/status_filter_chips.{
  type StatusCounts, AllStatuses, Chip, OnlyBlocked, OnlyCompleted,
  OnlyInProgress, OnlyPending, StatusCounts, active_chip, build_chips,
  chip_page_url, chip_url, filter_to_key, has_any, invariant_holds, parse_active,
  render_ansi, render_html, shows_empty, sum_status_counts, total,
}
import gleam/list
import gleam/string
import gleeunit/should

fn baseline() -> StatusCounts {
  StatusCounts(pending: 12, in_progress: 4, blocked: 1, completed: 234)
}

// ── §1. Counts arithmetic ────────────────────────────────────────────────

pub fn total_sums_all_four_test() {
  total(baseline()) |> should.equal(251)
}

pub fn total_zero_test() {
  total(StatusCounts(0, 0, 0, 0)) |> should.equal(0)
}

pub fn has_any_true_when_nonzero_test() {
  has_any(baseline()) |> should.equal(True)
}

pub fn has_any_false_on_empty_test() {
  has_any(StatusCounts(0, 0, 0, 0)) |> should.equal(False)
}

// ── §2. Build chips ──────────────────────────────────────────────────────

pub fn build_returns_5_chips_test() {
  let chips = build_chips(baseline(), AllStatuses)
  list.length(chips) |> should.equal(5)
}

pub fn build_first_chip_is_all_test() {
  let chips = build_chips(baseline(), AllStatuses)
  let assert [first, ..] = chips
  first.status_key |> should.equal("all")
  first.count |> should.equal(251)
}

pub fn build_marks_active_correctly_test() {
  let chips = build_chips(baseline(), OnlyBlocked)
  let blocked_active = list.filter(chips, fn(c) { c.active }) |> list.length
  blocked_active |> should.equal(1)
  let assert Ok(active) = active_chip(chips)
  active.status_key |> should.equal("blocked")
}

pub fn build_carries_real_counts_test() {
  let chips = build_chips(baseline(), AllStatuses)
  let pending_chip = list.filter(chips, fn(c) { c.status_key == "pending" })
  let assert [p] = pending_chip
  p.count |> should.equal(12)
}

// ── §3. Variant assignments ──────────────────────────────────────────────

pub fn blocked_chip_is_p0_variant_test() {
  let chips = build_chips(baseline(), AllStatuses)
  let blocked = list.filter(chips, fn(c) { c.status_key == "blocked" })
  let assert [b] = blocked
  b.variant |> should.equal("p0")
}

pub fn in_progress_chip_is_p1_variant_test() {
  let chips = build_chips(baseline(), AllStatuses)
  let ip = list.filter(chips, fn(c) { c.status_key == "in_progress" })
  let assert [i] = ip
  i.variant |> should.equal("p1")
}

// ── §4. parse_active / filter_to_key round-trip ──────────────────────────

pub fn parse_active_unknown_defaults_to_all_test() {
  parse_active("garbage") |> should.equal(AllStatuses)
  parse_active("") |> should.equal(AllStatuses)
}

pub fn parse_active_canonical_test() {
  parse_active("pending") |> should.equal(OnlyPending)
  parse_active("in_progress") |> should.equal(OnlyInProgress)
  parse_active("blocked") |> should.equal(OnlyBlocked)
  parse_active("completed") |> should.equal(OnlyCompleted)
}

pub fn filter_to_key_round_trip_test() {
  let filters = [
    AllStatuses,
    OnlyPending,
    OnlyInProgress,
    OnlyBlocked,
    OnlyCompleted,
  ]
  list.each(filters, fn(f) {
    let key = filter_to_key(f)
    parse_active(key) |> should.equal(f)
  })
}

// ── §5. HTML render ──────────────────────────────────────────────────────

pub fn render_html_includes_chip_row_class_test() {
  let html = render_html(build_chips(baseline(), AllStatuses))
  string.contains(html, "chip-row") |> should.be_true()
  string.contains(html, "role=\"toolbar\"") |> should.be_true()
}

pub fn render_html_includes_all_status_keys_test() {
  let html = render_html(build_chips(baseline(), AllStatuses))
  string.contains(html, "data-status=\"all\"") |> should.be_true()
  string.contains(html, "data-status=\"pending\"") |> should.be_true()
  string.contains(html, "data-status=\"in_progress\"") |> should.be_true()
  string.contains(html, "data-status=\"blocked\"") |> should.be_true()
  string.contains(html, "data-status=\"completed\"") |> should.be_true()
}

pub fn render_html_includes_real_counts_test() {
  let html = render_html(build_chips(baseline(), AllStatuses))
  // pending=12 must appear with chip-count class
  string.contains(html, "chip-count\">12") |> should.be_true()
  string.contains(html, "chip-count\">234") |> should.be_true()
}

pub fn render_html_marks_active_with_class_test() {
  let html = render_html(build_chips(baseline(), OnlyBlocked))
  string.contains(html, "chip-active") |> should.be_true()
}

// ── §6. ANSI render ──────────────────────────────────────────────────────

pub fn render_ansi_active_bracketed_test() {
  let ansi = render_ansi(build_chips(baseline(), OnlyBlocked))
  string.contains(ansi, "[Blocked 1]") |> should.be_true()
}

pub fn render_ansi_includes_all_labels_test() {
  let ansi = render_ansi(build_chips(baseline(), AllStatuses))
  string.contains(ansi, "Pending") |> should.be_true()
  string.contains(ansi, "In Progress") |> should.be_true()
  string.contains(ansi, "Blocked") |> should.be_true()
  string.contains(ansi, "Completed") |> should.be_true()
}

// ── §7. URL builders ─────────────────────────────────────────────────────

pub fn chip_url_uses_pagination_endpoint_test() {
  let chip = Chip("Pending", "pending", 12, False, "p2")
  chip_url(chip, 0, 100)
  |> should.equal("/api/v1/planning/page?status=pending&offset=0&limit=100")
}

pub fn chip_url_handles_offset_test() {
  let chip = Chip("Pending", "pending", 12, False, "p2")
  chip_url(chip, 100, 50)
  |> should.equal("/api/v1/planning/page?status=pending&offset=100&limit=50")
}

pub fn chip_page_url_uses_query_string_test() {
  let chip = Chip("Blocked", "blocked", 1, False, "p0")
  chip_page_url(chip) |> should.equal("/planning?status=blocked")
}

// ── §8. Empty-state predicate ────────────────────────────────────────────

pub fn shows_empty_when_filter_zero_test() {
  let zero = StatusCounts(pending: 0, in_progress: 4, blocked: 1, completed: 0)
  shows_empty(OnlyPending, zero) |> should.equal(True)
  shows_empty(OnlyCompleted, zero) |> should.equal(True)
  shows_empty(OnlyInProgress, zero) |> should.equal(False)
}

pub fn shows_empty_all_when_total_zero_test() {
  shows_empty(AllStatuses, StatusCounts(0, 0, 0, 0)) |> should.equal(True)
}

// ── §9. Invariant: All chip count == sum of status chips ─────────────────
//
// Critical anti-Stub-That-Lies test: proves the All-chip aggregate is real
// arithmetic, not a stubbed literal.

pub fn invariant_all_equals_sum_of_statuses_test() {
  let chips = build_chips(baseline(), AllStatuses)
  invariant_holds(chips) |> should.equal(True)
  // Sanity: explicit sum check
  sum_status_counts(chips) |> should.equal(251)
}

pub fn invariant_holds_on_zero_state_test() {
  let chips = build_chips(StatusCounts(0, 0, 0, 0), AllStatuses)
  invariant_holds(chips) |> should.equal(True)
}
