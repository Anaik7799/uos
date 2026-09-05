import birl
import filepath
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/regexp
import gleam/result
import gleam/string
import simplifile
import uos_planning_ledger/database
import uos_planning_ledger/digest
import uos_planning_ledger/prompt.{PartialOrTruncated, Prompt, VerbatimAvailable}
import uos_planning_ledger/safety
import uos_planning_ledger/writer_lock

const ledger_relative_directory = "docs/journal/uos-planning-ledger"

// These independent pins make changes to executable ledger sources explicit:
// editing a seed requires reviewing and updating its compiled-in expectation.
const expected_schema_sha256 = "710c9c24c69df4552a76678956b031d29b1a7b2f1ccd1e95a90d8f84e0f90a15"

const expected_inventory_seed_sha256 = "43b1dbd19bb0c0ef8b51507494ccb488ef229fa206af0e037338a671f204eac8"

const expected_core_seed_sha256 = "382970d00acfaf03f8d8a65bcefac9ec93f0a4ab76554631f388d90aa15801be"

pub type MaterializationSummary {
  MaterializationSummary(
    artifacts: Int,
    prompts: Int,
    mandate_inputs: Int,
    clauses: Int,
    directives: Int,
    source_maps: Int,
    capabilities: Int,
  )
}

pub type MaterializeError {
  InvalidDestination(reason: String)
  InvalidObservedAt(value: String)
  FilesystemFailure(
    operation: String,
    path: String,
    error: simplifile.FileError,
  )
  DatabaseFailure(operation: String, error: database.DatabaseError)
  PreflightFailure(path: String, error: safety.PreflightError)
  WriterLockFailure(
    operation: String,
    path: String,
    error: writer_lock.LockError,
  )
  InvariantFailure(name: String, expected: String, actual: String)
  BodyAndRollbackFailure(
    body: MaterializeError,
    rollback: database.DatabaseError,
  )
  BodyAndCloseFailure(body: MaterializeError, close: database.DatabaseError)
  BodyAndLockReleaseFailure(
    body: MaterializeError,
    release: writer_lock.LockError,
  )
  LockReleaseFailureAfterPublish(
    summary: MaterializationSummary,
    path: String,
    error: writer_lock.LockError,
  )
}

type ArtifactSpec {
  ArtifactSpec(
    id: String,
    path: String,
    role: String,
    media_type: String,
    truth_status: String,
  )
}

type LoadedArtifact {
  LoadedArtifact(spec: ArtifactSpec, bytes: BitArray)
}

type ExpectedCounts {
  ExpectedCounts(prompts: Int, current_prompts: Int)
}

type LoadedSql {
  LoadedSql(text: String, sha256: String)
}

type BuildInputs {
  BuildInputs(
    schema: LoadedSql,
    inventory_seed: LoadedSql,
    core_seed: LoadedSql,
    artifacts: List(LoadedArtifact),
    source_metadata: List(#(String, String)),
  )
}

/// Reconstruct, verify, close, and publish the planning database. The candidate
/// is deliberately adjacent to the destination so publication is a
/// same-filesystem rename. Parent-directory fsync is not provided by
/// `simplifile`, so this is not claimed as fully crash-durable publication.
pub fn materialize(
  workspace_root workspace_root: String,
  destination destination: String,
  observed_at observed_at: String,
) -> Result(MaterializationSummary, MaterializeError) {
  use _ <- result.try(validate_observed_at(observed_at))
  use _ <- result.try(validate_destination(destination))
  use _ <- result.try(validate_source_intake())
  let lock = destination <> ".materialize.lock"
  use held_lock <- result.try(acquire_lock(lock, observed_at))
  let outcome =
    materialize_while_locked(workspace_root, destination, observed_at)
  let released = writer_lock.release(held_lock)
  case outcome, released {
    Ok(summary), Ok(Nil) -> Ok(summary)
    Error(body), Ok(Nil) -> Error(body)
    Error(body), Error(release) ->
      Error(BodyAndLockReleaseFailure(body: body, release: release))
    Ok(summary), Error(error) ->
      Error(LockReleaseFailureAfterPublish(
        summary: summary,
        path: lock,
        error: error,
      ))
  }
}

/// Deliberate current-corpus interlock, not a secret classifier or a generic
/// admission engine. Both locators remain mandatory historical inputs in
/// artifact_specs(), so no corpus rebuild is admissible yet. Do not replace
/// this hold with a CLI bypass. A reviewed sanitized intake manifest, the
/// original incident dispositions, and publication-safety tests must precede
/// any relaxation. This runs before locking, source reads or hashing.
fn validate_source_intake() -> Result(Nil, MaterializeError) {
  Error(InvariantFailure(
    name: "source intake admission",
    expected: "all fixed-corpus artifacts classified admissible before reading",
    actual: "WITHHELD_PENDING_CLASSIFICATION: INC-UOS-REVIEW-PREFLIGHT-001, INC-UOS-REVIEW-PREFLIGHT-002",
  ))
}

fn validate_observed_at(value: String) -> Result(Nil, MaterializeError) {
  let assert Ok(second_precision_with_offset) =
    regexp.from_string(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:Z|[+-][0-9]{2}:[0-9]{2})$",
    )
  case
    regexp.check(with: second_precision_with_offset, content: value),
    birl.parse(value)
  {
    True, Ok(_) -> Ok(Nil)
    _, _ -> Error(InvalidObservedAt(value))
  }
}

fn materialize_while_locked(
  workspace_root: String,
  destination: String,
  observed_at: String,
) -> Result(MaterializationSummary, MaterializeError) {
  use inputs <- result.try(load_build_inputs(workspace_root))
  let candidate = destination <> ".next.sqlite3"
  use _ <- result.try(prepare_candidate(candidate))
  use db <- result.try(open_database(candidate, "open candidate"))

  let built = build_database(db, observed_at, inputs)
  let closed = database.close(db)

  case built, closed {
    Error(body), Error(close) -> {
      let _ = remove_if_present(candidate)
      Error(BodyAndCloseFailure(body: body, close: close))
    }
    Error(body), Ok(Nil) -> {
      let _ = remove_if_present(candidate)
      Error(body)
    }
    Ok(_), Error(close) -> {
      let _ = remove_if_present(candidate)
      Error(DatabaseFailure(operation: "close candidate", error: close))
    }
    Ok(expected), Ok(Nil) ->
      case verify_closed_candidate(candidate, workspace_root, expected) {
        Error(error) -> {
          let _ = remove_if_present(candidate)
          Error(error)
        }
        Ok(summary) -> publish(candidate, destination, summary)
      }
  }
}

fn acquire_lock(
  path: String,
  observed_at: String,
) -> Result(writer_lock.Lock, MaterializeError) {
  writer_lock.acquire(
    at: path,
    owner_context: "uos-planning-ledger@" <> observed_at,
  )
  |> result.map_error(fn(error) {
    WriterLockFailure(
      operation: "acquire exclusive writer lock",
      path: path,
      error: error,
    )
  })
}

fn prepare_candidate(path: String) -> Result(Nil, MaterializeError) {
  use _ <- result.try(remove_if_present(path))
  use _ <- result.try(
    simplifile.create_file(at: path)
    |> result.map_error(fn(error) {
      FilesystemFailure(
        operation: "create candidate exclusively",
        path: path,
        error: error,
      )
    }),
  )
  case simplifile.set_permissions_octal(for_file_at: path, to: 0o600) {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let _ = remove_if_present(path)
      Error(FilesystemFailure(
        operation: "set candidate permissions before ingestion",
        path: path,
        error: error,
      ))
    }
  }
}

fn build_database(
  db: database.Database,
  observed_at: String,
  inputs: BuildInputs,
) -> Result(ExpectedCounts, MaterializeError) {
  use _ <- result.try(configure_connection(db, "configure candidate"))
  use _ <- result.try(db_step(
    database.exec_static(db, inputs.schema.text),
    "apply schema",
  ))

  use expected <- result.try(
    in_transaction(db, "dynamic source transaction", fn() {
      use _ <- result.try(
        list.try_each(inputs.artifacts, fn(artifact) {
          insert_artifact(db, observed_at, artifact)
        }),
      )
      use historical_archive <- result.try(loaded_artifact_text(
        inputs.artifacts,
        "ART-PROMPT-LEGACY",
      ))
      use historical <- result.try(insert_prompt_archive(
        db,
        historical_archive,
        "ART-PROMPT-LEGACY",
        "HIST",
        observed_at,
      ))
      use current_archive <- result.try(loaded_artifact_text(
        inputs.artifacts,
        "ART-JOURNAL-CURRENT",
      ))
      use current <- result.try(insert_prompt_archive(
        db,
        current_archive,
        "ART-JOURNAL-CURRENT",
        "CURR",
        observed_at,
      ))
      use _ <- result.try(db_step(
        database.exec_static(db, inputs.core_seed.text),
        "apply core seed",
      ))
      Ok(ExpectedCounts(prompts: historical + current, current_prompts: current))
    }),
  )

  use _ <- result.try(db_step(
    database.exec_static(db, inputs.inventory_seed.text),
    "apply policy and capability inventory",
  ))
  use _ <- result.try(insert_metadata(db, observed_at, inputs.source_metadata))
  Ok(expected)
}

fn in_transaction(
  db: database.Database,
  name: String,
  body: fn() -> Result(a, MaterializeError),
) -> Result(a, MaterializeError) {
  use _ <- result.try(db_step(
    database.exec_static(db, "BEGIN IMMEDIATE;"),
    name <> " begin",
  ))
  case body() {
    Ok(value) -> {
      use _ <- result.try(db_step(
        database.exec_static(db, "COMMIT;"),
        name <> " commit",
      ))
      Ok(value)
    }
    Error(error) ->
      case database.exec_static(db, "ROLLBACK;") {
        Ok(Nil) -> Error(error)
        Error(rollback) ->
          Error(BodyAndRollbackFailure(body: error, rollback: rollback))
      }
  }
}

fn insert_artifact(
  db: database.Database,
  observed_at: String,
  artifact: LoadedArtifact,
) -> Result(Nil, MaterializeError) {
  let LoadedArtifact(spec, bytes) = artifact
  db_step(
    database.execute(
      db,
      "INSERT INTO artifact_snapshot (artifact_id,path,role,media_type,content,sha256,byte_count,observed_at,truth_status) VALUES (?,?,?,?,?,?,?,?,?);",
      [
        database.text(spec.id),
        database.text(spec.path),
        database.text(spec.role),
        database.text(spec.media_type),
        database.blob(bytes),
        database.text(digest.sha256_hex(bytes)),
        database.int(bit_array.byte_size(bytes)),
        database.text(observed_at),
        database.text(spec.truth_status),
      ],
    ),
    "insert artifact " <> spec.id,
  )
}

fn insert_prompt_archive(
  db: database.Database,
  archive: String,
  artifact_id: String,
  id_prefix: String,
  observed_at: String,
) -> Result(Int, MaterializeError) {
  let records = prompt.extract(archive)
  use _ <- result.try(
    records
    |> list.index_map(fn(record, index) { #(record, index + 1) })
    |> list.try_each(fn(record_and_ordinal) {
      let #(Prompt(label, text, availability), ordinal) = record_and_ordinal
      let prompt_id =
        id_prefix
        <> "-"
        <> string.pad_start(int.to_string(ordinal), to: 3, with: "0")
      let availability_text = case availability {
        VerbatimAvailable -> "available_in_source_snapshot"
        PartialOrTruncated -> "partial_or_truncated"
      }
      let integrity_note = case availability {
        VerbatimAvailable ->
          "Complete normalized extraction: record-edge whitespace follows the versioned grammar; only the referenced artifact_snapshot BLOB preserves every source byte and is byte-verbatim authority."
        PartialOrTruncated ->
          "Source explicitly describes this reconstructed record as partial or truncated."
      }
      db_step(
        database.execute(
          db,
          "INSERT INTO prompt_event (prompt_id,ordinal,label,source_artifact_id,source_anchor,verbatim_text,availability,integrity_note,sha256,observed_at) VALUES (?,?,?,?,?,?,?,?,?,?);",
          [
            database.text(prompt_id),
            database.int(ordinal),
            database.text(label),
            database.text(artifact_id),
            database.text(label),
            database.text(text),
            database.text(availability_text),
            database.text(integrity_note),
            database.text(
              text
              |> bit_array.from_string
              |> digest.sha256_hex,
            ),
            database.text(observed_at),
          ],
        ),
        "insert prompt " <> prompt_id,
      )
    }),
  )
  Ok(list.length(records))
}

fn insert_metadata(
  db: database.Database,
  observed_at: String,
  source_metadata: List(#(String, String)),
) -> Result(Nil, MaterializeError) {
  use sqlite_version <- result.try(db_step(
    database.scalar_text(db, "SELECT sqlite_version();"),
    "read SQLite version",
  ))
  use sqlite_source_id <- result.try(db_step(
    database.scalar_text(db, "SELECT sqlite_source_id();"),
    "read SQLite source id",
  ))
  let compile_decoder = {
    use option <- decode.field(0, decode.string)
    decode.success(option)
  }
  use compile_options <- result.try(db_step(
    database.query(db, "PRAGMA compile_options;", [], compile_decoder),
    "read SQLite compile options",
  ))
  let metadata = [
    #("materialized_at", observed_at),
    #(
      "materialization_time_assurance",
      "Local wall-clock capture time only; NTP and host-offset assurance remain UNKNOWN.",
    ),
    #("materializer_language", "Gleam"),
    #("sqlite_api", "sqlight@1.2.0/esqlite@0.9.0"),
    #("sqlite_runtime_version", sqlite_version),
    #("sqlite_source_id", sqlite_source_id),
    #("sqlite_compile_options", string.join(compile_options, ";")),
    #(
      "publication_assurance",
      "Verified closed candidate and same-directory rename; parent-directory fsync is unavailable and no crash-durability claim is made.",
    ),
    #(
      "runtime_authority",
      "Pre-UOS planning-only sqlight/esqlite NIF; admitted UOS runtime authority remains target-absent and requires an isolated supervised boundary.",
    ),
    #(
      "prompt_extraction_semantics",
      "Prompt rows are normalized records under the versioned parser grammar; artifact_snapshot BLOBs are the byte-exact source authority.",
    ),
    ..source_metadata
  ]

  in_transaction(db, "metadata transaction", fn() {
    list.try_each(metadata, fn(entry) {
      let #(key, value) = entry
      db_step(
        database.execute(
          db,
          "INSERT INTO ledger_meta (key,value) VALUES (?,?);",
          [database.text(key), database.text(value)],
        ),
        "insert metadata " <> key,
      )
    })
  })
}

fn load_build_inputs(
  workspace_root: String,
) -> Result(BuildInputs, MaterializeError) {
  use schema <- result.try(load_ledger_sql(workspace_root, "001_schema.sql"))
  use inventory_seed <- result.try(load_ledger_sql(
    workspace_root,
    "002_policy_capability_inventory.sql",
  ))
  use core_seed <- result.try(load_ledger_sql(
    workspace_root,
    "003_core_seed.sql",
  ))
  use _ <- result.try(require_digest(
    "schema source pin",
    expected_schema_sha256,
    schema.sha256,
  ))
  use _ <- result.try(require_digest(
    "inventory seed pin",
    expected_inventory_seed_sha256,
    inventory_seed.sha256,
  ))
  use _ <- result.try(require_digest(
    "core seed pin",
    expected_core_seed_sha256,
    core_seed.sha256,
  ))
  use artifacts <- result.try(
    artifact_specs()
    |> list.try_map(fn(spec) {
      let path = filepath.join(workspace_root, spec.path)
      use bytes <- result.try(read_bits(path))
      use _ <- result.try(preflight(path, bytes))
      Ok(LoadedArtifact(spec: spec, bytes: bytes))
    }),
  )
  use other_metadata <- result.try(
    [
      #("materializer_manifest_sha256", "manifest.toml"),
      #("package_spec_sha256", "gleam.toml"),
      #("main_source_sha256", "src/uos_planning_ledger.gleam"),
      #(
        "materializer_source_sha256",
        "src/uos_planning_ledger/materializer.gleam",
      ),
      #("database_api_source_sha256", "src/uos_planning_ledger/database.gleam"),
      #("digest_source_sha256", "src/uos_planning_ledger/digest.gleam"),
      #("prompt_parser_source_sha256", "src/uos_planning_ledger/prompt.gleam"),
      #("safety_source_sha256", "src/uos_planning_ledger/safety.gleam"),
      #(
        "writer_lock_source_sha256",
        "src/uos_planning_ledger/writer_lock.gleam",
      ),
    ]
    |> list.try_map(fn(entry) {
      let #(key, relative_path) = entry
      let path =
        filepath.join(
          filepath.join(workspace_root, ledger_relative_directory),
          relative_path,
        )
      use bytes <- result.try(read_bits(path))
      use _ <- result.try(preflight(path, bytes))
      Ok(#(key, digest.sha256_hex(bytes)))
    }),
  )
  Ok(
    BuildInputs(
      schema: schema,
      inventory_seed: inventory_seed,
      core_seed: core_seed,
      artifacts: artifacts,
      source_metadata: [
        #("schema_source_sha256", schema.sha256),
        #("inventory_seed_sha256", inventory_seed.sha256),
        #("core_seed_sha256", core_seed.sha256),
        ..other_metadata
      ],
    ),
  )
}

fn load_ledger_sql(
  workspace_root: String,
  name: String,
) -> Result(LoadedSql, MaterializeError) {
  let path =
    filepath.join(
      filepath.join(workspace_root, ledger_relative_directory),
      name,
    )
  use bytes <- result.try(read_bits(path))
  use _ <- result.try(preflight(path, bytes))
  case bit_array.to_string(bytes) {
    Ok(text) -> Ok(LoadedSql(text: text, sha256: digest.sha256_hex(bytes)))
    Error(Nil) ->
      Error(InvariantFailure(
        name: "UTF-8 SQL source " <> path,
        expected: "valid UTF-8",
        actual: "invalid byte sequence",
      ))
  }
}

fn verify_closed_candidate(
  candidate: String,
  workspace_root: String,
  expected: ExpectedCounts,
) -> Result(MaterializationSummary, MaterializeError) {
  use db <- result.try(db_step(
    database.open_read_only(candidate),
    "reopen candidate read-only",
  ))
  let verified = case configure_connection(db, "configure verification") {
    Error(error) -> Error(error)
    Ok(Nil) -> verify_database(db, workspace_root, expected)
  }
  let closed = database.close(db)
  case verified, closed {
    Error(body), Error(close) ->
      Error(BodyAndCloseFailure(body: body, close: close))
    Error(body), Ok(Nil) -> Error(body)
    Ok(_), Error(close) ->
      Error(DatabaseFailure(operation: "close verified candidate", error: close))
    Ok(summary), Ok(Nil) -> Ok(summary)
  }
}

fn configure_connection(
  db: database.Database,
  operation: String,
) -> Result(Nil, MaterializeError) {
  db_step(
    database.exec_static(
      db,
      "PRAGMA foreign_keys = ON; PRAGMA trusted_schema = OFF; PRAGMA busy_timeout = 5000;",
    ),
    operation,
  )
}

fn verify_database(
  db: database.Database,
  workspace_root: String,
  expected: ExpectedCounts,
) -> Result(MaterializationSummary, MaterializeError) {
  use _ <- result.try(check_int(db, "foreign_keys", "PRAGMA foreign_keys;", 1))
  use _ <- result.try(check_int(
    db,
    "trusted_schema",
    "PRAGMA trusted_schema;",
    0,
  ))
  use _ <- result.try(check_int(
    db,
    "busy_timeout",
    "PRAGMA busy_timeout;",
    5000,
  ))
  use _ <- result.try(check_int(db, "synchronous", "PRAGMA synchronous;", 2))
  use _ <- result.try(check_int(db, "user_version", "PRAGMA user_version;", 7))
  use _ <- result.try(check_text(
    db,
    "journal_mode",
    "PRAGMA journal_mode;",
    "delete",
  ))
  use _ <- result.try(check_int(
    db,
    "schema table count",
    "SELECT count(*) FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%';",
    28,
  ))
  use _ <- result.try(check_int(
    db,
    "schema trigger count",
    "SELECT count(*) FROM sqlite_schema WHERE type='trigger';",
    45,
  ))
  use _ <- result.try(check_int(
    db,
    "schema view count",
    "SELECT count(*) FROM sqlite_schema WHERE type='view';",
    11,
  ))

  let dynamic_decoder = decode.dynamic
  use foreign_key_rows <- result.try(db_step(
    database.query(db, "PRAGMA foreign_key_check;", [], dynamic_decoder),
    "foreign-key check",
  ))
  use _ <- result.try(case foreign_key_rows {
    [] -> Ok(Nil)
    rows ->
      Error(InvariantFailure(
        name: "foreign-key check",
        expected: "0 findings",
        actual: int.to_string(list.length(rows)) <> " findings",
      ))
  })
  use _ <- result.try(check_text(
    db,
    "integrity check",
    "PRAGMA integrity_check;",
    "ok",
  ))

  use summary <- result.try(read_summary(db))
  use _ <- result.try(validate_summary(summary, expected))
  use _ <- result.try(validate_seed_gates(db, expected))
  use _ <- result.try(validate_planning_only(db))
  use _ <- result.try(validate_prompt_hashes(db))
  use _ <- result.try(
    list.try_each(artifact_specs(), fn(spec) {
      validate_artifact_snapshot(db, workspace_root, spec)
    }),
  )
  Ok(summary)
}

/// Defensive read-only predicate over a planning snapshot. This only denies
/// unsupported positive states; it cannot issue a positive UOS admission.
/// Schema checks protect normal inserts, while this gate also catches data
/// inserted by a connection which disabled CHECK enforcement.
pub fn validate_planning_only(
  db: database.Database,
) -> Result(Nil, MaterializeError) {
  [
    #(
      "planning operational credit",
      "SELECT count(*) FROM mechanism_audit WHERE operational_credit != 0;",
    ),
    #(
      "planning mandate admission",
      "SELECT count(*) FROM mandate_revision WHERE status='admitted';",
    ),
    #(
      "planning work completion",
      "SELECT count(*) FROM work_item WHERE status='complete';",
    ),
    #(
      "planning directive verification",
      "SELECT count(*) FROM directive_superset WHERE current_status IN ('implemented','verified','admitted');",
    ),
    #(
      "planning capability runtime",
      "SELECT count(*) FROM capability_inventory WHERE executor_state='implemented_observed';",
    ),
    #(
      "planning formal credit",
      "SELECT count(*) FROM formal_tool_authority WHERE runtime_effect_authority != 0 OR evidence_state IN ('fresh_passing','verified','admitted');",
    ),
    #(
      "planning clause status",
      "SELECT count(*) FROM formal_clause WHERE current_status NOT IN ('planned','implemented_planning_only','historical_evidence','blocked');",
    ),
    #(
      "planning ontology admission",
      "SELECT count(*) FROM classification_scheme WHERE status='admitted';",
    ),
    #(
      "planning timestamp verification",
      "SELECT count(*) FROM timestamp_namespace WHERE current_status='verified';",
    ),
    #(
      "planning prompt incorporation",
      "SELECT count(*) FROM mandate_prompt_lineage WHERE incorporation_status != 'captured_unreviewed';",
    ),
  ]
  |> list.try_each(fn(check) {
    let #(name, sql) = check
    check_int(db, name, sql, 0)
  })
}

fn read_summary(
  db: database.Database,
) -> Result(MaterializationSummary, MaterializeError) {
  use artifacts <- result.try(table_count(db, "artifact_snapshot"))
  use prompts <- result.try(table_count(db, "prompt_event"))
  use mandate_inputs <- result.try(table_count(db, "mandate_prompt_lineage"))
  use clauses <- result.try(table_count(db, "formal_clause"))
  use directives <- result.try(table_count(db, "directive_superset"))
  use source_maps <- result.try(table_count(db, "directive_source_mapping"))
  use capabilities <- result.try(table_count(db, "capability_inventory"))
  Ok(MaterializationSummary(
    artifacts: artifacts,
    prompts: prompts,
    mandate_inputs: mandate_inputs,
    clauses: clauses,
    directives: directives,
    source_maps: source_maps,
    capabilities: capabilities,
  ))
}

fn validate_summary(
  summary: MaterializationSummary,
  expected: ExpectedCounts,
) -> Result(Nil, MaterializeError) {
  list.try_each(
    [
      #("artifacts", list.length(artifact_specs()), summary.artifacts),
      #("prompts", expected.prompts, summary.prompts),
      #("mandate inputs", expected.current_prompts, summary.mandate_inputs),
      #("formal clauses", 12, summary.clauses),
      #("directives", 38, summary.directives),
      #("source maps", 141, summary.source_maps),
      #("capabilities", 473, summary.capabilities),
    ],
    fn(entry) {
      let #(name, wanted, actual) = entry
      require_int(name, wanted, actual)
    },
  )
}

fn validate_seed_gates(
  db: database.Database,
  expected: ExpectedCounts,
) -> Result(Nil, MaterializeError) {
  let message_decoder = {
    use body <- decode.field(0, decode.string)
    use stored_digest <- decode.field(1, decode.string)
    decode.success(#(body, stored_digest))
  }
  use message <- result.try(db_step(
    database.query(
      db,
      "SELECT body,body_sha256 FROM agent_message WHERE message_id='MSG-UOS-001';",
      [],
      message_decoder,
    ),
    "read seed message",
  ))
  use _ <- result.try(case message {
    [#(body, stored)] ->
      case digest.sha256_hex(bit_array.from_string(body)) == stored {
        True -> Ok(Nil)
        False ->
          Error(InvariantFailure(
            name: "seed message digest",
            expected: stored,
            actual: digest.sha256_hex(bit_array.from_string(body)),
          ))
      }
    _ ->
      Error(InvariantFailure(
        name: "seed message digest",
        expected: "one matching SHA-256",
        actual: "missing or mismatched",
      ))
  })

  use _ <- result.try(check_int(
    db,
    "claimed work has lease",
    "SELECT count(*) FROM claimed_work_without_open_claim;",
    0,
  ))
  use _ <- result.try(check_int(
    db,
    "draft mandate anchored to first captured cumulative input",
    "SELECT count(*) FROM mandate_revision WHERE mandate_id='UOS-MANDATE-v1' AND status='draft' AND source_prompt_id=(SELECT prompt_id FROM prompt_event WHERE prompt_id GLOB 'CURR-*' ORDER BY ordinal ASC LIMIT 1);",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "mandate lineage",
    "SELECT count(*) FROM mandate_prompt_lineage WHERE mandate_id='UOS-MANDATE-v1';",
    expected.current_prompts,
  ))
  use _ <- result.try(check_int(
    db,
    "terminal lineage role",
    "SELECT count(*) FROM mandate_prompt_lineage WHERE mandate_id='UOS-MANDATE-v1' AND lineage_role='terminal';",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "SQLite API clause",
    "SELECT count(*) FROM formal_clause WHERE mandate_id='UOS-MANDATE-v1' AND clause_id='CLAUSE-SQLITE-API';",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "DMC/TCM Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-DMC-TCM-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Formal Verification Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-FV-MASTER-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Formal Verification Tome evidence remains scope-correct",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-FV-MASTER-TOME' AND blocking_gap LIKE '%Traceability.lean%' AND evidence LIKE '%Rocq 9.1.1%';",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Wiki/ZK/KM Analysis remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-WIKI-ZK-KM-ANALYSIS' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Wiki/ZK/KM Master Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-WIKI-ZK-KM-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Algebraic Atlas Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-ALGEBRAIC-ATLAS-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Sa-Plan C3I Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-SA-PLAN-C3I-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Forecasting Engine Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-FORECASTING-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "Fractal Multidimensional Unification Tome remains non-authoritative",
    "SELECT count(*) FROM mechanism_audit WHERE mechanism_id='MECH-FRACTAL-UNIFICATION-TOME' AND observed_status='documented_only' AND authority_class='A0_reference' AND operational_credit=0;",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "policy identity denominator",
    "SELECT count(*) FROM source_policy_identity;",
    44,
  ))
  use _ <- result.try(check_int(
    db,
    "supplemental provider policy denominator",
    "SELECT count(*) FROM source_policy_identity WHERE identity_kind='supplemental_provider_input';",
    4,
  ))
  use _ <- result.try(check_int(
    db,
    "scoped policy denominator",
    "SELECT count(*) FROM source_policy_identity WHERE identity_kind='scoped_policy';",
    28,
  ))
  use _ <- result.try(check_int(
    db,
    "C3I provider agent placements",
    "SELECT observed_count FROM capability_inventory_summary WHERE inventory_summary_id='CAPSUM-C3I-AGENT-PLACEMENTS-ALL';",
    169,
  ))
  use _ <- result.try(check_int(
    db,
    "C3I provider agent body variants",
    "SELECT observed_count FROM capability_inventory_summary WHERE inventory_summary_id='CAPSUM-C3I-AGENT-BODY-VARIANTS';",
    111,
  ))
  use _ <- result.try(check_int(
    db,
    "C3I divergent agent names",
    "SELECT observed_count FROM capability_inventory_summary WHERE inventory_summary_id='CAPSUM-C3I-AGENT-DIVERGENT-NAMES';",
    46,
  ))
  use _ <- result.try(check_int(
    db,
    "DMC/TCM Tome snapshot truth boundary",
    "SELECT count(*) FROM artifact_snapshot WHERE artifact_id='ART-MASTER-TOME-DMC-TCM' AND role='receipt' AND truth_status='historical_source';",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "multidimensional fractal proposal remains review evidence",
    "SELECT count(*) FROM artifact_snapshot WHERE artifact_id='ART-AUDIT-FRACTAL-VECTORS' AND role='review' AND truth_status='review_evidence';",
    1,
  ))
  use _ <- result.try(check_int(
    db,
    "ZigVM database MCP partition",
    "SELECT count(*) FROM capability_inventory WHERE capability_id LIKE 'CAP-ZIGVM-MCP-%' AND capability_id NOT LIKE 'CAP-ZIGVM-MCP-STALE-%' AND source_path LIKE 'harness/mcp_server.ml#%';",
    11,
  ))
  use _ <- result.try(check_int(
    db,
    "ZigVM harness MCP partition",
    "SELECT count(*) FROM capability_inventory WHERE capability_id LIKE 'CAP-ZIGVM-MCP-%' AND capability_id NOT LIKE 'CAP-ZIGVM-MCP-STALE-%' AND source_path LIKE 'harness/zigvm_harness.ml#%';",
    26,
  ))
  use _ <- result.try(check_int(
    db,
    "capability child locators",
    "SELECT count(*) FROM capability_source_locator;",
    8,
  ))
  use _ <- result.try(check_int(
    db,
    "composite pseudo-locators",
    "SELECT count(*) FROM capability_inventory WHERE source_path LIKE '% + %';",
    0,
  ))
  use _ <- result.try(check_int(
    db,
    "partial prompt count",
    "SELECT count(*) FROM prompt_event WHERE availability='partial_or_truncated';",
    1,
  ))
  check_int(
    db,
    "known partial prompt",
    "SELECT count(*) FROM prompt_event WHERE prompt_id='HIST-024' AND availability='partial_or_truncated';",
    1,
  )
}

fn validate_prompt_hashes(
  db: database.Database,
) -> Result(Nil, MaterializeError) {
  let row_decoder = {
    use id <- decode.field(0, decode.string)
    use text <- decode.field(1, decode.string)
    use stored <- decode.field(2, decode.string)
    decode.success(#(id, text, stored))
  }
  use rows <- result.try(db_step(
    database.query(
      db,
      "SELECT prompt_id,verbatim_text,sha256 FROM prompt_event ORDER BY prompt_id;",
      [],
      row_decoder,
    ),
    "read prompt hashes",
  ))
  list.try_each(rows, fn(row) {
    let #(id, text, stored) = row
    case digest.sha256_hex(bit_array.from_string(text)) == stored {
      True -> Ok(Nil)
      False ->
        Error(InvariantFailure(
          name: "prompt hash " <> id,
          expected: stored,
          actual: digest.sha256_hex(bit_array.from_string(text)),
        ))
    }
  })
}

fn validate_artifact_snapshot(
  db: database.Database,
  workspace_root: String,
  spec: ArtifactSpec,
) -> Result(Nil, MaterializeError) {
  let path = filepath.join(workspace_root, spec.path)
  use current <- result.try(read_bits(path))
  use _ <- result.try(preflight(path, current))
  let row_decoder = {
    use storage_class <- decode.field(0, decode.string)
    use stored <- decode.field(1, decode.bit_array)
    use stored_digest <- decode.field(2, decode.string)
    use byte_count <- decode.field(3, decode.int)
    decode.success(#(storage_class, stored, stored_digest, byte_count))
  }
  use rows <- result.try(db_step(
    database.query(
      db,
      "SELECT typeof(content),content,sha256,byte_count FROM artifact_snapshot WHERE artifact_id=?;",
      [database.text(spec.id)],
      row_decoder,
    ),
    "read artifact " <> spec.id,
  ))
  let current_digest = digest.sha256_hex(current)
  let current_byte_count = bit_array.byte_size(current)
  case rows {
    [#("blob", stored, stored_digest, byte_count)] ->
      case
        stored == current,
        stored_digest == current_digest,
        byte_count == current_byte_count
      {
        True, True, True -> Ok(Nil)
        _, _, _ ->
          Error(InvariantFailure(
            name: "artifact snapshot " <> spec.id,
            expected: "exact BLOB bytes, byte count, and SHA-256",
            actual: "mismatched",
          ))
      }
    _ ->
      Error(InvariantFailure(
        name: "artifact snapshot " <> spec.id,
        expected: "exact BLOB bytes, byte count, and SHA-256",
        actual: "missing or mismatched",
      ))
  }
}

fn table_count(
  db: database.Database,
  table: String,
) -> Result(Int, MaterializeError) {
  db_step(
    database.scalar_int(db, "SELECT count(*) FROM " <> table <> ";"),
    "count " <> table,
  )
}

fn check_int(
  db: database.Database,
  name: String,
  sql: String,
  expected: Int,
) -> Result(Nil, MaterializeError) {
  use actual <- result.try(db_step(database.scalar_int(db, sql), name))
  require_int(name, expected, actual)
}

fn require_int(
  name: String,
  expected: Int,
  actual: Int,
) -> Result(Nil, MaterializeError) {
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(InvariantFailure(
        name: name,
        expected: int.to_string(expected),
        actual: int.to_string(actual),
      ))
  }
}

fn check_text(
  db: database.Database,
  name: String,
  sql: String,
  expected: String,
) -> Result(Nil, MaterializeError) {
  use actual <- result.try(db_step(database.scalar_text(db, sql), name))
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(InvariantFailure(name: name, expected: expected, actual: actual))
  }
}

fn publish(
  candidate: String,
  destination: String,
  summary: MaterializationSummary,
) -> Result(MaterializationSummary, MaterializeError) {
  case simplifile.set_permissions_octal(for_file_at: candidate, to: 0o600) {
    Error(error) -> {
      let _ = remove_if_present(candidate)
      Error(FilesystemFailure(
        operation: "set candidate permissions",
        path: candidate,
        error: error,
      ))
    }
    Ok(Nil) ->
      case simplifile.rename(at: candidate, to: destination) {
        Ok(Nil) -> Ok(summary)
        Error(error) -> {
          let _ = remove_if_present(candidate)
          Error(FilesystemFailure(
            operation: "publish verified candidate",
            path: destination,
            error: error,
          ))
        }
      }
  }
}

fn validate_destination(destination: String) -> Result(Nil, MaterializeError) {
  let bytes = destination |> bit_array.from_string |> bit_array.byte_size
  case string.contains(destination, "\u{0}"), bytes > 480 {
    True, _ -> Error(InvalidDestination("embedded NUL byte"))
    _, True ->
      Error(InvalidDestination("path exceeds the guarded 480-byte limit"))
    False, False -> Ok(Nil)
  }
}

fn open_database(
  path: String,
  operation: String,
) -> Result(database.Database, MaterializeError) {
  database.open(path)
  |> result.map_error(fn(error) {
    DatabaseFailure(operation: operation, error: error)
  })
}

fn db_step(
  value: Result(a, database.DatabaseError),
  operation: String,
) -> Result(a, MaterializeError) {
  value
  |> result.map_error(fn(error) {
    DatabaseFailure(operation: operation, error: error)
  })
}

fn read_bits(path: String) -> Result(BitArray, MaterializeError) {
  simplifile.read_bits(from: path)
  |> result.map_error(fn(error) {
    FilesystemFailure(operation: "read exact bytes", path: path, error: error)
  })
}

fn preflight(path: String, bytes: BitArray) -> Result(Nil, MaterializeError) {
  safety.preflight_text(bytes)
  |> result.map_error(fn(error) { PreflightFailure(path: path, error: error) })
}

fn require_digest(
  name: String,
  expected: String,
  actual: String,
) -> Result(Nil, MaterializeError) {
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(InvariantFailure(name: name, expected: expected, actual: actual))
  }
}

fn loaded_artifact_text(
  artifacts: List(LoadedArtifact),
  artifact_id: String,
) -> Result(String, MaterializeError) {
  case artifacts {
    [] ->
      Error(InvariantFailure(
        name: "loaded artifact " <> artifact_id,
        expected: "one preflighted UTF-8 artifact",
        actual: "missing",
      ))
    [LoadedArtifact(spec, bytes), ..rest] ->
      case spec.id == artifact_id {
        False -> loaded_artifact_text(rest, artifact_id)
        True ->
          case bit_array.to_string(bytes) {
            Ok(text) -> Ok(text)
            Error(Nil) ->
              Error(InvariantFailure(
                name: "loaded artifact " <> artifact_id,
                expected: "valid UTF-8",
                actual: "invalid byte sequence",
              ))
          }
      }
  }
}

fn remove_if_present(path: String) -> Result(Nil, MaterializeError) {
  case simplifile.exists(filepath: path, follow_links: False) {
    Error(error) ->
      Error(FilesystemFailure(
        operation: "inspect candidate",
        path: path,
        error: error,
      ))
    Ok(False) -> Ok(Nil)
    Ok(True) ->
      simplifile.delete_file(at: path)
      |> result.map_error(fn(error) {
        FilesystemFailure(
          operation: "remove stale candidate",
          path: path,
          error: error,
        )
      })
  }
}

fn artifact_specs() -> List(ArtifactSpec) {
  [
    ArtifactSpec(
      "ART-POLICY-UOS-ROOT",
      "AGENTS.md",
      "policy",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-POLICY-UOS-CLAUDE",
      "CLAUDE.md",
      "policy",
      "text/markdown",
      "generated_projection",
    ),
    ArtifactSpec(
      "ART-PROMPT-LEGACY",
      "c3i/docs/journal/20260904-uos-full-history-evidence-review-journal.md",
      "prompt_archive",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-PROMPT-INVENTORY",
      "docs/design/2026-09-04-uos-complete-information-inventory.md",
      "prompt_archive",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-JOURNAL-CURRENT",
      "docs/journal/2026-09-05-uos-consolidation-context-journal.md",
      "journal",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-SPEC-UOS-V1",
      "docs/design/2026-09-05-uos-formal-mandate-spec.json",
      "formal_spec",
      "application/json",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-SPEC-SCHEMA-V1",
      "docs/design/2026-09-05-uos-formal-mandate-spec.schema.json",
      "formal_schema",
      "application/schema+json",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-DESIGN-UOS",
      "docs/design/2026-09-05-uos-standalone-jujutsu-monorepo-design.md",
      "design",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-PLAN-UOS",
      "docs/design/2026-09-05-uos-standalone-jujutsu-monorepo-implementation-plan.md",
      "plan",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-CATALOG-UOS",
      "docs/design/2026-09-05-uos-source-feature-traceability-catalog.md",
      "catalog",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-OPENCLAW",
      "docs/design/2026-09-05-uos-openclaw-compatibility-source-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-MODULAR",
      "docs/design/2026-09-05-uos-modular-max-mojo-source-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-DEEPSEEK",
      "docs/design/2026-09-05-uos-deepseek-harness-cordis-source-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-BUNDLE-INDEX",
      "docs/design/2026-09-05-uos-planning-bundle-index.md",
      "catalog",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-C3I-CAP",
      "docs/design/2026-09-05-uos-c3i-agent-skill-mcp-max-mojo-source-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-ZIG-HARNESS-CAP",
      "docs/design/2026-09-05-uos-zigvm-harness-agent-skill-mcp-observability-source-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AUDIT-FORMAL",
      "docs/design/2026-09-05-uos-formal-authority-z3-vfs-agent-protocol-audit.md",
      "source_audit",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-CONTRACT-SDLC-SRE",
      "docs/design/2026-09-05-uos-sdlc-sre-artifact-contract.md",
      "design",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-REVIEW-AGY-1",
      "docs/design/2026-09-05-uos-monorepo-agy-review.md",
      "review",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-REVIEW-AGY-2",
      "docs/design/2026-09-05-uos-monorepo-agy-pass2-verification.md",
      "review",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-REVIEW-AGY-3",
      "docs/design/2026-09-05-uos-monorepo-agy-pass3-sequencing-rollback-audit.md",
      "review",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-HANDOVER-GREENFIELD",
      "docs/design/2026-09-05-uos-greenfield-handover-canonical-reference-library.md",
      "receipt",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AGENT-POLICY-SUPERSET",
      "docs/design/2026-09-05-uos-agent-policy-capability-superset-mapping.md",
      "inventory",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-AGENT-CAPABILITY-INVENTORY",
      "docs/design/2026-09-05-uos-agent-capability-inventory.json",
      "inventory",
      "application/json",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-JOURNAL-POLICY-CAP",
      "docs/journal/uos-agent-policy-capability-unification-journal.md",
      "journal",
      "text/markdown",
      "planning_authority",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-DMC-TCM",
      "docs/design/DMC_TCM_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-JOURNAL-DMC-TCM",
      "docs/journal/2026-09-05-uos-dmc-tcm-master-tome-formalization-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-AUDIT-FRACTAL-VECTORS",
      "docs/design/2026-09-05-uos-monorepo-multidimensional-fractal-audit.md",
      "review",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-FV",
      "docs/design/FORMAL_VERIFICATION_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-JOURNAL-FV-TOME",
      "docs/journal/2026-09-05-uos-formal-verification-master-tome-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-ALGEBRAIC-ATLAS",
      "docs/design/ALGEBRAIC_ATLAS_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-SA-PLAN",
      "docs/design/SA_PLAN_C3I_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-FORECASTING",
      "docs/design/FORECASTING_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "historical_source",
    ),
    ArtifactSpec(
      "ART-JOURNAL-PILLARS-TOMES",
      "docs/journal/2026-09-05-uos-foundational-pillars-master-tomes-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-ANALYSIS-WIKI-ZK-KM",
      "docs/design/WIKI_ZK_KM_EXHAUSTIVE_ANALYSIS.md",
      "source_audit",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-JOURNAL-WIKI-ZK-KM",
      "docs/journal/2026-09-05-uos-wiki-zk-km-exhaustive-analysis-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-WIKI-ZK-KM",
      "docs/design/WIKI_ZK_KM_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-JOURNAL-WIKI-ZK-KM-10CYCLES",
      "docs/journal/2026-09-05-uos-wiki-zk-km-10-cycles-master-tome-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-MASTER-TOME-FRACTAL-UNIFICATION",
      "docs/design/FRACTAL_MULTIDIMENSIONAL_UNIFICATION_MASTER_TOME.md",
      "receipt",
      "text/markdown",
      "review_evidence",
    ),
    ArtifactSpec(
      "ART-JOURNAL-FRACTAL-UNIFICATION",
      "docs/journal/2026-09-05-uos-fractal-multidimensional-unification-journal.md",
      "journal",
      "text/markdown",
      "review_evidence",
    ),
  ]
}
