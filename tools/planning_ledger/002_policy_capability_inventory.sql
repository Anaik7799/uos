PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS source_policy_identity (
  policy_id TEXT PRIMARY KEY,
  source_system TEXT NOT NULL,
  provider TEXT NOT NULL,
  locator TEXT NOT NULL UNIQUE,
  canonical_locator TEXT NOT NULL,
  source_revision TEXT,
  content_sha256 TEXT NOT NULL CHECK (length(content_sha256) = 64),
  byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
  identity_kind TEXT NOT NULL CHECK (identity_kind IN (
    'transitional_authority', 'source_input', 'provider_projection',
    'supplemental_provider_input', 'scoped_policy', 'historical_snapshot'
  )),
  relationship TEXT NOT NULL CHECK (relationship IN (
    'canonical', 'divergent_peer', 'byte_identical_peer',
    'symlink_projection', 'scoped_constraint', 'historical_only'
  )),
  authority_class TEXT NOT NULL CHECK (authority_class IN (
    'transitional_root', 'A0_reference', 'none'
  )),
  observed_at TEXT NOT NULL,
  evidence TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS capability_inventory_summary (
  inventory_summary_id TEXT PRIMARY KEY,
  source_system TEXT NOT NULL,
  source_revision TEXT,
  source_root TEXT NOT NULL,
  source_path TEXT NOT NULL,
  capability_kind TEXT NOT NULL CHECK (capability_kind IN (
    'skill', 'superpower', 'agent', 'plugin', 'hook', 'mcp_tool',
    'wiki', 'zettelkasten', 'knowledge_management'
  )),
  source_role TEXT NOT NULL CHECK (source_role IN (
    'canonical', 'projection', 'declaration', 'implementation',
    'configured_exposure', 'handler', 'historical'
  )),
  authority_class TEXT NOT NULL CHECK (authority_class IN (
    'A0_reference', 'A1_advisory', 'A2_admission_veto',
    'A3_pure_generation', 'A4_runtime_evidence',
    'A5_direct_effect_forbidden', 'none'
  )),
  observed_count INTEGER NOT NULL CHECK (observed_count >= 0),
  count_unit TEXT NOT NULL,
  observation_status TEXT NOT NULL CHECK (observation_status IN (
    'observed', 'effective_with_projection', 'reported_conflict',
    'absence_observed', 'moving_unfrozen'
  )),
  disposition TEXT NOT NULL CHECK (disposition IN (
    'retain', 'adapt', 'oracle', 'reference', 'generate', 'quarantine',
    'exclude', 'pending_freeze'
  )),
  evidence TEXT NOT NULL,
  observed_at TEXT NOT NULL,
  UNIQUE(source_system, source_path, capability_kind, source_role, count_unit)
) STRICT;

CREATE TRIGGER IF NOT EXISTS source_policy_identity_no_update
BEFORE UPDATE ON source_policy_identity
BEGIN
  SELECT RAISE(ABORT, 'source policy identities are append-only');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_summary_no_update
BEFORE UPDATE ON capability_inventory_summary
BEGIN
  SELECT RAISE(ABORT, 'capability inventory summaries are append-only');
END;

CREATE TRIGGER IF NOT EXISTS source_policy_identity_no_delete
BEFORE DELETE ON source_policy_identity
BEGIN
  SELECT RAISE(ABORT, 'source policy identities cannot be deleted in place');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_summary_no_delete
BEFORE DELETE ON capability_inventory_summary
BEGIN
  SELECT RAISE(ABORT, 'capability inventory summaries cannot be deleted in place');
END;

-- Guard INSERT conflicts before SQLite REPLACE can delete a row. This does
-- not depend on recursive_triggers and also rejects ignored duplicates.
CREATE TRIGGER IF NOT EXISTS source_policy_identity_no_conflicting_insert
BEFORE INSERT ON source_policy_identity
WHEN EXISTS (SELECT 1 FROM source_policy_identity WHERE policy_id = NEW.policy_id OR locator = NEW.locator)
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: source_policy_identity');
END;

CREATE TRIGGER IF NOT EXISTS capability_inventory_summary_no_conflicting_insert
BEFORE INSERT ON capability_inventory_summary
WHEN EXISTS (SELECT 1 FROM capability_inventory_summary WHERE inventory_summary_id = NEW.inventory_summary_id OR (source_system = NEW.source_system AND source_path = NEW.source_path AND capability_kind = NEW.capability_kind AND source_role = NEW.source_role AND count_unit = NEW.count_unit))
BEGIN
  SELECT RAISE(ABORT, 'immutable identity conflict: capability_inventory_summary');
END;

CREATE VIEW IF NOT EXISTS capability_inventory_denominators AS
SELECT source_system, capability_kind, source_role, authority_class,
       observed_count, count_unit, observation_status, disposition,
       source_path, source_revision
FROM capability_inventory_summary
ORDER BY source_system, capability_kind, source_role, source_path;

INSERT INTO ledger_meta (key, value) VALUES
  ('schema_generation', '6'),
  ('target_state', 'UOS target absent; planning ledger only'),
  ('directive_family_count', '38'),
  ('directive_family_count_discrepancy',
   'Reviewer narrative said 34; delivered list contains 38 distinct DIR-* IDs; 38 is materialized.'),
  ('capability_authority_default',
   'All imported source capabilities are inert A0_reference evidence until separately adapted, reviewed and admitted.'),
  ('timestamp_conflict',
   'Harness YYYYMMDD-HHSS and ZigVM YYYYMMDD-HHMMSS remain distinct; canonical UOS-new human timestamp is UNRESOLVED.'),
  ('ntp_assurance',
   'UNKNOWN: no accepted offset-producing probe receipt is bound to this planning ledger.'),
  ('journal_section_count', '13'),
  ('detailed_inventory_state',
   'The 473 rows are a logical-name/family catalog, not a byte-lossless physical manifest. Exact per-item digest, license, executor, provider/body variants, configured-hook entries, external MCP schemas, knowledge child artifacts and frozen-source evidence remain pending.'),
  ('policy_identity_denominators',
   '44 ledger rows = 2 UOS root/projection + 14 external root/provider/historical + 28 first-party scoped policies. The 107-heading denominator covers only five selected root semantic-merge inputs; supplemental/scoped per-heading crosswalks remain pending.'),
  ('c3i_agent_identity_denominators',
   '169 provider/profile placements yield 61 logical names but 111 distinct name+body-digest candidates; 46 names have multiple body digests. Only explicit equivalence witnesses may reduce the 111-candidate provenance denominator.'),
  ('classification_contract',
   'Every directive and every capability item has one primary term on each of nine orthogonal axes; secondary terms preserve cross-cutting semantics without double-counting identities. Kind-default capability classifications remain provisional.'),
  ('harness_revision_coordinates',
   'Harness policy identities retain both dirty working-copy acd4546e629af9c7910afe7451dd5fbc31c3ba45 and parent 8a03c14f47c229db4cb086270b94c618ca8b1e06; directive/capability observations use the working-copy coordinate and do not imply a clean commit.'),
  ('vcs_authority',
   'Future UOS is standalone non-colocated Jujutsu; native Git mutation is forbidden in UOS.');

INSERT INTO source_policy_identity
(policy_id,source_system,provider,locator,canonical_locator,source_revision,
 content_sha256,byte_count,identity_kind,relationship,authority_class,
 observed_at,evidence)
SELECT 'POL-UOS-ROOT-AGENTS','UOS planning workspace','shared','AGENTS.md',
       'AGENTS.md','planning-pre-jj',a.sha256,a.byte_count,'transitional_authority',
       'canonical','transitional_root',a.observed_at,
       'Root transitional authority; artifact bytes are snapshotted in this ledger.'
FROM artifact_snapshot AS a WHERE a.artifact_id = 'ART-POLICY-UOS-ROOT';

INSERT INTO source_policy_identity
(policy_id,source_system,provider,locator,canonical_locator,source_revision,
 content_sha256,byte_count,identity_kind,relationship,authority_class,
 observed_at,evidence)
SELECT 'POL-UOS-ROOT-CLAUDE','UOS planning workspace','Claude','CLAUDE.md',
       'AGENTS.md','planning-pre-jj',a.sha256,a.byte_count,'provider_projection',
       'symlink_projection','transitional_root',a.observed_at,
       'Provider entrypoint is a symlink projection of root AGENTS.md; both paths are snapshotted.'
FROM artifact_snapshot AS a WHERE a.artifact_id = 'ART-POLICY-UOS-CLAUDE';

INSERT INTO source_policy_identity VALUES
('POL-C3I-VM-AGENTS','C3I VM-1','shared','/home/an/dev/ver/c3i/AGENTS.md',
 '/home/an/dev/ver/c3i/AGENTS.md','47f9322329fcda2fdbd7061988f586c65db00d17',
 '5e42d8d59f0600bbd9abadfd2cf6f783a70d84edf865e785cd17b540c4ecb56d',18327,
 'source_input','divergent_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Current loose main ref was observed separately from working-copy bytes; the source is moving/unfrozen and AGENTS diverges from VM CLAUDE.'),
('POL-C3I-VM-CLAUDE','C3I VM-1','Claude','/home/an/dev/ver/c3i/CLAUDE.md',
 '/home/an/dev/ver/c3i/CLAUDE.md','47f9322329fcda2fdbd7061988f586c65db00d17',
 '2fb366bb4ab81b5cf15345be275cedf887ee53cd7029e3300731919a1555d812',39010,
 'source_input','divergent_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Current loose main ref was observed separately from working-copy bytes; the source is moving/unfrozen and CLAUDE diverges from VM AGENTS.'),
('POL-C3I-NAS-AGENTS-HIST','C3I NAS historical','shared','/home/an/NAS-setup/c3i/AGENTS.md',
 '/home/an/NAS-setup/c3i/AGENTS.md',NULL,
 '8e5dc91940d2568edab5f5e8d42930abf268c8a1dba651e16387a3d2107801d0',33820,
 'historical_snapshot','byte_identical_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Historical snapshot; byte-identical to its NAS CLAUDE peer and divergent from both corresponding VM-1 files.'),
('POL-C3I-NAS-CLAUDE-HIST','C3I NAS historical','Claude','/home/an/NAS-setup/c3i/CLAUDE.md',
 '/home/an/NAS-setup/c3i/AGENTS.md',NULL,
 '8e5dc91940d2568edab5f5e8d42930abf268c8a1dba651e16387a3d2107801d0',33820,
 'historical_snapshot','byte_identical_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Historical snapshot; byte-identical to NAS AGENTS and retained without making it current authority.'),
('POL-ZIGVM-AGENTS','ZigVM VM-1','shared','/home/an/dev/ver/zigvm/AGENTS.md',
 '/home/an/dev/ver/zigvm/AGENTS.md','3cf87fedbc51e37c64eee057c30a553f9d346170',
 '1cc92910a02e70235f6c4741410059b7ecfa7f34ee0e4cdf07943813aa1edc3b',29080,
 'source_input','divergent_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Current loose master ref was observed separately from working-copy bytes; ZigVM AGENTS and CLAUDE are distinct inputs.'),
('POL-ZIGVM-CLAUDE','ZigVM VM-1','Claude','/home/an/dev/ver/zigvm/CLAUDE.md',
 '/home/an/dev/ver/zigvm/CLAUDE.md','3cf87fedbc51e37c64eee057c30a553f9d346170',
 '78ee00f784d9ebd63423c8ae4c237f481d7dfe1112c01bf2a3f9b51de53315ab',32105,
 'source_input','divergent_peer','A0_reference','2026-09-05T09:31:36+02:00',
 'Current loose master ref was observed separately from working-copy bytes; ZigVM CLAUDE and AGENTS are distinct inputs.'),
('POL-HARNESS-AGENTS','Harness-Bionic','shared','/home/an/NAS-setup/harness-bionic/AGENTS.md',
 '/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45-parent-8a03c14f47c229db4cb086270b94c618ca8b1e06',
 '617ea841a366dba6a8c5c7590b85729a5d9b4fea6870de45facee14dfa87e805',9020,
 'source_input','canonical','A0_reference','2026-09-05T09:31:36+02:00',
 'The /home/an/dev/ver/harness-bionic locator resolves to this same filesystem identity; inventory once and retain both locators.'),
('POL-HARNESS-CLAUDE','Harness-Bionic','Claude','/home/an/dev/ver/harness-bionic/CLAUDE.md',
 '/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45-parent-8a03c14f47c229db4cb086270b94c618ca8b1e06',
 '617ea841a366dba6a8c5c7590b85729a5d9b4fea6870de45facee14dfa87e805',9020,
 'provider_projection','symlink_projection','A0_reference','2026-09-05T09:31:36+02:00',
 'Symlink projection of Harness AGENTS.md.'),
('POL-HARNESS-CODEX','Harness-Bionic','Codex','/home/an/dev/ver/harness-bionic/CODEX.md',
 '/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45-parent-8a03c14f47c229db4cb086270b94c618ca8b1e06',
 '617ea841a366dba6a8c5c7590b85729a5d9b4fea6870de45facee14dfa87e805',9020,
 'provider_projection','symlink_projection','A0_reference','2026-09-05T09:31:36+02:00',
 'Symlink projection of Harness AGENTS.md.'),
('POL-HARNESS-GEMINI','Harness-Bionic','Gemini','/home/an/dev/ver/harness-bionic/GEMINI.md',
 '/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45-parent-8a03c14f47c229db4cb086270b94c618ca8b1e06',
 '617ea841a366dba6a8c5c7590b85729a5d9b4fea6870de45facee14dfa87e805',9020,
 'provider_projection','symlink_projection','A0_reference','2026-09-05T09:31:36+02:00',
   'Symlink projection of Harness AGENTS.md.');

-- Supplemental provider roots and first-party scoped policies are preserved
-- separately from the five-file semantic merge baseline. Their presence can
-- constrain a provider/module scope but cannot silently expand UOS authority.
INSERT INTO source_policy_identity VALUES
('POL-C3I-VM-GEMINI','C3I VM-1','Gemini','/home/an/dev/ver/c3i/GEMINI.md','/home/an/dev/ver/c3i/GEMINI.md','47f9322329fcda2fdbd7061988f586c65db00d17','d392659ef984ed2fa6fa515c3c3dc6b91ade9c37cc2b65a43ec79e7d602ebd17',39128,'supplemental_provider_input','divergent_peer','A0_reference','2026-09-05T12:24:56+02:00','Distinct provider policy with Gemini-specific subjects; retained for a future heading-to-directive crosswalk.'),
('POL-C3I-VM-CODEX-AGENTS','C3I VM-1','Codex','/home/an/dev/ver/c3i/.codex/AGENTS.md','/home/an/dev/ver/c3i/.codex/AGENTS.md','47f9322329fcda2fdbd7061988f586c65db00d17','349d7ddf9e731b7d18ed51112a1067b1f25bf848980d4e0478af36b1a049746b',1040,'supplemental_provider_input','divergent_peer','A0_reference','2026-09-05T12:24:56+02:00','Repository-local Codex policy; retained separately from the root AGENTS/CLAUDE merge baseline.'),
('POL-ZIGVM-CODEX','ZigVM VM-1','Codex','/home/an/dev/ver/zigvm/CODEX.md','/home/an/dev/ver/zigvm/CODEX.md','3cf87fedbc51e37c64eee057c30a553f9d346170','d751dedb1249cf8ad3ee5891a23bd7ecf145c3147e80d98e44c9871d6afaf0f1',22957,'supplemental_provider_input','divergent_peer','A0_reference','2026-09-05T12:24:56+02:00','Distinct Codex control-plane/toolchain subjects; future semantic crosswalk required.'),
('POL-ZIGVM-GEMINI','ZigVM VM-1','Gemini','/home/an/dev/ver/zigvm/GEMINI.md','/home/an/dev/ver/zigvm/GEMINI.md','3cf87fedbc51e37c64eee057c30a553f9d346170','5231cfc7c098f14c30d90736facf7ab9de423c2e9ac739323bb74f16eef57325',29109,'supplemental_provider_input','divergent_peer','A0_reference','2026-09-05T12:24:56+02:00','Distinct Gemini provider policy; future semantic crosswalk required.'),
('POL-C3I-SUBPROJECT-AGENTS','C3I VM-1','shared','/home/an/dev/ver/c3i/sub-projects/c3i/AGENTS.md','/home/an/dev/ver/c3i/AGENTS.md','47f9322329fcda2fdbd7061988f586c65db00d17','be860cca9423bce6f6d2f9d4ae3c2382813ec4deedecd68e6fb0c0b700b80858',14448,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','First-party subproject policy; scope must be retained during source mapping.'),
('POL-C3I-SUBPROJECT-CLAUDE','C3I VM-1','Claude','/home/an/dev/ver/c3i/sub-projects/c3i/CLAUDE.md','/home/an/dev/ver/c3i/CLAUDE.md','47f9322329fcda2fdbd7061988f586c65db00d17','2fb366bb4ab81b5cf15345be275cedf887ee53cd7029e3300731919a1555d812',39010,'scoped_policy','byte_identical_peer','A0_reference','2026-09-05T12:24:56+02:00','Byte-identical scoped placement of the root C3I CLAUDE policy.'),
('POL-C3I-SUBPROJECT-GEMINI','C3I VM-1','Gemini','/home/an/dev/ver/c3i/sub-projects/c3i/GEMINI.md','/home/an/dev/ver/c3i/GEMINI.md','47f9322329fcda2fdbd7061988f586c65db00d17','d392659ef984ed2fa6fa515c3c3dc6b91ade9c37cc2b65a43ec79e7d602ebd17',39128,'scoped_policy','byte_identical_peer','A0_reference','2026-09-05T12:24:56+02:00','Byte-identical scoped placement of the root C3I GEMINI policy.'),
('POL-C3I-SCRIPTS-GLEAM-AGENTS','C3I VM-1','shared','/home/an/dev/ver/c3i/sub-projects/scripts-gleam/AGENTS.md','/home/an/dev/ver/c3i/sub-projects/scripts-gleam/AGENTS.md','47f9322329fcda2fdbd7061988f586c65db00d17','1e47823d274778aebfe79cf5ee68ae8529345085d4a7f26ffeb223e3589557f3',4124,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','First-party scripts-Gleam scoped policy; target adaptation must obey the Gleam/OCaml executable rule.'),
('POL-HARNESS-MOD-FETCH-COWBOY','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/fetch_cowboy/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','74406b763c7652a7543fe831245ddf4ace52695f3e62493592f42ac91c099ee2',2341,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-GATEWAY','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/gateway/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','7fe9922beb72cc75e88f22773f1ef3842283156ff79c361dd599e64fe6a271b3',1379,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-AGENT-LOOP','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_agent_loop/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','9056e826e8d17468107cc31eecdddf30ec985975f7a0fda3eae5b7db0a2c39ee',4800,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-CLI','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_cli/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','02b9e8830c9fef11a27b88d0a1caa61481f9594852059e260c69cddaba4562d9',1382,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-DEPENDABILITY','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_dependability/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','14d0a82abca40c859961a93cb2bbd10d2530d061ddba80ba6c2642ee745a6391',4851,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-DUNE-GRAPH','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_dune_graph/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','2df2c47cd347f88d7ebc2ee3a042c59de25b7410d0056e82e8ae400b271871b4',2514,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-FPP','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_fpp_authority/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','f8e2f4c17895bd291c77f6ab0fdf452151dcf3766b571fabcbe4cd3b662c3f22',2490,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-HARNESS','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_harness/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','456a8a9253e716754fd04e6044652ca7318f8a2fd4ef26c3a9a57cb67a2efaa3',12545,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-STUBBER','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_harness_stubber/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','a205fc9f57c7af422b36ae07b2275e576e31965a3042b04da4f68dfcfb1bd6ef',2392,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-NIX','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_nix/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','4175e2518ff36c379020aeaef2660f660b6d40a42e2e3f6293483e8d5728fb23',1981,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-OPS','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_ops/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','0ba9551e2e296c3b69b884fbe2a0746554cd2d6d80211dc711917d85352ef4d1',4689,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-OPS-DASH','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_ops_dashboard/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','3dcc60e62068ca04623e5f910698a31eeb09860c0cb080dc3b03817226c9b8e4',3550,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SERVER','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_server/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','d408b5a54668d72781d6298b725263a9dbb91a9b119a8df664814f778018d6a4',2412,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SQLITE','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_sqlite/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','f6bc65a25e545804593ba5e4aa9403fbc53d30e1e8e23af3f3e2765d25619fe8',1385,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-STANZA','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_stanza/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','90dc64267286063918985c779177dea9dcea84274c3600f444ea1a86de8d5062',1416,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SYSML','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_sysml/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','14c1fdca1a7c468917c1106a203a2d87f48225cf0b0a0970a3417e225a2ec117',2734,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-TOOLCHAIN','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_toolchain/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','ee6ced44c9f96b2d05997959157ada45ef6d9083fefc7ab9c633e48e453bc17e',2522,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-VCS','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_vcs/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','ee4aed9f4a07bede4438212755281cdb9106648d0d7d254ee364f8d1603bffbb',3515,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-VISION','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_vision/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','67bf868648cb5f1b9379686a9b62228c3bba52c79b9cc98aec3d3876bcc6b2ef',2781,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-WIKI','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_wiki/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','be1d42d982b329f03fc8e2f5359c5f8300bdd9b8c041905850de76ce3ccf46c6',5775,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-ZELLIJ','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/hermes_zellij/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','79ecba13067309390ac12d58d684ca1bed6e808184c5f07f2dbad323ab6022fc',2636,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SA-PLAN','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/sa_plan/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','7a106d9f2c13eb0a28280aafc7e9d433662de3edb3a399d490879d148a8b8846',2355,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SWARM','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/swarm/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','a68be6746cf3c78407417f55658dc0d367300fe99496e226c7949345f6b9e018',4729,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.'),
('POL-HARNESS-MOD-SYSTEM-ENGG','Harness-Bionic','shared','/home/an/dev/ver/harness-bionic/modules/system_engg/AGENTS.md','/home/an/NAS-setup/harness-bionic/AGENTS.md','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','1804c407f24fc3ebdf9cc8ba758c5227f189b17588a6e1e804c962edfacae557',3227,'scoped_policy','scoped_constraint','A0_reference','2026-09-05T12:24:56+02:00','Harness module-scoped policy.');

INSERT INTO capability_inventory_summary VALUES
('CAPSUM-ZIGVM-SKILLS','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','skills/*/SKILL.md','skill','canonical','A0_reference',31,'top-level skill identities','moving_unfrozen','adapt','Focused inventory counted 31 current top-level skill identities; presence grants no executor credit.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-AGENTS','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/agents source profiles','agent','canonical','A0_reference',5,'ZigVM-authored semantic profile identities','moving_unfrozen','adapt','Five authored profiles; docs/agents also contains one non-profile formal-methods SOP.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-AGENT-DOCS','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/agents/*.md','agent','declaration','A0_reference',6,'agent-related Markdown documents','moving_unfrozen','reference','Five authored profiles plus FORMAL_METHODS_AGENT_SOP; the SOP is not an agent identity.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-AGENT-NAME-UNION','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/agents + Harness-derived provider adapters','agent','declaration','A0_reference',9,'cross-source unique profile names','moving_unfrozen','adapt','Five ZigVM names plus five Harness-origin names have one basename collision; nine is a name union only.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-AGENT-IDENTITY-CANDIDATES','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/agents + Harness-derived provider adapters','agent','declaration','A0_reference',10,'source-bound semantic identity candidates','moving_unfrozen','pending_freeze','The two full-symbiosis-supervisor bodies differ; keep ten source-bound candidates until equivalence is witnessed.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-AGENT-TOP-PROJECTION','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','provider top-level agent symlinks','agent','projection','A0_reference',4,'ZigVM-authored projections per provider','moving_unfrozen','generate','Only the four symbiosis supervisors are top-level projected; tyxml and the SOP are unprojected.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-HARNESS-ADAPTERS','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','provider nested Harness adapters','agent','projection','A0_reference',5,'Harness-origin adapter projections per provider','moving_unfrozen','generate','Five Harness-origin adapters are mirrored per provider; they retain Harness provenance.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-SKILL-PROJECTIONS','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','provider skill projections','skill','projection','A0_reference',25,'projected skill identities per provider','moving_unfrozen','generate','Twenty-five of 31 current canonical skill identities are projected; six remain reference-only. Provider placements are projections, not additional logical skills.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-SKILL-REFERENCE','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','skills reference-only set','skill','declaration','A0_reference',6,'reference-only skill identities','moving_unfrozen','reference','c3i-temporal-orchestration, docs-design, formal-verification-pipeline, fractal-workspace-audit, living-ontology and wiki-design are not projected.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-SKILLS','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','.claude/skills/*/SKILL.md','skill','canonical','A0_reference',18,'top-level skill identities','moving_unfrozen','adapt','Current focused inventory counted 18 canonical skills; .agents/skills is the same symlinked corpus and is not double-counted.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-AGENTS','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','.claude/agents/*.md','agent','canonical','A0_reference',5,'semantic agent profiles','moving_unfrozen','adapt','Five canonical Claude profiles; provider files are projections and do not increase the semantic denominator.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-AGENT-PLACEMENTS','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','.{agents,claude,codex}/agents','agent','projection','A0_reference',15,'provider profile placements','moving_unfrozen','generate','Five semantic profiles across three provider surfaces; exact equivalence requires the sync verifier and source freeze.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-AGENTS-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.agents/skills/*/SKILL.md','skill','canonical','A0_reference',11,'top-level skill identities','moving_unfrozen','adapt','Eleven top-level canonical identities; 14 SKILL.md files exist when three nested Allium subskills are counted.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-CLAUDE-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.claude/skills/*/SKILL.md','skill','projection','A0_reference',81,'logical SKILL documents','effective_with_projection','generate','Seventy-seven physical provider SKILL.md files plus the four-SKILL symlinked Allium bundle; projection drift must fail admission.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-GEMINI-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.gemini/skills/*/SKILL.md','skill','projection','A0_reference',81,'logical SKILL documents','effective_with_projection','generate','Seventy-seven physical provider SKILL.md files plus the four-SKILL symlinked Allium bundle; projection drift must fail admission.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-CODEX-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.codex/skills/*/SKILL.md','skill','projection','A0_reference',4,'top-level skill identities','moving_unfrozen','generate','Provider projection count; no execution authority inferred.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-PI-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.pi/skills/*/SKILL.md','skill','projection','A0_reference',40,'role/skill profile identities','moving_unfrozen','adapt','Pi role profiles; presence is not a running-agent or executor count.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-OPENCODE-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.opencode/skills/*.skill','skill','projection','A0_reference',5,'skill declaration files','moving_unfrozen','generate','Provider declarations only; bundled executable and node_modules are excluded.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-AGENTS-AGENTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.agents/agents/*.md','agent','canonical','A0_reference',6,'agent profile identities','moving_unfrozen','adapt','Canonical profile source candidates; not live agents.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-CLAUDE-AGENTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.claude/agents/*.md','agent','projection','A0_reference',60,'agent profile files','moving_unfrozen','generate','Claude provider profile corpus; same-name parity does not prove semantic parity.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-GEMINI-AGENTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.gemini/agents/*.md','agent','projection','A0_reference',60,'agent profile files','moving_unfrozen','generate','Gemini provider profile corpus; three known same-name files diverge from Claude.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-CODEX-AGENTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.codex/agents/*','agent','projection','A0_reference',3,'agent profile files','moving_unfrozen','generate','Codex provider projections; no activation evidence.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-PI-AGENT-PROFILES','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.pi/skills/*/SKILL.md','agent','declaration','A0_reference',40,'role profile identities','moving_unfrozen','adapt','Profiles can describe Pi roles but do not establish running agents.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-SUPERPOWERS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','first-party Superpowers implementation scan','superpower','implementation','none',0,'first-party implementations','absence_observed','reference','No first-party Superpowers implementation was observed; a historical external Harness reference is not an implementation.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-MCP-GLEAM-ADVERTISED','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','lib/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam','mcp_tool','declaration','A0_reference',31,'advertised tool names','reported_conflict','adapt','Advertised denominator is 31 while only 26 are dispatched; mismatch is non-green.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-MCP-GLEAM-DISPATCH','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','lib/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam','mcp_tool','handler','A0_reference',26,'dispatched tool names','reported_conflict','adapt','Five advertised vault tools lack dispatch and two unadvertised aliases dispatch; freeze and regenerate from one registry.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-MCP-RUST-LITERAL','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','sub-projects/c3i/mcp/c3i_server/src/tools','mcp_tool','declaration','A0_reference',23,'literal catalog names','reported_conflict','adapt','Literal source list has 23 names while its summary says 22; denominator must be recomputed after freeze.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-MCP-PI-STATIC','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.pi/mcp-registry-dynamic.ts','mcp_tool','declaration','A0_reference',55,'static registry rows','reported_conflict','exclude','Intended dynamic command is absent; replace with a generated typed registry.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-OPENCODE-NESTED','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','sub-projects/c3i/.opencode/skills','skill','projection','A0_reference',41,'nested skill identities','moving_unfrozen','adapt','Nested OpenCode corpus is source-owned but remains a provider profile set, not an executor set.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-SCRIPTS-GLEAM-SKILLS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','sub-projects/scripts-gleam skills','skill','implementation','A0_reference',8,'skill identities','moving_unfrozen','adapt','Source-owned scripts-Gleam skill set; exact executor correspondence remains to be admitted.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-AGENT-UNION','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','agent profile union','agent','canonical','A0_reference',61,'unique logical agent names','moving_unfrozen','adapt','Union across C3I provider surfaces; provider placements are not added to this semantic denominator.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-PLUGIN-MANIFEST','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','indrajaal-lsp manifest','plugin','declaration','A0_reference',1,'first-party plugin manifest','moving_unfrozen','oracle','Reference/port candidate only.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-PI-EXTENSIONS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.pi extensions','plugin','implementation','A0_reference',4,'source plugin handlers','moving_unfrozen','adapt','TypeScript c3i-bridge, cost-router, pi-lifecycle and zk-recall are semantic sources to port, not UOS executors.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-ORACLE-PLUGINS','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','external/hermes_source/plugins/**/plugin.yaml','plugin','historical','A0_reference',97,'frozen Python oracle manifests','moving_unfrozen','oracle','Reference-oracle catalog across 15 families; zero native UOS executor credit.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-HOOK-CLAUDE','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.claude hook settings','hook','configured_exposure','A0_reference',21,'configured command entries','moving_unfrozen','adapt','Canonicalization must remove hard paths, direct database mutation, suppression and shell/JS effects.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-HOOK-GEMINI','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.gemini hook settings','hook','projection','A0_reference',14,'configured command entries','moving_unfrozen','generate','Provider event semantics differ; projection count is not semantic equivalence.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-HOOK-AGENTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.agents hook settings','hook','projection','A0_reference',7,'configured command entries','moving_unfrozen','generate','Provider projection; bounded typed replacement required.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-HOOK-SOURCE','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','harness/agent_time_hook.ml + harness/run_agent_time_hook.ml','hook','implementation','A0_reference',2,'current OCaml source files','moving_unfrozen','adapt','Older dispatch-hook finding is stale; activation remains unproved.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-HOOK-PROJECTION','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','provider hooks.json','hook','projection','A0_reference',4,'host-clock projections','moving_unfrozen','generate','Current projections invoke an external shell path and are not admitted.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-HOOK-SOURCE','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','modules/system_engg/agent_time_hook*','hook','implementation','A0_reference',3,'OCaml time-hook source files','moving_unfrozen','adapt','Provider projections differ in command language and event semantics.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-MCP','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','harness/mcp_server.ml (11 db tools) + harness/zigvm_harness.ml (26 harness tools and assembly/dispatch)','mcp_tool','implementation','A0_reference',37,'first-party tool definitions','moving_unfrozen','adapt','Current source denominator is 37 across two definition files; stale catalog adds 13 missing forecast/VFS names. Built server was not freshly probed.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-MCP','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','native MCP server','mcp_tool','implementation','A0_reference',1,'native tool definition','moving_unfrozen','adapt','Only hermes_completion is native; ZigVM and Stitch entries are external.','2026-09-05T09:31:36+02:00'),
('CAPSUM-HARNESS-WIKI','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','modules/hermes_wiki','wiki','implementation','A0_reference',95,'source executable and test declarations','moving_unfrozen','adapt','Forty-two source libraries, ten source executables and 43 test declarations; no fresh build/corpus probe.','2026-09-05T09:31:36+02:00'),
('CAPSUM-ZIGVM-ZK-NOTES','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/zk','zettelkasten','implementation','A0_reference',397,'Markdown notes','moving_unfrozen','oracle','Primary semantic/differential corpus; writer paths use wall-clock and native Git and cannot be imported unchanged.','2026-09-05T09:31:36+02:00'),
('CAPSUM-C3I-KNOWLEDGE-MODULES','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','root Gleam knowledge/KMS/Smriti modules','knowledge_management','implementation','A0_reference',9,'first-party root modules','moving_unfrozen','oracle','No first-party wiki engine; modules and ten tests are selective semantic sources with unresolved defects.','2026-09-05T09:31:36+02:00');

INSERT INTO capability_inventory_summary VALUES
('CAPSUM-C3I-AGENT-PLACEMENTS-ALL','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','.{claude,gemini,agents,codex}/agents plus .pi/skills role profiles','agent','projection','A0_reference',169,'provider profile placements','moving_unfrozen','pending_freeze','Observed placements are Claude 60 + Gemini 60 + .agents 6 + Codex 3 + Pi 40. Placements are not semantic identities.','2026-09-05T12:24:56+02:00'),
('CAPSUM-C3I-AGENT-BODY-VARIANTS','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','same five provider/profile roots','agent','declaration','A0_reference',111,'distinct logical-name plus body-digest candidates','moving_unfrozen','pending_freeze','A safe Markdown/profile hash census produced 111 distinct (name, body digest) candidates. These must remain separate until equivalence witnesses permit projection merges; the current 61 capability rows are only a name-union view.','2026-09-05T12:24:56+02:00'),
('CAPSUM-C3I-AGENT-DIVERGENT-NAMES','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','same five provider/profile roots','agent','declaration','A0_reference',46,'logical names with more than one observed body digest','moving_unfrozen','pending_freeze','Forty-six of 61 logical names have multiple body digests across the five provider/profile roots; filename deduplication is prohibited.','2026-09-05T12:24:56+02:00');

-- Item-level rows are derived from the snapshotted machine inventory. They
-- preserve names and source roles, but remain non-green until the source
-- freeze supplies exact per-item digests, licenses, executors and evidence.
WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-ZIGVM-SKILL-' || j.value, 'skill', 'ZigVM VM-1',
       '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm',
       'skills/' || j.value || '/SKILL.md', j.value, 'canonical', NULL, NULL,
       'declaration_only', 'adapt', 'governance/skills/vendor/zigvm/' || j.value,
       'Name is source-observed; item digest/license/executor admission pending frozen manifest.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.skills.zigvm.names') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-HARNESS-SKILL-' || j.value, 'skill', 'Harness-Bionic',
       'jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45',
       '/home/an/NAS-setup/harness-bionic', '.claude/skills/' || j.value || '/SKILL.md',
       j.value, 'canonical', NULL, NULL, 'declaration_only', 'adapt',
       'governance/skills/vendor/harness/' || j.value,
       'Name is source-observed; .agents is a symlink projection and is not double-counted.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.skills.harness.names') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-C3I-CLAUDE-SKILL-' || j.value, 'skill', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       CASE WHEN j.value IN ('distill','elicit','propagate')
            THEN '.claude/skills/allium/skills/' || j.value || '/SKILL.md'
            ELSE '.claude/skills/' || j.value || '/SKILL.md' END,
       j.value, 'projection', NULL, NULL,
       'projection_only', 'adapt', 'governance/skills/vendor/c3i/' || j.value,
       'Primary provider-corpus identity; distill/elicit/propagate are nested Allium bundle members. Canonical/provider relationship and executor require item-level review.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.skills.c3i.primary_names') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
), roots(json_path, prefix, source_path, source_role, target_prefix) AS (
  VALUES
    ('$.skills.c3i.adapters.agents_root.names','CAP-C3I-AGENTS-SKILL-', '.agents/skills/', 'canonical', 'governance/skills/vendor/c3i/'),
    ('$.skills.c3i.adapters.codex.names','CAP-C3I-CODEX-SKILL-', '.codex/skills/', 'projection', 'governance/skills/projections/codex/'),
    ('$.skills.c3i.adapters.pi_role_profiles.names','CAP-C3I-PI-SKILL-', '.pi/skills/', 'projection', 'governance/skills/projections/pi/'),
    ('$.skills.c3i.adapters.nested_opencode.names','CAP-C3I-OPENCODE-SKILL-', 'sub-projects/c3i/.opencode/skills/', 'projection', 'governance/skills/projections/opencode/'),
    ('$.skills.c3i.adapters.scripts_gleam_pi.names','CAP-C3I-SCRIPTS-GLEAM-PI-SKILL-', 'sub-projects/scripts-gleam/.pi/skills/', 'projection', 'governance/skills/projections/pi/')
)
INSERT INTO capability_inventory
SELECT r.prefix || j.value, 'skill', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       r.source_path || j.value || '/SKILL.md', j.value, r.source_role, NULL, NULL,
       CASE WHEN r.source_role = 'canonical' THEN 'declaration_only' ELSE 'projection_only' END,
       'adapt', r.target_prefix || j.value,
       'Source-owned identity retained separately; same-name rows require semantic/body comparison, not basename collapse.',
       '2026-09-05T09:31:36+02:00'
FROM inv JOIN roots AS r JOIN json_each(inv.doc, r.json_path) AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-SUPERPOWER-' || j.value, 'superpower', 'External Superpowers',
       '6.3.0', '/home/an/.codex/plugins/cache/openai-curated-remote/superpowers/6.3.0',
       'skills/' || j.value || '/SKILL.md', j.value, 'declaration', NULL, NULL,
       'declaration_only', 'adapt', 'governance/skills/superpowers/' || j.value,
       'External observed workflow; pin/license and Jujutsu/authority adaptation required.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.skills.external_superpowers.names') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-C3I-AGENT-' || j.value, 'agent', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       '<provider-agent-union>/' || j.value, j.value, 'declaration', NULL, NULL,
       'declaration_only', 'adapt', 'governance/agents/vendor/c3i/' || j.value,
       'Logical union identity; provider placements and body variants remain explicit evidence.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.agents.c3i.names') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
), roots(json_path, prefix, source_path, source_role, target_prefix, source_system, revision, source_root) AS (
  VALUES
    ('$.agents.zigvm.source_profile_names','CAP-ZIGVM-AGENT-', 'docs/agents/', 'canonical', 'governance/agents/vendor/zigvm/', 'ZigVM VM-1', '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm'),
    ('$.agents.zigvm.harness_adapter_names','CAP-ZIGVM-HARNESS-ADAPTER-', '<harness-adapter-projections>/', 'projection', 'governance/agents/projections/', 'ZigVM VM-1', '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm'),
    ('$.agents.harness.names','CAP-HARNESS-AGENT-', '.claude/agents/', 'canonical', 'governance/agents/vendor/harness/', 'Harness-Bionic', 'jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45', '/home/an/NAS-setup/harness-bionic')
)
INSERT INTO capability_inventory
SELECT r.prefix || j.value, 'agent', r.source_system, r.revision, r.source_root,
       r.source_path || j.value ||
         CASE WHEN r.source_path LIKE '<%' THEN '' ELSE '.md' END,
       j.value, r.source_role, NULL, NULL,
       CASE WHEN r.source_role = 'canonical' THEN 'declaration_only' ELSE 'projection_only' END,
       'adapt', r.target_prefix || j.value,
       'Profile/adaptor identity only; native discovery, permissions, lifecycle and executor evidence pending.',
       '2026-09-05T09:31:36+02:00'
FROM inv JOIN roots AS r JOIN json_each(inv.doc, r.json_path) AS j;

INSERT INTO capability_inventory VALUES
('CAP-C3I-PLUGIN-INDRAJAAL-LSP','plugin','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','sub-projects/c3i/.claude/plugins/elixir-lsp/.claude-plugin/plugin.json','indrajaal-lsp','declaration',NULL,NULL,'declaration_only','reference','governance/plugins/indrajaal-lsp','Manifest 3.1.0; no executable handler admitted.','2026-09-05T09:31:36+02:00');

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-C3I-PI-EXT-' || replace(j.value, '.ts', ''), 'plugin', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       '.pi/extensions/' || j.value, j.value, 'implementation', NULL, NULL,
       'implemented_unverified', 'adapt', 'governance/plugins/' || replace(j.value, '.ts', ''),
       'Executable TypeScript semantic source; target implementation must be Gleam/OCaml.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.plugins.c3i_pi_extensions') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-C3I-HOOK-' || j.key, 'hook', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       '<provider-hook-settings>/' || j.value, j.value, 'configured_exposure', NULL, NULL,
       'unknown', 'adapt', 'governance/hooks/' || j.value,
       'Semantic family derived from configured entries; handler/projection equivalence and authority remain unresolved.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.hooks.c3i.semantic_families') AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
), roots(json_path, prefix, source_system, revision, source_root, disposition) AS (
  VALUES
    ('$.hooks.zigvm.authored_ocaml','CAP-ZIGVM-HOOK-', 'ZigVM VM-1', '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm', 'adapt'),
    ('$.hooks.harness.authored_ocaml','CAP-HARNESS-HOOK-', 'Harness-Bionic', 'jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45', '/home/an/NAS-setup/harness-bionic', 'adapt')
)
INSERT INTO capability_inventory
SELECT r.prefix || j.key, 'hook', r.source_system, r.revision, r.source_root,
       j.value, j.value, 'implementation', NULL, NULL, 'implemented_unverified',
       r.disposition, 'governance/hooks/time-sync',
       'Authored OCaml source; provider activation/equivalence is unproved.',
       '2026-09-05T09:31:36+02:00'
FROM inv JOIN roots AS r JOIN json_each(inv.doc, r.json_path) AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-C3I-GLEAM-MCP-' || j.value, 'mcp_tool', 'C3I VM-1',
       '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i',
       'lib/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam#' || j.value,
       j.value, 'implementation', NULL, NULL, 'implemented_unverified', 'adapt',
       'contracts/mcp/tools/' || j.value,
       'Advertised and dispatched Gleam tool; no fresh built/runtime evidence was observed.',
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.mcp.c3i.gleam_advertised_tools') AS j
WHERE CAST(j.key AS INTEGER) < 26;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
), roots(json_path, prefix, kind, source_system, revision, source_root, source_path, source_role, executor_state, disposition, target_prefix, evidence) AS (
  VALUES
    ('$.mcp.zigvm.stale_catalog_extra_tools','CAP-ZIGVM-MCP-STALE-', 'mcp_tool', 'ZigVM VM-1', '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm', '<stale-50-tool-catalog>#', 'historical', 'historical_only', 'reference', 'contracts/mcp/stale/', 'Name appears in stale 50-tool inventory but has no current Mcp.name implementation.'),
    ('$.mcp.harness.native_tools','CAP-HARNESS-MCP-', 'mcp_tool', 'Harness-Bionic', 'jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45', '/home/an/NAS-setup/harness-bionic', 'modules/hermes_ops/ops_mcp.ml#', 'implementation', 'implemented_unverified', 'adapt', 'contracts/mcp/tools/', 'Native Harness MCP tool; not freshly exercised.'),
    ('$.mcp.c3i.rust_tools','CAP-C3I-RUST-MCP-', 'mcp_tool', 'C3I VM-1', '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i', 'sub-projects/c3i/mcp/c3i_server/src/tools#', 'implementation', 'unavailable', 'adapt', 'contracts/mcp/tools/', 'Rust source catalog/dispatch exists, but configured VM binary path is absent.'),
    ('$.mcp.c3i.gleam_dead_dispatch','CAP-C3I-GLEAM-MCP-DEAD-', 'mcp_tool', 'C3I VM-1', '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i', 'lib/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam#', 'declaration', 'declaration_only', 'adapt', 'contracts/mcp/dead/', 'Advertised tool lacks dispatch.'),
    ('$.mcp.c3i.gleam_unadvertised_aliases','CAP-C3I-GLEAM-MCP-ALIAS-', 'mcp_tool', 'C3I VM-1', '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i', 'lib/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam#', 'handler', 'implemented_unverified', 'adapt', 'contracts/mcp/aliases/', 'Handler accepts an unadvertised alias; registry/dispatch mismatch.'),
    ('$.mcp.c3i.kms_tools','CAP-C3I-KMS-MCP-', 'mcp_tool', 'C3I VM-1', '47f9322329fcda2fdbd7061988f586c65db00d17', '/home/an/dev/ver/c3i', 'sub-projects/c3i/lib/indrajaal/kms/mcp_server.ex#', 'declaration', 'unknown', 'oracle', 'contracts/mcp/kms/', 'KMS declaration retained as selective semantic/oracle input; handler execution unproved.')
)
INSERT INTO capability_inventory
SELECT r.prefix || j.value, r.kind, r.source_system, r.revision, r.source_root,
       r.source_path || j.value, j.value, r.source_role, NULL, NULL,
       r.executor_state, r.disposition, r.target_prefix || j.value, r.evidence,
       '2026-09-05T09:31:36+02:00'
FROM inv JOIN roots AS r JOIN json_each(inv.doc, r.json_path) AS j;

WITH inv(doc) AS (
  SELECT CAST(content AS TEXT) FROM artifact_snapshot
  WHERE artifact_id = 'ART-AGENT-CAPABILITY-INVENTORY'
)
INSERT INTO capability_inventory
SELECT 'CAP-ZIGVM-MCP-' || j.value, 'mcp_tool', 'ZigVM VM-1',
       '3cf87fedbc51e37c64eee057c30a553f9d346170', '/home/an/dev/ver/zigvm',
       CASE WHEN j.value IN (
              'facts','observe','graph_contexts','graph_system',
              'graph_analyze_text','graph_export_text','graph_acquire_text',
              'graph_intelligence_text','next_slice','record_cycle','log_ooda'
            )
            THEN 'harness/mcp_server.ml#' || j.value
            ELSE 'harness/zigvm_harness.ml#' || j.value END,
       j.value, 'implementation', NULL, NULL, 'implemented_unverified',
       'adapt', 'contracts/mcp/tools/' || j.value,
       CASE WHEN j.value IN (
              'facts','observe','graph_contexts','graph_system',
              'graph_analyze_text','graph_export_text','graph_acquire_text',
              'graph_intelligence_text','next_slice','record_cycle','log_ooda'
            )
            THEN 'Current source-defined database tool in Mcp.db_tools; composed and dispatched by zigvm_harness. Fresh runtime execution is unrun.'
            ELSE 'Current source-defined harness tool in zigvm_harness; built artifact presence is not fresh runtime verification.' END,
       '2026-09-05T09:31:36+02:00'
FROM inv, json_each(inv.doc, '$.mcp.zigvm.tools') AS j;

INSERT INTO capability_inventory VALUES
('CAP-HARNESS-WIKI','wiki','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','/home/an/NAS-setup/harness-bionic','modules/hermes_wiki','hermes_wiki','implementation',NULL,NULL,'implemented_unverified','adapt','engines/hermes/modules/hermes_wiki','Preferred modular basis; source rich but dirty and not freshly built/corpus-verified.','2026-09-05T09:31:36+02:00'),
('CAP-ZIGVM-ZK','zettelkasten','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','/home/an/dev/ver/zigvm','docs/zk','zigvm-zk','implementation',NULL,NULL,'implemented_unverified','oracle','docs/zettelkasten','Primary corpus/differential oracle; the engine is separately located at harness/docs_wiki.ml; writers use local time and native Git.','2026-09-05T09:31:36+02:00'),
('CAP-C3I-KM','knowledge_management','C3I VM-1','47f9322329fcda2fdbd7061988f586c65db00d17','/home/an/dev/ver/c3i','lib/cepaf_gleam/src/cepaf_gleam/knowledge','c3i-km','implementation',NULL,NULL,'implemented_unverified','oracle','governance/knowledge/km','Primary Gleam knowledge directory; KMS, Smriti and Indrajaal directories are separately located. Selective schemas/behaviors only; known stubs, panics and envelope/ingest defects.','2026-09-05T09:31:36+02:00');

INSERT INTO capability_source_locator
(locator_id,capability_id,source_path,locator_kind,relation,observed_state,evidence) VALUES
('LOC-ZIGVM-ZK-CORPUS','CAP-ZIGVM-ZK','docs/zk','directory','primary','exists_unfrozen','Current Zettelkasten corpus directory; mutable writers are not admitted.'),
('LOC-ZIGVM-ZK-ENGINE','CAP-ZIGVM-ZK','harness/docs_wiki.ml','file','secondary','exists_unfrozen','Principal OCaml wiki/ZK engine candidate.'),
('LOC-C3I-KM-GLEAM-KNOWLEDGE','CAP-C3I-KM','lib/cepaf_gleam/src/cepaf_gleam/knowledge','directory','primary','exists_unfrozen','Root Gleam knowledge modules.'),
('LOC-C3I-KM-GLEAM-KMS','CAP-C3I-KM','lib/cepaf_gleam/src/cepaf_gleam/kms','directory','secondary','exists_unfrozen','Root Gleam KMS modules.'),
('LOC-C3I-KM-GLEAM-SMRITI','CAP-C3I-KM','lib/cepaf_gleam/src/cepaf_gleam/smriti','directory','secondary','exists_unfrozen','Root Gleam Smriti modules.'),
('LOC-C3I-KM-INDRAJAAL-KNOWLEDGE','CAP-C3I-KM','sub-projects/c3i/lib/indrajaal/knowledge','directory','secondary','exists_unfrozen','Indrajaal knowledge subsystem.'),
('LOC-C3I-KM-INDRAJAAL-KMS','CAP-C3I-KM','sub-projects/c3i/lib/indrajaal/kms','directory','secondary','exists_unfrozen','Indrajaal KMS subsystem.'),
('LOC-C3I-KM-INDRAJAAL-SMRITI','CAP-C3I-KM','sub-projects/c3i/lib/indrajaal/smriti','directory','secondary','exists_unfrozen','Indrajaal Smriti subsystem.');

INSERT INTO directive_superset
(directive_id,category,title,normative_text,target_owner,target_path,
 authority_boundary,current_status,admission_gate) VALUES
('DIR-AUTH-001','authority','Authority and precedence','One typed precedence graph governs operator, root policy, source evidence, admission and effect authority.','Gleam policy owner','governance/policy/authority.toml','Source policies remain A0 evidence; operator and admitted root policy govern.','planned','Precedence graph validates and conflicting authority is fail-closed.'),
('DIR-READ-001','source acquisition','Read and source-inspection discipline','Source inspection is read-only, revision/dirty-state aware, redacted and receipted.','OCaml evidence owner','governance/sources/acquisition.toml','No source write or inferred working-copy content.','planned','Freeze manifest, sanitized digest, license and locator all present.'),
('DIR-LANG-001','language','Language and path authority','Every executable and generated artifact obeys the declared Gleam/OCaml/Zig/native/Modular path matrix.','Gleam admission owner','governance/policy/language-boundaries.toml','Vendor bytes are inert; prohibited languages cannot become UOS authority.','planned','Path-language scanner plus build graph passes.'),
('DIR-VCS-001','version control','Jujutsu-only UOS workflow','All active UOS change, commit, operation, bookmark and workspace semantics use standalone Jujutsu.','Gleam change-policy owner','governance/policy/version-control.toml','Native Git mutation in UOS is forbidden.','planned','Mutation audit finds no native Git path and receipts bind JJ identities.'),
('DIR-AUTO-001','autonomy','Bounded autonomy and effect authorization','Autonomous reasoning remains bounded by explicit capabilities, leases, admission and operator authority.','Gleam capability owner','apps/cepaf_gleam/src/uos/policy/autonomy.gleam','No imported instruction transfers standing autonomy.','planned','Negative effect tests and capability-fence tests pass.'),
('DIR-AGT-001','agents','Canonical agent registry','Agent identities, roles, providers, lifecycle and permissions are canonical typed records with generated projections.','Gleam coordination owner','governance/agents/registry.toml','Profile presence is not live-agent credit.','planned','Registry/projection bijection and provider discovery probes pass.'),
('DIR-SYM-001','symbiosis','Cross-agent symbiosis','Claude, Codex, AGY, Gemini and Pi interactions use one addressed, correlated and receipted coordination model.','Gleam coordination owner','governance/agents/symbiosis.toml','Models advise; none self-admits or directly actuates.','planned','Provider adapters pass parity, timeout, cancellation and handover laws.'),
('DIR-SKL-001','skills','Canonical skill registry','Skills retain source identity, trigger, dependencies, permissions, executor and projection freshness.','Gleam registry owner','governance/skills/registry.toml','Imported skill text is inert until admitted.','planned','Every invocable skill has a reachable tested executor and fresh projection.'),
('DIR-SUP-001','superpowers','Superpowers adaptation','Pinned Superpowers workflows are adapted to UOS authority and Jujutsu semantics without treating prose as execution.','Gleam registry owner','governance/skills/superpowers/registry.toml','Git-worktree and push semantics cannot enter active UOS policy.','planned','Semantic adaptation review and executor tests pass.'),
('DIR-HOOK-001','hooks','Hook admission','Hooks are typed, bounded, reversible or observational, and cannot silently mutate or notify externally.','Gleam hook owner','governance/hooks/registry.toml','Source hook configuration is reference-only.','planned','Trigger, timeout, effect, secret and rollback tests pass.'),
('DIR-TOOL-001','tools','Tool capability registry','Every tool has typed input/output, capability, executor, resource bound, evidence and retirement state.','Gleam tool owner','governance/tools/registry.toml','Declaration without handler is non-green.','planned','Registry-handler-test-evidence bijection passes.'),
('DIR-PLAN-001','planning','Planning and trace ledger','Plans, requirements, mappings, decisions and status denominators are normalized in SQLite plus typed code.','Gleam planning-ledger owner','governance/planning/schema.sql','Markdown is a human projection, not state authority; the pre-UOS sqlight NIF backend has no admitted UOS runtime authority.','planned','Schema, foreign keys, integrity and projection drift checks pass.'),
('DIR-GATE-001','admission','Composite admission gates','Admission requires fresh behavior and every applicable machine check at the same candidate revision.','Gleam admission owner','governance/admission/gates.toml','Unknown, unavailable, skipped and stale never become green.','planned','Positive, negative, mutation and freshness controls pass.'),
('DIR-TEST-001','testing','Layered verification taxonomy','Unit, property, integration, differential, conformance, fault, performance and live checks retain separate applicability and evidence.','OCaml evidence owner','governance/verification/test-taxonomy.toml','Counts and filenames alone confer no credit.','planned','Every requirement maps to applicable checks and explicit residuals.'),
('DIR-UI-001','interfaces','Shared operator interface model','Applicable Web, typed API and TUI views share one domain/evidence model and declare non-applicability.','Gleam interface owner','governance/interfaces/applicability.toml','Duplicated mock UI receives no functionality credit.','planned','Cross-view parity and live evidence binding pass.'),
('DIR-AGUI-001','protocols','AG-UI protocol profile','AG-UI events, state, streaming and HITL semantics are typed, bounded and correlated.','Gleam protocol owner','governance/protocols/agui.toml','Protocol messages do not bypass policy or capability checks.','planned','Schema, replay, ordering and cancellation corpus passes.'),
('DIR-A2UI-001','protocols','A2UI protocol profile','A2UI catalog, schema, rendering and validation semantics are mapped without placeholder credit.','Gleam protocol owner','governance/protocols/a2ui.toml','Generated UI remains non-authoritative.','planned','Catalog-renderer-validator bijection and adversarial corpus pass.'),
('DIR-OBS-001','observability','Evidence-bound observability','Logs, metrics, traces and dashboards bind source, revision, action, outcome, freshness and residual state.','Gleam telemetry owner','governance/observability/schema.sql','Telemetry reports; it never self-authorizes effects.','planned','Signal schema, cardinality, redaction and receipt checks pass.'),
('DIR-MCP-001','MCP','MCP registry and dispatch','MCP declarations, configured exposure, dispatch handlers and tests derive from one typed registry.','Gleam MCP owner','governance/mcp/registry.toml','External servers and secret-bearing configs are quarantined until admitted.','planned','Advertise-dispatch-handler-test parity and capability probes pass.'),
('DIR-CONFIG-001','environment','Deterministic configuration','Determinate Nix/devenv pins tools, runtimes, dependencies and build inputs with drift evidence.','Nix configuration owner','governance/environment/toolchain.toml','Configuration cannot silently grant runtime authority.','planned','Locked evaluation, build, provenance and drift checks pass.'),
('DIR-DB-001','data','SQLite authority and migration','Typed migrations, single-writer ownership, integrity and content-addressed evidence govern UOS planning data.','Gleam database owner','governance/planning/schema.sql','Live source databases, WAL and SHM are never copied as source.','planned','Migration replay, FK, integrity, crash and backup/restore tests pass.'),
('DIR-SWARM-001','coordination','Agent message board and swarm','Coordination is append-only, addressed, sequenced, correlated, acknowledged, leased and revision-bound.','Gleam coordination owner','governance/coordination/schema.sql','Synthetic activity and timer simulations receive no execution credit.','planned','Ordering, fencing, replay, cancellation and crash recovery laws pass.'),
('DIR-ALG-001','formal','Algebraic and denotational registry','Algebras, denotations, morphisms, laws and applicability are named, versioned and linked to implementations and evidence.','OCaml formal owner','governance/formal/algebra-registry.toml','Mathematical labels without executable laws are advisory only.','planned','Law suites, mutants and implementation correspondence pass.'),
('DIR-FORMAL-001','formal','Formal-tool operational authority','Formal authority is exact-path, invocation-specific, bounded, fail-closed and effect-free.','OCaml formal owner','governance/formal/tool-authority.toml','Formal results may veto or inform but never directly actuate.','planned','Pinned tool, assumptions, applicability, negative controls and fresh receipts pass.'),
('DIR-RULE-001','rules','Rete-UL rule authority','Rules are canonical typed data and Rete-UL is a bounded final evaluator after independent-oracle agreement.','Gleam rule owner','governance/rules/rete-ul.toml','Rule conclusions do not bypass admission or effects.','planned','Differential oracle, termination, conflict and mutation checks pass.'),
('DIR-BAYES-001','intelligence','Bayesian inference authority','Bayesian models expose priors, data lineage, uncertainty, calibration and advisory-only decision boundaries.','OCaml evidence owner','intelligence/bayesian/registry.toml','Probabilistic output cannot directly authorize an effect.','planned','Calibration, posterior predictive, sensitivity and lineage checks pass.'),
('DIR-SAFE-001','safety','STAMP/STPA and FMEA integration','Control hazards and component failure modes link to constraints, effects, tests, observations, stops and rollback.','Gleam safety owner','governance/safety/control-actions.toml','Safety methods are evidence structures, not proof by declaration.','planned','Unsafe-control-action and failure-mode coverage with residual risks passes review.'),
('DIR-SEC-001','security','Least-authority security','Secrets, identity, data classes and external effects use least authority, redaction, isolation and explicit grants.','Gleam security owner','governance/security/capabilities.toml','Secret bytes are neither copied nor hashed into the ledger.','planned','Secret scan, capability negatives, isolation and audit checks pass.'),
('DIR-HA-001','reliability','Supervision and high availability','OTP supervision, deadlines, cancellation, fencing, backpressure and recovery govern live services.','Gleam supervision owner','apps/cepaf_gleam/src/uos/ha/supervision.gleam','A dashboard label or standby process is not HA evidence.','planned','Fault injection, failover, fencing, recovery and SLO evidence pass.'),
('DIR-INF-001','inference','Inference and provider integration','Pi, chat, voice, Cortex, OpenClaw and local Modular inference are mapped to supervised Gleam adapters and isolated advisory workers.','Gleam inference owner','services/inference','Models and provider adapters never directly authorize external effects.','planned','Model/provider/version/license/resource pins plus timeout, cancellation, fallback and evaluation receipts pass.'),
('DIR-BROWSER-001','oracles','Browser interaction oracle','Browser automation is isolated, pinned and used as a bounded observational/test oracle.','OCaml oracle owner','services/oracles/browser','Browser sessions and credentials cannot become source artifacts.','planned','Pinned adapter, capability bounds, replay and screenshot/DOM evidence pass.'),
('DIR-FIGMA-001','oracles','Figma interaction oracle','Figma operations are explicit external capabilities with pinned adapters, artifact lineage and authorization.','OCaml oracle owner','services/oracles/figma','No external design mutation without operator-authorized effect scope.','planned','Read/write distinction, authorization, artifact and parity checks pass.'),
('DIR-TIME-001','time','Typed time namespaces','Host offset, source system-to-model delta, agent freshness, human formats, protocol time and monotonic duration remain distinct types.','Gleam time-policy owner','governance/time/namespaces.toml','Conflicting source formats remain unresolved and never silently normalize.','conflict_unresolved','Offset receipt, boundary tests, freshness and namespace round trips pass.'),
('DIR-JOURNAL-001','journaling','Exact 13-section journal contract','Every planning, implementation or review journal uses the exact 13 sections with normalized scaling and prompt lineage.','OCaml journal owner','governance/journal/contract.toml','Secret bytes are redacted by presence-only incident records; external delivery requires authorization.','planned','Section/order/schema/link/redaction/hash checks pass.'),
('DIR-PKM-001','knowledge','Wiki, Zettelkasten and KM','Knowledge artifacts preserve semantic IDs, provenance, links, supersession and executable/evidence relationships.','OCaml knowledge owner','engines/hermes/wiki','Rendered pages and embeddings are projections, not independent truth.','planned','Link, source, freshness, duplicate, projection and retrieval checks pass.'),
('DIR-SRE-001','SRE','SRE operational contract','SLOs, indicators, budgets, runbooks, alerts, capacity, incidents, recovery and residual risks bind to live evidence.','Gleam operations owner','governance/sre/contracts.toml','Synthetic or stale telemetry is non-green.','planned','Failure-mode, alert, restore, load and live-readback gates pass.'),
('DIR-DOC-001','documentation','Documentation as generated view','Architecture, runbooks, diagrams and catalogs derive from typed registries and retain source/evidence lineage.','OCaml documentation owner','governance/docs/registry.toml','Markdown cannot override code, database or admitted specs.','planned','Schema, link, diagram and projection-drift checks pass.'),
('DIR-INTF-001','interfaces','Interface and interaction contracts','All cross-component interactions name protocol, data, authority, timing, failure, observation and compatibility semantics.','Gleam protocol owner','governance/interfaces/registry.toml','Undeclared coupling receives no admission.','planned','Contract, conformance, fault, version and traceability checks pass.');

INSERT INTO classification_scheme
(scheme_id,version,definition_artifact_id,temporal_model,status,definition,observed_at)
VALUES
('UOS-CLASSIFICATION-ONTOLOGY-v1','1.0.0','ART-AGENT-POLICY-SUPERSET',
 'current source capability and target directive classifications are distinct',
 'planning',
 'Nine independent axes: ontology class; ONT/SDLC/SRE/CTL/DAT/FRM process family; SDLC phase; SRE function; operational plane; process type; authority role; lifecycle state; migration disposition.',
 '2026-09-05T09:31:36+02:00');

INSERT INTO classification_term
(axis_id,term_id,label,definition) VALUES
('ontology_class','authority','Authority','Precedence, permission or effect-control concepts.'),
('ontology_class','provenance','Provenance','Source identity, lineage, custody and acquisition concepts.'),
('ontology_class','language','Language boundary','Executable-language and path-ownership concepts.'),
('ontology_class','change','Change system','Versioning, change identity and configuration evolution concepts.'),
('ontology_class','agency','Agency','Agent identity, autonomy, role and lifecycle concepts.'),
('ontology_class','interaction','Interaction','Protocol, message and cross-component relationship concepts.'),
('ontology_class','capability','Capability','Skills, powers, permissions and executor-binding concepts.'),
('ontology_class','lifecycle','Lifecycle','Trigger, hook, transition and lifecycle-edge concepts.'),
('ontology_class','tooling','Tooling','Commands, tools, registries and invocation concepts.'),
('ontology_class','planning','Planning','Intent, work, decision and trace-ledger concepts.'),
('ontology_class','assurance','Assurance','Testing, admission, conformance and verification concepts.'),
('ontology_class','interface','Interface','Human, API, TUI, browser and design-surface concepts.'),
('ontology_class','observability','Observability','Logs, metrics, traces, receipts and dashboards.'),
('ontology_class','configuration','Configuration','Environment, dependency, toolchain and declarative configuration.'),
('ontology_class','data','Data','Persistent state, schema, migration and transaction concepts.'),
('ontology_class','coordination','Coordination','Swarm, scheduling, handoff and message-board concepts.'),
('ontology_class','semantics','Semantics','Algebraic, denotational and ontology concepts.'),
('ontology_class','formal_method','Formal method','Machine proof, model checking and solver authority.'),
('ontology_class','rule_system','Rule system','Rule representation, matching and bounded evaluation.'),
('ontology_class','intelligence','Intelligence','Probabilistic, model and inference concepts.'),
('ontology_class','safety','Safety','Hazards, unsafe control actions and failure modes.'),
('ontology_class','security','Security','Identity, secrets, least authority and isolation.'),
('ontology_class','reliability','Reliability','Availability, supervision, failover and recovery.'),
('ontology_class','time','Time','Clock, timestamp, duration, drift and freshness.'),
('ontology_class','knowledge','Knowledge','Wiki, Zettelkasten, KM and archival semantics.'),
('ontology_class','operations','Operations','SLO, runbook, capacity and incident concepts.'),
('ontology_class','documentation','Documentation','Generated human projections, catalogs and records.'),
('process_family','ontological','ONT — ontological','Identity, semantics, taxonomy, registry or projection process.'),
('process_family','sdlc','SDLC','Acquisition, design, build, test, release or evolution process.'),
('process_family','sre','SRE','Reliability, security, observability, time, recovery or cost process.'),
('process_family','control','CTL — control','Authorization, coordination, state transition or effect-control process.'),
('process_family','data','DAT — data','Ingest, validate, persist, query, transform or archive process.'),
('process_family','formal','FRM — formal','Specification, proof, model, oracle, solver or evidence-judgment process.'),
('sdlc_phase','discover','Discover','Inventory and acquire evidence.'),
('sdlc_phase','specify','Specify','State requirements, authority and acceptance semantics.'),
('sdlc_phase','design','Design','Define structures, interfaces and decisions.'),
('sdlc_phase','implement','Implement','Create executable or generated carriers.'),
('sdlc_phase','verify','Verify','Test, prove, compare or inspect behavior.'),
('sdlc_phase','release','Release','Package, admit and cut over a candidate.'),
('sdlc_phase','operate','Operate','Run, observe and control a live system.'),
('sdlc_phase','evolve','Evolve','Refine while preserving lineage and compatibility.'),
('sdlc_phase','retire','Retire','Revoke, archive or remove capability safely.'),
('sdlc_phase','cross_lifecycle','Cross-lifecycle','Applies across multiple SDLC phases.'),
('sre_function','service_level','Service level','SLI/SLO and user-visible service outcomes.'),
('sre_function','observability','Observability','Operational signals, telemetry and readback.'),
('sre_function','incident_response','Incident response','Detection, containment, response and learning.'),
('sre_function','change_management','Change management','Controlled change, rollout and traceability.'),
('sre_function','reliability_engineering','Reliability engineering','Failure prevention, tolerance and recovery.'),
('sre_function','capacity_performance','Capacity and performance','Resource, latency, throughput and efficiency.'),
('sre_function','security_resilience','Security resilience','Operational security, custody and abuse resistance.'),
('sre_function','continuity_recovery','Continuity and recovery','Backup, restore, failover and disaster recovery.'),
('sre_function','operational_readiness','Operational readiness','Admission, runbooks, gates and readiness evidence.'),
('sre_function','knowledge_management','Knowledge management','Durable operational knowledge and learning.'),
('sre_function','not_applicable','Not directly applicable','No direct SRE function; retained explicitly.'),
('operational_plane','governance','Governance plane','Policy, ownership, precedence and admission.'),
('operational_plane','control','Control plane','Intent, coordination, scheduling and actuation control.'),
('operational_plane','data','Data plane','Persistent and flowing domain data.'),
('operational_plane','evidence','Evidence plane','Observations, tests, receipts and audit records.'),
('operational_plane','formal','Formal plane','Specifications, solvers, proofs and models.'),
('operational_plane','intelligence','Intelligence plane','Inference, rules, optimization and decision support.'),
('operational_plane','runtime','Runtime plane','Supervised executing processes and native engines.'),
('operational_plane','interface','Interface plane','Human and machine interaction surfaces.'),
('operational_plane','knowledge','Knowledge plane','Wiki, ZK, KM and semantic memory.'),
('operational_plane','security','Security plane','Identity, secret custody and capability enforcement.'),
('process_type','normative','Normative','Defines what must or must not hold.'),
('process_type','analytical','Analytical','Interprets evidence or computes advice.'),
('process_type','generative','Generative','Produces code, configuration, views or candidates.'),
('process_type','transformational','Transformational','Migrates or translates one representation to another.'),
('process_type','executable','Executable','Runs a bounded operation or service.'),
('process_type','observational','Observational','Reads or records state without authorizing change.'),
('process_type','verification','Verification','Tests, proves or differentially checks claims.'),
('process_type','coordination','Coordination','Sequences or routes work and messages.'),
('process_type','operational','Operational','Maintains a running service or response process.'),
('process_type','archival','Archival','Preserves durable lineage, records or knowledge.'),
('process_type','external_effect','External effect','Can affect a system or recipient outside the planning boundary.'),
('authority_role','normative_policy','Normative policy','Transitional UOS policy requirement.'),
('authority_role','reference_evidence','Reference evidence','Inert source evidence with no execution authority.'),
('authority_role','advisory','Advisory','May inform but cannot admit or actuate.'),
('authority_role','admission_veto','Admission veto','May block admission only within a declared invocation.'),
('authority_role','pure_generation','Pure generation','May generate a candidate but cannot admit it.'),
('authority_role','runtime_evidence','Runtime evidence','May report observed behavior but cannot self-authorize.'),
('authority_role','direct_effect_forbidden','Direct effect forbidden','Must pass through typed policy and an authorized executor.'),
('lifecycle_state','discovered','Discovered','Located but not yet classified.'),
('lifecycle_state','classified','Classified','Assigned ontology and process semantics.'),
('lifecycle_state','mapped','Mapped','Mapped to a UOS owner and target representation.'),
('lifecycle_state','adapted','Adapted','Translated into target-safe semantics.'),
('lifecycle_state','implemented','Implemented','Executable target carrier exists.'),
('lifecycle_state','verified','Verified','Fresh applicable verification passes.'),
('lifecycle_state','admitted','Admitted','Authorized for its declared UOS role.'),
('lifecycle_state','quarantined','Quarantined','Isolated due to secret, safety or provenance risk.'),
('lifecycle_state','excluded','Excluded','Intentionally outside target scope with loss recorded.'),
('lifecycle_state','retired','Retired','Previously admitted identity has been revoked and archived.'),
('lifecycle_state','conflict_unresolved','Conflict unresolved','Cannot advance until incompatible source semantics are resolved.'),
('migration_disposition','retain','Retain','Preserve semantics and representation.'),
('migration_disposition','adapt','Adapt','Preserve semantics through a target-safe translation.'),
('migration_disposition','oracle','Oracle','Use as independent comparison evidence.'),
('migration_disposition','reference','Reference','Retain as non-executable evidence.'),
('migration_disposition','generate','Generate','Produce as a projection from canonical state.'),
('migration_disposition','quarantine','Quarantine','Isolate; do not ingest prohibited bytes or grant authority.'),
('migration_disposition','exclude','Exclude','Do not map into the target implementation.'),
('migration_disposition','pending_freeze','Pending freeze','Defer identity decision until the source is frozen.');

CREATE TEMP TABLE _directive_profile (
  directive_id TEXT PRIMARY KEY,
  ontology_term TEXT NOT NULL,
  sdlc_terms TEXT NOT NULL CHECK (json_valid(sdlc_terms)),
  sre_terms TEXT NOT NULL CHECK (json_valid(sre_terms)),
  plane_terms TEXT NOT NULL CHECK (json_valid(plane_terms)),
  process_terms TEXT NOT NULL CHECK (json_valid(process_terms)),
  authority_terms TEXT NOT NULL CHECK (json_valid(authority_terms)),
  lifecycle_term TEXT NOT NULL,
  disposition_term TEXT NOT NULL
);

INSERT INTO _directive_profile VALUES
('DIR-AUTH-001','authority','["specify","cross_lifecycle"]','["change_management"]','["governance","control"]','["normative","verification"]','["normative_policy"]','mapped','retain'),
('DIR-READ-001','provenance','["discover"]','["knowledge_management"]','["evidence","governance"]','["observational","archival"]','["normative_policy"]','mapped','retain'),
('DIR-LANG-001','language','["design","verify"]','["change_management"]','["governance","formal"]','["normative","verification"]','["normative_policy"]','mapped','adapt'),
('DIR-VCS-001','change','["cross_lifecycle"]','["change_management","continuity_recovery"]','["control","evidence"]','["operational","archival"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-AUTO-001','agency','["operate","evolve"]','["reliability_engineering"]','["control","governance"]','["operational","executable"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-AGT-001','agency','["operate","evolve"]','["operational_readiness","reliability_engineering"]','["control","runtime"]','["coordination","executable"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-SYM-001','interaction','["operate","verify"]','["reliability_engineering"]','["control","interface"]','["coordination","verification"]','["normative_policy"]','mapped','adapt'),
('DIR-SKL-001','capability','["cross_lifecycle"]','["change_management"]','["governance","control"]','["generative","verification"]','["normative_policy","pure_generation"]','mapped','adapt'),
('DIR-SUP-001','capability','["implement","verify"]','["change_management"]','["governance","control"]','["transformational","verification"]','["normative_policy","pure_generation"]','mapped','adapt'),
('DIR-HOOK-001','lifecycle','["operate","verify"]','["reliability_engineering","observability"]','["control","runtime","evidence"]','["executable","observational"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-TOOL-001','tooling','["implement","operate"]','["operational_readiness"]','["control","runtime"]','["executable","verification"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-PLAN-001','planning','["cross_lifecycle"]','["change_management"]','["control","data"]','["coordination","archival"]','["normative_policy"]','mapped','adapt'),
('DIR-GATE-001','assurance','["verify","release"]','["operational_readiness"]','["evidence","control"]','["verification","normative"]','["normative_policy","admission_veto"]','mapped','retain'),
('DIR-TEST-001','assurance','["verify"]','["reliability_engineering"]','["evidence","formal"]','["verification"]','["normative_policy","admission_veto"]','mapped','retain'),
('DIR-UI-001','interface','["implement","operate"]','["service_level"]','["interface","data"]','["executable","observational"]','["normative_policy"]','mapped','adapt'),
('DIR-AGUI-001','interaction','["design","implement"]','["reliability_engineering"]','["interface","control","data"]','["normative","executable"]','["normative_policy"]','mapped','adapt'),
('DIR-A2UI-001','interaction','["design","implement"]','["reliability_engineering"]','["interface","data"]','["generative","verification"]','["normative_policy","pure_generation"]','mapped','adapt'),
('DIR-OBS-001','observability','["operate","verify"]','["observability"]','["evidence","data","runtime"]','["observational","archival"]','["normative_policy","runtime_evidence"]','mapped','adapt'),
('DIR-MCP-001','interaction','["implement","operate"]','["reliability_engineering","operational_readiness"]','["interface","control","runtime"]','["executable","verification"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-CONFIG-001','configuration','["design","release"]','["change_management"]','["governance","control"]','["transformational","verification"]','["normative_policy"]','mapped','adapt'),
('DIR-DB-001','data','["implement","operate"]','["reliability_engineering","continuity_recovery"]','["data","control","evidence"]','["executable","archival"]','["normative_policy"]','mapped','adapt'),
('DIR-SWARM-001','coordination','["operate","verify"]','["reliability_engineering"]','["control","runtime"]','["coordination","executable"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-ALG-001','semantics','["design","verify"]','["not_applicable"]','["formal","evidence"]','["analytical","verification"]','["normative_policy","admission_veto"]','mapped','adapt'),
('DIR-FORMAL-001','formal_method','["specify","verify"]','["operational_readiness"]','["formal","evidence"]','["verification","analytical"]','["normative_policy","admission_veto"]','mapped','adapt'),
('DIR-RULE-001','rule_system','["design","operate"]','["reliability_engineering"]','["intelligence","control","formal"]','["analytical","executable"]','["normative_policy","admission_veto"]','mapped','adapt'),
('DIR-BAYES-001','intelligence','["design","operate"]','["capacity_performance"]','["intelligence","evidence"]','["analytical","observational"]','["normative_policy","advisory"]','mapped','oracle'),
('DIR-SAFE-001','safety','["cross_lifecycle"]','["reliability_engineering","security_resilience"]','["control","evidence","formal"]','["analytical","verification"]','["normative_policy","admission_veto"]','mapped','retain'),
('DIR-SEC-001','security','["cross_lifecycle"]','["security_resilience"]','["security","control","evidence"]','["normative","verification"]','["normative_policy","admission_veto"]','mapped','retain'),
('DIR-HA-001','reliability','["operate","verify"]','["continuity_recovery","reliability_engineering"]','["runtime","control","evidence"]','["operational","verification"]','["normative_policy"]','mapped','adapt'),
('DIR-INF-001','intelligence','["implement","operate"]','["capacity_performance","reliability_engineering"]','["intelligence","runtime","control"]','["analytical","executable"]','["normative_policy","advisory"]','mapped','adapt'),
('DIR-BROWSER-001','interface','["verify","operate"]','["security_resilience","service_level"]','["interface","control"]','["executable","external_effect"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-FIGMA-001','interface','["design","verify"]','["change_management"]','["interface","evidence"]','["generative","external_effect"]','["normative_policy","direct_effect_forbidden"]','mapped','adapt'),
('DIR-TIME-001','time','["operate","verify"]','["observability","reliability_engineering"]','["evidence","control"]','["observational","verification"]','["normative_policy","runtime_evidence"]','conflict_unresolved','adapt'),
('DIR-JOURNAL-001','provenance','["cross_lifecycle"]','["knowledge_management","change_management"]','["evidence","knowledge"]','["archival","observational"]','["normative_policy"]','mapped','retain'),
('DIR-PKM-001','knowledge','["cross_lifecycle"]','["knowledge_management"]','["knowledge","data","evidence"]','["archival","analytical"]','["normative_policy"]','mapped','adapt'),
('DIR-SRE-001','operations','["operate","evolve"]','["service_level","reliability_engineering","incident_response"]','["control","evidence"]','["operational","observational"]','["normative_policy","runtime_evidence"]','mapped','retain'),
('DIR-DOC-001','documentation','["cross_lifecycle"]','["knowledge_management"]','["knowledge","evidence"]','["generative","archival"]','["normative_policy","pure_generation"]','mapped','adapt'),
('DIR-INTF-001','interaction','["design","verify"]','["reliability_engineering"]','["interface","control","data"]','["normative","verification"]','["normative_policy"]','mapped','adapt');

INSERT INTO directive_classification
(directive_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT directive_id,'ontology_class',ontology_term,1,'target','document_review','reviewed',
       'Primary domain ontology assigned by the UOS classification contract.'
FROM _directive_profile
UNION ALL
SELECT p.directive_id,'sdlc_phase',j.value,CAST(j.key AS INTEGER)+1,'target','document_review','reviewed',
       'Ordered SDLC applicability; rank 1 is primary.'
FROM _directive_profile AS p JOIN json_each(p.sdlc_terms) AS j
UNION ALL
SELECT p.directive_id,'sre_function',j.value,CAST(j.key AS INTEGER)+1,'target','document_review','reviewed',
       'Ordered SRE applicability; not_applicable is explicit rather than omitted.'
FROM _directive_profile AS p JOIN json_each(p.sre_terms) AS j
UNION ALL
SELECT p.directive_id,'operational_plane',j.value,CAST(j.key AS INTEGER)+1,'target','document_review','reviewed',
       'Ordered plane membership preserves cross-plane semantics.'
FROM _directive_profile AS p JOIN json_each(p.plane_terms) AS j
UNION ALL
SELECT p.directive_id,'process_type',j.value,CAST(j.key AS INTEGER)+1,'target','document_review','reviewed',
       'Ordered process semantics; rank 1 is the dominant behavior.'
FROM _directive_profile AS p JOIN json_each(p.process_terms) AS j
UNION ALL
SELECT p.directive_id,'authority_role',j.value,CAST(j.key AS INTEGER)+1,'target','document_review','reviewed',
       'Policy authority is separated from advisory, veto, evidence and effect roles.'
FROM _directive_profile AS p JOIN json_each(p.authority_terms) AS j
UNION ALL
SELECT directive_id,'lifecycle_state',lifecycle_term,1,'target','document_review','reviewed',
       'Current UOS planning lifecycle state; target execution remains absent.'
FROM _directive_profile
UNION ALL
SELECT directive_id,'migration_disposition',disposition_term,1,'target','document_review','reviewed',
       'Planned semantic disposition; source bytes remain unchanged.'
FROM _directive_profile;

CREATE TEMP TABLE _directive_process_family (
  directive_id TEXT PRIMARY KEY,
  family_terms TEXT NOT NULL CHECK (json_valid(family_terms))
);

INSERT INTO _directive_process_family VALUES
('DIR-AUTH-001','["control","ontological","formal"]'),
('DIR-READ-001','["sdlc","data","formal"]'),
('DIR-LANG-001','["sdlc","ontological","control"]'),
('DIR-VCS-001','["sdlc","control","sre"]'),
('DIR-AUTO-001','["control","sre","formal"]'),
('DIR-AGT-001','["ontological","control","sre"]'),
('DIR-SYM-001','["control","ontological","sre"]'),
('DIR-SKL-001','["ontological","sdlc","control"]'),
('DIR-SUP-001','["sdlc","control"]'),
('DIR-HOOK-001','["control","sdlc","sre","formal"]'),
('DIR-TOOL-001','["sdlc","sre","control"]'),
('DIR-PLAN-001','["sdlc","control","data"]'),
('DIR-GATE-001','["formal","control","sdlc"]'),
('DIR-TEST-001','["sdlc","formal","sre"]'),
('DIR-UI-001','["sdlc","ontological","data"]'),
('DIR-AGUI-001','["control","ontological","data","sre"]'),
('DIR-A2UI-001','["ontological","data","sdlc"]'),
('DIR-OBS-001','["sre","data","formal"]'),
('DIR-MCP-001','["control","ontological","sre","data"]'),
('DIR-CONFIG-001','["data","control","sre","ontological"]'),
('DIR-DB-001','["data","sre","formal"]'),
('DIR-SWARM-001','["control","sre","sdlc"]'),
('DIR-ALG-001','["formal","ontological"]'),
('DIR-FORMAL-001','["formal","control","sdlc"]'),
('DIR-RULE-001','["formal","control","data"]'),
('DIR-BAYES-001','["formal","data"]'),
('DIR-SAFE-001','["control","formal","sre"]'),
('DIR-SEC-001','["sre","control","formal"]'),
('DIR-HA-001','["sre","control"]'),
('DIR-INF-001','["data","formal","control","sre"]'),
('DIR-BROWSER-001','["control","sdlc","sre"]'),
('DIR-FIGMA-001','["sdlc","ontological","data"]'),
('DIR-TIME-001','["sre","data","formal","control"]'),
('DIR-JOURNAL-001','["data","sdlc","formal","ontological"]'),
('DIR-PKM-001','["data","ontological","sre"]'),
('DIR-SRE-001','["sre","control","data","formal"]'),
('DIR-DOC-001','["sdlc","ontological","data","formal"]'),
('DIR-INTF-001','["ontological","control","data","sdlc"]');

INSERT INTO directive_classification
(directive_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT p.directive_id,'process_family',j.value,CAST(j.key AS INTEGER)+1,
       'target','document_review','reviewed',
       'Primary family uses the operator-requested ONT/SDLC/SRE/CTL/DAT/FRM taxonomy; later ranks preserve cross-cutting process semantics.'
FROM _directive_process_family AS p JOIN json_each(p.family_terms) AS j;

DROP TABLE _directive_process_family;

DROP TABLE _directive_profile;

INSERT INTO capability_classification
(capability_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT capability_id,'ontology_class',
       CASE capability_kind
         WHEN 'skill' THEN 'capability' WHEN 'superpower' THEN 'capability'
         WHEN 'agent' THEN 'agency' WHEN 'plugin' THEN 'interaction'
         WHEN 'hook' THEN 'lifecycle' WHEN 'mcp_tool' THEN 'tooling'
         WHEN 'wiki' THEN 'knowledge' WHEN 'zettelkasten' THEN 'knowledge'
         WHEN 'knowledge_management' THEN 'knowledge' END,
       1,'current','kind_default','provisional',
       'Classification derived from the inventory kind; semantic refinement remains a per-item admission task.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'sdlc_phase',
       CASE WHEN capability_kind IN ('agent','plugin','hook','mcp_tool') THEN 'operate'
            ELSE 'cross_lifecycle' END,
       1,'current','kind_default','provisional',
       'Primary lifecycle applicability derived conservatively from capability kind.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'sre_function',
       CASE WHEN capability_kind IN ('skill','superpower') THEN 'change_management'
            WHEN capability_kind IN ('agent','plugin','hook','mcp_tool') THEN 'reliability_engineering'
            ELSE 'knowledge_management' END,
       1,'current','kind_default','provisional',
       'Primary SRE function derived from capability kind; directives carry finer secondary classifications.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'process_type',
       CASE WHEN capability_kind IN ('skill','superpower') THEN 'generative'
            WHEN capability_kind = 'agent' THEN 'coordination'
            WHEN capability_kind IN ('plugin','hook','mcp_tool') THEN 'executable'
            ELSE 'archival' END,
       1,'current','kind_default','provisional',
       'Dominant process type derived from capability kind and kept non-authoritative.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'authority_role','reference_evidence',1,'current','kind_default','provisional',
       'All imported source items are inert evidence until item-level adaptation, verification and admission.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'lifecycle_state',
       CASE disposition WHEN 'quarantine' THEN 'quarantined'
                        WHEN 'exclude' THEN 'excluded'
                        ELSE 'classified' END,
       1,'current','kind_default','provisional',
       'Classification is current planning state; source implementation does not imply UOS implementation.'
FROM capability_inventory
UNION ALL
SELECT capability_id,'migration_disposition',disposition,1,'current','kind_default','provisional',
       'Copied from the explicit item disposition in the capability inventory.'
FROM capability_inventory;

INSERT INTO capability_classification
(capability_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT capability_id,'process_family',
       CASE capability_kind
         WHEN 'skill' THEN 'ontological'
         WHEN 'superpower' THEN 'sdlc'
         WHEN 'agent' THEN 'control'
         WHEN 'plugin' THEN 'control'
         WHEN 'hook' THEN 'control'
         WHEN 'mcp_tool' THEN 'control'
         WHEN 'wiki' THEN 'data'
         WHEN 'zettelkasten' THEN 'data'
         WHEN 'knowledge_management' THEN 'data' END,
       1,'current','kind_default','provisional',
       'Artifact/container family only. Skill, plugin and MCP operation semantics require body/handler review before semantic coverage credit.'
FROM capability_inventory;

WITH plane_rule(kind,term_id,rank) AS (VALUES
  ('skill','governance',1),('skill','control',2),
  ('superpower','governance',1),('superpower','control',2),
  ('agent','control',1),('agent','runtime',2),
  ('plugin','interface',1),('plugin','runtime',2),
  ('hook','control',1),('hook','runtime',2),('hook','evidence',3),
  ('mcp_tool','interface',1),('mcp_tool','control',2),('mcp_tool','runtime',3),
  ('wiki','knowledge',1),('wiki','data',2),('wiki','evidence',3),
  ('zettelkasten','knowledge',1),('zettelkasten','data',2),('zettelkasten','evidence',3),
  ('knowledge_management','knowledge',1),('knowledge_management','data',2),('knowledge_management','evidence',3)
)
INSERT INTO capability_classification
(capability_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT i.capability_id,'operational_plane',r.term_id,r.rank,
       'current','kind_default','provisional',
       'Ordered cross-plane membership derived from capability kind; rank 1 is primary.'
FROM capability_inventory AS i JOIN plane_rule AS r ON r.kind = i.capability_kind;

INSERT INTO capability_classification
(capability_id,axis_id,term_id,rank,temporal_scope,classification_method,
 classification_status,rationale)
SELECT capability_id,'authority_role','direct_effect_forbidden',2,
       'current','kind_default','provisional',
       'Imported executable-facing artifacts cannot directly actuate UOS.'
FROM capability_inventory
WHERE capability_kind IN ('agent','plugin','hook','mcp_tool');

INSERT INTO directive_source_mapping
(mapping_id,directive_id,source_system,source_revision,source_path,
 source_anchor,relation,conflict_id,evidence)
SELECT 'MAP-UOS-ROOT-' || d.directive_id,
       d.directive_id,
       'UOS transitional root',
       'planning-pre-jj',
       'AGENTS.md',
       CASE
         WHEN d.directive_id IN ('DIR-AUTH-001','DIR-READ-001') THEN 'Sections 1-3'
         WHEN d.directive_id = 'DIR-VCS-001' THEN 'Section 4'
         WHEN d.directive_id IN ('DIR-LANG-001','DIR-CONFIG-001') THEN 'Section 5'
         WHEN d.directive_id IN ('DIR-GATE-001','DIR-TEST-001','DIR-OBS-001') THEN 'Section 6'
         WHEN d.directive_id IN ('DIR-FORMAL-001','DIR-BROWSER-001','DIR-FIGMA-001') THEN 'Section 7'
         WHEN d.directive_id IN ('DIR-ALG-001','DIR-RULE-001','DIR-BAYES-001','DIR-SAFE-001') THEN 'Section 8'
         WHEN d.directive_id IN ('DIR-AGT-001','DIR-SYM-001','DIR-SKL-001','DIR-SUP-001','DIR-HOOK-001','DIR-TOOL-001','DIR-MCP-001','DIR-DB-001','DIR-SWARM-001','DIR-HA-001','DIR-PKM-001','DIR-SRE-001','DIR-DOC-001','DIR-INTF-001') THEN 'Section 9'
         WHEN d.directive_id IN ('DIR-TIME-001','DIR-JOURNAL-001') THEN 'Section 10'
         WHEN d.directive_id IN ('DIR-AUTO-001','DIR-SEC-001') THEN 'Section 11'
         WHEN d.directive_id = 'DIR-INF-001' THEN 'Sections 5 and 17'
         WHEN d.directive_id IN ('DIR-UI-001','DIR-AGUI-001','DIR-A2UI-001') THEN 'Section 12'
         ELSE 'Composite root policy'
       END,
       'requirements_only',
       CASE WHEN d.directive_id = 'DIR-TIME-001' THEN 'CONFLICT-TIMESTAMP-FORMAT-001' ELSE NULL END,
       'Root policy supplies the transitional UOS requirement. Detailed source-by-source anchors and dispositions belong in docs/design/2026-09-05-uos-agent-policy-capability-superset-mapping.md.'
FROM directive_superset AS d;

CREATE TEMP TABLE _source_anchor (
  directive_id TEXT PRIMARY KEY,
  c3i_path TEXT, c3i_anchor TEXT,
  zigvm_path TEXT, zigvm_anchor TEXT,
  harness_path TEXT, harness_anchor TEXT
);

INSERT INTO _source_anchor VALUES
('DIR-AUTH-001','/home/an/dev/ver/c3i/CLAUDE.md','§1.0 System Identity & Mandate','/home/an/dev/ver/zigvm/CLAUDE.md','What this is','/home/an/NAS-setup/harness-bionic/AGENTS.md','Required reading order; canonical policy statement'),
('DIR-READ-001','/home/an/dev/ver/c3i/AGENTS.md','Key Source Paths; Related Documents','/home/an/dev/ver/zigvm/AGENTS.md','Required Context','/home/an/NAS-setup/harness-bionic/AGENTS.md','Required reading order'),
('DIR-LANG-001','/home/an/dev/ver/c3i/AGENTS.md','Universal Effect TypeScript; fp-core Rust; Safe Rust; Functional Runtime rules','/home/an/dev/ver/zigvm/AGENTS.md','Project Boundary; Harness & Scripting Rule','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: language boundaries'),
('DIR-VCS-001','/home/an/dev/ver/c3i/AGENTS.md','Planning & Orchestration','/home/an/dev/ver/zigvm/CLAUDE.md','Sa-plan Durable Control Contract; autonomous mutation semantics','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: Jujutsu'),
('DIR-AUTO-001','/home/an/dev/ver/c3i/AGENTS.md','Planning & Orchestration; agent coordination','/home/an/dev/ver/zigvm/AGENTS.md','Autonomous operation (standing)','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: swarm/offload behavior'),
('DIR-AGT-001','/home/an/dev/ver/c3i/AGENTS.md','Agent Architecture; named agent families','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces','/home/an/NAS-setup/harness-bionic/AGENTS.md','Cross-agent surface algebra'),
('DIR-SYM-001','/home/an/dev/ver/c3i/AGENTS.md','Functional Runtime Supervisor Rule; Agent Coordination','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces','/home/an/NAS-setup/harness-bionic/AGENTS.md','Cross-agent surface algebra'),
('DIR-SKL-001','/home/an/dev/ver/c3i/CLAUDE.md','§10 Active Constraints Cross-Reference; skills referenced by policy','/home/an/dev/ver/zigvm/AGENTS.md','Required Context; governing skills','/home/an/NAS-setup/harness-bionic/AGENTS.md','Required reading order; repository skill rules'),
('DIR-SUP-001',NULL,NULL,'/home/an/dev/ver/zigvm/AGENTS.md','Required Context: external Superpowers references','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository skills; five structural Superpowers declarations'),
('DIR-HOOK-001','/home/an/dev/ver/c3i/AGENTS.md','Functional Runtime Supervisor Rule','/home/an/dev/ver/zigvm/AGENTS.md','Approach B journal/time controls','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: lifecycle and timestamp hooks'),
('DIR-TOOL-001','/home/an/dev/ver/c3i/CLAUDE.md','§4.0 Build & Test Commands','/home/an/dev/ver/zigvm/CLAUDE.md','Commands','/home/an/NAS-setup/harness-bionic/AGENTS.md','The toolchain'),
('DIR-PLAN-001','/home/an/dev/ver/c3i/AGENTS.md','Planning & Orchestration (L3-L4)','/home/an/dev/ver/zigvm/CLAUDE.md','Sa-plan Durable Control Contract','/home/an/NAS-setup/harness-bionic/AGENTS.md','The toolchain; swarm/offload'),
('DIR-GATE-001','/home/an/dev/ver/c3i/CLAUDE.md','§8.0 Testing Gold Standard','/home/an/dev/ver/zigvm/AGENTS.md','Two-Tier Verification & the OODA Loop','/home/an/NAS-setup/harness-bionic/AGENTS.md','Synchronization gate'),
('DIR-TEST-001','/home/an/dev/ver/c3i/AGENTS.md','UI Testing Workflow','/home/an/dev/ver/zigvm/AGENTS.md','Testing Disciplines Rule','/home/an/NAS-setup/harness-bionic/AGENTS.md','Synchronization gate; evidence orientation'),
('DIR-UI-001','/home/an/dev/ver/c3i/CLAUDE.md','§3.0 Triple-Interface; §7.0 Fractal Widget Architecture','/home/an/dev/ver/zigvm/AGENTS.md','Browser Control; Figma Design Control','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: operations UI projection'),
('DIR-AGUI-001','/home/an/dev/ver/c3i/CLAUDE.md','§5.0 AG-UI 32-Event Protocol',NULL,NULL,NULL,NULL),
('DIR-A2UI-001','/home/an/dev/ver/c3i/CLAUDE.md','§6.0 A2UI Declarative Catalog',NULL,NULL,NULL,NULL),
('DIR-OBS-001','/home/an/dev/ver/c3i/CLAUDE.md','§2.5 Zenoh OTel; §2.6 ZMOF','/home/an/dev/ver/zigvm/AGENTS.md','Approach B performance and observability rule','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: evidence orientation'),
('DIR-MCP-001','/home/an/dev/ver/c3i/CLAUDE.md','§14 OpenClaw capabilities; §17 Cortex & Gateway','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces; MCP control plane','/home/an/NAS-setup/harness-bionic/AGENTS.md','The toolchain; MCP configuration'),
('DIR-CONFIG-001','/home/an/dev/ver/c3i/CLAUDE.md','§4 build environment; §9 key locations','/home/an/dev/ver/zigvm/AGENTS.md','Project Boundary; required environment','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants R23/R31: declarative configuration'),
('DIR-DB-001','/home/an/dev/ver/c3i/CLAUDE.md','§12 Task Management Authority; Smriti/planning','/home/an/dev/ver/zigvm/CLAUDE.md','Sa-plan Durable Control Contract','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: typed wiki/data behavior'),
('DIR-SWARM-001','/home/an/dev/ver/c3i/AGENTS.md','Agent Coordination for UI Work','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces; Tier-2 parallelism','/home/an/NAS-setup/harness-bionic/AGENTS.md','Cross-agent surface algebra; swarm/offload'),
('DIR-ALG-001','/home/an/dev/ver/c3i/CLAUDE.md','§11.0 Allium Behavioral Specification','/home/an/dev/ver/zigvm/AGENTS.md','Algebraic Structure Rule; Fractal FP Atlas','/home/an/NAS-setup/harness-bionic/AGENTS.md','Cross-agent surface algebra; fractal coordinates'),
('DIR-FORMAL-001','/home/an/dev/ver/c3i/CLAUDE.md','§11.0 Allium Behavioral Specification','/home/an/dev/ver/zigvm/AGENTS.md','Formal Verification (Rocq & Quint) Pipeline','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: formal verification'),
('DIR-RULE-001','/home/an/dev/ver/c3i/CLAUDE.md','§11.0 RETE-UL Rule Engine','/home/an/dev/ver/zigvm/AGENTS.md','Two-Tier verification and rule gates','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: evidence/formal gates'),
('DIR-BAYES-001',NULL,NULL,'/home/an/dev/ver/zigvm/AGENTS.md','Decision-support: Stan/Bayesian posteriors are ADVISORY',NULL,NULL),
('DIR-SAFE-001','/home/an/dev/ver/c3i/AGENTS.md','STAMP Constraints (UI Agent Scope)','/home/an/dev/ver/zigvm/AGENTS.md','Required Context: STPA safety protocol','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: controlled external access and evidence'),
('DIR-SEC-001','/home/an/dev/ver/c3i/CLAUDE.md','§10 Secrets Vault; Safe Rust constraints','/home/an/dev/ver/zigvm/CLAUDE.md','Hard boundaries','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: controlled external access'),
('DIR-HA-001','/home/an/dev/ver/c3i/CLAUDE.md','§13.0 High Availability & Zero-Downtime Evolution','/home/an/dev/ver/zigvm/CLAUDE.md','Default fractal OTP-parity loop','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: recovery and synchronization'),
('DIR-INF-001','/home/an/dev/ver/c3i/CLAUDE.md','§14-§17 OpenClaw, chat, voice, Cortex and gateway','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces and model adapters','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: agent/provider boundaries'),
('DIR-BROWSER-001',NULL,NULL,'/home/an/dev/ver/zigvm/AGENTS.md','Browser Control Rule',NULL,NULL),
('DIR-FIGMA-001',NULL,NULL,'/home/an/dev/ver/zigvm/AGENTS.md','Figma Design Control Rule',NULL,NULL),
('DIR-TIME-001','/home/an/dev/ver/c3i/.claude/rules/timestamp-sync.md','SC-TIME timestamp synchronization rule','/home/an/dev/ver/zigvm/AGENTS.md','Approach B timestamp format and cadence','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariant: YYYYMMDD-HHSS timestamp'),
('DIR-JOURNAL-001','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','SC-JOURNAL exact journal protocol','/home/an/dev/ver/zigvm/AGENTS.md','Approach B Journal/Design Bundle Hard Control','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariant: append-only journal naming and sync'),
('DIR-PKM-001','/home/an/dev/ver/c3i/CLAUDE.md','Knowledge, Smriti and ZK constraints','/home/an/dev/ver/zigvm/AGENTS.md','Approach B OAIS/PKM/Logseq controls','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: wiki/ZK behavior'),
('DIR-SRE-001','/home/an/dev/ver/c3i/CLAUDE.md','§3.5 Muda Waste Reduction Protocol','/home/an/dev/ver/zigvm/AGENTS.md','Approach B performance/observability; OODA gates','/home/an/NAS-setup/harness-bionic/AGENTS.md','Repository invariants: operations UI, evidence and economy'),
('DIR-DOC-001','/home/an/dev/ver/c3i/AGENTS.md','Key Source Paths; Related Documents','/home/an/dev/ver/zigvm/AGENTS.md','Required Context; Fractal FP Atlas Sync','/home/an/NAS-setup/harness-bionic/AGENTS.md','Required reading order; synchronization gate'),
('DIR-INTF-001','/home/an/dev/ver/c3i/CLAUDE.md','§2 Penta-Stack; §3 Triple-Interface','/home/an/dev/ver/zigvm/AGENTS.md','Agent Surfaces','/home/an/NAS-setup/harness-bionic/AGENTS.md','Cross-agent surface algebra');

WITH maps(mapping_id,directive_id,source_system,source_revision,source_path,source_anchor) AS (
  SELECT 'MAP-C3I-' || directive_id,directive_id,'C3I VM-1',
         '47f9322329fcda2fdbd7061988f586c65db00d17',c3i_path,c3i_anchor
  FROM _source_anchor WHERE c3i_path IS NOT NULL
  UNION ALL
  SELECT 'MAP-ZIGVM-' || directive_id,directive_id,'ZigVM VM-1',
         '3cf87fedbc51e37c64eee057c30a553f9d346170',zigvm_path,zigvm_anchor
  FROM _source_anchor WHERE zigvm_path IS NOT NULL
  UNION ALL
  SELECT 'MAP-HARNESS-' || directive_id,directive_id,'Harness-Bionic',
         'jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45',harness_path,harness_anchor
  FROM _source_anchor WHERE harness_path IS NOT NULL
)
INSERT INTO directive_source_mapping
(mapping_id,directive_id,source_system,source_revision,source_path,
 source_anchor,relation,conflict_id,evidence)
SELECT mapping_id,directive_id,source_system,source_revision,source_path,source_anchor,
       CASE directive_id
         WHEN 'DIR-VCS-001' THEN 'incompatible'
         WHEN 'DIR-TIME-001' THEN 'splits'
         WHEN 'DIR-LANG-001' THEN 'splits'
         WHEN 'DIR-AUTO-001' THEN 'restricts'
         ELSE 'requirements_only' END,
       CASE directive_id
         WHEN 'DIR-VCS-001' THEN 'CONFLICT-NATIVE-GIT-VS-JJ-001'
         WHEN 'DIR-TIME-001' THEN 'CONFLICT-TIMESTAMP-FORMAT-001'
         WHEN 'DIR-LANG-001' THEN 'CONFLICT-SOURCE-VS-UOS-LANGUAGE-001'
         WHEN 'DIR-AUTO-001' THEN 'CONFLICT-STANDING-AUTONOMY-001'
         ELSE NULL END,
       'Source-specific heading or rule contributes to the unified directive. Source bytes remain unchanged and A0 reference-only.'
FROM maps;

DROP TABLE _source_anchor;

INSERT INTO timestamp_namespace VALUES
('TIME-HARNESS-HUMAN','Harness-Bionic','YYYYMMDD-HHSS','year,month,day,hour,second; no minute field','unchanged_source_type','source_requirement','/home/an/dev/ver/harness-bionic/AGENTS.md:21; source hash 617ea841a366dba6a8c5c7590b85729a5d9b4fea6870de45facee14dfa87e805.'),
('TIME-ZIGVM-HUMAN','ZigVM VM-1','YYYYMMDD-HHMMSS','year,month,day,hour,minute,second','unchanged_source_type','source_requirement','/home/an/dev/ver/zigvm/AGENTS.md:98-99,348-349; source hash 1cc92910a02e70235f6c4741410059b7ecfa7f34ee0e4cdf07943813aa1edc3b.'),
('TIME-UOS-HUMAN-NEW','UOS','UNRESOLVED','canonical UOS-new human timestamp fields are not selected','unresolved_target_type','conflict_unresolved','Harness and ZigVM forms are not equivalent. Use semantic IDs/content digests for identity until operator resolution and typed round-trip tests.'),
('TIME-C3I-SYSTEM-MODEL-DELTA','C3I VM-1','signed duration seconds','source system-to-model delta; normalized bands below 2, 2..<5, 5..10, above 10','unchanged_source_type','planned','/home/an/dev/ver/c3i/.claude/rules/timestamp-sync.md; hash 5b4bfb8c83ed9bfcf1488c19a938a4d8f3985dd07134362a0231fa057caec287. Boundary interpretation is NORMALIZED, not unchanged behavior.'),
('TIME-UOS-HOST-OFFSET','UOS','signed duration with uncertainty','host NTP offset, probe source, uncertainty and sync assurance','protocol_native','planned','No accepted offset-producing probe is bound to this ledger; value and assurance remain UNKNOWN.'),
('TIME-UOS-AGENT-CONTEXT','UOS','monotonic age duration','agent context refresh at session start and every 30 minutes; stale at 40 minutes','protocol_native','planned','Freshness is separate from wall-clock offset. Missing/stale context requires correction and disclosure.'),
('TIME-OTEL-NATIVE','OpenTelemetry','Unix epoch nanoseconds','protocol-native event timestamp and duration fields','protocol_native','source_requirement','Protocol-native OTEL units retain their specified schema and are not formatted as human journal timestamps.'),
('TIME-PKM-DATE','PKM schema','declared date-only type','calendar date without invented time-of-day','protocol_native','source_requirement','Date-only fields retain their declared schema; no time component is synthesized.');

INSERT INTO source_protocol_identity VALUES
('PROTO-C3I-TIME-RULE','timestamp','source_rule','C3I VM-1','/home/an/dev/ver/c3i/.claude/rules/timestamp-sync.md','5b4bfb8c83ed9bfcf1488c19a938a4d8f3985dd07134362a0231fa057caec287',9161,'PRESERVED_UNCHANGED','A0_reference','Normative source semantics; UOS adaptation is a new typed artifact.','2026-09-05T09:31:36+02:00'),
('PROTO-C3I-TIME-SKILL','timestamp','provider_procedure','C3I VM-1','/home/an/dev/ver/c3i/.claude/skills/timestamp-sync/SKILL.md','b5736ed2adad86272d9793c1a86d8148ea24bf40d83b3f58456109d3f764bc93',1323,'PRESERVED_UNCHANGED','A0_reference','Provider procedure retained separately from the rule.','2026-09-05T09:31:36+02:00'),
('PROTO-C3I-JOURNAL-RULE','journal','source_rule','C3I VM-1','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c',1515,'PRESERVED_UNCHANGED','A0_reference','Exact 13-section source contract; normalized boundaries and safety overrides are separate target facts.','2026-09-05T09:31:36+02:00'),
('PROTO-C3I-JOURNAL-SKILL','journal','provider_procedure','C3I VM-1','/home/an/dev/ver/c3i/.claude/skills/journal-protocol/SKILL.md','7664b1fb2600b03b4ee6c779e36add4c87283008f662aa9bc70f18675d481376',1560,'PRESERVED_UNCHANGED','A0_reference','Provider procedure retained separately from the rule.','2026-09-05T09:31:36+02:00');

INSERT INTO journal_contract_section
(ordinal,title,required,scaling_rule,source_path,source_sha256) VALUES
(1,'Scope & Trigger',1,'1-3 files: 1-2 lines; 4-14: paragraph/full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(2,'Pre-State Assessment',1,'1-3 files: 1-2 lines; 4-14: paragraph/full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(3,'Execution Detail',1,'1-3 files: 1-2 lines; 4-14: paragraph/full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(4,'Root Cause Analysis',1,'1-3 files: 1-2 lines; 4-14: paragraph/full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(5,'Fix Taxonomy',1,'1-3 files: 1-2 lines; 4-14: paragraph/full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(6,'Patterns & Anti-Patterns Discovered',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(7,'Verification Matrix',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(8,'Files Modified',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(9,'Architectural Observations',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(10,'Remaining Gaps',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(11,'Metrics Summary',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(12,'STAMP & Constitutional Alignment',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c'),
(13,'Conclusion',1,'1-3 files: 1-2 lines; 4-14: full detail; 15 or more: subsections and diagrams; exact 15 is NORMALIZED to major.','/home/an/dev/ver/c3i/.claude/rules/journal-protocol.md','d1f93e792287d7ca2144c1e2963221e30363b6ff01dfe0cf7cd40e4e610f8b0c');

INSERT INTO formal_tool_authority
(tool_authority_id,source_system,language_or_tool,source_revision,source_path,
 role,invoked_by,blocks_build,blocks_release,runtime_effect_authority,
 evidence_state,details) VALUES
('FTO-ZIGVM-ROCQ','ZigVM VM-1','Rocq','3cf87fedbc51e37c64eee057c30a553f9d346170','proofs/rocq','machine_check','source formal harness',0,1,0,'stale_or_unbound','Thirteen observed proof families are source candidates; dirty/current candidate, assumption census and fresh kernel receipt are unresolved.'),
('FTO-ZIGVM-LEAN','ZigVM VM-1','Lean 4','3cf87fedbc51e37c64eee057c30a553f9d346170','proofs/lean','machine_check','source formal harness',0,1,0,'denominator_mismatch','Ninety-five files were later observed while a historical run records 94 checks; sorry/assumption census and rerun are required.'),
('FTO-ZIGVM-QUINT','ZigVM VM-1','Quint','3cf87fedbc51e37c64eee057c30a553f9d346170','specs','model_exploration','bounded source runner',0,1,0,'bounded_unrerun','Bounded exploration and conditional pure-fragment generation only; no universal-proof authority.'),
('FTO-ZIGVM-AEON-Z3','ZigVM VM-1','Aeon + Z3','3cf87fedbc51e37c64eee057c30a553f9d346170','harness/aeon_lang.ml','advisory_analysis','ambient source launcher',0,0,0,'unsafe_fail_open','Some nonzero solver paths can degrade to parse-only acceptance; quarantine unchanged launcher.'),
('FTO-HARNESS-FORMAL','Harness-Bionic','Rocq/Lean/Quint/Gospel','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','modules','machine_check','ops formal',1,1,0,'implemented_unrerun','Scoped fail-closed candidate, but weak assumptions, skip accounting, pin closure and current receipts remain unresolved.'),
('FTO-C3I-FORMAL','C3I VM-1','TLA+/Quint/Agda/Allium/Wolfram','47f9322329fcda2fdbd7061988f586c65db00d17','specs','documented_only',NULL,0,0,0,'unproven_uncontrolled','Authored sources exist, but no complete reproducible root gate is admitted.'),
('FTO-INDRAJAAL-RUNTIME','C3I/Indrajaal','Quint regex runtime','47f9322329fcda2fdbd7061988f586c65db00d17','sub-projects/c3i/lib/indrajaal','advisory_analysis','MSORuntime',0,0,0,'direct_effect_pattern_forbidden','Regex-parsed formal text must never directly invoke Sentinel, Guardian or Zenoh; requirements evidence only.'),
('FTO-OPENCLAW','OpenClaw pinned baseline','formal proof tooling',NULL,NULL,'absent',NULL,0,0,0,'absent','No machine-proof or SMT authority was observed at the pinned compatibility baseline.'),
('FTO-UOS-TARGET','UOS','formal authority registry',NULL,'governance/formal/tool-authority.toml','documented_only',NULL,0,1,0,'planned_target_absent','Target repository and operational gate do not exist.');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-HARNESS-Z3-WORKER','solver','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','modules/hermes_ops_dashboard','implemented_unavailable','A2_admission_veto',0,'Resource-envelope preflight deliberately returns Implemented_unavailable.','Closed Smtml subset, bounds, process-group reaping, framing and dual-backend protocol are implemented; production admission correctly fails closed.','2026-09-05T09:31:36+02:00'),
('MECH-ZIGVM-Z3','solver','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','harness/solver_sandbox.ml','unsafe_legacy','A1_advisory',0,'Ambient environment, incomplete bounds, sequential pipe reads and weak reset/hash behavior.','Useful differential input only; no current production solver authority.','2026-09-05T09:31:36+02:00'),
('MECH-UOS-VFS','vfs','UOS',NULL,'apps/cepaf_gleam + engines/zigvm','absent','none',0,'No supervised capability owner or descriptor-relative transactional backend exists.','Target requires traversal, encoding, symlink/hardlink/race/mount, quota, durability, rollback and crash evidence.','2026-09-05T09:31:36+02:00'),
('MECH-ZIGVM-FS','vfs','ZigVM VM-1','3cf87fedbc51e37c64eee057c30a553f9d346170','src + harness filesystem BIFs','partial','A1_advisory',0,'No tenant/session capability, transaction/receipt layer or proven race confinement.','Best observed low-level substrate, but not a VFS authority.','2026-09-05T09:31:36+02:00'),
('MECH-HARNESS-FPP','fpp','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','modules/hermes_fpp_authority','partial','A3_pure_generation',0,'No NASA F Prime runtime or official FPP toolchain/validator evidence.','Custom OCaml FPP-like model can seed identifiers and non-authoritative projections only.','2026-09-05T09:31:36+02:00'),
('MECH-HARNESS-SYSML','sysml','Harness-Bionic','jj-working-copy-acd4546e629af9c7910afe7451dd5fbc31c3ba45','modules/hermes_sysml','partial','A3_pure_generation',0,'Partial EDSL with unit placeholders, mock projection and no SysML v2 parser/API/validator.','Use as source model only; standards conformance remains unavailable.','2026-09-05T09:31:36+02:00'),
('MECH-PLANNING-MESSAGE-BOARD','coordination','UOS planning workspace',NULL,'docs/journal/uos-planning-ledger/001_schema.sql','partial','A1_advisory',0,'Generated snapshot schema exists, but rebuild replacement is not durable event retention and the supervised Gleam transport/executor is target-absent.','Message rows have in-instance update/delete guards and typed relations; ad-hoc rows are not preserved across materialization, so live coordination authority is not claimed.','2026-09-05T09:31:36+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-DMC-TCM-TOME','formal','DMC/TCM Master Tome',NULL,'docs/design/DMC_TCM_MASTER_TOME.md','documented_only','A0_reference',0,'The cited Traceability.lean, dispatch-hook executable and three dmc-tcm-mandate.md paths were absent during the 2026-09-05 source check; ratification, authorship, theorem, capability and runtime claims are unverified.','The two local Tome copies were byte-identical at SHA-256 62302b57186bf1ff26afece8f97acaf751996d1ba5da598cc95d31610ef61972. Preserve one logical artifact plus its alias; grant no proof, review, runtime or effect authority.','2026-09-05T12:13:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-FRACTAL-MULTIDIMENSIONAL-PROPOSAL','formal','AGY-labelled multidimensional fractal artifact',NULL,'docs/design/2026-09-05-uos-monorepo-multidimensional-fractal-audit.md','documented_only','A0_reference',0,'The proposed L0-L9 and 13-axis structures lack target carriers and a witnessed morphism to the canonical UOS 8D coordinate plus separate 13-point packet; the cited Traceability.lean is absent and runtime, formal, numerical, consensus and zero-loss claims were not reproduced.','The proposal is preserved as review evidence. Direct path checks and semantic inspection found absent target paths plus mismatches between several claimed theorem/runtime meanings and the observed ZigVM sources.','2026-09-05T12:24:56+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-FV-MASTER-TOME','formal','Formal Verification Master Tome',NULL,'docs/design/FORMAL_VERIFICATION_MASTER_TOME.md','documented_only','A0_reference',0,'The cited Traceability.lean and formal-verification-mandate.md paths were absent during the 2026-09-05 source check; asserted capability/law totals remain unverified proposals.','Verified authentic Rocq 9.1.1 proofs (CRDT_Mesh.v, Scheduler_Signal.v, Arena_NoAlias.v, etc.), registry PROVEN-IMPLIES-COMPILES, staleness lattice guard, and Rete-UL FV-Tier1 rule. Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T12:45:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-ALGEBRAIC-ATLAS-TOME','formal','Algebraic Atlas Master Tome',NULL,'docs/design/ALGEBRAIC_ATLAS_MASTER_TOME.md','documented_only','A0_reference',0,'Automated cross-language Lean 4 functor bridge remains a proposal; full mathematical equivalence proofs pending.','Verified authentic pure OCaml registry (harness/fractal_fp_atlas_registry.ml), pure renderer, 16 invariant laws, and 12 native Zig algebras in src/. Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T12:50:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-SA-PLAN-C3I-TOME','coordination','Sa-Plan C3I Master Tome',NULL,'docs/design/SA_PLAN_C3I_MASTER_TOME.md','documented_only','A0_reference',0,'Legacy C3I implementation relied on prohibited native Git workflows; UOS Jujutsu translation must be executed upon cutover.','Verified authentic Quint safety kernel and access control state machine in C3I source, alongside systemd service definitions. Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T12:55:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-FORECASTING-TOME','solver','Forecasting Engine Master Tome',NULL,'docs/design/FORECASTING_MASTER_TOME.md','documented_only','A0_reference',0,'The cited run_agent_dispatch_hook.exe and forecasting-mandate.md were absent during verification; probability predictions are advisory.','Verified authentic Stan MCMC Bayesian probability models in OCaml, high-resolution time hooks, and SQLite WAL telemetry ledgers in ZigVM source. Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T12:58:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-WIKI-ZK-KM-ANALYSIS','formal','Wiki/ZK/KM Substrate & C3I KMS',NULL,'docs/design/WIKI_ZK_KM_EXHAUSTIVE_ANALYSIS.md','documented_only','A0_reference',0,'The analysis is a document, not an implemented unified substrate. Source functions and laws need exact-path, semantic and runtime verification before any operational credit.','Earlier prose promoted source byte totals, lossless AST laws and topological sheaf claims without sufficient witnesses. Preserve those historical claims in the original document; this corrected planning row grants no implementation or proof credit. See UOS_AGY_SINGLE_FILE_SUMMARY.md and reviews/claude-P2.raw.json, finding 4.','2026-09-05T13:00:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-WIKI-ZK-KM-TOME','formal','Wiki/ZK/KM Master Tome',NULL,'docs/design/WIKI_ZK_KM_MASTER_TOME.md','documented_only','A0_reference',0,'Cross-language cutover and runtime execution of the 10 evolutionary cycles pending operator authorization; operational credit requires Two-Key Verification.','Master Tome formalizing 10 evolutionary cycles across >730KB physical source (ZigVM OCaml harness & C3I KMS/Smriti architecture). Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T13:10:00+02:00');

INSERT INTO mechanism_audit
(mechanism_id,domain,source_system,source_revision,source_path,observed_status,
 authority_class,operational_credit,blocking_gap,evidence,observed_at) VALUES
('MECH-FRACTAL-UNIFICATION-TOME','formal','Fractal Multidimensional Unification Master Tome',NULL,'docs/design/FRACTAL_MULTIDIMENSIONAL_UNIFICATION_MASTER_TOME.md','documented_only','A0_reference',0,'Cross-cutting implementation and runtime admission of unified skills, rules, and superpowers pending cutover; operational credit requires Two-Key Verification.','Master Tome unifying 473 capabilities, 38 directive families, 10 fractal surfaces (L0-L9), 8D atomic trace coordinate, 13-point packet, 9-axis taxonomy, and closed-loop SDLC/SRE processes. Preserved as A0_reference review evidence with zero unverified operational credit.','2026-09-05T13:10:00+02:00');

PRAGMA user_version = 7;

COMMIT;
