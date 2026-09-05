import filepath
import gleam/dynamic/decode
import gleam/list
import gleeunit/should
import simplifile
import uos_planning_ledger/database
import uos_planning_ledger/materializer.{MaterializationSummary}
import uos_planning_ledger/prompt

pub fn reconstructs_the_complete_planning_ledger_with_gleam_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let destination =
    filepath.join(
      workspace_root,
      "docs/journal/uos-planning-ledger/build/materializer-test.sqlite3",
    )
  let _ = simplifile.delete_file(at: destination)
  let _ = simplifile.delete_file(at: destination <> ".next.sqlite3")
  let _ = simplifile.delete_file(at: destination <> ".materialize.lock")

  let assert Ok(legacy_archive) =
    simplifile.read(filepath.join(
      workspace_root,
      "c3i/docs/journal/20260904-uos-full-history-evidence-review-journal.md",
    ))
  let assert Ok(current_archive) =
    simplifile.read(filepath.join(
      workspace_root,
      "docs/journal/2026-09-05-uos-consolidation-context-journal.md",
    ))
  let expected_prompts =
    list.length(prompt.extract(legacy_archive))
    + list.length(prompt.extract(current_archive))
  let expected_mandate_inputs = list.length(prompt.extract(current_archive))

  materializer.materialize(
    workspace_root: workspace_root,
    destination: destination,
    observed_at: "2026-09-05T12:00:00+02:00",
  )
  |> should.equal(
    Ok(MaterializationSummary(
      artifacts: 40,
      prompts: expected_prompts,
      mandate_inputs: expected_mandate_inputs,
      clauses: 12,
      directives: 38,
      source_maps: 141,
      capabilities: 473,
    )),
  )

  // A second verified build exercises replacement of an existing destination.
  let assert Ok(second_summary) =
    materializer.materialize(
      workspace_root: workspace_root,
      destination: destination,
      observed_at: "2026-09-05T12:00:01+02:00",
    )
  second_summary.prompts |> should.equal(expected_prompts)
  simplifile.exists(
    filepath: destination <> ".next.sqlite3",
    follow_links: False,
  )
  |> should.equal(Ok(False))
  simplifile.exists(
    filepath: destination <> ".materialize.lock",
    follow_links: False,
  )
  |> should.equal(Ok(False))

  let assert Ok(db) = database.open(destination)
  let metadata_decoder = {
    use key <- decode.field(0, decode.string)
    use value <- decode.field(1, decode.string)
    decode.success(#(key, value))
  }
  let assert Ok(metadata) =
    database.query(
      db,
      "SELECT key, value FROM ledger_meta WHERE key IN ('materializer_language', 'sqlite_api') ORDER BY key;",
      [],
      metadata_decoder,
    )
  metadata
  |> should.equal([
    #("materializer_language", "Gleam"),
    #("sqlite_api", "sqlight@1.2.0/esqlite@0.9.0"),
  ])
  database.query(
    db,
    "SELECT value FROM ledger_meta WHERE key='materialized_at';",
    [],
    {
      use value <- decode.field(0, decode.string)
      decode.success(value)
    },
  )
  |> should.equal(Ok(["2026-09-05T12:00:01+02:00"]))

  [
    #("agent", 5),
    #("agent_message", 1),
    #("artifact_snapshot", 40),
    #("capability_classification", 5096),
    #("capability_inventory", 473),
    #("capability_inventory_summary", 48),
    #("capability_source_locator", 8),
    #("classification_scheme", 1),
    #("classification_term", 101),
    #("coordination_protocol", 3),
    #("directive_classification", 577),
    #("directive_source_mapping", 141),
    #("directive_superset", 38),
    #("formal_clause", 12),
    #("formal_tool_authority", 9),
    #("journal_contract_section", 13),
    #("ledger_meta", 36),
    #("mandate_prompt_lineage", expected_mandate_inputs),
    #("mandate_revision", 1),
    #("mechanism_audit", 16),
    #("message_delivery", 0),
    #("prompt_event", expected_prompts),
    #("review_finding", 0),
    #("source_policy_identity", 44),
    #("source_protocol_identity", 4),
    #("timestamp_namespace", 8),
    #("work_claim", 0),
    #("work_item", 4),
  ]
  |> list.each(fn(expected) {
    let #(table, count) = expected
    let assert Ok(actual) =
      database.scalar_int(db, "SELECT count(*) FROM " <> table <> ";")
    actual |> should.equal(count)
  })

  let digest_decoder = {
    use count <- decode.field(0, decode.int)
    decode.success(count)
  }
  let assert Ok([0]) =
    database.query(
      db,
      "SELECT count(*) FROM prompt_event WHERE sha256 IS NULL OR length(sha256) != 64;",
      [],
      digest_decoder,
    )

  database.scalar_int(
    db,
    "SELECT count(*) FROM prompt_event WHERE availability='verbatim_available';",
  )
  |> should.equal(Ok(0))
  database.scalar_int(
    db,
    "SELECT count(*) FROM prompt_event WHERE availability='available_in_source_snapshot';",
  )
  |> should.equal(Ok(expected_prompts - 1))
  database.scalar_int(
    db,
    "SELECT count(*) FROM ledger_meta WHERE key IN ('schema_source_sha256','inventory_seed_sha256','core_seed_sha256','materializer_manifest_sha256','package_spec_sha256','main_source_sha256','materializer_source_sha256','database_api_source_sha256','digest_source_sha256','prompt_parser_source_sha256','safety_source_sha256','writer_lock_source_sha256');",
  )
  |> should.equal(Ok(12))

  let assert Ok(Nil) = database.close(db)
  let _ = simplifile.delete_file(at: destination)
  let _ = simplifile.delete_file(at: destination <> ".next.sqlite3")
  let _ = simplifile.delete_file(at: destination <> ".materialize.lock")
  list.length(metadata) |> should.equal(2)
}

pub fn failed_build_preserves_existing_destination_bytes_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let destination =
    filepath.join(
      workspace_root,
      "docs/journal/uos-planning-ledger/build/materializer-failure-test.sqlite3",
    )
  let sentinel = <<"existing destination must survive":utf8>>
  let assert Ok(Nil) = simplifile.write_bits(to: destination, bits: sentinel)

  let assert Error(_) =
    materializer.materialize(
      workspace_root: filepath.join(workspace_root, "definitely-missing-root"),
      destination: destination,
      observed_at: "2026-09-05T12:00:02+02:00",
    )
  simplifile.read_bits(from: destination) |> should.equal(Ok(sentinel))
  simplifile.exists(
    filepath: destination <> ".next.sqlite3",
    follow_links: False,
  )
  |> should.equal(Ok(False))
  simplifile.exists(
    filepath: destination <> ".materialize.lock",
    follow_links: False,
  )
  |> should.equal(Ok(False))

  let _ = simplifile.delete_file(at: destination)
}

pub fn invalid_observation_timestamp_fails_before_touching_destination_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let destination =
    filepath.join(
      workspace_root,
      "docs/journal/uos-planning-ledger/build/materializer-time-test.sqlite3",
    )
  let sentinel = <<"existing destination":utf8>>
  let assert Ok(Nil) = simplifile.write_bits(to: destination, bits: sentinel)

  let assert Error(materializer.InvalidObservedAt(_)) =
    materializer.materialize(
      workspace_root: workspace_root,
      destination: destination,
      observed_at: "2026-99-77 12:00",
    )
  simplifile.read_bits(from: destination) |> should.equal(Ok(sentinel))
  simplifile.exists(
    filepath: destination <> ".materialize.lock",
    follow_links: False,
  )
  |> should.equal(Ok(False))

  let _ = simplifile.delete_file(at: destination)
}

pub fn an_existing_writer_lock_fails_closed_without_touching_destination_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let destination =
    filepath.join(
      workspace_root,
      "docs/journal/uos-planning-ledger/build/materializer-lock-test.sqlite3",
    )
  let lock = destination <> ".materialize.lock"
  let sentinel = <<"existing destination":utf8>>
  let held = <<"held by another writer":utf8>>
  let assert Ok(Nil) = simplifile.write_bits(to: destination, bits: sentinel)
  let assert Ok(Nil) = simplifile.write_bits(to: lock, bits: held)

  let assert Error(_) =
    materializer.materialize(
      workspace_root: workspace_root,
      destination: destination,
      observed_at: "2026-09-05T12:00:03+02:00",
    )
  simplifile.read_bits(from: destination) |> should.equal(Ok(sentinel))
  simplifile.read_bits(from: lock) |> should.equal(Ok(held))
  simplifile.exists(
    filepath: destination <> ".next.sqlite3",
    follow_links: False,
  )
  |> should.equal(Ok(False))

  let _ = simplifile.delete_file(at: destination)
  let _ = simplifile.delete_file(at: lock)
}
