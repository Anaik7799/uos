import gleam/int
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/board
import uos_swarm/session_recovery as recovery
import uos_swarm/session_recovery_store as staging
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

@external(erlang, "session_store_ffi", "open")
fn open_connection(path: String) -> Result(store.Conn, String)

@external(erlang, "session_store_ffi", "query")
fn query(
  connection: store.Conn,
  sql: String,
  params: List(store.Cell),
) -> Result(List(List(store.Cell)), String)

@external(erlang, "session_store_ffi", "close")
fn close_connection(connection: store.Conn) -> Result(Nil, String)

@external(erlang, "session_store_ffi", "create_exclusive")
fn create_exclusive(path: String) -> Result(Nil, String)

fn private_parent() -> String {
  let parent = "/tmp/uos-recovery-test-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory(parent)
  let assert Ok(_) = simplifile.set_permissions_octal(parent, 0o700)
  parent
}

fn events(count: Int) -> List(sync.Event) {
  let ordinals =
    list.repeat(Nil, count) |> list.index_map(fn(_, index) { index + 1 })
  let #(_, reversed) =
    list.fold(ordinals, #(sync.empty(), []), fn(acc, ordinal) {
      let #(state, previous) = acc
      let command = case ordinal {
        1 -> sync.Register("codex", "codex", "/uos", "revision-a", [])
        _ -> sync.Heartbeat("codex", "revision-a", [])
      }
      let event =
        sync.make_event(
          state,
          command,
          "operation-" <> int.to_string(ordinal),
          "host-a",
          "boot-a",
          ordinal * 1000,
          ordinal * 1000 + 1_000_000_000,
        )
      let assert Ok(next) =
        sync.replay(
          list.reverse([event, ..previous])
          |> list.map(sync.event_string)
          |> string.join("\n"),
        )
      #(next, [event, ..previous])
    })
  list.reverse(reversed)
}

fn source(raws: List(String)) -> recovery.Source {
  recovery.Source(
    recovery.FileJournal,
    "fixture:file-history",
    list.index_map(raws, fn(raw, index) {
      recovery.RawRecord("event:" <> int.to_string(index + 1), raw)
    }),
  )
}

fn sqlite_row(event: sync.Event) -> String {
  json.object([
    #("sequence", json.int(event.sequence)),
    #("operation_id", json.string(event.operation_id)),
    #("host_id", json.string(event.host_id)),
    #("boot_id", json.string(event.boot_id)),
    #("tick_us", json.int(event.tick_us)),
    #("utc_us", json.int(event.utc_us)),
    #("operation", json.string(sync.operation(event.command))),
    #("actor", json.string(sync.actor(event.command))),
    #(
      "command_json",
      json.string(json.to_string(sync.command_to_json(event.command))),
    ),
    #("body_json", json.string(sync.body_json_string(event))),
    #("previous_digest", json.string(event.previous_digest)),
    #("digest", json.string(event.digest)),
    #("inserted_utc_us", json.int(event.utc_us + 10)),
  ])
  |> json.to_string
}

pub fn valid_history_is_preserved_but_never_admitted_test() {
  let originals = events(3) |> list.map(sync.event_string)
  let input = source(originals)
  let assert Ok(candidate) = recovery.assess([input])
  let assert [assessed] = recovery.sources(candidate)
  assessed.source |> should.equal(input)
  list.map(assessed.records, fn(record) { record.record.raw })
  |> should.equal(originals)
  list.each(assessed.records, fn(record) {
    record.verdict |> should.equal(recovery.Uncorroborated)
    record.raw_digest |> should.equal(board.sha256_hex(record.record.raw))
  })
  let rendered = recovery.to_json(candidate) |> json.to_string
  string.contains(rendered, "\"admitted\":false") |> should.be_true
  string.contains(rendered, "\"authority\":\"evidence_only\"") |> should.be_true
  recovery.assess([input]) |> should.equal(Ok(candidate))
}

pub fn tamper_preserves_original_digest_and_blocks_the_suffix_test() {
  let assert [first, second, third] = events(3)
  let damaged = sync.Event(..second, digest: "untrusted-origin-digest")
  let assert Ok(candidate) =
    recovery.assess([
      source(list.map([first, damaged, third], sync.event_string)),
    ])
  let assert [assessed] = recovery.sources(candidate)
  let assert [good, bad, blocked] = assessed.records
  good.verdict |> should.equal(recovery.Uncorroborated)
  bad.origin_digest |> should.equal(Some("untrusted-origin-digest"))
  let assert recovery.Rejected(_) = bad.verdict
  let assert recovery.Blocked(_) = blocked.verdict
  blocked.record.raw |> should.equal(sync.event_string(third))
}

pub fn malformed_unknown_and_unregistered_commands_cannot_gain_authority_test() {
  let assert [registered] = events(1)
  let ghost =
    sync.make_event(
      sync.empty(),
      sync.Heartbeat("ghost", "rev", []),
      "ghost",
      "host-a",
      "boot-a",
      1,
      100,
    )
  [
    "not-json",
    string.replace(sync.event_string(registered), "register", "ratify_cycle"),
    sync.event_string(ghost),
  ]
  |> list.each(fn(raw) {
    let assert Ok(candidate) = recovery.assess([source([raw])])
    let assert [assessed] = recovery.sources(candidate)
    let assert [graded] = assessed.records
    let assert recovery.Rejected(_) = graded.verdict
    graded.record.raw |> should.equal(raw)
  })
}

pub fn sqlite_metadata_must_match_the_canonical_event_test() {
  let assert [event] = events(1)
  let raw = sqlite_row(event)
  let input =
    recovery.Source(recovery.SqliteLedger, "fixture:sqlite", [
      recovery.RawRecord("row:1", raw),
    ])
  let assert Ok(candidate) = recovery.assess([input])
  let assert [assessed] = recovery.sources(candidate)
  let assert [graded] = assessed.records
  graded.verdict |> should.equal(recovery.Uncorroborated)
  graded.origin_digest |> should.equal(Some(event.digest))
  [
    #("\"actor\":\"codex\"", "\"actor\":\"forged\""),
    #("\"sequence\":1", "\"sequence\":2"),
  ]
  |> list.each(fn(change) {
    let altered = string.replace(raw, change.0, change.1)
    let assert Ok(candidate) =
      recovery.assess([
        recovery.Source(..input, records: [recovery.RawRecord("row:1", altered)]),
      ])
    let assert [assessed] = recovery.sources(candidate)
    let assert [graded] = assessed.records
    let assert recovery.Rejected(_) = graded.verdict
  })
}

pub fn independent_sources_cannot_supply_each_others_registration_test() {
  let assert [first, second] = events(2)
  let left = source([sync.event_string(first)])
  let right =
    recovery.Source(
      ..source([sync.event_string(second)]),
      locator: "fixture:second",
    )
  let assert Ok(candidate) = recovery.assess([left, right])
  let assert [_, assessed] = recovery.sources(candidate)
  let assert [graded] = assessed.records
  let assert recovery.Rejected(_) = graded.verdict
}

pub fn admission_does_not_follow_empty_history_test() {
  let assert Ok(candidate) = recovery.assess([source([])])
  let assert [assessed] = recovery.sources(candidate)
  assessed.records |> should.equal([])
  recovery.to_json(candidate)
  |> json.to_string
  |> string.contains("\"admitted\":false")
  |> should.be_true
}

pub fn bounded_inputs_and_duplicate_locators_fail_closed_test() {
  let input = source(["{}"])
  recovery.assess([]) |> result.is_error |> should.be_true
  recovery.assess([input, input]) |> result.is_error |> should.be_true
  recovery.assess([recovery.Source(..input, locator: "")])
  |> result.is_error
  |> should.be_true
  recovery.assess([
    recovery.Source(..input, records: [
      recovery.RawRecord("same", "{}"),
      recovery.RawRecord("same", "{}"),
    ]),
  ])
  |> result.is_error
  |> should.be_true
  recovery.assess([source([string.repeat("x", recovery.max_record_bytes + 1)])])
  |> result.is_error
  |> should.be_true
  recovery.assess([source(list.repeat("{}", recovery.max_records + 1))])
  |> result.is_error
  |> should.be_true
}

pub fn streaming_assessment_matches_reference_replay_for_prefixes_test() {
  let canonical = events(20) |> list.map(sync.event_string)
  list.repeat(Nil, 20)
  |> list.index_map(fn(_, index) { index + 1 })
  |> list.each(fn(length) {
    let prefix = list.take(canonical, length)
    let variants = [prefix, ["{}", ..prefix], list.append(prefix, ["{}"])]
    list.each(variants, fn(raws) {
      let assert Ok(candidate) = recovery.assess([source(raws)])
      let assert [assessed] = recovery.sources(candidate)
      list.all(assessed.records, fn(graded) {
        graded.verdict == recovery.Uncorroborated
      })
      |> should.equal(sync.replay(string.join(raws, "\n")) |> result.is_ok)
    })
  })
}

pub fn limits_apply_across_sources_and_at_exact_byte_boundaries_test() {
  let largest = string.repeat("x", recovery.max_record_bytes)
  recovery.assess([source([largest])]) |> result.is_ok |> should.be_true
  let oversized_sources =
    list.repeat(Nil, recovery.max_sources + 1)
    |> list.index_map(fn(_, index) {
      recovery.Source(..source([]), locator: "source:" <> int.to_string(index))
    })
  recovery.assess(oversized_sources) |> result.is_error |> should.be_true
  let full = source(list.repeat(largest, 256))
  let extra = recovery.Source(..source(["x"]), locator: "source:extra")
  recovery.assess([full, extra]) |> result.is_error |> should.be_true
  let records = source(list.repeat("{}", recovery.max_records))
  recovery.assess([records, extra]) |> result.is_error |> should.be_true
}

pub fn correctly_hashed_duplicate_operation_is_rejected_test() {
  let assert [first] = events(1)
  let assert Ok(state) = sync.replay(sync.event_string(first))
  let duplicate =
    sync.make_event(
      state,
      first.command,
      first.operation_id,
      first.host_id,
      first.boot_id,
      first.tick_us + 1,
      first.utc_us + 1,
    )
  let assert Ok(candidate) =
    recovery.assess([
      source(list.map([first, duplicate], sync.event_string)),
    ])
  let assert [assessed] = recovery.sources(candidate)
  let assert [_, graded] = assessed.records
  graded.verdict
  |> should.equal(recovery.Rejected("duplicate operation in immutable history"))
}

pub fn raw_evidence_bytes_are_not_normalized_or_resigned_test() {
  let raw = "  {\"digest\":\"origin\",\"note\":\"Å — evidence\"}\n"
  let assert Ok(candidate) = recovery.assess([source([raw])])
  let assert [assessed] = recovery.sources(candidate)
  let assert [graded] = assessed.records
  graded.record.raw |> should.equal(raw)
  graded.origin_digest |> should.equal(Some("origin"))
  graded.raw_digest |> should.equal(board.sha256_hex(raw))
  let assert Ok(changed) = recovery.assess([source([string.trim(raw)])])
  { recovery.digest(candidate) == recovery.digest(changed) } |> should.be_false
}

pub fn private_sqlite_staging_round_trips_evidence_without_active_events_test() {
  let assert [registered] = events(1)
  let assert Ok(state) = sync.replay(sync.event_string(registered))
  let claim =
    sync.make_event(
      state,
      sync.Claim("codex", "integration/main", 60_000_000),
      "historical-claim",
      registered.host_id,
      registered.boot_id,
      registered.tick_us + 1,
      registered.utc_us + 1,
    )
  let assert Ok(candidate) =
    recovery.assess([
      source([
        sync.event_string(registered),
        sync.event_string(claim),
        "{}",
        "'; DROP TABLE events; -- evidence only",
      ]),
    ])
  let directory = private_parent() <> "/candidate"
  let assert Ok(receipt) = staging.stage(directory, candidate)
  let assert Ok(info) = simplifile.file_info(directory)
  simplifile.file_info_permissions_octal(info) |> should.equal(0o700)
  receipt.digest |> should.equal(recovery.digest(candidate))
  let assert Ok(connection) = open_connection(receipt.database)
  query(connection, "SELECT COUNT(*) FROM events", [])
  |> should.equal(Ok([[store.CellInt(0)]]))
  query(connection, "SELECT raw FROM quarantine", [])
  |> should.equal(
    Ok([[store.CellText(json.to_string(recovery.to_json(candidate)))]]),
  )
  let assert Ok(_) = close_connection(connection)
  let assert Ok(opened) = store.open(receipt.database)
  let assert Ok(state) = store.replay(opened)
  state |> should.equal(sync.empty())
  let assert Ok(_) = store.close(opened)
  staging.stage(directory, candidate) |> result.is_error |> should.be_true
}

pub fn staging_refuses_existing_directory_without_touching_its_files_test() {
  let directory = private_parent() <> "/existing"
  let assert Ok(_) = simplifile.create_directory(directory)
  let sentinel = directory <> "/coordinator.sqlite3"
  let assert Ok(_) = simplifile.write(sentinel, "original evidence")
  let assert Ok(candidate) = recovery.assess([source([])])
  staging.stage(directory, candidate) |> result.is_error |> should.be_true
  simplifile.read(sentinel) |> should.equal(Ok("original evidence"))
}

pub fn staging_enforces_private_parent_and_protected_ancestors_test() {
  let assert Ok(candidate) = recovery.assess([source([])])
  let parent = private_parent()
  let assert Ok(_) = simplifile.set_permissions_octal(parent, 0o755)
  staging.stage(parent <> "/candidate", candidate)
  |> result.is_error
  |> should.be_true
  simplifile.is_directory(parent <> "/candidate") |> should.equal(Ok(False))
  let nested = parent <> "/private"
  let assert Ok(_) = simplifile.create_directory(nested)
  let assert Ok(_) = simplifile.set_permissions_octal(nested, 0o700)
  let assert Ok(_) = simplifile.set_permissions_octal(parent, 0o777)
  staging.stage(nested <> "/candidate", candidate)
  |> result.is_error
  |> should.be_true
  let assert Ok(_) = simplifile.set_permissions_octal(parent, 0o700)
  let alias = parent <> "/alias"
  let assert Ok(_) = simplifile.create_symlink(nested, alias)
  staging.stage(alias <> "/candidate", candidate)
  |> result.is_error
  |> should.be_true
  staging.stage(parent <> "/../candidate", candidate)
  |> result.is_error
  |> should.be_true
}

pub fn exclusive_creation_refuses_prepopulated_and_symlink_paths_test() {
  let parent = private_parent()
  let target = parent <> "/existing"
  let assert Ok(_) = simplifile.write(target, "preserved")
  create_exclusive(target) |> result.is_error |> should.be_true
  let alias = parent <> "/alias"
  let assert Ok(_) = simplifile.create_symlink(target, alias)
  create_exclusive(alias) |> result.is_error |> should.be_true
  simplifile.read(target) |> should.equal(Ok("preserved"))
  let created = parent <> "/new"
  create_exclusive(created) |> should.equal(Ok(Nil))
  let assert Ok(info) = simplifile.file_info(created)
  simplifile.file_info_permissions_octal(info) |> should.equal(0o600)
}
