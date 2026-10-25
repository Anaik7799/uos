//// Pure bounded Telegram ledger. These values do not grant task authority.
//// A durable adapter must commit transitions atomically under real task/resource
//// fences. Recovery never re-executes a request that may have produced a result.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const max_queue_capacity = 1000

pub const max_batch_size = 1000

pub const max_chunks = 16

pub const max_chunk_payload_bytes = 4096

pub type InboxStatus {
  InboxPending
  InboxProcessing(worker: String, epoch: Int)
  InboxResultReady(digest: String)
  InboxCompleted(digest: String)
  InboxRejected(reason: String)
  InboxHold(reason: String)
}

pub type InboxRecord {
  InboxRecord(
    update_id: Int,
    message_id: Int,
    chat_id: Int,
    user_id: Int,
    text_hash: String,
    status: InboxStatus,
    created_at_ms: Int,
    bot_id: Int,
    request_id: String,
  )
}

pub type Watermark {
  Watermark(last_committed_offset: Int)
}

pub type OutboxStatus {
  OutboxPending
  OutboxSending(worker: String, epoch: Int)
  OutboxDelivered(telegram_msg_id: Int)
  OutboxFailed(err: String)
  OutboxUncertain(err: String)
}

pub type OutboxChunk {
  OutboxChunk(
    request_id: String,
    chunk_index: Int,
    total_chunks: Int,
    chat_id: Int,
    payload: String,
    status: OutboxStatus,
    attempt_count: Int,
    bot_id: Int,
    result_digest: String,
  )
}

fn bounded(xs: List(a), limit: Int) -> Bool {
  list.length(list.take(xs, limit + 1)) <= limit
}

fn require(ok: Bool, reason: String) -> Result(Nil, String) {
  case ok {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

pub fn valid_worker(worker: String, epoch: Int) -> Bool {
  string.byte_size(worker) > 0
  && string.byte_size(worker) <= 128
  && list.all(string.to_graphemes(worker), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
      c,
    )
  })
  && epoch > 0
  && epoch <= guard.max_identity
}

pub fn make_request_id(bot_id: Int, update_id: Int) -> String {
  "tg-" <> int.to_string(bot_id) <> "-" <> int.to_string(update_id)
}

pub fn valid_record(r: InboxRecord) -> Bool {
  guard.valid_update_id(r.update_id)
  && guard.valid_positive_id(r.bot_id)
  && r.request_id == make_request_id(r.bot_id, r.update_id)
  && r.created_at_ms >= 0
  && r.created_at_ms <= guard.max_identity
  && guard.valid_digest(r.text_hash)
  && case r.status {
    InboxProcessing(w, e) -> valid_worker(w, e)
    InboxResultReady(d) | InboxCompleted(d) -> guard.valid_digest(d)
    InboxHold(reason) -> reason != "" && string.byte_size(reason) <= 128
    _ -> True
  }
  && case r.status {
    InboxRejected("withdrawn_by_requester") ->
      guard.valid_positive_id(r.message_id) && guard.valid_positive_id(r.user_id)
      && guard.valid_chat_id(r.chat_id)
    InboxRejected(reason) -> reason != "" && string.byte_size(reason) <= 128
    _ ->
      guard.valid_positive_id(r.message_id)
      && guard.valid_positive_id(r.user_id)
      && guard.valid_chat_id(r.chat_id)
  }
}

fn verdict_record(
  v: guard.IngressVerdict,
  now: Int,
) -> Result(InboxRecord, String) {
  use _ <- result.try(require(
    now >= 0 && now <= guard.max_identity,
    "invalid_time",
  ))
  case v {
    guard.AcceptedEnvelope(uid, mid, chat, user, hash, text, directive, bot, _cb_id) -> {
      use _ <- result.try(require(
        guard.valid_update_id(uid)
          && guard.valid_positive_id(bot)
          && guard.valid_positive_id(mid)
          && guard.valid_positive_id(user)
          && guard.valid_chat_id(chat)
          && guard.valid_text(text)
          && hash == files.digest(text)
          && directive == guard.classify_directive(text),
        "invalid_accepted_envelope",
      ))
      Ok(InboxRecord(
        uid,
        mid,
        chat,
        user,
        hash,
        InboxPending,
        now,
        bot,
        make_request_id(bot, uid),
      ))
    }
    guard.RejectedUpdate(uid, bot, hash, reason) -> {
      use _ <- result.try(require(
        guard.valid_update_id(uid)
          && guard.valid_positive_id(bot)
          && guard.valid_digest(hash)
          && reason != ""
          && string.byte_size(reason) <= 128,
        "invalid_rejection_tombstone",
      ))
      Ok(InboxRecord(
        uid,
        0,
        0,
        0,
        hash,
        InboxRejected(reason),
        now,
        bot,
        make_request_id(bot, uid),
      ))
    }
    guard.UnidentifiedRejection(_) ->
      Error("unidentified_update_cannot_advance_offset")
  }
}

fn same_identity(a: InboxRecord, b: InboxRecord) -> Bool {
  a.request_id == b.request_id
  && a.bot_id == b.bot_id
  && a.update_id == b.update_id
  && a.message_id == b.message_id
  && a.chat_id == b.chat_id
  && a.user_id == b.user_id
  && a.text_hash == b.text_hash
  && case a.status, b.status {
    InboxRejected("withdrawn_by_requester"), InboxPending -> True
    InboxRejected(x), InboxRejected(y) -> x == y
    InboxRejected(_), _ | _, InboxRejected(_) -> False
    _, _ -> True
  }
}

pub fn ingest_single(
  v: guard.IngressVerdict,
  now: Int,
  inbox: List(InboxRecord),
) -> Result(InboxRecord, String) {
  use _ <- result.try(require(bounded(inbox, max_queue_capacity), "queue_bound"))
  use proposed <- result.try(verdict_record(v, now))
  let matches =
    list.filter(inbox, fn(r) { r.request_id == proposed.request_id })
  case matches {
    [] -> {
      use _ <- result.try(require(
        list.length(inbox) < max_queue_capacity,
        "queue_full",
      ))
      Ok(proposed)
    }
    [old] -> {
      use _ <- result.try(require(
        valid_record(old) && same_identity(old, proposed),
        "identity_collision",
      ))
      Ok(old)
    }
    _ -> Error("duplicate_persisted_identity")
  }
}

fn uid(v: guard.IngressVerdict) -> Int {
  case v {
    guard.AcceptedEnvelope(update_id: id, ..) -> id
    guard.RejectedUpdate(update_id: id, ..) -> id
    guard.UnidentifiedRejection(_) -> -1
  }
}

/// One watermark belongs to exactly one bot. Reject mixed-bot batches/inboxes.
/// Equal-ID groups are checked completely before committing their representative.
pub fn ingest_batch(
  watermark: Watermark,
  updates: List(guard.IngressVerdict),
  inbox: List(InboxRecord),
  now: Int,
) -> #(Watermark, List(InboxRecord), List(String)) {
  case
    bounded(updates, max_batch_size)
    && bounded(inbox, max_queue_capacity)
    && watermark.last_committed_offset >= 0
    && watermark.last_committed_offset <= guard.max_update_id + 1
  {
    False -> #(watermark, inbox, ["batch_or_watermark_bound"])
    True -> {
      let records = list.try_map(updates, fn(v) { verdict_record(v, now) })
      case records {
        Error(err) -> #(watermark, inbox, [err])
        Ok(rs) -> {
          let bots =
            list.unique(list.append(
              list.map(rs, fn(r) { r.bot_id }),
              list.map(inbox, fn(r) { r.bot_id }),
            ))
          case
            list.length(bots) <= 1
            && list.all(inbox, valid_record)
            && list.length(list.unique(list.map(inbox, fn(r) { r.request_id })))
            == list.length(inbox)
          {
            False -> #(watermark, inbox, ["invalid_or_mixed_bot_inbox"])
            True ->
              do_batch(
                watermark,
                list.sort(updates, fn(a, b) { int.compare(uid(a), uid(b)) }),
                inbox,
                now,
              )
          }
        }
      }
    }
  }
}

fn do_batch(
  wm: Watermark,
  updates: List(guard.IngressVerdict),
  inbox: List(InboxRecord),
  now: Int,
) -> #(Watermark, List(InboxRecord), List(String)) {
  case updates {
    [] -> #(wm, inbox, [])
    [first, ..] -> {
      let group = list.take_while(updates, fn(v) { uid(v) == uid(first) })
      let rest = list.drop(updates, list.length(group))
      let checked = {
        use proposed <- result.try(verdict_record(first, now))
        use group_rows <- result.try(
          list.try_map(group, fn(v) { verdict_record(v, now) }),
        )
        use _ <- result.try(require(
          list.all(group_rows, fn(r) { same_identity(r, proposed) }),
          "batch_identity_collision",
        ))
        use _ <- result.try(require(
          proposed.update_id >= wm.last_committed_offset
            || list.any(inbox, fn(r) { r.request_id == proposed.request_id }),
          "unseen_update_below_committed_offset",
        ))
        ingest_single(first, now, inbox)
      }
      case checked {
        Error(err) -> #(wm, inbox, [err])
        Ok(row) -> {
          let next_inbox = case
            list.any(inbox, fn(r) { r.request_id == row.request_id })
          {
            True -> inbox
            False -> [row, ..inbox]
          }
          do_batch(
            Watermark(int.max(wm.last_committed_offset, row.update_id + 1)),
            rest,
            next_inbox,
            now,
          )
        }
      }
    }
  }
}

pub fn claim_inbox_task(
  r: InboxRecord,
  worker: String,
  epoch: Int,
) -> Result(InboxRecord, String) {
  use _ <- result.try(require(
    valid_record(r) && valid_worker(worker, epoch),
    "invalid_record_or_owner",
  ))
  case r.status {
    InboxPending -> Ok(InboxRecord(..r, status: InboxProcessing(worker, epoch)))
    _ -> Error("inbox_not_pending")
  }
}

pub fn payload_valid(payload: String) -> Bool {
  string.trim(payload) != ""
  && string.byte_size(payload) <= max_chunk_payload_bytes
  && !string.contains(payload, "\u{0}")
}

/// Digest schema v2 binds every immutable inbox field and ordered payloads.
/// No v1 persisted data is admitted by this unreleased development module.
fn result_digest(r: InboxRecord, payloads: List(String)) -> String {
  json.object([
    #("schema", json.string("uos.telegram-result.v2")),
    #("request_id", json.string(r.request_id)),
    #("bot_id", json.int(r.bot_id)),
    #("chat_id", json.int(r.chat_id)),
    #("update_id", json.int(r.update_id)),
    #("message_id", json.int(r.message_id)),
    #("user_id", json.int(r.user_id)),
    #("text_hash", json.string(r.text_hash)),
    #("created_at_ms", json.int(r.created_at_ms)),
    #("payloads", json.array(payloads, json.string)),
  ])
  |> json.to_string
  |> files.digest
}

/// The only normal path producing a result. Persist returned record and all
/// chunks in one transaction; replaying this on ResultReady is refused.
pub fn record_result(
  r: InboxRecord,
  payloads: List(String),
  worker: String,
  epoch: Int,
) -> Result(#(InboxRecord, List(OutboxChunk)), String) {
  use _ <- result.try(require(
    valid_record(r) && valid_worker(worker, epoch),
    "invalid_record_or_owner",
  ))
  use _ <- result.try(require(
    r.status == InboxProcessing(worker, epoch),
    "result_owner_or_state_mismatch",
  ))
  use _ <- result.try(require(
    payloads != []
      && bounded(payloads, max_chunks)
      && list.all(payloads, payload_valid),
    "result_payload_bound",
  ))
  let digest = result_digest(r, payloads)
  let total = list.length(payloads)
  let chunks =
    list.index_map(payloads, fn(payload, index) {
      OutboxChunk(
        r.request_id,
        index,
        total,
        r.chat_id,
        payload,
        OutboxPending,
        0,
        r.bot_id,
        digest,
      )
    })
  Ok(#(InboxRecord(..r, status: InboxResultReady(digest)), chunks))
}

pub fn valid_chunk(c: OutboxChunk) -> Bool {
  c.chunk_index >= 0
  && c.total_chunks > 0
  && c.total_chunks <= max_chunks
  && c.chunk_index < c.total_chunks
  && payload_valid(c.payload)
  && guard.valid_positive_id(c.bot_id)
  && guard.valid_chat_id(c.chat_id)
  && guard.valid_digest(c.result_digest)
  && case c.status {
    OutboxPending -> c.attempt_count == 0
    OutboxSending(w, e) -> c.attempt_count == 1 && valid_worker(w, e)
    OutboxDelivered(id) -> c.attempt_count == 1 && guard.valid_positive_id(id)
    OutboxUncertain(reason) | OutboxFailed(reason) ->
      c.attempt_count == 1 && reason != "" && string.byte_size(reason) <= 128
  }
}

/// Complete set validation is independent of input order and rejects missing or
/// duplicate indices. All paths that send/reconcile/complete use this validator.
pub fn validate_result(
  r: InboxRecord,
  chunks: List(OutboxChunk),
) -> Result(#(String, List(OutboxChunk)), String) {
  use _ <- result.try(require(
    valid_record(r) && chunks != [] && bounded(chunks, max_chunks),
    "invalid_result_bound",
  ))
  let ordered =
    list.sort(chunks, fn(a, b) { int.compare(a.chunk_index, b.chunk_index) })
  let count = list.length(ordered)
  use _ <- result.try(require(
    list.all(
      list.index_map(ordered, fn(c, i) {
        valid_chunk(c)
        && c.request_id == r.request_id
        && c.chat_id == r.chat_id
        && c.bot_id == r.bot_id
        && c.total_chunks == count
        && c.chunk_index == i
      }),
      fn(ok) { ok },
    ),
    "result_identity_or_chunk_set_mismatch",
  ))
  let digest = result_digest(r, list.map(ordered, fn(c) { c.payload }))
  use _ <- result.try(require(
    list.all(ordered, fn(c) { c.result_digest == digest }),
    "result_digest_mismatch",
  ))
  use _ <- result.try(require(
    case r.status {
      InboxResultReady(d) | InboxCompleted(d) -> d == digest
      InboxProcessing(_, _) -> True
      _ -> False
    },
    "result_record_state_or_digest_mismatch",
  ))
  Ok(#(digest, ordered))
}

fn valid_delivery_progress(chunks: List(OutboxChunk)) -> Bool {
  let prefix =
    list.take_while(chunks, fn(c) {
      case c.status {
        OutboxDelivered(_) -> True
        _ -> False
      }
    })
  case list.drop(chunks, list.length(prefix)) {
    [] -> True
    [first, ..rest] -> {
      let pending_suffix = list.all(rest, fn(c) { c.status == OutboxPending })
      pending_suffix
      && case first.status {
        OutboxPending | OutboxSending(_, _) -> True
        _ -> False
      }
    }
  }
}

fn ready_result(
  r: InboxRecord,
  chunks: List(OutboxChunk),
) -> Result(List(OutboxChunk), String) {
  use #(_, ordered) <- result.try(validate_result(r, chunks))
  use _ <- result.try(require(
    valid_delivery_progress(ordered),
    "inconsistent_or_uncertain_delivery_progress",
  ))
  case r.status {
    InboxResultReady(_) -> Ok(ordered)
    _ -> Error("result_not_ready")
  }
}

pub fn claim_outbox_send(
  r: InboxRecord,
  chunks: List(OutboxChunk),
  index: Int,
  worker: String,
  epoch: Int,
) -> Result(List(OutboxChunk), String) {
  use ordered <- result.try(ready_result(r, chunks))
  use _ <- result.try(require(
    valid_worker(worker, epoch) && index >= 0 && index < list.length(ordered),
    "invalid_send_owner_or_index",
  ))
  use target <- result.try(
    list.find(ordered, fn(c) { c.chunk_index == index })
    |> result.replace_error("missing_chunk"),
  )
  use _ <- result.try(require(
    target.status == OutboxPending,
    "blind_retry_or_terminal_refused",
  ))
  // Send in order, never cross an earlier uncertain/failed/pending chunk.
  use _ <- result.try(require(
    list.all(list.take(ordered, index), fn(c) {
      case c.status {
        OutboxDelivered(_) -> True
        _ -> False
      }
    }),
    "prior_chunk_not_delivered",
  ))
  Ok(
    list.map(ordered, fn(c) {
      case c.chunk_index == index {
        True ->
          OutboxChunk(
            ..c,
            status: OutboxSending(worker, epoch),
            attempt_count: 1,
          )
        False -> c
      }
    }),
  )
}

pub fn reconcile_send_outcome(
  r: InboxRecord,
  chunks: List(OutboxChunk),
  index: Int,
  http_status: Int,
  ok: Bool,
  remote_chat_id: Int,
  remote_msg_id: Int,
  worker: String,
  epoch: Int,
) -> Result(List(OutboxChunk), String) {
  use ordered <- result.try(ready_result(r, chunks))
  use _ <- result.try(require(valid_worker(worker, epoch), "invalid_owner"))
  use target <- result.try(
    list.find(ordered, fn(c) { c.chunk_index == index })
    |> result.replace_error("missing_chunk"),
  )
  use _ <- result.try(require(
    target.status == OutboxSending(worker, epoch),
    "owner_or_state_mismatch",
  ))
  let outcome = case
    http_status == 200
    && ok
    && remote_chat_id == r.chat_id
    && guard.valid_positive_id(remote_msg_id)
  {
    True -> OutboxDelivered(remote_msg_id)
    False -> OutboxUncertain("remote_outcome_unverified")
  }
  Ok(
    list.map(ordered, fn(c) {
      case c.chunk_index == index {
        True -> OutboxChunk(..c, status: outcome)
        False -> c
      }
    }),
  )
}

pub fn complete_inbox_task(
  r: InboxRecord,
  chunks: List(OutboxChunk),
) -> Result(InboxRecord, String) {
  use ordered <- result.try(ready_result(r, chunks))
  use _ <- result.try(require(
    list.all(ordered, fn(c) {
      case c.status {
        OutboxDelivered(_) -> True
        _ -> False
      }
    }),
    "delivery_not_complete",
  ))
  Ok(
    InboxRecord(
      ..r,
      status: InboxCompleted(result_digest(
        r,
        list.map(ordered, fn(c) { c.payload }),
      )),
    ),
  )
}

/// One request at a time; callers must group a bounded ledger by request ID.
/// No fake completion digest, no requeue, no automatic uncertain delivery retry.
pub fn recover_request(
  r: InboxRecord,
  chunks: List(OutboxChunk),
) -> #(InboxRecord, List(OutboxChunk)) {
  case valid_record(r), r.status, chunks {
    True, InboxPending, []
    | True, InboxRejected(_), []
    | True, InboxHold(_), _
    -> #(r, chunks)
    _, _, _ -> recover_result(r, chunks)
  }
}

fn recover_result(
  r: InboxRecord,
  chunks: List(OutboxChunk),
) -> #(InboxRecord, List(OutboxChunk)) {
  let held = fn(reason) {
    #(InboxRecord(..r, status: InboxHold(reason)), chunks)
  }
  case validate_result(r, chunks) {
    Error(_) -> held("invalid_or_missing_durable_result")
    Ok(#(digest, ordered)) -> {
      let recovered =
        list.map(ordered, fn(c) {
          case c.status {
            OutboxSending(_, _) ->
              OutboxChunk(..c, status: OutboxUncertain("crash_during_send"))
            _ -> c
          }
        })
      let unsafe =
        list.any(recovered, fn(c) {
          case c.status {
            OutboxUncertain(_) | OutboxFailed(_) -> True
            _ -> False
          }
        })
      case unsafe {
        True -> #(
          InboxRecord(..r, status: InboxHold("uncertain_or_failed_delivery")),
          recovered,
        )
        False -> {
          let all_delivered =
            list.all(recovered, fn(c) {
              case c.status {
                OutboxDelivered(_) -> True
                _ -> False
              }
            })
          // Reject impossible delivered-after-pending snapshots.
          let prefix =
            list.take_while(recovered, fn(c) {
              case c.status {
                OutboxDelivered(_) -> True
                _ -> False
              }
            })
          let suffix = list.drop(recovered, list.length(prefix))
          case
            list.all(suffix, fn(c) { c.status == OutboxPending })
            && case r.status {
              InboxCompleted(_) -> all_delivered
              _ -> True
            }
          {
            False -> #(
              InboxRecord(..r, status: InboxHold("inconsistent_delivery_order")),
              recovered,
            )
            True -> #(
              InboxRecord(..r, status: case all_delivered {
                True -> InboxCompleted(digest)
                False -> InboxResultReady(digest)
              }),
              recovered,
            )
          }
        }
      }
    }
  }
}
