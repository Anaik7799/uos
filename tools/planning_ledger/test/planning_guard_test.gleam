import gleam/list
import gleam/string
import gleeunit/should
import simplifile
import uos_planning_ledger/database
import uos_planning_ledger/materializer

// Real generation schema with deliberately small, synthetic records. These
// fixtures are not historical prompts, evidence receipts, or capability credit.
fn with_fixture(assertions: fn(database.Database) -> Nil) {
  let assert Ok(db) = database.open(":memory:")
  let assert Ok(schema) = simplifile.read("001_schema.sql")
  let assert Ok(inventory) =
    simplifile.read("002_policy_capability_inventory.sql")
  let assert [inventory_ddl, ..] = string.split(inventory, "\nINSERT")
  let assert Ok(Nil) = database.exec_static(db, schema)
  let assert Ok(Nil) = database.exec_static(db, inventory_ddl <> "\nCOMMIT;")
  let assert Ok(Nil) = database.exec_static(db, fixtures)
  assertions(db)
  database.close(db) |> should.equal(Ok(Nil))
}

fn rejects_constraint(result: Result(Nil, database.DatabaseError)) {
  case result {
    Error(database.SqliteFailure(code, _, _)) -> code % 256 |> should.equal(19)
    other -> other |> should.equal(Error(database.SqliteFailure(19, "", 0)))
  }
}

pub fn planning_rows_cannot_grant_operational_credit_test() {
  use db <- with_fixture
  database.exec_static(
    db,
    "INSERT INTO mechanism_audit VALUES('POS','formal','synthetic',NULL,NULL,'implemented','A0_reference',1,'gap','not a receipt','2026-09-05T12:00:00Z');",
  )
  |> rejects_constraint
  database.scalar_int(
    db,
    "SELECT count(*) FROM mechanism_audit WHERE operational_credit != 0;",
  )
  |> should.equal(Ok(0))
}

pub fn planning_status_promotion_requires_an_unimplemented_admission_engine_test() {
  use db <- with_fixture
  [
    "UPDATE mandate_revision SET status='admitted' WHERE mandate_id='M';",
    "UPDATE work_item SET status='complete' WHERE work_id='W';",
    "UPDATE directive_superset SET current_status='verified' WHERE directive_id='D';",
    "UPDATE timestamp_namespace SET current_status='verified' WHERE namespace_id='TIME';",
    "UPDATE formal_tool_authority SET evidence_state='fresh_passing' WHERE tool_authority_id='TOOL';",
    "INSERT INTO formal_clause VALUES('FC','M','target','/target','synthetic','schema','admitted');",
    "INSERT INTO capability_inventory VALUES('C2','skill','synthetic',NULL,'/fixture','/fixture/c2','other','declaration',NULL,NULL,'implemented_observed','adapt',NULL,'not a receipt','2026-09-05T12:00:00Z');",
    "INSERT INTO classification_scheme VALUES('S2','1','ART','observation','admitted','synthetic','2026-09-05T12:00:00Z');",
  ]
  |> list.each(fn(sql) { database.exec_static(db, sql) |> rejects_constraint })
}

pub fn all_fifteen_immutable_families_reject_replace_with_recursive_triggers_off_test() {
  use db <- with_fixture
  let assert Ok(Nil) =
    database.exec_static(db, "PRAGMA recursive_triggers=OFF;")
  database.scalar_int(db, "PRAGMA recursive_triggers;") |> should.equal(Ok(0))
  [
    "artifact_snapshot", "prompt_event", "agent_message", "mechanism_audit",
    "capability_inventory", "capability_source_locator",
    "directive_source_mapping", "classification_term", "classification_scheme",
    "directive_classification", "capability_classification",
    "source_protocol_identity", "mandate_prompt_lineage",
    "source_policy_identity", "capability_inventory_summary",
  ]
  |> list.each(fn(table) {
    // Table identifiers are a closed literal test list, never external values.
    database.exec_static(
      db,
      "INSERT OR REPLACE INTO " <> table <> " SELECT * FROM " <> table <> ";",
    )
    |> rejects_constraint
    database.scalar_int(db, "SELECT count(*) FROM " <> table <> ";")
    |> should.equal(Ok(1))
  })
}

pub fn alternate_unique_keys_cannot_replace_evidence_or_message_identity_test() {
  use db <- with_fixture
  let assert Ok(Nil) =
    database.exec_static(db, "PRAGMA recursive_triggers=OFF;")
  let assert Ok(Nil) =
    database.exec_static(
      db,
      "INSERT INTO artifact_snapshot VALUES('ORPHAN','/fixture/orphan','journal','text/plain',X'41',printf('%064d',0),1,'2026-09-05T12:00:00Z','historical_source');",
    )
  database.exec_static(
    db,
    "INSERT OR REPLACE INTO artifact_snapshot VALUES('NEW','/fixture/orphan','journal','text/plain',X'42',printf('%064d',0),1,'2026-09-05T12:00:00Z','historical_source');",
  )
  |> rejects_constraint
  database.scalar_text(
    db,
    "SELECT artifact_id || ':' || hex(content) FROM artifact_snapshot WHERE path='/fixture/orphan';",
  )
  |> should.equal(Ok("ORPHAN:41"))
  database.exec_static(
    db,
    "INSERT OR REPLACE INTO agent_message VALUES('NEW','THREAD',1,'A',NULL,'W','context','replacement',printf('%064d',0),NULL,NULL,'2026-09-05T12:00:00Z');",
  )
  |> rejects_constraint
  database.scalar_text(
    db,
    "SELECT message_id || ':' || body FROM agent_message;",
  )
  |> should.equal(Ok("MSG:synthetic"))
}

pub fn verification_rejects_credit_even_if_a_writer_disabled_schema_checks_test() {
  use db <- with_fixture
  materializer.validate_planning_only(db) |> should.equal(Ok(Nil))
  let assert Ok(Nil) =
    database.exec_static(
      db,
      "PRAGMA ignore_check_constraints=ON; INSERT INTO mechanism_audit VALUES('FORGED','formal','synthetic',NULL,NULL,'implemented','A0_reference',1,'gap','not a receipt','2026-09-05T12:00:00Z');",
    )
  let assert Error(materializer.InvariantFailure(name, _, _)) =
    materializer.validate_planning_only(db)
  name |> should.equal("planning operational credit")
}

pub fn repeated_authoritative_seed_is_not_silently_ignored_test() {
  use db <- with_fixture
  add_spec_locators(db)
  let assert Ok(seed) = simplifile.read("003_core_seed.sql")
  let assert Ok(Nil) = database.exec_static(db, seed)
  database.exec_static(db, seed) |> rejects_constraint
}

pub fn newly_captured_prompt_does_not_claim_reviewed_semantic_incorporation_test() {
  use db <- with_fixture
  add_spec_locators(db)
  let assert Ok(Nil) =
    database.exec_static(
      db,
      "INSERT INTO prompt_event VALUES('CURR-002',2,'synthetic continuation','ART','fixture:2','new unreviewed obligation','available_in_source_snapshot','synthetic only',NULL,'2026-09-05T12:00:00Z');",
    )
  let assert Ok(seed) = simplifile.read("003_core_seed.sql")
  let assert Ok(Nil) = database.exec_static(db, seed)
  database.scalar_int(
    db,
    "SELECT count(*) FROM prompt_event WHERE prompt_id='CURR-002';",
  )
  |> should.equal(Ok(1))
  database.scalar_text(
    db,
    "SELECT source_prompt_id FROM mandate_revision WHERE mandate_id='UOS-MANDATE-v1';",
  )
  |> should.equal(Ok("CURR-001"))
  database.scalar_text(
    db,
    "SELECT incorporation_status FROM mandate_prompt_lineage WHERE mandate_id='UOS-MANDATE-v1' AND source_prompt_id='CURR-002';",
  )
  |> should.equal(Ok("captured_unreviewed"))
  database.scalar_text(
    db,
    "SELECT source_prompt_id FROM mandate_revision WHERE mandate_id='UOS-MANDATE-v1';",
  )
  |> should.equal(Ok("CURR-001"))
}

fn add_spec_locators(db: database.Database) {
  [
    #("ART-SPEC-UOS-V1", "/fixture/spec"),
    #("ART-SPEC-SCHEMA-V1", "/fixture/schema"),
  ]
  |> list.each(fn(entry) {
    let #(id, path) = entry
    let assert Ok(Nil) =
      database.execute(
        db,
        "INSERT INTO artifact_snapshot VALUES(?,?,'formal_spec','application/json',X'7B7D',printf('%064d',0),2,'2026-09-05T12:00:00Z','planning_authority');",
        [database.text(id), database.text(path)],
      )
  })
}

const fixtures = "
INSERT INTO artifact_snapshot VALUES('ART','/fixture/art','journal','text/plain',X'41',printf('%064d',0),1,'2026-09-05T12:00:00Z','historical_source');
INSERT INTO prompt_event VALUES('CURR-001',1,'synthetic base','ART','fixture:1','synthetic','available_in_source_snapshot','synthetic only',NULL,'2026-09-05T12:00:00Z');
INSERT INTO mandate_revision VALUES('M','CURR-001','ART','ART','synthetic','draft','2026-09-05T12:00:00Z',NULL);
INSERT INTO mandate_prompt_lineage(mandate_id,source_prompt_id,lineage_ordinal,lineage_role,derivation_note) VALUES('M','CURR-001',1,'base','synthetic captured input');
INSERT INTO agent VALUES('A','synthetic',NULL,NULL,'test','none','planned',NULL);
INSERT INTO work_item VALUES('W','synthetic','none','ready',0,'A',NULL,'2026-09-05T12:00:00Z','2026-09-05T12:00:00Z');
INSERT INTO agent_message VALUES('MSG','THREAD',1,'A',NULL,'W','context','synthetic',printf('%064d',0),NULL,NULL,'2026-09-05T12:00:00Z');
INSERT INTO mechanism_audit VALUES('MECH','formal','synthetic',NULL,NULL,'documented_only','A0_reference',0,'gap','synthetic','2026-09-05T12:00:00Z');
INSERT INTO capability_inventory VALUES('C','skill','synthetic',NULL,'/fixture','/fixture/c','name','declaration',NULL,NULL,'declaration_only','adapt',NULL,'synthetic','2026-09-05T12:00:00Z');
INSERT INTO capability_source_locator VALUES('LOC','C','/fixture/c','file','primary','unverified','synthetic');
INSERT INTO directive_superset VALUES('D','test','synthetic','none','none','/fixture','none','planned','unavailable');
INSERT INTO directive_source_mapping VALUES('MAP','D','synthetic',NULL,'/fixture','anchor','requirements_only',NULL,'synthetic');
INSERT INTO classification_scheme VALUES('S','1','ART','observation','planning','synthetic','2026-09-05T12:00:00Z');
INSERT INTO classification_term VALUES('S','ontology_class','TERM','synthetic','synthetic');
INSERT INTO directive_classification VALUES('D','S','ontology_class','TERM',1,'current','document_review','provisional','synthetic');
INSERT INTO capability_classification VALUES('C','S','ontology_class','TERM',1,'current','document_review','provisional','synthetic');
INSERT INTO source_protocol_identity VALUES('PROTOCOL','timestamp','source_rule','synthetic','/fixture/protocol',printf('%064d',0),1,'PRESERVED_UNCHANGED','A0_reference','synthetic','2026-09-05T12:00:00Z');
INSERT INTO source_policy_identity VALUES('POLICY','synthetic','test','/fixture/policy','/fixture/policy',NULL,printf('%064d',0),1,'source_input','canonical','A0_reference','2026-09-05T12:00:00Z','synthetic');
INSERT INTO capability_inventory_summary VALUES('SUMMARY','synthetic',NULL,'/fixture','/fixture/summary','skill','declaration','A0_reference',1,'synthetic','observed','reference','synthetic','2026-09-05T12:00:00Z');
INSERT INTO timestamp_namespace VALUES('TIME','synthetic','fixture','none','unresolved_target_type','planned','synthetic');
INSERT INTO formal_tool_authority VALUES('TOOL','synthetic','test',NULL,NULL,'documented_only',NULL,0,0,0,'unrun','synthetic');
"
