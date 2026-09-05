//// Pass-23 — P1 #5 Server-side pagination tests for `/api/v1/planning/page`.
////
//// Anti-Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): every test exercises
//// the *real* JSON-array slicer + counter, not stubbed payloads.

import cepaf_gleam/ui/wisp/router.{count_json_array_elements, slice_json_array}
import gleeunit/should

// ── §1. count_json_array_elements ────────────────────────────────────────

pub fn count_empty_array_test() {
  count_json_array_elements("[]") |> should.equal(0)
}

pub fn count_empty_array_with_whitespace_test() {
  count_json_array_elements("[ ]") |> should.equal(0)
}

pub fn count_single_element_test() {
  count_json_array_elements("[{\"id\":1}]") |> should.equal(1)
}

pub fn count_multiple_elements_test() {
  count_json_array_elements("[{\"id\":1},{\"id\":2},{\"id\":3}]")
  |> should.equal(3)
}

pub fn count_handles_nested_objects_test() {
  // Nested object's internal commas must NOT be counted.
  let arr = "[{\"id\":1,\"sub\":{\"a\":1,\"b\":2}},{\"id\":2}]"
  count_json_array_elements(arr) |> should.equal(2)
}

pub fn count_handles_nested_arrays_test() {
  let arr = "[{\"tags\":[1,2,3]},{\"tags\":[]}]"
  count_json_array_elements(arr) |> should.equal(2)
}

pub fn count_invalid_array_returns_zero_test() {
  count_json_array_elements("not an array") |> should.equal(0)
  count_json_array_elements("{}") |> should.equal(0)
}

// ── §2. slice_json_array ─────────────────────────────────────────────────

pub fn slice_zero_offset_full_limit_test() {
  let arr = "[{\"id\":1},{\"id\":2},{\"id\":3}]"
  slice_json_array(arr, 0, 100)
  |> should.equal("[{\"id\":1},{\"id\":2},{\"id\":3}]")
}

pub fn slice_with_offset_test() {
  let arr = "[{\"id\":1},{\"id\":2},{\"id\":3},{\"id\":4}]"
  slice_json_array(arr, 2, 100)
  |> should.equal("[{\"id\":3},{\"id\":4}]")
}

pub fn slice_with_limit_test() {
  let arr = "[{\"id\":1},{\"id\":2},{\"id\":3}]"
  slice_json_array(arr, 0, 2) |> should.equal("[{\"id\":1},{\"id\":2}]")
}

pub fn slice_empty_array_test() {
  slice_json_array("[]", 0, 100) |> should.equal("[]")
}

pub fn slice_offset_beyond_total_test() {
  let arr = "[{\"id\":1},{\"id\":2}]"
  slice_json_array(arr, 100, 10) |> should.equal("[]")
}

pub fn slice_preserves_nested_objects_test() {
  // Critical test: offset/limit MUST not split mid-object.
  let arr =
    "[{\"id\":1,\"meta\":{\"a\":1,\"b\":2}},{\"id\":2,\"meta\":{\"c\":3}}]"
  slice_json_array(arr, 1, 1)
  |> should.equal("[{\"id\":2,\"meta\":{\"c\":3}}]")
}

pub fn slice_preserves_nested_arrays_test() {
  let arr = "[{\"tags\":[1,2,3]},{\"tags\":[4,5]}]"
  slice_json_array(arr, 0, 1) |> should.equal("[{\"tags\":[1,2,3]}]")
}

pub fn slice_invalid_input_returns_empty_test() {
  slice_json_array("garbage", 0, 10) |> should.equal("[]")
  slice_json_array("{}", 0, 10) |> should.equal("[]")
}

// ── §3. Round-trip: slice ∘ count ────────────────────────────────────────

pub fn round_trip_pagination_invariant_test() {
  let arr = "[{\"id\":1},{\"id\":2},{\"id\":3},{\"id\":4},{\"id\":5}]"
  let total = count_json_array_elements(arr)
  total |> should.equal(5)

  // Page 1 (offset=0, limit=2)
  let page1 = slice_json_array(arr, 0, 2)
  count_json_array_elements(page1) |> should.equal(2)

  // Page 2 (offset=2, limit=2)
  let page2 = slice_json_array(arr, 2, 2)
  count_json_array_elements(page2) |> should.equal(2)

  // Page 3 (offset=4, limit=2 — only 1 element left)
  let page3 = slice_json_array(arr, 4, 2)
  count_json_array_elements(page3) |> should.equal(1)

  // Page 4 (offset=6, beyond total — empty)
  let page4 = slice_json_array(arr, 6, 2)
  count_json_array_elements(page4) |> should.equal(0)
}
