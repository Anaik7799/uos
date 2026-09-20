import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import uos_swarm/board
import uos_swarm/session_sync as sync

pub const max_sources = 16

pub const max_records = 4096

pub const max_record_bytes = 65_536

pub const max_total_bytes = 16_777_216

pub type SourceKind {
  FileJournal
  SqliteLedger
}

pub type RawRecord {
  RawRecord(locator: String, raw: String)
}

pub type Source {
  Source(kind: SourceKind, locator: String, records: List(RawRecord))
}

pub type Verdict {
  Uncorroborated
  Rejected(reason: String)
  Blocked(reason: String)
}

pub type GradedRecord {
  GradedRecord(
    record: RawRecord,
    raw_digest: String,
    origin_digest: Option(String),
    verdict: Verdict,
  )
}

pub type AssessedSource {
  AssessedSource(source: Source, records: List(GradedRecord))
}

pub opaque type Candidate {
  Candidate(sources: List(AssessedSource))
}

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn valid_locator(locator: String) -> Bool {
  string.trim(locator) != ""
  && string.byte_size(locator) <= 1024
  && !string.contains(locator, "\u{0}")
  && !string.contains(locator, "\n")
  && !string.contains(locator, "\r")
}

fn validate_inputs(inputs: List(Source)) -> Result(Nil, String) {
  use _ <- result.try(require(
    !list.is_empty(inputs) && list.length(inputs) <= max_sources,
    "recovery requires between 1 and 16 sources",
  ))
  use _ <- result.try(
    list.try_fold(inputs, #(set.new(), 0, 0), fn(acc, source) {
      let #(seen_sources, count, bytes) = acc
      use _ <- result.try(require(
        valid_locator(source.locator)
          && !set.contains(seen_sources, source.locator),
        "invalid or duplicate source locator",
      ))
      use #(_, count, bytes) <- result.try(
        list.try_fold(
          source.records,
          #(set.new(), count, bytes),
          fn(acc, record) {
            let #(seen_records, count, bytes) = acc
            let size = string.byte_size(record.raw)
            use _ <- result.try(require(
              valid_locator(record.locator)
                && !set.contains(seen_records, record.locator),
              "invalid or duplicate record locator",
            ))
            use _ <- result.try(require(
              count < max_records
                && size <= max_record_bytes
                && bytes + size <= max_total_bytes,
              "recovery input exceeds record or byte limits",
            ))
            Ok(#(
              set.insert(seen_records, record.locator),
              count + 1,
              bytes + size,
            ))
          },
        ),
      )
      Ok(#(set.insert(seen_sources, source.locator), count, bytes))
    }),
  )
  Ok(Nil)
}

fn sqlite_event(raw: String) -> Result(sync.Event, String) {
  let decoder = {
    use sequence <- decode.field("sequence", decode.int)
    use operation_id <- decode.field("operation_id", decode.string)
    use host <- decode.field("host_id", decode.string)
    use boot <- decode.field("boot_id", decode.string)
    use tick <- decode.field("tick_us", decode.int)
    use utc <- decode.field("utc_us", decode.int)
    use operation <- decode.field("operation", decode.string)
    use actor <- decode.field("actor", decode.string)
    use command <- decode.field("command_json", decode.string)
    use body <- decode.field("body_json", decode.string)
    use previous <- decode.field("previous_digest", decode.string)
    use digest <- decode.field("digest", decode.string)
    use _inserted <- decode.field("inserted_utc_us", decode.int)
    decode.success(#(
      sequence,
      operation_id,
      host,
      boot,
      tick,
      utc,
      operation,
      actor,
      command,
      body,
      previous,
      digest,
    ))
  }
  use row <- result.try(
    json.parse(raw, decoder)
    |> result.replace_error("malformed SQLite evidence row"),
  )
  let #(
    sequence,
    operation_id,
    host,
    boot,
    tick,
    utc,
    operation,
    actor,
    command,
    body,
    previous,
    digest,
  ) = row
  use _ <- result.try(require(
    board.sha256_hex(body) == digest,
    "SQLite body digest mismatch",
  ))
  use event <- result.try(sync.decode_event(
    "{\"body\":"
    <> body
    <> ",\"digest\":"
    <> json.to_string(json.string(digest))
    <> "}",
  ))
  use _ <- result.try(require(
    event.sequence == sequence
      && event.operation_id == operation_id
      && event.host_id == host
      && event.boot_id == boot
      && event.tick_us == tick
      && event.utc_us == utc
      && sync.operation(event.command) == operation
      && sync.actor(event.command) == actor
      && json.to_string(sync.command_to_json(event.command)) == command
      && event.previous_digest == previous,
    "SQLite metadata does not match the canonical event",
  ))
  Ok(event)
}

fn decode_record(kind: SourceKind, raw: String) -> Result(sync.Event, String) {
  case kind {
    FileJournal -> sync.decode_event(raw)
    SqliteLedger -> sqlite_event(raw)
  }
}

fn advance(state: sync.State, event: sync.Event) -> Result(sync.State, String) {
  use _ <- result.try(require(
    event.sequence == state.sequence + 1
      && event.previous_digest == state.digest
      && event.digest == board.sha256_hex(sync.body_json_string(event)),
    "event sequence, chain or digest mismatch",
  ))
  use #(next, _, duplicate) <- result.try(sync.apply(
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
    "duplicate operation in immutable history",
  ))
  Ok(sync.State(..next, digest: event.digest))
}

fn origin_digest(raw: String) -> Option(String) {
  let decoder = {
    use digest <- decode.field("digest", decode.string)
    decode.success(digest)
  }
  case json.parse(raw, decoder) {
    Ok(digest) -> Some(digest)
    Error(_) -> None
  }
}

fn assess_source(source: Source) -> AssessedSource {
  let #(_, reversed) =
    list.fold(source.records, #(Ok(sync.empty()), []), fn(acc, record) {
      let #(state, records) = acc
      let #(next, verdict) = case state {
        Error(reason) -> #(state, Blocked(reason))
        Ok(current) -> {
          let outcome =
            decode_record(source.kind, record.raw)
            |> result.try(fn(event) { advance(current, event) })
          case outcome {
            Ok(_) -> #(outcome, Uncorroborated)
            Error(reason) -> #(outcome, Rejected(reason))
          }
        }
      }
      let graded =
        GradedRecord(
          record,
          board.sha256_hex(record.raw),
          origin_digest(record.raw),
          verdict,
        )
      #(next, [graded, ..records])
    })
  AssessedSource(source, list.reverse(reversed))
}

pub fn assess(inputs: List(Source)) -> Result(Candidate, String) {
  use _ <- result.try(validate_inputs(inputs))
  Ok(Candidate(list.map(inputs, assess_source)))
}

pub fn sources(candidate: Candidate) -> List(AssessedSource) {
  candidate.sources
}

fn verdict_json(verdict: Verdict) -> json.Json {
  let #(grade, reason) = case verdict {
    Uncorroborated -> #(
      "UNCORROBORATED",
      "valid replay is not authenticated provenance",
    )
    Rejected(reason) -> #("REJECTED", reason)
    Blocked(reason) -> #("BLOCKED_BY_PRIOR_FAILURE", reason)
  }
  json.object([#("grade", json.string(grade)), #("reason", json.string(reason))])
}

pub fn to_json(candidate: Candidate) -> json.Json {
  json.object([
    #("schema", json.string("uos.coordinator-recovery-evidence.v1")),
    #("authority", json.string("evidence_only")),
    #("admitted", json.bool(False)),
    #(
      "sources",
      json.array(candidate.sources, fn(assessed) {
        let kind = case assessed.source.kind {
          FileJournal -> "file_journal"
          SqliteLedger -> "sqlite_ledger"
        }
        json.object([
          #("kind", json.string(kind)),
          #("locator", json.string(assessed.source.locator)),
          #(
            "records",
            json.array(assessed.records, fn(graded) {
              json.object([
                #("locator", json.string(graded.record.locator)),
                #("raw", json.string(graded.record.raw)),
                #("raw_digest", json.string(graded.raw_digest)),
                #(
                  "origin_digest",
                  json.nullable(graded.origin_digest, json.string),
                ),
                #("assessment", verdict_json(graded.verdict)),
              ])
            }),
          ),
        ])
      }),
    ),
  ])
}

pub fn digest(candidate: Candidate) -> String {
  to_json(candidate) |> json.to_string |> board.sha256_hex
}
