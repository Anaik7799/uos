//// Local session coordination for Claude, Codex and AGY.
////
//// Denotation: a command history maps to registered sessions, fenced resources,
//// native board messages, recipient acknowledgements and immutable receipts.
//// `apply` is the pure map interpretation; `replay` is the journal interpreter.
//// Same operation ID + same command is idempotent; a conflicting reuse fails.
//// Every accepted claim increases its resource epoch, including after release.
//// ACK, revision references and transport projections never authorize effects.
////
//// Linux storage is serialized across BEAM instances by session_sync_ffi.
//// Authority is the private local Unix-account directory. Same-UID processes
//// are trusted; this is not remote or hostile-tenant authentication. Leases
//// coordinate cooperating clients: executors must enforce `check` themselves.
//// STAMP: SC-TUI-COORD-001; SC-FPP-INTENT-001. #fractal-l2 #zero-muda

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/coord

pub type Command {
  Register(
    session: String,
    provider: String,
    workspace: String,
    revision: String,
    refs: List(String),
  )
  Heartbeat(session: String, revision: String, refs: List(String))
  Claim(session: String, resource: String, ttl_us: Int)
  Renew(session: String, resource: String, epoch: Int, ttl_us: Int)
  Release(session: String, resource: String, epoch: Int)
  Send(
    session: String,
    to: String,
    kind: board.Kind,
    text: String,
    refs: List(String),
  )
  Ack(session: String, message_id: String)
  Retire(session: String)
}

pub type Session {
  Session(
    id: String,
    provider: String,
    workspace: String,
    revision: String,
    refs: List(String),
    boot_id: String,
    heartbeat_us: Int,
    retired: Bool,
  )
}

pub type Receipt {
  Receipt(
    operation_id: String,
    operation: String,
    epoch: Int,
    expires_us: Int,
    message_id: String,
    sequence: Int,
  )
}

pub type Seen {
  Seen(command: Command, receipt: Receipt)
}

pub type State {
  State(
    coordinator: coord.Coord,
    sessions: Dict(String, Session),
    messages: Dict(String, board.Message),
    acknowledgements: Dict(String, List(String)),
    seen: Dict(String, Seen),
    sequence: Int,
    digest: String,
    host_id: String,
    boot_id: String,
    tick_us: Int,
  )
}

pub type Event {
  Event(
    sequence: Int,
    operation_id: String,
    host_id: String,
    boot_id: String,
    tick_us: Int,
    utc_us: Int,
    command: Command,
    previous_digest: String,
    digest: String,
  )
}

pub const genesis = "uos-session-sync/v1"

pub const freshness_us = 120_000_000

pub const max_ttl_us = 3_600_000_000

pub fn empty() -> State {
  State(
    coord.new(coord.default_policy([], 32)),
    dict.new(),
    dict.new(),
    dict.new(),
    dict.new(),
    0,
    genesis,
    "",
    "",
    0,
  )
}

fn identifier(value: String) -> Bool {
  let characters_valid =
    string.to_graphemes(value)
    |> list.all(fn(c) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:",
        c,
      )
    })
  value != "" && string.length(value) <= 128 && characters_valid
}

fn bounded_text(value: String, maximum: Int) -> Bool {
  string.length(value) <= maximum && !string.contains(value, "\u{0000}")
}

fn valid_refs(refs: List(String)) -> Bool {
  list.length(refs) <= 32 && list.all(refs, fn(r) { bounded_text(r, 1024) })
}

fn require(condition: Bool, error: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

pub fn actor(command: Command) -> String {
  case command {
    Register(s, _, _, _, _)
    | Heartbeat(s, _, _)
    | Claim(s, _, _)
    | Renew(s, _, _, _)
    | Release(s, _, _)
    | Send(s, _, _, _, _)
    | Ack(s, _)
    | Retire(s) -> s
  }
}

pub fn operation(command: Command) -> String {
  case command {
    Register(..) -> "register"
    Heartbeat(..) -> "heartbeat"
    Claim(..) -> "claim"
    Renew(..) -> "renew"
    Release(..) -> "release"
    Send(..) -> "send"
    Ack(..) -> "ack"
    Retire(..) -> "retire"
  }
}

pub fn valid_resource(resource: String) -> Bool {
  case resource {
    "integration/main" -> True
    "task:" <> id | "runtime:" <> id -> identifier(id)
    "workspace:" <> path ->
      string.starts_with(path, "/")
      && bounded_text(path, 2048)
      && !list.contains(string.split(path, "/"), "..")
    _ -> False
  }
}

@external(erlang, "session_sync_ffi", "canonical_workspace")
fn storage_canonical_workspace(path: String) -> Result(String, String)

fn require_canonical_workspace(path: String) -> Result(String, String) {
  use canonical <- result.try(storage_canonical_workspace(path))
  use _ <- result.try(require(
    canonical == path,
    "workspace path must use its canonical real directory spelling",
  ))
  Ok(path)
}

/// Validate resource syntax and require workspace resources to name an existing
/// real directory without symlink or lexical aliases.
pub fn canonical_resource(resource: String) -> Result(String, String) {
  use _ <- result.try(require(
    valid_resource(resource),
    "unsupported resource namespace",
  ))
  case resource {
    "workspace:" <> path -> {
      use _ <- result.try(require_canonical_workspace(path))
      Ok(resource)
    }
    _ -> Ok(resource)
  }
}

/// Public so `session_store` can apply the same workspace/resource
/// canonicalization before entering its own SQLite transaction, exactly as
/// `execute` does for the file journal.
pub fn canonical_command(command: Command) -> Result(Command, String) {
  case command {
    Register(_, _, workspace, _, _) -> {
      use _ <- result.try(require_canonical_workspace(workspace))
      Ok(command)
    }
    Claim(_, resource, _)
    | Renew(_, resource, _, _)
    | Release(_, resource, _) -> {
      use _ <- result.try(canonical_resource(resource))
      Ok(command)
    }
    _ -> Ok(command)
  }
}

fn active(state: State, session: String) -> Result(Session, String) {
  use current <- result.try(
    dict.get(state.sessions, session)
    |> result.replace_error("session is not registered"),
  )
  use _ <- result.try(require(
    !current.retired,
    "session is retired; register a new session ID",
  ))
  Ok(current)
}

fn fresh(
  state: State,
  session: String,
  boot: String,
  now: Int,
) -> Result(Session, String) {
  use current <- result.try(active(state, session))
  use _ <- result.try(require(
    current.boot_id == boot
      && now >= current.heartbeat_us
      && now - current.heartbeat_us <= freshness_us,
    "session heartbeat is stale; heartbeat before claiming or renewing",
  ))
  Ok(current)
}

/// Public so `session_store`'s read-only `observe` can normalize replayed
/// state against the current host/boot/tick exactly like the file
/// coordinator's `observe` does before running a status/inbox/check query.
pub fn rebase_clock(
  state: State,
  host: String,
  boot: String,
  now: Int,
) -> Result(State, String) {
  use _ <- result.try(require(
    host != "" && boot != "" && now >= 0,
    "invalid clock identity",
  ))
  use _ <- result.try(require(
    state.host_id == "" || state.host_id == host,
    "journal belongs to another host; cross-host leases are not supported",
  ))
  case state.boot_id == boot {
    True -> {
      use _ <- result.try(require(
        now >= state.tick_us,
        "monotonic clock moved backward",
      ))
      Ok(State(..state, tick_us: now))
    }
    False ->
      Ok(
        State(
          ..state,
          host_id: host,
          boot_id: boot,
          tick_us: now,
          coordinator: coord.Coord(
            ..state.coordinator,
            leases: dict.new(),
            heartbeats: dict.new(),
          ),
        ),
      )
  }
}

fn lease_error(error: coord.Violation) -> String {
  coord.violation_label(error)
}

/// Pure policy transition. Receipts describe accepted commands, never permissions
/// to execute a future operation. Retry a lost reply with the same operation ID.
pub fn apply(
  state: State,
  command: Command,
  operation_id: String,
  host: String,
  boot: String,
  now: Int,
  utc: Int,
) -> Result(#(State, Receipt, Bool), String) {
  use _ <- result.try(require(identifier(operation_id), "invalid operation ID"))
  use _ <- result.try(require(identifier(actor(command)), "invalid session ID"))
  use clocked <- result.try(rebase_clock(state, host, boot, now))
  case dict.get(state.seen, operation_id) {
    Ok(previous) -> {
      use _ <- result.try(require(
        previous.command == command,
        "operation ID already belongs to a different command",
      ))
      Ok(#(clocked, previous.receipt, True))
    }
    Error(_) -> {
      let base =
        Receipt(operation_id, operation(command), 0, 0, "", state.sequence + 1)
      use #(next, receipt) <- result.try(transition(
        clocked,
        command,
        base,
        boot,
        now,
        utc,
      ))
      let next =
        State(
          ..next,
          sequence: receipt.sequence,
          seen: dict.insert(next.seen, operation_id, Seen(command, receipt)),
        )
      Ok(#(next, receipt, False))
    }
  }
}

fn transition(
  state: State,
  command: Command,
  receipt: Receipt,
  boot: String,
  now: Int,
  utc: Int,
) -> Result(#(State, Receipt), String) {
  case command {
    Register(id, provider, workspace, revision, refs) -> {
      use _ <- result.try(require(
        list.contains(["claude", "codex", "agy"], provider),
        "provider must be claude, codex, or agy",
      ))
      use _ <- result.try(require(
        !dict.has_key(state.sessions, id),
        "session already registered; retry original op_id or heartbeat",
      ))
      use _ <- result.try(require(
        string.starts_with(workspace, "/")
          && bounded_text(workspace, 2048)
          && bounded_text(revision, 512)
          && valid_refs(refs),
        "invalid workspace, revision, or metadata refs",
      ))
      let session =
        Session(id, provider, workspace, revision, refs, boot, now, False)
      let sessions = dict.insert(state.sessions, id, session)
      let roster =
        sessions
        |> dict.values
        |> list.map(fn(s) { board.Agent(s.id, "L2", s.provider) })
      let c =
        coord.Coord(
          ..state.coordinator,
          policy: coord.Policy(..state.coordinator.policy, roster: roster),
        )
      Ok(#(
        State(..state, sessions: sessions, coordinator: coord.beat(c, id, now)),
        receipt,
      ))
    }
    Heartbeat(id, revision, refs) -> {
      use current <- result.try(active(state, id))
      use _ <- result.try(require(
        bounded_text(revision, 512) && valid_refs(refs),
        "invalid revision or metadata refs",
      ))
      let session =
        Session(
          ..current,
          revision: revision,
          refs: refs,
          boot_id: boot,
          heartbeat_us: now,
        )
      Ok(#(
        State(
          ..state,
          sessions: dict.insert(state.sessions, id, session),
          coordinator: coord.beat(state.coordinator, id, now),
        ),
        receipt,
      ))
    }
    Claim(id, resource, ttl) -> {
      use _ <- result.try(fresh(state, id, boot, now))
      use _ <- result.try(require(
        valid_resource(resource),
        "unsupported resource namespace",
      ))
      use _ <- result.try(require(
        ttl >= 1_000_000 && ttl <= max_ttl_us,
        "lease TTL must be 1..3600 seconds",
      ))
      use _ <- result.try(require(
        list.length(coord.live_leases(state.coordinator, now)) < 128,
        "active resource limit reached",
      ))
      use #(c, lease) <- result.try(
        coord.acquire(state.coordinator, resource, id, now, ttl)
        |> result.map_error(lease_error),
      )
      Ok(#(
        State(..state, coordinator: c),
        Receipt(..receipt, epoch: lease.epoch, expires_us: lease.expires_us),
      ))
    }
    Renew(id, resource, epoch, ttl) -> {
      use _ <- result.try(fresh(state, id, boot, now))
      use _ <- result.try(require(
        ttl >= 1_000_000 && ttl <= max_ttl_us,
        "lease TTL must be 1..3600 seconds",
      ))
      use #(c, lease) <- result.try(
        coord.renew(state.coordinator, resource, id, epoch, now, ttl)
        |> result.map_error(lease_error),
      )
      Ok(#(
        State(..state, coordinator: c),
        Receipt(..receipt, epoch: lease.epoch, expires_us: lease.expires_us),
      ))
    }
    Release(id, resource, epoch) -> {
      use _ <- result.try(active(state, id))
      use c <- result.try(
        coord.release(state.coordinator, resource, id, epoch)
        |> result.map_error(lease_error),
      )
      Ok(#(State(..state, coordinator: c), Receipt(..receipt, epoch: epoch)))
    }
    Send(id, to, kind, text, refs) -> {
      use sender <- result.try(active(state, id))
      use _ <- result.try(require(
        to == "broadcast" || dict.has_key(state.sessions, to),
        "unknown recipient",
      ))
      use _ <- result.try(require(
        list.contains(
          [
            board.Report,
            board.Progress,
            board.Question,
            board.Answer,
            board.Andon,
          ],
          kind,
        ),
        "session messages are observations; executable/control message kinds are not allowed",
      ))
      use _ <- result.try(require(
        bounded_text(text, 4096) && valid_refs(refs),
        "message body or refs too large",
      ))
      let prior =
        state.messages
        |> dict.values
        |> board.by_agent(id)
        |> list.sort(fn(a, b) { int.compare(a.lamport, b.lamport) })
        |> list.last
        |> result.map(fn(m) { m.digest })
        |> result.unwrap("")
      let trace = board.sha256_hex(receipt.operation_id)
      let draft =
        board.Draft(
          board.Agent(id, "L2", sender.provider),
          to,
          kind,
          [
            #("text", text),
            #("revision", sender.revision),
            #("refs", json.to_string(json.array(refs, json.string))),
            #("operation_id", receipt.operation_id),
            #("authority", "observation-only"),
          ],
          board.no_semantics,
          board.Causality(None, []),
          Some(string.slice(trace, 0, 32)),
          None,
        )
      let sealed =
        board.seal(
          draft,
          "uos-session-sync",
          utc,
          receipt.sequence,
          string.slice(trace, 32, 16),
          prior,
        )
      // Re-seal's digest covers its generated ID; retain that valid envelope and
      // use operation_id only as the durable mailbox key and user-facing ACK ID.
      Ok(#(
        State(
          ..state,
          messages: dict.insert(state.messages, receipt.operation_id, sealed),
        ),
        Receipt(..receipt, message_id: receipt.operation_id),
      ))
    }
    Ack(id, message_id) -> {
      use _ <- result.try(active(state, id))
      use message <- result.try(
        dict.get(state.messages, message_id)
        |> result.replace_error("unknown message ID"),
      )
      use _ <- result.try(require(
        { message.to == id || message.to == "broadcast" }
          && message.from.id != id,
        "only an actual recipient may acknowledge this message",
      ))
      let recipients =
        dict.get(state.acknowledgements, message_id) |> result.unwrap([])
      let acks =
        dict.insert(
          state.acknowledgements,
          message_id,
          list.unique([id, ..recipients]),
        )
      Ok(#(
        State(..state, acknowledgements: acks),
        Receipt(..receipt, message_id: message_id),
      ))
    }
    Retire(id) -> {
      use current <- result.try(active(state, id))
      use _ <- result.try(require(
        !list.any(coord.live_leases(state.coordinator, now), fn(l) {
          l.holder == id
        }),
        "release or expire live resources before retiring",
      ))
      Ok(#(
        State(
          ..state,
          sessions: dict.insert(
            state.sessions,
            id,
            Session(..current, retired: True),
          ),
          coordinator: coord.retire(state.coordinator, id),
        ),
        receipt,
      ))
    }
  }
}

pub fn check(
  state: State,
  session: String,
  resource: String,
  epoch: Int,
  boot: String,
  now: Int,
) -> Result(Nil, String) {
  use _ <- result.try(fresh(state, session, boot, now))
  use lease <- result.try(
    dict.get(state.coordinator.leases, resource)
    |> result.replace_error("resource is not leased"),
  )
  require(
    state.boot_id == boot
      && lease.holder == session
      && lease.epoch == epoch
      && now < lease.expires_us,
    "lease fence is expired or belongs to another holder/epoch",
  )
}

pub fn inbox(state: State, session: String) -> List(#(String, board.Message)) {
  state.messages
  |> dict.to_list
  |> list.filter(fn(entry) {
    let #(id, m) = entry
    let acks = dict.get(state.acknowledgements, id) |> result.unwrap([])
    { m.to == session || m.to == "broadcast" }
    && m.from.id != session
    && !list.contains(acks, session)
  })
  |> list.sort(fn(a, b) { int.compare(a.1.lamport, b.1.lamport) })
}

fn command_json(command: Command) -> Json {
  let #(a, b, c, refs, epoch, ttl) = case command {
    Register(_, p, w, r, refs) -> #(p, w, r, refs, 0, 0)
    Heartbeat(_, r, refs) -> #(r, "", "", refs, 0, 0)
    Claim(_, resource, ttl) -> #(resource, "", "", [], 0, ttl)
    Renew(_, resource, epoch, ttl) -> #(resource, "", "", [], epoch, ttl)
    Release(_, resource, epoch) -> #(resource, "", "", [], epoch, 0)
    Send(_, to, kind, text, refs) -> #(
      to,
      board.kind_label(kind),
      text,
      refs,
      0,
      0,
    )
    Ack(_, id) -> #(id, "", "", [], 0, 0)
    Retire(_) -> #("", "", "", [], 0, 0)
  }
  json.object([
    #("operation", json.string(operation(command))),
    #("session", json.string(actor(command))),
    #("a", json.string(a)),
    #("b", json.string(b)),
    #("c", json.string(c)),
    #("refs", json.array(refs, json.string)),
    #("epoch", json.int(epoch)),
    #("ttl_us", json.int(ttl)),
  ])
}

fn command_decoder() -> decode.Decoder(Command) {
  use op <- decode.field("operation", decode.string)
  use s <- decode.field("session", decode.string)
  use a <- decode.field("a", decode.string)
  use b <- decode.field("b", decode.string)
  use c <- decode.field("c", decode.string)
  use refs <- decode.field("refs", decode.list(decode.string))
  use epoch <- decode.field("epoch", decode.int)
  use ttl <- decode.field("ttl_us", decode.int)
  case op {
    "register" -> decode.success(Register(s, a, b, c, refs))
    "heartbeat" -> decode.success(Heartbeat(s, a, refs))
    "claim" -> decode.success(Claim(s, a, ttl))
    "renew" -> decode.success(Renew(s, a, epoch, ttl))
    "release" -> decode.success(Release(s, a, epoch))
    "send" ->
      case board.kind_from_label(b) {
        Ok(kind) -> decode.success(Send(s, a, kind, c, refs))
        Error(_) ->
          decode.failure(Send(s, a, board.Report, c, refs), "known board kind")
      }
    "ack" -> decode.success(Ack(s, a))
    "retire" -> decode.success(Retire(s))
    _ -> decode.failure(Retire(s), "known session command")
  }
}

fn event_body(event: Event) -> Json {
  json.object([
    #("schema", json.string(genesis)),
    #("sequence", json.int(event.sequence)),
    #("operation_id", json.string(event.operation_id)),
    #("host_id", json.string(event.host_id)),
    #("boot_id", json.string(event.boot_id)),
    #("tick_us", json.int(event.tick_us)),
    #("utc_us", json.int(event.utc_us)),
    #("command", command_json(event.command)),
    #("previous_digest", json.string(event.previous_digest)),
  ])
}

pub fn event_string(event: Event) -> String {
  json.to_string(
    json.object([
      #("body", event_body(event)),
      #("digest", json.string(event.digest)),
    ]),
  )
}

/// The exact bytes `make_event`'s digest is computed over: the canonical
/// `body` sub-object, serialized. `session_store` persists this string
/// verbatim as `events.body_json` so a stored row can recompute and verify
/// its own digest, and so `session_store.replay` can rebuild a canonical
/// journal line as `{"body":<body_json>,"digest":"<digest>"}` without
/// re-encoding (and thereby risking byte drift from) the stored JSON.
pub fn body_json_string(event: Event) -> String {
  json.to_string(event_body(event))
}

/// The command sub-object exactly as embedded in `event_body`. Exposed so
/// `session_store` can persist `events.command_json` as the same bytes,
/// independent of the digest-bearing `body_json` column.
pub fn command_to_json(command: Command) -> Json {
  command_json(command)
}

/// Public wrapper over the private `event_decoder`, for callers (such as
/// `session_store`) that reconstruct a single canonical journal line from
/// stored columns and need to decode it back into an `Event` without
/// duplicating the schema-version and field-shape checks below.
pub fn decode_event(line: String) -> Result(Event, String) {
  json.parse(line, event_decoder())
  |> result.replace_error("malformed journal event; decode refused")
}

fn event_decoder() -> decode.Decoder(Event) {
  use schema <- decode.subfield(["body", "schema"], decode.string)
  use seq <- decode.subfield(["body", "sequence"], decode.int)
  use id <- decode.subfield(["body", "operation_id"], decode.string)
  use host <- decode.subfield(["body", "host_id"], decode.string)
  use boot <- decode.subfield(["body", "boot_id"], decode.string)
  use tick <- decode.subfield(["body", "tick_us"], decode.int)
  use utc <- decode.subfield(["body", "utc_us"], decode.int)
  use command <- decode.field("body", {
    use command <- decode.field("command", command_decoder())
    decode.success(command)
  })
  use previous <- decode.subfield(["body", "previous_digest"], decode.string)
  use digest <- decode.field("digest", decode.string)
  let event = Event(seq, id, host, boot, tick, utc, command, previous, digest)
  case schema == genesis {
    True -> decode.success(event)
    False -> decode.failure(event, "uos-session-sync/v1 schema")
  }
}

pub fn make_event(
  state: State,
  command: Command,
  id: String,
  host: String,
  boot: String,
  tick: Int,
  utc: Int,
) -> Event {
  let event =
    Event(
      state.sequence + 1,
      id,
      host,
      boot,
      tick,
      utc,
      command,
      state.digest,
      "",
    )
  Event(..event, digest: board.sha256_hex(json.to_string(event_body(event))))
}

pub fn replay(journal: String) -> Result(State, String) {
  let lines =
    string.split(journal, "\n")
    |> list.filter(fn(line) { string.trim(line) != "" })
  list.try_fold(lines, empty(), fn(state, line) {
    use event <- result.try(
      json.parse(line, event_decoder())
      |> result.replace_error("malformed journal event; replay refused"),
    )
    use _ <- result.try(require(
      event.sequence == state.sequence + 1
        && event.previous_digest == state.digest
        && event.digest == board.sha256_hex(json.to_string(event_body(event))),
      "journal sequence or digest mismatch; replay refused",
    ))
    use #(next, _, duplicate) <- result.try(apply(
      state,
      event.command,
      event.operation_id,
      event.host_id,
      event.boot_id,
      event.tick_us,
      event.utc_us,
    ))
    use _ <- result.try(require(
      !duplicate,
      "duplicate operation in immutable journal; replay refused",
    ))
    Ok(State(..next, digest: event.digest))
  })
}

/// Compact a journal after invalid events have been removed from it.
///
/// Incident 2026-09-07 20:00–21:21Z: a foreign writer OVERWROTE events 417–419
/// in place with commands this module has no constructor for, destroying a
/// lease claim and two reports and leaving the survivors unlinked. Removing the
/// invalid files leaves sequence gaps, which `resign` refuses by design, so a
/// separate mode is needed: `compact` rebuilds the SURVIVING events in file
/// order, assigning contiguous sequences and canonical digests from genesis.
///
/// Content is never invented and never edited. An event whose command the
/// coordinator would refuse in its new context — typically a `Release` whose
/// `Claim` was destroyed — is not forced through: it is dropped from the chain
/// and returned in the second element as `#(original_sequence, reason)` so the
/// caller can quarantine it as evidence. A journal with nothing to compact
/// returns the same events `resign` would.
pub fn compact(
  journal: String,
) -> Result(#(List(Event), List(#(Int, String))), String) {
  let lines =
    string.split(journal, "\n")
    |> list.filter(fn(line) { string.trim(line) != "" })
  use #(_, rebuilt, orphaned) <- result.try(
    list.try_fold(lines, #(empty(), [], []), fn(acc, line) {
      let #(state, out, orphans) = acc
      use stored <- result.try(
        json.parse(line, event_decoder())
        |> result.replace_error(
          "malformed journal event after stored sequence "
          <> int.to_string(state.sequence)
          <> "; compact refused",
        ),
      )
      let event =
        make_event(
          state,
          stored.command,
          stored.operation_id,
          stored.host_id,
          stored.boot_id,
          stored.tick_us,
          stored.utc_us,
        )
      case
        apply(
          state,
          stored.command,
          stored.operation_id,
          stored.host_id,
          stored.boot_id,
          stored.tick_us,
          stored.utc_us,
        )
      {
        Ok(#(next, _, False)) ->
          Ok(#(State(..next, digest: event.digest), [event, ..out], orphans))
        Ok(#(_, _, True)) ->
          Ok(
            #(state, out, [
              #(stored.sequence, "duplicate operation after compaction"),
              ..orphans
            ]),
          )
        Error(reason) ->
          Ok(#(state, out, [#(stored.sequence, reason), ..orphans]))
      }
    }),
  )
  Ok(#(list.reverse(rebuilt), list.reverse(orphaned)))
}

/// Re-sign a journal whose byte form and digests were produced by a foreign
/// writer (incident 2026-09-07 17:12:46Z: every event file was re-serialized
/// and re-signed outside this module, so `replay` refuses the chain from
/// event 1). The command content of every event is kept exactly; only the
/// canonical byte form, the digest and the `previous_digest` link are
/// recomputed from genesis with the same `make_event` this module uses to
/// append. Sequence numbers must still be contiguous and every command must
/// still be accepted by `apply`; anything else is refused with the offending
/// sequence, so a content change cannot hide behind a re-signing. The caller
/// writes the returned events to a NEW directory and keeps the foreign form
/// as evidence; this function never touches storage.
pub fn resign(journal: String) -> Result(List(Event), String) {
  let lines =
    string.split(journal, "\n")
    |> list.filter(fn(line) { string.trim(line) != "" })
  use #(_, rebuilt) <- result.try(
    list.try_fold(lines, #(empty(), []), fn(acc, line) {
      let #(state, out) = acc
      use stored <- result.try(
        json.parse(line, event_decoder())
        |> result.replace_error(
          "malformed journal event at sequence "
          <> int.to_string(state.sequence + 1)
          <> "; resign refused",
        ),
      )
      use _ <- result.try(require(
        stored.sequence == state.sequence + 1,
        "sequence gap at stored event "
          <> int.to_string(stored.sequence)
          <> " (expected "
          <> int.to_string(state.sequence + 1)
          <> "); resign refused",
      ))
      let event =
        make_event(
          state,
          stored.command,
          stored.operation_id,
          stored.host_id,
          stored.boot_id,
          stored.tick_us,
          stored.utc_us,
        )
      use #(next, _, duplicate) <- result.try(
        apply(
          state,
          stored.command,
          stored.operation_id,
          stored.host_id,
          stored.boot_id,
          stored.tick_us,
          stored.utc_us,
        )
        |> result.map_error(fn(e) {
          "event "
          <> int.to_string(stored.sequence)
          <> " refused by apply: "
          <> e
        }),
      )
      use _ <- result.try(require(
        !duplicate,
        "duplicate operation at event "
          <> int.to_string(stored.sequence)
          <> "; resign refused",
      ))
      Ok(#(State(..next, digest: event.digest), [event, ..out]))
    }),
  )
  Ok(list.reverse(rebuilt))
}

pub fn receipt_json(receipt: Receipt, duplicate: Bool) -> Json {
  json.object([
    #("ok", json.bool(True)),
    #("operation_id", json.string(receipt.operation_id)),
    #("operation", json.string(receipt.operation)),
    #("sequence", json.int(receipt.sequence)),
    #("duplicate", json.bool(duplicate)),
    #("epoch", json.int(receipt.epoch)),
    #("expires_boot_us", json.int(receipt.expires_us)),
    #("message_id", json.string(receipt.message_id)),
    #(
      "authority",
      json.string(
        "local-cooperative-lease; executor must recheck current fence",
      ),
    ),
  ])
}

@external(erlang, "session_sync_ffi", "transact")
fn storage_transaction(
  root: String,
  run: fn(String, String, String, Int, Int) -> Result(#(String, String), String),
) -> Result(String, String)

@external(erlang, "session_sync_ffi", "read")
pub fn read_journal(root: String) -> Result(String, String)

@external(erlang, "session_sync_ffi", "recover_lock")
pub fn recover_lock(root: String) -> Result(String, String)

/// Every accepted mutation is durable before the receipt is returned. No board
/// projection can overwrite or regenerate this immutable event authority.
pub fn execute(
  root: String,
  command: Command,
  operation_id: String,
) -> Result(String, String) {
  use command <- result.try(canonical_command(command))
  storage_transaction(root, fn(journal, host, boot, now, utc) {
    use state <- result.try(replay(journal))
    use #(_, receipt, duplicate) <- result.try(apply(
      state,
      command,
      operation_id,
      host,
      boot,
      now,
      utc,
    ))
    let line = case duplicate {
      True -> ""
      False ->
        event_string(make_event(
          state,
          command,
          operation_id,
          host,
          boot,
          now,
          utc,
        ))
    }
    Ok(#(line, json.to_string(receipt_json(receipt, duplicate))))
  })
}

pub fn observe(
  root: String,
  query: fn(State, String, Int) -> Result(Json, String),
) -> Result(String, String) {
  storage_transaction(root, fn(journal, host, boot, now, _utc) {
    use state <- result.try(replay(journal))
    use current <- result.try(rebase_clock(state, host, boot, now))
    use observation <- result.try(query(current, boot, now))
    Ok(#("", json.to_string(observation)))
  })
}

pub fn status_json(state: State, boot: String, now: Int) -> Json {
  let sessions =
    state.sessions
    |> dict.values
    |> list.sort(fn(a, b) { string.compare(a.id, b.id) })
  json.object([
    #("schema", json.string(genesis)),
    #("sequence", json.int(state.sequence)),
    #("journal_digest", json.string(state.digest)),
    #("authority", json.string("private-local-unix-account")),
    #(
      "sessions",
      json.array(sessions, fn(s) {
        let status = case s.retired {
          True -> "retired"
          False ->
            case fresh(state, s.id, boot, now) {
              Ok(_) -> "fresh-self-reported"
              Error(_) -> "stale"
            }
        }
        json.object([
          #("session", json.string(s.id)),
          #("provider", json.string(s.provider)),
          #("workspace", json.string(s.workspace)),
          #("revision", json.string(s.revision)),
          #("refs", json.array(s.refs, json.string)),
          #("status", json.string(status)),
          #("heartbeat_boot_us", json.int(s.heartbeat_us)),
          #("pending_messages", json.int(list.length(inbox(state, s.id)))),
        ])
      }),
    ),
    #(
      "leases",
      json.array(coord.live_leases(state.coordinator, now), fn(l) {
        json.object([
          #("resource", json.string(l.resource)),
          #("holder", json.string(l.holder)),
          #("epoch", json.int(l.epoch)),
          #("expires_boot_us", json.int(l.expires_us)),
        ])
      }),
    ),
    #(
      "epoch_counters",
      json.object(
        state.coordinator.epochs
        |> dict.to_list
        |> list.map(fn(e) { #(e.0, json.int(e.1)) }),
      ),
    ),
    #(
      "acknowledgements",
      json.object(
        state.acknowledgements
        |> dict.to_list
        |> list.map(fn(e) { #(e.0, json.array(e.1, json.string)) }),
      ),
    ),
  ])
}

pub fn inbox_json(state: State, session: String) -> Json {
  json.object([
    #("session", json.string(session)),
    #("authority", json.string("observation-only")),
    #(
      "messages",
      json.array(inbox(state, session), fn(entry) {
        json.object([
          #("message_id", json.string(entry.0)),
          #("envelope", board.to_json(entry.1)),
        ])
      }),
    ),
  ])
}
