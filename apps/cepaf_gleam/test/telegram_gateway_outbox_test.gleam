import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn req(kind: outbox.Kind, digest: String, at: Int) -> outbox.Request {
  outbox.Request(
    kind: kind,
    chat_id: 7,
    text: "text-" <> digest,
    source_topic: "t",
    observed_at_ms: at,
    digest: digest,
  )
}

fn add(q: outbox.Queue, kind: outbox.Kind, digest: String, at: Int) {
  let assert Ok(q2) = outbox.enqueue(q, req(kind, digest, at))
  q2
}

fn digests(rs: List(outbox.Request)) -> List(String) {
  list.map(rs, fn(r) { r.digest })
}

pub fn capacity_is_clamped_test() {
  outbox.capacity(outbox.new(0)) |> should.equal(1)
  outbox.capacity(outbox.new(-5)) |> should.equal(1)
  outbox.capacity(outbox.new(10)) |> should.equal(10)
  outbox.capacity(outbox.new(64)) |> should.equal(64)
  outbox.capacity(outbox.new(1000)) |> should.equal(64)
}

pub fn enqueue_counts_len_test() {
  let q =
    outbox.new(4) |> add(outbox.Notice, "a", 1) |> add(outbox.Notice, "b", 2)
  outbox.len(q) |> should.equal(2)
  outbox.uncertain_count(q) |> should.equal(0)
}

pub fn full_notice_is_refused_test() {
  let q =
    outbox.new(2) |> add(outbox.Notice, "a", 1) |> add(outbox.Notice, "b", 2)
  outbox.enqueue(q, req(outbox.Notice, "c", 3))
  |> should.equal(Error(outbox.Full(False)))
}

pub fn full_critical_with_only_criticals_is_refused_test() {
  let q =
    outbox.new(2)
    |> add(outbox.Critical, "a", 1)
    |> add(outbox.Critical, "b", 2)
  outbox.enqueue(q, req(outbox.Critical, "c", 3))
  |> should.equal(Error(outbox.Full(False)))
}

pub fn critical_evicts_oldest_notice_test() {
  let q =
    outbox.new(3)
    |> add(outbox.Notice, "n1", 1)
    |> add(outbox.Critical, "c1", 2)
    |> add(outbox.Notice, "n2", 3)
    |> add(outbox.Critical, "c2", 4)
  outbox.len(q) |> should.equal(3)
  outbox.dropped_notices(q) |> should.equal(1)
  let #(taken, _) = outbox.select(q, 10)
  // n1 (oldest notice) was evicted; n2 survives.
  taken |> digests |> should.equal(["c1", "c2", "n2"])
}

pub fn duplicate_digest_is_refused_test() {
  let q = outbox.new(4) |> add(outbox.Notice, "a", 1)
  outbox.enqueue(q, req(outbox.Critical, "a", 2))
  |> should.equal(Error(outbox.Duplicate("a")))
}

pub fn duplicate_refused_while_inflight_test() {
  let q = outbox.new(4) |> add(outbox.Notice, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  outbox.enqueue(q, req(outbox.Notice, "a", 2))
  |> should.equal(Error(outbox.Duplicate("a")))
}

pub fn resolved_digest_may_be_requeued_test() {
  let q = outbox.new(4) |> add(outbox.Notice, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  let q = outbox.drain_result(q, "a", ledger.OutboxFailed("http 500"))
  outbox.enqueue(q, req(outbox.Notice, "a", 2)) |> should.be_ok()
}

pub fn oversize_is_refused_test() {
  let q = outbox.new(4)
  let big =
    outbox.Request(
      ..req(outbox.Notice, "big", 1),
      text: string.repeat("x", 3501),
    )
  outbox.enqueue(q, big) |> should.equal(Error(outbox.Oversize))
  let edge =
    outbox.Request(
      ..req(outbox.Notice, "edge", 1),
      text: string.repeat("x", 3500),
    )
  outbox.enqueue(q, edge) |> should.be_ok()
}

pub fn oversize_counts_bytes_not_graphemes_test() {
  // 1200 three-byte characters = 3600 bytes > 3500
  let q = outbox.new(4)
  let r =
    outbox.Request(..req(outbox.Notice, "u", 1), text: string.repeat("€", 1200))
  outbox.enqueue(q, r) |> should.equal(Error(outbox.Oversize))
}

pub fn select_orders_critical_first_oldest_first_test() {
  let q =
    outbox.new(8)
    |> add(outbox.Notice, "n1", 1)
    |> add(outbox.Critical, "c1", 2)
    |> add(outbox.Notice, "n2", 3)
    |> add(outbox.Critical, "c2", 4)
  let #(taken, rest) = outbox.select(q, 3)
  taken |> digests |> should.equal(["c1", "c2", "n1"])
  outbox.len(rest) |> should.equal(1)
  outbox.inflight_count(rest) |> should.equal(3)
}

pub fn select_respects_budget_test() {
  let q =
    outbox.new(8)
    |> add(outbox.Notice, "a", 1)
    |> add(outbox.Notice, "b", 2)
    |> add(outbox.Notice, "c", 3)
  let #(none, q0) = outbox.select(q, 0)
  none |> should.equal([])
  outbox.len(q0) |> should.equal(3)
  let #(neg, _) = outbox.select(q, -3)
  neg |> should.equal([])
  let #(one, q1) = outbox.select(q, 1)
  one |> digests |> should.equal(["a"])
  outbox.len(q1) |> should.equal(2)
}

pub fn select_bounded_by_inflight_room_test() {
  let q =
    outbox.new(2)
    |> add(outbox.Notice, "a", 1)
    |> add(outbox.Notice, "b", 2)
  let #(first, q) = outbox.select(q, 10)
  first |> digests |> should.equal(["a", "b"])
  let q = add(q, outbox.Notice, "c", 3)
  // two requests in flight == capacity: nothing more may be handed out
  let #(second, q) = outbox.select(q, 10)
  second |> should.equal([])
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(1))
  let #(third, _) = outbox.select(q, 10)
  third |> digests |> should.equal(["c"])
}

pub fn drain_delivered_and_failed_test() {
  let q =
    outbox.new(4) |> add(outbox.Notice, "a", 1) |> add(outbox.Notice, "b", 2)
  let #(_, q) = outbox.select(q, 2)
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(42))
  let q = outbox.drain_result(q, "b", ledger.OutboxFailed("boom"))
  outbox.delivered_count(q) |> should.equal(1)
  outbox.failed_count(q) |> should.equal(1)
  outbox.inflight_count(q) |> should.equal(0)
  outbox.uncertain_count(q) |> should.equal(0)
}

pub fn drain_uncertain_is_preserved_test() {
  let q = outbox.new(4) |> add(outbox.Critical, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  let q = outbox.drain_result(q, "a", ledger.OutboxUncertain("timeout"))
  outbox.uncertain_count(q) |> should.equal(1)
  outbox.inflight_count(q) |> should.equal(0)
  outbox.delivered_count(q) |> should.equal(0)
  outbox.failed_count(q) |> should.equal(0)
  // Uncertain blocks a blind resend of the same digest.
  outbox.enqueue(q, req(outbox.Critical, "a", 9))
  |> should.equal(Error(outbox.Duplicate("a")))
  // A later definitive report resolves it.
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(5))
  outbox.uncertain_count(q) |> should.equal(0)
  outbox.delivered_count(q) |> should.equal(1)
}

/// Review G-04: an uncertain backlog at capacity refuses Notices but not
/// Criticals, which are admitted until the hard ceiling of twice the capacity.
pub fn uncertain_at_capacity_blocks_notices_not_criticals_test() {
  let q = outbox.new(1) |> add(outbox.Critical, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  let q = outbox.drain_result(q, "a", ledger.OutboxUncertain("t"))
  outbox.uncertain_count(q) |> should.equal(1)
  outbox.enqueue(q, req(outbox.Notice, "n", 2))
  |> should.equal(Error(outbox.Full(True)))
  let assert Ok(q) = outbox.enqueue(q, req(outbox.Critical, "b", 2))
  let #(_, q) = outbox.select(q, 1)
  let q = outbox.drain_result(q, "b", ledger.OutboxUncertain("t"))
  outbox.uncertain_count(q) |> should.equal(outbox.uncertain_hard_ceiling(q))
  outbox.enqueue(q, req(outbox.Critical, "c", 3))
  |> should.equal(Error(outbox.Full(True)))
  // Resolving one uncertain request readmits a Critical.
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(5))
  outbox.enqueue(q, req(outbox.Critical, "c", 3)) |> should.be_ok()
}

/// Review G-05: a delivery claim needs a positive message id.
pub fn delivered_with_non_positive_id_is_uncertain_test() {
  let q = outbox.new(4) |> add(outbox.Critical, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(0))
  outbox.delivered_count(q) |> should.equal(0)
  outbox.uncertain_count(q) |> should.equal(1)
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(-3))
  outbox.delivered_count(q) |> should.equal(0)
  outbox.uncertain_count(q) |> should.equal(1)
  outbox.validate_status(ledger.OutboxDelivered(0))
  |> should.equal(ledger.OutboxUncertain("invalid_message_id"))
  outbox.validate_status(ledger.OutboxDelivered(1))
  |> should.equal(ledger.OutboxDelivered(1))
  let q = outbox.drain_result(q, "a", ledger.OutboxDelivered(1))
  outbox.delivered_count(q) |> should.equal(1)
}

/// A full pending list with only Criticals refuses with the pending flag.
pub fn pending_full_refusal_is_not_an_uncertain_backlog_test() {
  let q = outbox.new(1) |> add(outbox.Critical, "a", 1)
  outbox.enqueue(q, req(outbox.Critical, "b", 2))
  |> should.equal(Error(outbox.Full(False)))
}

pub fn drain_unknown_digest_and_nonterminal_are_noops_test() {
  let q = outbox.new(4) |> add(outbox.Notice, "a", 1)
  let #(_, q) = outbox.select(q, 1)
  let same = outbox.drain_result(q, "zzz", ledger.OutboxDelivered(1))
  outbox.delivered_count(same) |> should.equal(0)
  outbox.inflight_count(same) |> should.equal(1)
  let pending = outbox.drain_result(q, "a", ledger.OutboxPending)
  outbox.inflight_count(pending) |> should.equal(1)
}

pub fn request_has_no_credential_field_test() {
  // The request record is credential-free by construction; the rendered form
  // must not mention a token either.
  let rendered = string.inspect(req(outbox.Critical, "d", 5))
  string.contains(string.lowercase(rendered), "token") |> should.be_false()
  string.contains(string.lowercase(rendered), "secret") |> should.be_false()
}

/// Review G-04 residual: a quarter of the pending capacity is reserved for
/// Criticals, so a Notice flood cannot fill the queue and a Critical is
/// admitted without an eviction until the reserve is used.
pub fn notices_cannot_take_the_critical_reserve_test() {
  let q = outbox.new(8)
  outbox.critical_reserve(q) |> should.equal(2)
  let q =
    q
    |> add(outbox.Notice, "n1", 1)
    |> add(outbox.Notice, "n2", 2)
    |> add(outbox.Notice, "n3", 3)
    |> add(outbox.Notice, "n4", 4)
    |> add(outbox.Notice, "n5", 5)
    |> add(outbox.Notice, "n6", 6)
  outbox.enqueue(q, req(outbox.Notice, "n7", 7))
  |> should.equal(Error(outbox.Full(False)))
  outbox.len(q) |> should.equal(6)
  // Two Criticals fit in the reserve without evicting anything.
  let q = q |> add(outbox.Critical, "c1", 8) |> add(outbox.Critical, "c2", 9)
  outbox.len(q) |> should.equal(8)
  outbox.dropped_notices(q) |> should.equal(0)
  // The next Critical evicts the oldest Notice.
  let q = add(q, outbox.Critical, "c3", 10)
  outbox.len(q) |> should.equal(8)
  outbox.dropped_notices(q) |> should.equal(1)
  let #(taken, _) = outbox.select(q, 8)
  taken
  |> digests
  |> should.equal(["c1", "c2", "c3", "n2", "n3", "n4", "n5", "n6"])
  // Below four there is no reserve.
  outbox.critical_reserve(outbox.new(3)) |> should.equal(0)
  outbox.critical_reserve(outbox.new(64)) |> should.equal(16)
}

/// Review G-04 residual: the oldest uncertain observation is exposed so a
/// ticker can alarm on a stale backlog.
pub fn oldest_uncertain_observation_is_exposed_test() {
  let q = outbox.new(4)
  outbox.oldest_uncertain_observed_at_ms(q) |> should.equal(None)
  let q = q |> add(outbox.Notice, "a", 500) |> add(outbox.Critical, "b", 100)
  let #(_, q) = outbox.select(q, 2)
  let q = outbox.drain_result(q, "a", ledger.OutboxUncertain("t"))
  outbox.oldest_uncertain_observed_at_ms(q) |> should.equal(Some(500))
  let q = outbox.drain_result(q, "b", ledger.OutboxUncertain("t"))
  outbox.oldest_uncertain_observed_at_ms(q) |> should.equal(Some(100))
  let q = outbox.drain_result(q, "b", ledger.OutboxDelivered(3))
  outbox.oldest_uncertain_observed_at_ms(q) |> should.equal(Some(500))
}
