PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;
PRAGMA synchronous = FULL;
PRAGMA user_version = 7;

-- Planning generation only: there is no positive receipt-admission engine.
-- Raw claims may be preserved as artifact bytes, never as operational credit.

CREATE TABLE IF NOT EXISTS ledger_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS artifact_snapshot (
  artifact_id TEXT PRIMARY KEY,
  path TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN (
    'prompt_archive', 'journal', 'formal_spec', 'formal_schema',
    'design', 'plan', 'catalog', 'source_audit', 'policy', 'inventory',
    'review', 'receipt'
  )),
  media_type TEXT NOT NULL,
  content BLOB NOT NULL,
  sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
  byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
  observed_at TEXT NOT NULL,
  truth_status TEXT NOT NULL CHECK (truth_status IN (
    'historical_source', 'planning_authority', 'generated_projection',
    'review_evidence', 'runtime_evidence'
  ))
) STRICT;

CREATE TABLE IF NOT EXISTS prompt_event (
  prompt_id TEXT PRIMARY KEY,
  ordinal INTEGER,
  label TEXT NOT NULL,
  source_artifact_id TEXT NOT NULL REFERENCES artifact_snapshot(artifact_id),
  source_anchor TEXT NOT NULL,
  verbatim_text TEXT,
  availability TEXT NOT NULL CHECK (availability IN (
    'verbatim_available', 'available_in_source_snapshot',
    'partial_or_truncated', 'summary_only', 'not_available'
  )),
  integrity_note TEXT NOT NULL,
  sha256 TEXT CHECK (sha256 IS NULL OR length(sha256) = 64),
  observed_at TEXT NOT NULL,
  UNIQUE(source_artifact_id, label, source_anchor)
) STRICT;

CREATE TABLE IF NOT EXISTS mandate_revision (
  mandate_id TEXT PRIMARY KEY,
  source_prompt_id TEXT NOT NULL REFERENCES prompt_event(prompt_id),
  formal_spec_artifact_id TEXT NOT NULL REFERENCES artifact_snapshot(artifact_id),
  schema_artifact_id TEXT NOT NULL REFERENCES artifact_snapshot(artifact_id),
  derivation_method TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('draft', 'reviewed', 'superseded')),
  created_at TEXT NOT NULL,
  supersedes_id TEXT REFERENCES mandate_revision(mandate_id)
) STRICT;

CREATE TABLE IF NOT EXISTS mandate_prompt_lineage (
  mandate_id TEXT NOT NULL REFERENCES mandate_revision(mandate_id),
  source_prompt_id TEXT NOT NULL REFERENCES prompt_event(prompt_id),
  lineage_ordinal INTEGER NOT NULL CHECK (lineage_ordinal > 0),
  lineage_role TEXT NOT NULL CHECK (lineage_role IN (
    'base', 'continuation', 'terminal'
  )),
  derivation_note TEXT NOT NULL,
  incorporation_status TEXT NOT NULL DEFAULT 'captured_unreviewed'
    CHECK (incorporation_status = 'captured_unreviewed'),
  PRIMARY KEY(mandate_id, source_prompt_id),
  UNIQUE(mandate_id, lineage_ordinal)
) STRICT;

CREATE TABLE IF NOT EXISTS formal_clause (
  clause_id TEXT PRIMARY KEY,
  mandate_id TEXT NOT NULL REFERENCES mandate_revision(mandate_id),
  clause_kind TEXT NOT NULL CHECK (clause_kind IN (
    'source_authority', 'target', 'prohibition', 'language_boundary',
    'formal_authority', 'trace_dimension', 'artifact_field',
    'evolution', 'compatibility', 'invariant', 'acceptance'
  )),
  json_pointer TEXT NOT NULL,
  normative_text TEXT NOT NULL,
  authority_class TEXT NOT NULL,
  current_status TEXT NOT NULL CHECK (current_status IN (
    'planned', 'implemented_planning_only', 'historical_evidence', 'blocked'
  )),
  UNIQUE(mandate_id, json_pointer)
) STRICT;

CREATE TABLE IF NOT EXISTS formal_tool_authority (
  tool_authority_id TEXT PRIMARY KEY,
  source_system TEXT NOT NULL,
  language_or_tool TEXT NOT NULL,
  source_revision TEXT,
  source_path TEXT,
  role TEXT NOT NULL CHECK (role IN (
    'normative_spec', 'machine_check', 'model_exploration',
    'certificate_check', 'code_generator', 'advisory_analysis',
    'documented_only', 'absent'
  )),
  invoked_by TEXT,
  blocks_build INTEGER NOT NULL CHECK (blocks_build IN (0,1)),
  blocks_release INTEGER NOT NULL CHECK (blocks_release IN (0,1)),
  runtime_effect_authority INTEGER NOT NULL CHECK (runtime_effect_authority = 0),
  evidence_state TEXT NOT NULL CHECK (evidence_state NOT IN (
    'fresh_passing', 'verified', 'admitted'
  )),
  details TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS mechanism_audit (
  mechanism_id TEXT PRIMARY KEY,
  domain TEXT NOT NULL CHECK (domain IN (
    'formal', 'solver', 'vfs', 'fpp', 'sysml', 'coordination'
  )),
  source_system TEXT NOT NULL,
  source_revision TEXT,
  source_path TEXT,
  observed_status TEXT NOT NULL CHECK (observed_status IN (
    'implemented', 'implemented_unavailable', 'partial', 'mock',
    'unsafe_legacy', 'documented_only', 'absent', 'historical_evidence'
  )),
  authority_class TEXT NOT NULL CHECK (authority_class IN (
    'A0_reference', 'A1_advisory', 'A2_admission_veto',
    'A3_pure_generation', 'A4_runtime_evidence', 'A5_direct_effect_forbidden',
    'none'
  )),
  operational_credit INTEGER NOT NULL CHECK (operational_credit = 0),
  blocking_gap TEXT NOT NULL,
  evidence TEXT NOT NULL,
  observed_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS agent (
  agent_id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  model TEXT,
  effort TEXT,
  role TEXT NOT NULL,
  authority TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('planned', 'active', 'idle', 'complete', 'blocked', 'retired')),
  last_seen_at TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS work_item (
  work_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  specification TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('backlog', 'ready', 'claimed', 'review', 'blocked', 'cancelled')),
  priority INTEGER NOT NULL,
  owner_agent_id TEXT REFERENCES agent(agent_id),
  artifact_revision TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS agent_message (
  message_id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  sequence_no INTEGER NOT NULL CHECK (sequence_no > 0),
  sender_agent_id TEXT NOT NULL REFERENCES agent(agent_id),
  recipient_agent_id TEXT REFERENCES agent(agent_id),
  work_id TEXT REFERENCES work_item(work_id),
  message_kind TEXT NOT NULL CHECK (message_kind IN (
    'task', 'context', 'question', 'answer', 'finding', 'decision',
    'review', 'receipt', 'heartbeat', 'handover'
  )),
  body TEXT NOT NULL,
  body_sha256 TEXT NOT NULL CHECK (length(body_sha256) = 64),
  causation_message_id TEXT REFERENCES agent_message(message_id),
  artifact_revision TEXT,
  sent_at TEXT NOT NULL,
  UNIQUE(thread_id, sequence_no)
) STRICT;

CREATE TABLE IF NOT EXISTS message_delivery (
  message_id TEXT NOT NULL REFERENCES agent_message(message_id),
  recipient_agent_id TEXT NOT NULL REFERENCES agent(agent_id),
  state TEXT NOT NULL CHECK (state IN ('queued', 'delivered', 'acknowledged', 'rejected', 'expired')),
  state_at TEXT NOT NULL,
  note TEXT NOT NULL,
  PRIMARY KEY(message_id, recipient_agent_id, state)
) STRICT;

CREATE TABLE IF NOT EXISTS work_claim (
  claim_id TEXT PRIMARY KEY,
  work_id TEXT NOT NULL REFERENCES work_item(work_id),
  agent_id TEXT NOT NULL REFERENCES agent(agent_id),
  lease_generation INTEGER NOT NULL CHECK (lease_generation > 0),
  claimed_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  released_at TEXT,
  release_reason TEXT
) STRICT;

CREATE TABLE IF NOT EXISTS review_finding (
  finding_id TEXT PRIMARY KEY,
  work_id TEXT NOT NULL REFERENCES work_item(work_id),
  reviewer_agent_id TEXT NOT NULL REFERENCES agent(agent_id),
  severity TEXT NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low', 'note')),
  claim TEXT NOT NULL,
  evidence TEXT NOT NULL,
  disposition TEXT NOT NULL CHECK (disposition IN ('open', 'accepted', 'rejected_with_reason', 'fixed', 'deferred')),
  artifact_revision TEXT NOT NULL,
  created_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS coordination_protocol (
  protocol_id TEXT PRIMARY KEY,
  notation TEXT NOT NULL CHECK (notation IN ('SysML', 'FPrime', 'typed_state_machine', 'message_schema')),
  source_system TEXT NOT NULL,
  source_path TEXT,
  status TEXT NOT NULL CHECK (status IN ('source_backed', 'planned', 'documented_only', 'absent', 'quarantined')),
  definition TEXT NOT NULL,
  evidence TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS capability_inventory (
  capability_id TEXT PRIMARY KEY,
  capability_kind TEXT NOT NULL CHECK (capability_kind IN (
    'skill', 'superpower', 'agent', 'plugin', 'hook', 'mcp_tool',
    'wiki', 'zettelkasten', 'knowledge_management'
  )),
  source_system TEXT NOT NULL,
  source_revision TEXT,
  source_root TEXT NOT NULL,
  source_path TEXT NOT NULL,
  logical_name TEXT NOT NULL,
  source_role TEXT NOT NULL CHECK (source_role IN (
    'canonical', 'projection', 'declaration', 'implementation',
    'configured_exposure', 'handler', 'historical'
  )),
  projection_of TEXT REFERENCES capability_inventory(capability_id),
  content_sha256 TEXT CHECK (content_sha256 IS NULL OR length(content_sha256) = 64),
  executor_state TEXT NOT NULL CHECK (executor_state IN (
    'implemented_unverified', 'unavailable',
    'declaration_only', 'projection_only', 'historical_only', 'unknown'
  )),
  disposition TEXT NOT NULL CHECK (disposition IN (
    'retain', 'adapt', 'oracle', 'reference', 'generate', 'quarantine',
    'exclude', 'pending_freeze'
  )),
  target_path TEXT,
  evidence TEXT NOT NULL,
  observed_at TEXT NOT NULL,
  UNIQUE(source_system, source_path, logical_name, source_role)
) STRICT;

CREATE TABLE IF NOT EXISTS capability_source_locator (
  locator_id TEXT PRIMARY KEY,
  capability_id TEXT NOT NULL REFERENCES capability_inventory(capability_id),
  source_path TEXT NOT NULL,
  locator_kind TEXT NOT NULL CHECK (locator_kind IN ('file','directory')),
  relation TEXT NOT NULL CHECK (relation IN ('primary','secondary')),
  observed_state TEXT NOT NULL CHECK (observed_state IN (
    'exists_unfrozen', 'missing', 'unverified'
  )),
  evidence TEXT NOT NULL,
  UNIQUE(capability_id, source_path)
) STRICT;

CREATE TABLE IF NOT EXISTS directive_superset (
  directive_id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  normative_text TEXT NOT NULL,
  target_owner TEXT NOT NULL,
  target_path TEXT NOT NULL,
  authority_boundary TEXT NOT NULL,
  current_status TEXT NOT NULL CHECK (current_status IN (
    'planned', 'conflict_unresolved',
    'quarantined', 'excluded'
  )),
  admission_gate TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS directive_source_mapping (
  mapping_id TEXT PRIMARY KEY,
  directive_id TEXT NOT NULL REFERENCES directive_superset(directive_id),
  source_system TEXT NOT NULL,
  source_revision TEXT,
  source_path TEXT NOT NULL,
  source_anchor TEXT NOT NULL,
  relation TEXT NOT NULL CHECK (relation IN (
    'equivalent', 'refines', 'extends', 'restricts', 'splits', 'merges',
    'oracle_for', 'requirements_only', 'retired', 'excluded', 'incompatible'
  )),
  conflict_id TEXT,
  evidence TEXT NOT NULL,
  UNIQUE(directive_id, source_system, source_path, source_anchor)
) STRICT;

CREATE TABLE IF NOT EXISTS classification_scheme (
  scheme_id TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  definition_artifact_id TEXT NOT NULL REFERENCES artifact_snapshot(artifact_id),
  temporal_model TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('planning','reviewed','superseded')),
  definition TEXT NOT NULL,
  observed_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS classification_term (
  scheme_id TEXT NOT NULL DEFAULT 'UOS-CLASSIFICATION-ONTOLOGY-v1'
    REFERENCES classification_scheme(scheme_id),
  axis_id TEXT NOT NULL CHECK (axis_id IN (
    'ontology_class', 'process_family', 'sdlc_phase', 'sre_function',
    'operational_plane', 'process_type', 'authority_role', 'lifecycle_state',
    'migration_disposition'
  )),
  term_id TEXT NOT NULL,
  label TEXT NOT NULL,
  definition TEXT NOT NULL,
  PRIMARY KEY(scheme_id, axis_id, term_id)
) STRICT;

CREATE TABLE IF NOT EXISTS directive_classification (
  directive_id TEXT NOT NULL REFERENCES directive_superset(directive_id),
  scheme_id TEXT NOT NULL DEFAULT 'UOS-CLASSIFICATION-ONTOLOGY-v1'
    REFERENCES classification_scheme(scheme_id),
  axis_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  rank INTEGER NOT NULL CHECK (rank > 0),
  temporal_scope TEXT NOT NULL CHECK (temporal_scope IN ('current','target')),
  classification_method TEXT NOT NULL CHECK (classification_method IN (
    'kind_default', 'name_heuristic', 'document_review', 'body_review',
    'runtime_evidence'
  )),
  classification_status TEXT NOT NULL CHECK (classification_status IN (
    'provisional', 'reviewed', 'conflicted', 'not_applicable'
  )),
  rationale TEXT NOT NULL,
  PRIMARY KEY(directive_id, scheme_id, axis_id, term_id, temporal_scope),
  UNIQUE(directive_id, scheme_id, axis_id, temporal_scope, rank),
  FOREIGN KEY(scheme_id, axis_id, term_id)
    REFERENCES classification_term(scheme_id, axis_id, term_id)
) STRICT;

CREATE TABLE IF NOT EXISTS capability_classification (
  capability_id TEXT NOT NULL REFERENCES capability_inventory(capability_id),
  scheme_id TEXT NOT NULL DEFAULT 'UOS-CLASSIFICATION-ONTOLOGY-v1'
    REFERENCES classification_scheme(scheme_id),
  axis_id TEXT NOT NULL,
  term_id TEXT NOT NULL,
  rank INTEGER NOT NULL CHECK (rank > 0),
  temporal_scope TEXT NOT NULL CHECK (temporal_scope IN ('current','target')),
  classification_method TEXT NOT NULL CHECK (classification_method IN (
    'kind_default', 'name_heuristic', 'document_review', 'body_review',
    'runtime_evidence'
  )),
  classification_status TEXT NOT NULL CHECK (classification_status IN (
    'provisional', 'reviewed', 'conflicted', 'not_applicable'
  )),
  rationale TEXT NOT NULL,
  PRIMARY KEY(capability_id, scheme_id, axis_id, term_id, temporal_scope),
  UNIQUE(capability_id, scheme_id, axis_id, temporal_scope, rank),
  FOREIGN KEY(scheme_id, axis_id, term_id)
    REFERENCES classification_term(scheme_id, axis_id, term_id)
) STRICT;

CREATE TABLE IF NOT EXISTS timestamp_namespace (
  namespace_id TEXT PRIMARY KEY,
  source_system TEXT NOT NULL,
  format TEXT NOT NULL,
  semantic_fields TEXT NOT NULL,
  preservation TEXT NOT NULL CHECK (preservation IN (
    'unchanged_source_type', 'unresolved_target_type', 'protocol_native'
  )),
  current_status TEXT NOT NULL CHECK (current_status IN (
    'source_requirement', 'conflict_unresolved', 'planned'
  )),
  evidence TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS source_protocol_identity (
  protocol_artifact_id TEXT PRIMARY KEY,
  protocol_family TEXT NOT NULL CHECK (protocol_family IN ('timestamp','journal')),
  artifact_kind TEXT NOT NULL CHECK (artifact_kind IN ('source_rule','provider_procedure')),
  source_system TEXT NOT NULL,
  source_path TEXT NOT NULL UNIQUE,
  content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
  byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
  preservation TEXT NOT NULL CHECK (preservation = 'PRESERVED_UNCHANGED'),
  authority_class TEXT NOT NULL CHECK (authority_class = 'A0_reference'),
  evidence TEXT NOT NULL,
  observed_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS journal_contract_section (
  ordinal INTEGER PRIMARY KEY CHECK (ordinal BETWEEN 1 AND 13),
  title TEXT NOT NULL UNIQUE,
  required INTEGER NOT NULL CHECK (required = 1),
  scaling_rule TEXT NOT NULL,
  source_path TEXT NOT NULL,
  source_sha256 TEXT NOT NULL CHECK (length(source_sha256) = 64)
) STRICT;

CREATE TRIGGER IF NOT EXISTS artifact_snapshot_no_update
BEFORE UPDATE ON artifact_snapshot
BEGIN
  SELECT RAISE(ABORT, 'artifact snapshots are append-only');
END;

CREATE TRIGGER IF NOT EXISTS prompt_event_no_update
BEFORE UPDATE ON prompt_event
BEGIN
  SELECT RAISE(ABORT, 'prompt events are append-only');
END;

CREATE TRIGGER IF NOT EXISTS agent_message_no_update
BEFORE UPDATE ON agent_message
BEGIN
  SELECT RAISE(ABORT, 'agent messages are append-only');
END;

CREATE TRIGGER IF NOT EXISTS mechanism_audit_no_update
BEFORE UPDATE ON mechanism_audit
BEGIN
  SELECT RAISE(ABORT, 'mechanism audits are append-only');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_no_update
BEFORE UPDATE ON capability_inventory
BEGIN
  SELECT RAISE(ABORT, 'capability inventory is append-only');
END;

CREATE TRIGGER IF NOT EXISTS capability_source_locator_no_update
BEFORE UPDATE ON capability_source_locator
BEGIN
  SELECT RAISE(ABORT, 'capability source locators are append-only');
END;

CREATE TRIGGER IF NOT EXISTS directive_source_mapping_no_update
BEFORE UPDATE ON directive_source_mapping
BEGIN
  SELECT RAISE(ABORT, 'directive source mappings are append-only');
END;

CREATE TRIGGER IF NOT EXISTS classification_term_no_update
BEFORE UPDATE ON classification_term
BEGIN
  SELECT RAISE(ABORT, 'classification terms are append-only');
END;

CREATE TRIGGER IF NOT EXISTS classification_scheme_no_update
BEFORE UPDATE ON classification_scheme
BEGIN
  SELECT RAISE(ABORT, 'classification schemes are append-only');
END;

CREATE TRIGGER IF NOT EXISTS directive_classification_no_update
BEFORE UPDATE ON directive_classification
BEGIN
  SELECT RAISE(ABORT, 'directive classifications are append-only');
END;

CREATE TRIGGER IF NOT EXISTS capability_classification_no_update
BEFORE UPDATE ON capability_classification
BEGIN
  SELECT RAISE(ABORT, 'capability classifications are append-only');
END;

CREATE TRIGGER IF NOT EXISTS source_protocol_identity_no_update
BEFORE UPDATE ON source_protocol_identity
BEGIN
  SELECT RAISE(ABORT, 'source protocol identities are append-only');
END;

CREATE TRIGGER IF NOT EXISTS mandate_prompt_lineage_no_update
BEFORE UPDATE ON mandate_prompt_lineage
BEGIN
  SELECT RAISE(ABORT, 'mandate prompt lineage is append-only');
END;

CREATE TRIGGER IF NOT EXISTS artifact_snapshot_no_delete
BEFORE DELETE ON artifact_snapshot
BEGIN
  SELECT RAISE(ABORT, 'artifact snapshots cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS prompt_event_no_delete
BEFORE DELETE ON prompt_event
BEGIN
  SELECT RAISE(ABORT, 'prompt events cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS agent_message_no_delete
BEFORE DELETE ON agent_message
BEGIN
  SELECT RAISE(ABORT, 'agent messages cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS mechanism_audit_no_delete
BEFORE DELETE ON mechanism_audit
BEGIN
  SELECT RAISE(ABORT, 'mechanism audits cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_no_delete
BEFORE DELETE ON capability_inventory
BEGIN
  SELECT RAISE(ABORT, 'capability inventory cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS capability_source_locator_no_delete
BEFORE DELETE ON capability_source_locator
BEGIN
  SELECT RAISE(ABORT, 'capability source locators cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS directive_source_mapping_no_delete
BEFORE DELETE ON directive_source_mapping
BEGIN
  SELECT RAISE(ABORT, 'directive source mappings cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS classification_term_no_delete
BEFORE DELETE ON classification_term
BEGIN
  SELECT RAISE(ABORT, 'classification terms cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS classification_scheme_no_delete
BEFORE DELETE ON classification_scheme
BEGIN
  SELECT RAISE(ABORT, 'classification schemes cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS directive_classification_no_delete
BEFORE DELETE ON directive_classification
BEGIN
  SELECT RAISE(ABORT, 'directive classifications cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS capability_classification_no_delete
BEFORE DELETE ON capability_classification
BEGIN
  SELECT RAISE(ABORT, 'capability classifications cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS source_protocol_identity_no_delete
BEFORE DELETE ON source_protocol_identity
BEGIN
  SELECT RAISE(ABORT, 'source protocol identities cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS mandate_prompt_lineage_no_delete
BEFORE DELETE ON mandate_prompt_lineage
BEGIN
  SELECT RAISE(ABORT, 'mandate prompt lineage cannot be deleted in place');
END;

-- Guard INSERT conflicts before SQLite REPLACE can delete a row. This does
-- not depend on recursive_triggers and also rejects ignored duplicates.
CREATE TRIGGER IF NOT EXISTS artifact_snapshot_no_conflicting_insert
BEFORE INSERT ON artifact_snapshot
WHEN EXISTS (SELECT 1 FROM artifact_snapshot WHERE artifact_id = NEW.artifact_id OR path = NEW.path)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: artifact_snapshot');
END;

CREATE TRIGGER IF NOT EXISTS prompt_event_no_conflicting_insert
BEFORE INSERT ON prompt_event
WHEN EXISTS (SELECT 1 FROM prompt_event WHERE prompt_id = NEW.prompt_id OR (source_artifact_id = NEW.source_artifact_id AND label = NEW.label AND source_anchor = NEW.source_anchor))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: prompt_event');
END;

CREATE TRIGGER IF NOT EXISTS agent_message_no_conflicting_insert
BEFORE INSERT ON agent_message
WHEN EXISTS (SELECT 1 FROM agent_message WHERE message_id = NEW.message_id OR (thread_id = NEW.thread_id AND sequence_no = NEW.sequence_no))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: agent_message');
END;

CREATE TRIGGER IF NOT EXISTS mechanism_audit_no_conflicting_insert
BEFORE INSERT ON mechanism_audit
WHEN EXISTS (SELECT 1 FROM mechanism_audit WHERE mechanism_id = NEW.mechanism_id)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: mechanism_audit');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_no_conflicting_insert
BEFORE INSERT ON capability_inventory
WHEN EXISTS (SELECT 1 FROM capability_inventory WHERE capability_id = NEW.capability_id OR (source_system = NEW.source_system AND source_path = NEW.source_path AND logical_name = NEW.logical_name AND source_role = NEW.source_role))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: capability_inventory');
END;

CREATE TRIGGER IF NOT EXISTS capability_source_locator_no_conflicting_insert
BEFORE INSERT ON capability_source_locator
WHEN EXISTS (SELECT 1 FROM capability_source_locator WHERE locator_id = NEW.locator_id OR (capability_id = NEW.capability_id AND source_path = NEW.source_path))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: capability_source_locator');
END;

CREATE TRIGGER IF NOT EXISTS directive_source_mapping_no_conflicting_insert
BEFORE INSERT ON directive_source_mapping
WHEN EXISTS (SELECT 1 FROM directive_source_mapping WHERE mapping_id = NEW.mapping_id OR (directive_id = NEW.directive_id AND source_system = NEW.source_system AND source_path = NEW.source_path AND source_anchor = NEW.source_anchor))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: directive_source_mapping');
END;

CREATE TRIGGER IF NOT EXISTS classification_term_no_conflicting_insert
BEFORE INSERT ON classification_term
WHEN EXISTS (SELECT 1 FROM classification_term WHERE scheme_id = NEW.scheme_id AND axis_id = NEW.axis_id AND term_id = NEW.term_id)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: classification_term');
END;

CREATE TRIGGER IF NOT EXISTS classification_scheme_no_conflicting_insert
BEFORE INSERT ON classification_scheme
WHEN EXISTS (SELECT 1 FROM classification_scheme WHERE scheme_id = NEW.scheme_id)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: classification_scheme');
END;

CREATE TRIGGER IF NOT EXISTS directive_classification_no_conflicting_insert
BEFORE INSERT ON directive_classification
WHEN EXISTS (SELECT 1 FROM directive_classification WHERE directive_id = NEW.directive_id AND scheme_id = NEW.scheme_id AND axis_id = NEW.axis_id AND temporal_scope = NEW.temporal_scope AND (term_id = NEW.term_id OR rank = NEW.rank))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: directive_classification');
END;

CREATE TRIGGER IF NOT EXISTS capability_classification_no_conflicting_insert
BEFORE INSERT ON capability_classification
WHEN EXISTS (SELECT 1 FROM capability_classification WHERE capability_id = NEW.capability_id AND scheme_id = NEW.scheme_id AND axis_id = NEW.axis_id AND temporal_scope = NEW.temporal_scope AND (term_id = NEW.term_id OR rank = NEW.rank))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: capability_classification');
END;

CREATE TRIGGER IF NOT EXISTS source_protocol_identity_no_conflicting_insert
BEFORE INSERT ON source_protocol_identity
WHEN EXISTS (SELECT 1 FROM source_protocol_identity WHERE protocol_artifact_id = NEW.protocol_artifact_id OR source_path = NEW.source_path)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: source_protocol_identity');
END;

CREATE TRIGGER IF NOT EXISTS mandate_prompt_lineage_no_conflicting_insert
BEFORE INSERT ON mandate_prompt_lineage
WHEN EXISTS (SELECT 1 FROM mandate_prompt_lineage WHERE mandate_id = NEW.mandate_id AND (source_prompt_id = NEW.source_prompt_id OR lineage_ordinal = NEW.lineage_ordinal))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: mandate_prompt_lineage');
END;

CREATE VIEW IF NOT EXISTS message_board AS
SELECT m.thread_id, m.sequence_no, m.message_id, m.sent_at,
       s.agent_id AS sender, r.agent_id AS recipient,
       m.message_kind, m.work_id, w.status AS work_status,
       m.body, m.artifact_revision
FROM agent_message AS m
JOIN agent AS s ON s.agent_id = m.sender_agent_id
LEFT JOIN agent AS r ON r.agent_id = m.recipient_agent_id
LEFT JOIN work_item AS w ON w.work_id = m.work_id
ORDER BY m.thread_id, m.sequence_no;

CREATE VIEW IF NOT EXISTS claimed_work_without_open_claim AS
SELECT w.work_id, w.title, w.owner_agent_id
FROM work_item AS w
WHERE w.status = 'claimed'
  AND NOT EXISTS (
    SELECT 1 FROM work_claim AS c
    WHERE c.work_id = w.work_id AND c.released_at IS NULL
  );

CREATE VIEW IF NOT EXISTS capability_locator_coverage AS
SELECT capability_kind, source_system,
       sum(CASE WHEN source_path LIKE '<%' THEN 1 ELSE 0 END)
         AS explicit_placeholder_locators,
       sum(CASE WHEN source_path NOT LIKE '<%' THEN 1 ELSE 0 END)
         AS named_locator_candidates,
       count(*) AS capability_rows
FROM capability_inventory
GROUP BY capability_kind, source_system;

CREATE VIEW IF NOT EXISTS prompt_integrity AS
SELECT p.prompt_id, p.ordinal, p.label, p.availability,
       p.sha256, a.path AS source_path, a.sha256 AS source_sha256,
       p.integrity_note
FROM prompt_event AS p
JOIN artifact_snapshot AS a ON a.artifact_id = p.source_artifact_id
ORDER BY p.ordinal, p.prompt_id;

CREATE VIEW IF NOT EXISTS formal_authority_non_green AS
SELECT * FROM formal_tool_authority;

CREATE VIEW IF NOT EXISTS mechanism_non_green AS
SELECT * FROM mechanism_audit
WHERE operational_credit = 0
   OR observed_status IN (
     'implemented_unavailable', 'partial', 'mock', 'unsafe_legacy',
     'documented_only', 'absent', 'historical_evidence'
   );

CREATE VIEW IF NOT EXISTS capability_non_green AS
SELECT * FROM capability_inventory
WHERE executor_state != 'implemented_observed'
   OR disposition IN ('quarantine', 'exclude', 'pending_freeze');

CREATE VIEW IF NOT EXISTS directive_mapping_coverage AS
SELECT d.directive_id, d.category, d.title, d.current_status,
       count(m.mapping_id) AS source_mapping_count,
       d.target_owner, d.target_path, d.admission_gate
FROM directive_superset AS d
LEFT JOIN directive_source_mapping AS m ON m.directive_id = d.directive_id
GROUP BY d.directive_id, d.category, d.title, d.current_status,
         d.target_owner, d.target_path, d.admission_gate;

CREATE VIEW IF NOT EXISTS directive_classification_coverage AS
SELECT s.scheme_id, d.directive_id,
       count(DISTINCT c.axis_id) AS classified_axes,
       sum(CASE WHEN c.rank = 1 THEN 1 ELSE 0 END) AS primary_terms,
       sum(CASE WHEN c.rank = 1 AND c.classification_status = 'reviewed'
                THEN 1 ELSE 0 END) AS reviewed_primary_terms,
       CASE WHEN count(DISTINCT c.axis_id) = 9
                  AND sum(CASE WHEN c.rank = 1 THEN 1 ELSE 0 END) = 9
                  AND sum(CASE WHEN c.rank = 1 AND c.classification_status = 'reviewed'
                               THEN 1 ELSE 0 END) = 9
            THEN 1 ELSE 0 END AS complete
FROM classification_scheme AS s
CROSS JOIN directive_superset AS d
LEFT JOIN directive_classification AS c
  ON c.directive_id = d.directive_id
 AND c.scheme_id = s.scheme_id
 AND c.temporal_scope = 'target'
GROUP BY s.scheme_id, d.directive_id;

CREATE VIEW IF NOT EXISTS capability_classification_coverage AS
SELECT s.scheme_id, i.capability_id, i.capability_kind, i.source_system,
       count(DISTINCT c.axis_id) AS classified_axes,
       sum(CASE WHEN c.rank = 1 THEN 1 ELSE 0 END) AS primary_terms,
       sum(CASE WHEN c.rank = 1 AND c.classification_status = 'reviewed'
                THEN 1 ELSE 0 END) AS reviewed_primary_terms,
       CASE WHEN count(DISTINCT c.axis_id) = 9
                  AND sum(CASE WHEN c.rank = 1 THEN 1 ELSE 0 END) = 9
                  AND sum(CASE WHEN c.rank = 1 AND c.classification_status = 'reviewed'
                               THEN 1 ELSE 0 END) = 9
            THEN 1 ELSE 0 END AS complete
FROM classification_scheme AS s
CROSS JOIN capability_inventory AS i
LEFT JOIN capability_classification AS c
  ON c.capability_id = i.capability_id
 AND c.scheme_id = s.scheme_id
 AND c.temporal_scope = 'current'
GROUP BY s.scheme_id, i.capability_id, i.capability_kind, i.source_system;
