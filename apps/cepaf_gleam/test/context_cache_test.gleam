// =============================================================================
// context_cache_test.gleam — LRU Context Cache Tests
// =============================================================================
// 14 tests covering:
//   T01–T03: init / default
//   T04–T06: get (hit, miss, access_count increment)
//   T07–T09: put (insert, update, capacity eviction)
//   T10–T11: evict_lru
//   T12–T13: hit_rate, size, contains
//   T14:     summary, to_json, hottest_entries
//
// STAMP: SC-ZK-IMP-001, SC-SATYA-002, SC-MUDA-001
// Layer: L5_COGNITIVE
// =============================================================================

import cepaf_gleam/ha/context_cache
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// T01 — init with custom capacity
// ---------------------------------------------------------------------------

pub fn init_custom_capacity_test() {
  let state = context_cache.init(64)
  state.max_entries |> should.equal(64)
  state.hits |> should.equal(0)
  state.misses |> should.equal(0)
  state.entries |> should.equal([])
}

// ---------------------------------------------------------------------------
// T02 — init_default uses 128 capacity
// ---------------------------------------------------------------------------

pub fn init_default_capacity_test() {
  let state = context_cache.init_default()
  state.max_entries |> should.equal(128)
}

// ---------------------------------------------------------------------------
// T03 — init with capacity < 1 is clamped to 1
// ---------------------------------------------------------------------------

pub fn init_min_capacity_clamped_test() {
  let state = context_cache.init(0)
  { state.max_entries >= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T04 — get on empty cache returns Error and increments misses
// ---------------------------------------------------------------------------

pub fn get_miss_increments_misses_test() {
  let state = context_cache.init(16)
  let #(new_state, result) = context_cache.get(state, "zk-999")
  result |> should.be_error()
  new_state.misses |> should.equal(1)
  new_state.hits |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T05 — get on existing entry returns Ok and increments hits
// ---------------------------------------------------------------------------

pub fn get_hit_returns_content_test() {
  let state = context_cache.init(16)
  let filled = context_cache.put(state, "zk-001", "content-001", 1000)
  let #(after, result) = context_cache.get(filled, "zk-001")
  result |> should.equal(Ok("content-001"))
  after.hits |> should.equal(1)
  after.misses |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T06 — get increments access_count on the entry
// ---------------------------------------------------------------------------

pub fn get_increments_access_count_test() {
  let state = context_cache.init(16)
  let s1 = context_cache.put(state, "zk-002", "data", 1000)
  let #(s2, _) = context_cache.get(s1, "zk-002")
  let #(s3, _) = context_cache.get(s2, "zk-002")
  // Initial put sets access_count=1, two gets increment to 3
  let entry = list.find(s3.entries, fn(e) { e.holon_id == "zk-002" })
  case entry {
    Ok(e) -> { e.access_count >= 2 } |> should.be_true()
    Error(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// T07 — put inserts new entry and is retrievable
// ---------------------------------------------------------------------------

pub fn put_insert_new_entry_test() {
  let state = context_cache.init(16)
  let s1 = context_cache.put(state, "zk-100", "hello world", 5000)
  context_cache.contains(s1, "zk-100") |> should.be_true()
  let #(_, result) = context_cache.get(s1, "zk-100")
  result |> should.equal(Ok("hello world"))
}

// ---------------------------------------------------------------------------
// T08 — put updates content on existing entry
// ---------------------------------------------------------------------------

pub fn put_updates_existing_entry_test() {
  let state = context_cache.init(16)
  let s1 = context_cache.put(state, "zk-200", "old-content", 1000)
  let s2 = context_cache.put(s1, "zk-200", "new-content", 2000)
  // Still only one entry
  context_cache.size(s2) |> should.equal(1)
  let #(_, result) = context_cache.get(s2, "zk-200")
  result |> should.equal(Ok("new-content"))
}

// ---------------------------------------------------------------------------
// T09 — put at capacity triggers LRU eviction
// ---------------------------------------------------------------------------

pub fn put_at_capacity_evicts_lru_test() {
  // Use capacity=2
  let state = context_cache.init(2)
  let s1 = context_cache.put(state, "zk-a", "aaa", 100)
  let s2 = context_cache.put(s1, "zk-b", "bbb", 200)
  context_cache.size(s2) |> should.equal(2)

  // Adding a third entry must evict one (the LRU = "zk-a" with ts=100)
  let s3 = context_cache.put(s2, "zk-c", "ccc", 300)
  context_cache.size(s3) |> should.equal(2)

  // zk-a should have been evicted
  context_cache.contains(s3, "zk-a") |> should.be_false()
  // zk-b and zk-c should still be present
  context_cache.contains(s3, "zk-b") |> should.be_true()
  context_cache.contains(s3, "zk-c") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T10 — evict_lru removes the entry with the smallest last_accessed_ms
// ---------------------------------------------------------------------------

pub fn evict_lru_removes_oldest_test() {
  let state = context_cache.init(10)
  let s1 = context_cache.put(state, "old", "old-data", 100)
  let s2 = context_cache.put(s1, "mid", "mid-data", 500)
  let s3 = context_cache.put(s2, "new", "new-data", 1000)
  context_cache.size(s3) |> should.equal(3)

  let evicted = context_cache.evict_lru(s3)
  context_cache.size(evicted) |> should.equal(2)
  // "old" had smallest ts=100 and should be gone
  context_cache.contains(evicted, "old") |> should.be_false()
  context_cache.contains(evicted, "mid") |> should.be_true()
  context_cache.contains(evicted, "new") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T11 — evict_lru on empty cache is a no-op
// ---------------------------------------------------------------------------

pub fn evict_lru_empty_cache_noop_test() {
  let state = context_cache.init(8)
  let after = context_cache.evict_lru(state)
  context_cache.size(after) |> should.equal(0)
  after.hits |> should.equal(0)
  after.misses |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T12 — hit_rate returns 0.0 when no lookups
// ---------------------------------------------------------------------------

pub fn hit_rate_zero_on_no_lookups_test() {
  let state = context_cache.init(16)
  context_cache.hit_rate(state) |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// T13 — hit_rate is correct after mixed hits and misses
// ---------------------------------------------------------------------------

pub fn hit_rate_calculation_test() {
  let state = context_cache.init(16)
  let s1 = context_cache.put(state, "zk-x", "data", 1000)
  let #(s2, _) = context_cache.get(s1, "zk-x")
  // 1 hit
  let #(s3, _) = context_cache.get(s2, "zk-x")
  // 2 hits
  let #(s4, _) = context_cache.get(s3, "zk-miss")
  // 1 miss — total = 3
  let rate = context_cache.hit_rate(s4)
  // 2/3 ≈ 0.666...
  { rate >. 0.6 } |> should.be_true()
  { rate <. 0.8 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T14 — summary contains expected fields; to_json has JSON shape
// ---------------------------------------------------------------------------

pub fn summary_contains_size_and_hit_rate_test() {
  let state = context_cache.init(32)
  let s1 = context_cache.put(state, "zk-s", "content", 100)
  let #(s2, _) = context_cache.get(s1, "zk-s")
  let summ = context_cache.summary(s2)
  string.contains(summ, "size=") |> should.be_true()
  string.contains(summ, "hit_rate=") |> should.be_true()
  string.contains(summ, "hits=") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T15 — to_json produces valid-looking JSON
// ---------------------------------------------------------------------------

pub fn to_json_contains_expected_keys_test() {
  let state = context_cache.init(8)
  let s1 = context_cache.put(state, "zk-json", "payload", 999)
  let j = context_cache.to_json(s1)
  string.contains(j, "\"size\"") |> should.be_true()
  string.contains(j, "\"hits\"") |> should.be_true()
  string.contains(j, "\"misses\"") |> should.be_true()
  string.contains(j, "\"hit_rate\"") |> should.be_true()
  string.contains(j, "zk-json") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T16 — hottest_entries returns entries sorted by access_count descending
// ---------------------------------------------------------------------------

pub fn hottest_entries_sorted_by_access_count_test() {
  let state = context_cache.init(16)
  let s1 = context_cache.put(state, "zk-cold", "cold", 100)
  let s2 = context_cache.put(s1, "zk-hot", "hot", 200)
  // Access "zk-hot" 3 times
  let #(s3, _) = context_cache.get(s2, "zk-hot")
  let #(s4, _) = context_cache.get(s3, "zk-hot")
  let #(s5, _) = context_cache.get(s4, "zk-hot")
  // Access "zk-cold" once
  let #(s6, _) = context_cache.get(s5, "zk-cold")

  let hot_list = context_cache.hottest_entries(s6)
  case hot_list {
    [first, ..] -> first.holon_id |> should.equal("zk-hot")
    [] -> should.fail()
  }
}
