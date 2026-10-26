//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/telegram_gateway_outbox</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005, SC-JIDOKA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Pure, bounded request queue between the Zenoh-to-Telegram gateway and the
//// drain that sends. The gateway never sends: it enqueues typed requests, a
//// policy (`select`) hands a bounded batch to whoever owns the transport, and
//// that owner reports back with `drain_result`.
////
//// A Request carries no bot token and no chat secret. Credentials stay in the
//// reviewed private transport configuration of the sender.
////
//// Semantics (review G-03, G-04, G-05 applied in wave 6n):
////   * capacity is clamped to 1..64 and bounds the pending list and the
////     in-flight list separately.
////   * the digest is computed by the gateway over kind, chat, topic and text,
////     so a Notice can never pre-empt a Critical with the same text as a
////     duplicate.
////   * refusal is explicit (`Backpressure`); nothing is dropped silently. The
////     one admitted eviction (a Critical request displacing the oldest Notice
////     on a full pending list) is counted by `dropped_notices`.
////   * an Uncertain delivery is never discarded or retried by this module. It
////     blocks an identical digest. An uncertain backlog at `capacity` refuses
////     further Notices (`Full(uncertain_backlog: True)`); a Critical is still
////     admitted until the hard ceiling of twice the capacity, so a hung
////     transport cannot starve critical alerts behind routine ones.
////   * a quarter of the pending capacity is reserved for Criticals: a Notice
////     flood cannot fill the queue (capacities below four have no reserve).
////   * a `Delivered` report whose message id is not positive is not a
////     delivery: it is recorded as `Uncertain("invalid_message_id")`.

import cepaf_gleam/harness/telegram_delivery_ledger.{
  type OutboxStatus, OutboxDelivered, OutboxFailed, OutboxUncertain,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_capacity = 64

pub const max_text_bytes = 3500

pub type Kind {
  Critical
  Notice
}

pub type Request {
  Request(
    kind: Kind,
    chat_id: Int,
    text: String,
    source_topic: String,
    observed_at_ms: Int,
    digest: String,
  )
}

pub type Backpressure {
  /// The queue refused the request. `uncertain_backlog` is True when the
  /// refusal came from the uncertain list, False when the pending list was
  /// full and no Notice could be evicted.
  Full(uncertain_backlog: Bool)
  Duplicate(digest: String)
  Oversize
  /// Returned only by the drain's total clients, never by this module: no
  /// reply was observed within the bound (`call_timeout`) or the actor was
  /// absent (`actor_unavailable`). The request is neither known to be admitted
  /// nor known to be refused; a retry is safe because a repeated digest is
  /// refused as `Duplicate`.
  Unobserved(reason: String)
}

pub opaque type Queue {
  Queue(
    capacity: Int,
    pending: List(Request),
    inflight: List(Request),
    uncertain: List(Request),
    dropped_notices: Int,
    delivered: Int,
    failed: Int,
  )
}

pub fn new(capacity: Int) -> Queue {
  Queue(
    capacity: clamp(capacity),
    pending: [],
    inflight: [],
    uncertain: [],
    dropped_notices: 0,
    delivered: 0,
    failed: 0,
  )
}

fn clamp(n: Int) -> Int {
  case n < 1 {
    True -> 1
    False ->
      case n > max_capacity {
        True -> max_capacity
        False -> n
      }
  }
}

pub fn capacity(queue: Queue) -> Int {
  queue.capacity
}

/// Uncertain backlog beyond which even a Critical is refused.
pub fn uncertain_hard_ceiling(queue: Queue) -> Int {
  queue.capacity * 2
}

/// Pending slots a Notice may never take (review G-04): a quarter of the
/// capacity, so a Notice flood leaves room for Criticals without an eviction.
/// A capacity below four has no reserve; eviction is the only control there.
pub fn critical_reserve(queue: Queue) -> Int {
  queue.capacity / 4
}

/// Earliest `observed_at_ms` among uncertain requests, or `None`. A ticker
/// compares it with its clock to alarm on a stale uncertain backlog; this
/// module holds no clock and raises no alarm itself.
pub fn oldest_uncertain_observed_at_ms(queue: Queue) -> Option(Int) {
  list.fold(queue.uncertain, None, fn(acc, r) {
    case acc {
      None -> Some(r.observed_at_ms)
      Some(t) if r.observed_at_ms < t -> Some(r.observed_at_ms)
      Some(_) -> acc
    }
  })
}

fn pending_room(queue: Queue, kind: Kind) -> Int {
  case kind {
    Notice -> queue.capacity - critical_reserve(queue)
    Critical -> queue.capacity
  }
}

pub fn len(queue: Queue) -> Int {
  list.length(queue.pending)
}

pub fn inflight_count(queue: Queue) -> Int {
  list.length(queue.inflight)
}

pub fn uncertain_count(queue: Queue) -> Int {
  list.length(queue.uncertain)
}

pub fn dropped_notices(queue: Queue) -> Int {
  queue.dropped_notices
}

pub fn delivered_count(queue: Queue) -> Int {
  queue.delivered
}

pub fn failed_count(queue: Queue) -> Int {
  queue.failed
}

fn known_digest(queue: Queue, digest: String) -> Bool {
  let same = fn(r: Request) { r.digest == digest }
  list.any(queue.pending, same)
  || list.any(queue.inflight, same)
  || list.any(queue.uncertain, same)
}

fn uncertain_blocks(queue: Queue, kind: Kind) -> Bool {
  let backlog = list.length(queue.uncertain)
  case kind {
    Notice -> backlog >= queue.capacity
    Critical -> backlog >= uncertain_hard_ceiling(queue)
  }
}

pub fn enqueue(queue: Queue, request: Request) -> Result(Queue, Backpressure) {
  case string.byte_size(request.text) > max_text_bytes {
    True -> Error(Oversize)
    False ->
      case known_digest(queue, request.digest) {
        True -> Error(Duplicate(request.digest))
        False ->
          case uncertain_blocks(queue, request.kind) {
            True -> Error(Full(True))
            False ->
              case
                list.length(queue.pending) >= pending_room(queue, request.kind)
              {
                False ->
                  Ok(
                    Queue(
                      ..queue,
                      pending: list.append(queue.pending, [request]),
                    ),
                  )
                True -> admit_when_full(queue, request)
              }
          }
      }
  }
}

/// A pending list with no room for the request's kind admits only a Critical,
/// and only by evicting the oldest Notice. Criticals are never evicted; a
/// Notice at the reserve boundary is refused outright.
fn admit_when_full(
  queue: Queue,
  request: Request,
) -> Result(Queue, Backpressure) {
  case request.kind, list.any(queue.pending, is_notice) {
    Critical, True -> {
      let kept = drop_first_notice(queue.pending)
      Ok(
        Queue(
          ..queue,
          pending: list.append(kept, [request]),
          dropped_notices: queue.dropped_notices + 1,
        ),
      )
    }
    _, _ -> Error(Full(False))
  }
}

fn is_notice(r: Request) -> Bool {
  r.kind == Notice
}

fn drop_first_notice(xs: List(Request)) -> List(Request) {
  case xs {
    [] -> []
    [first, ..rest] ->
      case first.kind {
        Notice -> rest
        Critical -> [first, ..drop_first_notice(rest)]
      }
  }
}

/// Take at most `budget` requests: Critical before Notice, oldest first. The
/// batch is also bounded by the free in-flight slots. Taken requests stay
/// in-flight until `drain_result` reports on their digest.
pub fn select(queue: Queue, budget: Int) -> #(List(Request), Queue) {
  let room = queue.capacity - list.length(queue.inflight)
  let n = int_min(int_min(budget, room), list.length(queue.pending))
  case n <= 0 {
    True -> #([], queue)
    False -> {
      let ordered =
        list.append(
          list.filter(queue.pending, fn(r) { r.kind == Critical }),
          list.filter(queue.pending, fn(r) { r.kind == Notice }),
        )
      let taken = list.take(ordered, n)
      let taken_digests = list.map(taken, fn(r) { r.digest })
      let remaining =
        list.filter(queue.pending, fn(r) {
          !list.contains(taken_digests, r.digest)
        })
      #(
        taken,
        Queue(
          ..queue,
          pending: remaining,
          inflight: list.append(queue.inflight, taken),
        ),
      )
    }
  }
}

fn int_min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

/// A delivery claim is valid only with a positive Telegram message id.
pub fn validate_status(status: OutboxStatus) -> OutboxStatus {
  case status {
    OutboxDelivered(id) if id <= 0 -> OutboxUncertain("invalid_message_id")
    _ -> status
  }
}

/// Record the outcome for a digest that was handed out by `select` (or that is
/// already Uncertain). Delivered (with a positive id) and Failed resolve it;
/// Uncertain keeps the request on the uncertain list so it is neither lost nor
/// blindly retried. Non-terminal statuses and unknown digests leave the queue
/// unchanged.
pub fn drain_result(
  queue: Queue,
  digest: String,
  status: OutboxStatus,
) -> Queue {
  let status = validate_status(status)
  let by_digest = fn(r: Request) { r.digest == digest }
  let found_inflight = list.find(queue.inflight, by_digest)
  let found_uncertain = list.find(queue.uncertain, by_digest)
  let without_inflight =
    list.filter(queue.inflight, fn(r) { r.digest != digest })
  let without_uncertain =
    list.filter(queue.uncertain, fn(r) { r.digest != digest })
  case status, found_inflight, found_uncertain {
    OutboxDelivered(_), Ok(_), _ | OutboxDelivered(_), _, Ok(_) ->
      Queue(
        ..queue,
        inflight: without_inflight,
        uncertain: without_uncertain,
        delivered: queue.delivered + 1,
      )
    OutboxFailed(_), Ok(_), _ | OutboxFailed(_), _, Ok(_) ->
      Queue(
        ..queue,
        inflight: without_inflight,
        uncertain: without_uncertain,
        failed: queue.failed + 1,
      )
    OutboxUncertain(_), Ok(request), _ ->
      Queue(
        ..queue,
        inflight: without_inflight,
        uncertain: list.append(queue.uncertain, [request]),
      )
    _, _, _ -> queue
  }
}
