INSERT INTO mandate_revision
(mandate_id,source_prompt_id,formal_spec_artifact_id,schema_artifact_id,derivation_method,status,created_at,supersedes_id)
SELECT 'UOS-MANDATE-v1', prompt_id, 'ART-SPEC-UOS-V1', 'ART-SPEC-SCHEMA-V1',
       'Draft interpretation anchored to the first captured cumulative prompt. Subsequent capture does not establish semantic incorporation; every lineage input awaits explicit clause-level review.',
       'draft', '2026-09-05T00:00:00+02:00', NULL
FROM prompt_event
WHERE prompt_id GLOB 'CURR-*'
ORDER BY ordinal ASC LIMIT 1;

INSERT INTO mandate_prompt_lineage
(mandate_id,source_prompt_id,lineage_ordinal,lineage_role,derivation_note)
SELECT 'UOS-MANDATE-v1', prompt_id, ordinal,
       CASE WHEN ordinal = 1 THEN 'base'
            WHEN ordinal = (SELECT max(ordinal) FROM prompt_event WHERE prompt_id GLOB 'CURR-*') THEN 'terminal'
            ELSE 'continuation' END,
       CASE WHEN ordinal = 1
            THEN 'Captured cumulative base; clause-level interpretation remains unreviewed.'
            WHEN ordinal = (SELECT max(ordinal) FROM prompt_event WHERE prompt_id GLOB 'CURR-*')
            THEN 'Latest captured continuation, not a claim of incorporation into the unchanged formal specification.'
            ELSE 'Captured continuation awaiting semantic incorporation and clause-level review.' END
FROM prompt_event
WHERE prompt_id GLOB 'CURR-*'
ORDER BY ordinal;

INSERT INTO formal_clause VALUES
('CLAUSE-ROOT','UOS-MANDATE-v1','target','/target','All admitted UOS artifacts converge below /home/an/NAS-setup/uos in a standalone Jujutsu repository.','composite_gate','planned'),
('CLAUSE-NO-BG','UOS-MANDATE-v1','prohibition','/prohibitions/0','Bevy and Graphite code, dependency and runtime roles are excluded.','composite_gate','planned'),
('CLAUSE-LANG','UOS-MANDATE-v1','language_boundary','/language_policy','Production owners are Gleam/OTP, bounded OCaml/C/C++/Rust NIFs or services, ZigVM, and only Modular Python.','typed_code','planned'),
('CLAUSE-TRACE','UOS-MANDATE-v1','trace_dimension','/trace_space/dimensions','Traceability is scalar across eight independently classified dimensions.','schema','planned'),
('CLAUSE-PACKET','UOS-MANDATE-v1','artifact_field','/trace_space/artifact_packet_fields','Every applicable aspect has a complete 13-field packet.','schema','planned'),
('CLAUSE-EVOL','UOS-MANDATE-v1','evolution','/evolution','Fifteen append-only refinement cycles preserve scope and semantic lineage.','composite_gate','planned'),
('CLAUSE-OC','UOS-MANDATE-v1','compatibility','/compatibility_profiles/0','OpenClaw full compatibility is named, pinned, atomic and currently non-green.','composite_gate','planned'),
('CLAUSE-CODE-SPEC','UOS-MANDATE-v1','invariant','/invariants/4','Admission requires fresh working behavior and applicable machine checks at one revision.','composite_gate','planned'),
('CLAUSE-PROMPT','UOS-MANDATE-v1','invariant','/invariants/12','Available prompts and derived obligations retain content and derivation provenance.','schema','planned'),
('CLAUSE-COORD','UOS-MANDATE-v1','invariant','/invariants/13','Agent coordination is append-only, addressed, correlated, acknowledged and revision-bound.','schema','planned'),
('CLAUSE-CLASS','UOS-MANDATE-v1','invariant','/classification_policy','Every subject receives orthogonal ontology, process-family, SDLC, SRE, plane, process-type, authority, lifecycle and disposition classifications without upgrading readiness.','schema','planned'),
('CLAUSE-SQLITE-API','UOS-MANDATE-v1','invariant','/invariants/17','SQLite materialization and mutation use a typed Gleam sqlight boundary with parameter binding and exact BLOB ingestion; shell SQLite, interpolation, readfile(), Bash and Perl have no write authority.','composite_gate','implemented_planning_only');

INSERT INTO agent VALUES
('AGENT-CODEX-ROOT','OpenAI','Codex','current','primary planner/integrator','advisory author; no self-admission','active','2026-09-05T00:00:00+02:00'),
('AGENT-AGY','AGY',NULL,'high','independent architecture reviewer','advisory reviewer; no self-admission','planned',NULL),
('AGENT-CLAUDE-FABLE','Anthropic','Claude Fable','max','independent architecture reviewer','advisory reviewer; no self-admission','planned',NULL),
('AGENT-CODEX-REVIEW','OpenAI','Codex independent context','high','independent consistency reviewer','advisory reviewer; no self-admission','planned',NULL),
('AGENT-PI','Pi',NULL,NULL,'governed agent/process carrier','no authority until separately admitted','planned',NULL);

INSERT INTO work_item VALUES
('WORK-UOS-PLAN','Close UOS planning and traceability bundle','Review every source family, formalize the mandate, close mappings, run three independent review waves and preserve evidence.','review',100,'AGENT-CODEX-ROOT','planning-pre-jj','2026-09-05T00:00:00+02:00','2026-09-05T00:00:00+02:00'),
('WORK-AGY-REVIEW','AGY three-pass review','Provenance; architecture/safety; sequencing/false-completion review at highest supported effort.','ready',90,'AGENT-AGY','planning-pre-jj','2026-09-05T00:00:00+02:00','2026-09-05T00:00:00+02:00'),
('WORK-CLAUDE-REVIEW','Claude Fable three-pass review','Provenance; architecture/safety; sequencing/false-completion review at max effort.','ready',90,'AGENT-CLAUDE-FABLE','planning-pre-jj','2026-09-05T00:00:00+02:00','2026-09-05T00:00:00+02:00'),
('WORK-CODEX-REVIEW','Independent Codex three-pass review','Definition/reference, architecture and completion-claim audit in an independent context.','ready',90,'AGENT-CODEX-REVIEW','planning-pre-jj','2026-09-05T00:00:00+02:00','2026-09-05T00:00:00+02:00');

INSERT INTO agent_message VALUES
('MSG-UOS-001','THREAD-UOS-PLAN',1,'AGENT-CODEX-ROOT',NULL,'WORK-UOS-PLAN','context',
 'Canonical target is /home/an/NAS-setup/uos; no migration has started. Use source-grounded findings, explicit residuals, and no capability credit from prose.',
 '54dc9e020bd164f8987910c78d039f85bf7838062eb3450a62aa6934ae902dc7',NULL,'planning-pre-jj','2026-09-05T00:00:00+02:00');

INSERT INTO coordination_protocol VALUES
('COORD-TYPED-MESSAGE-v1','message_schema','UOS','docs/journal/uos-planning-ledger/001_schema.sql','source_backed',
 'Append-only thread sequence with sender, recipient, work item, kind, causation, content digest, revision and delivery acknowledgement.',
 'Generated-snapshot schema constraints and views are materialized in the planning ledger; rebuilds do not preserve ad-hoc events and runtime transport remains planned.'),
('COORD-SYSML-v1','SysML','Harness-Bionic/UOS',NULL,'planned',
 'Model agent blocks, ports, item flows, states, activities, requirements and verification cases; source authority still under audit.',
 'No current SysML execution or build-gate claim.'),
('COORD-FPRIME-v1','FPrime','Harness-Bionic/UOS',NULL,'planned',
 'Map only source-backed F Prime components, ports, commands, events, telemetry and topology if found; otherwise retain an absent finding.',
 'No current F Prime runtime or generation claim.');
