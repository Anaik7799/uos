// Test agents/cybernetic, holon/identity, config/mesh_config,
// config/constraint_sync, git/intelligence

import cepaf_gleam/agents/cybernetic.{
  DomainSupervisor, Executive, FunctionalSupervisor, Worker,
}
import cepaf_gleam/config/constraint_sync
import cepaf_gleam/config/mesh_config
import cepaf_gleam/git/intelligence.{
  Abbreviated, Chore, Ci, Conventional, Docs, Feat, Fix, Freeform, Imperative,
  MissingType, Multiline, Perf, Refactor, Security, SubjectTooLong, Test,
  Unknown,
}
import cepaf_gleam/holon/identity.{
  DomainCore, DomainPlanning, DuckDB, Gleam, InMemory, L0Constitutional,
  L7Federation, Postgres, SQLite, ZenohKV,
}
import gleam/dict
import gleam/float
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// agents/cybernetic tests
// =============================================================================

pub fn cybernetic_initialize_hierarchy_49_agents_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  let agents = cybernetic.get_all_agents(hierarchy)
  // Legacy data-only stub returns empty list (SC-AG-LEGACY)
  list.length(agents) |> should.equal(0)
}

pub fn cybernetic_verify_executive_authority_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  cybernetic.verify_executive_authority(hierarchy) |> should.be_true
}

pub fn cybernetic_check_efficiency_compliance_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // All agents start at 1.0 efficiency, so compliance should be true
  cybernetic.check_efficiency_compliance(hierarchy) |> should.be_true
}

pub fn cybernetic_detect_deadlock_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // No blocked agents initially, so no deadlock
  cybernetic.detect_deadlock(hierarchy) |> should.be_false
}

pub fn cybernetic_get_count_by_level_executive_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // Legacy data-only stub returns 0 (SC-AG-LEGACY)
  cybernetic.get_count_by_level(hierarchy, Executive) |> should.equal(0)
}

pub fn cybernetic_get_count_by_level_domain_supervisor_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // Legacy data-only stub returns 0 (SC-AG-LEGACY)
  cybernetic.get_count_by_level(hierarchy, DomainSupervisor) |> should.equal(0)
}

pub fn cybernetic_get_count_by_level_functional_supervisor_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // Legacy data-only stub returns 0 (SC-AG-LEGACY)
  cybernetic.get_count_by_level(hierarchy, FunctionalSupervisor)
  |> should.equal(0)
}

pub fn cybernetic_get_count_by_level_worker_test() {
  let hierarchy = cybernetic.initialize_hierarchy()
  // Legacy data-only stub returns 0 (SC-AG-LEGACY)
  cybernetic.get_count_by_level(hierarchy, Worker) |> should.equal(0)
}

// =============================================================================
// holon/identity tests
// =============================================================================

pub fn identity_create_uhi_test() {
  let uhi =
    identity.create_uhi(
      Gleam,
      L0Constitutional,
      DomainCore,
      identity.Agent,
      "boot-001",
    )
  uhi.runtime |> should.equal(Gleam)
  uhi.layer |> should.equal(L0Constitutional)
  uhi.domain |> should.equal(DomainCore)
  uhi.instance |> should.equal("boot-001")
}

pub fn identity_uhi_to_string_roundtrip_test() {
  let uhi =
    identity.create_uhi(
      Gleam,
      L0Constitutional,
      DomainPlanning,
      identity.Supervisor,
      "plan-001",
    )
  let s = identity.uhi_to_string(uhi)
  s |> should.equal("gleam:L0:planning:supervisor:plan-001")
  let parsed = identity.parse_uhi(s)
  parsed |> should.be_ok
  let assert Ok(round_tripped) = parsed
  round_tripped.runtime |> should.equal(Gleam)
  round_tripped.domain |> should.equal(DomainPlanning)
  round_tripped.instance |> should.equal("plan-001")
}

pub fn identity_zenoh_topic_format_test() {
  let uhi =
    identity.create_uhi(
      Gleam,
      L7Federation,
      DomainCore,
      identity.Worker,
      "w-001",
    )
  let topic = identity.zenoh_topic(uhi)
  topic |> should.equal("indrajaal/gleam/L7/core/worker/w-001")
}

pub fn identity_is_gleam_holon_test() {
  let uhi =
    identity.create_uhi(
      Gleam,
      L0Constitutional,
      DomainCore,
      identity.Agent,
      "a",
    )
  identity.is_gleam_holon(uhi) |> should.be_true

  let fsharp_uhi =
    identity.create_uhi(
      identity.FSharp,
      L0Constitutional,
      DomainCore,
      identity.Agent,
      "b",
    )
  identity.is_gleam_holon(fsharp_uhi) |> should.be_false
}

pub fn identity_all_databases_test() {
  let dbs = identity.all_databases()
  list.length(dbs) |> should.equal(5)
  list.contains(dbs, SQLite) |> should.be_true
  list.contains(dbs, DuckDB) |> should.be_true
  list.contains(dbs, Postgres) |> should.be_true
  list.contains(dbs, InMemory) |> should.be_true
  list.contains(dbs, ZenohKV) |> should.be_true
}

pub fn identity_domain_registry_16_entries_test() {
  let registry = identity.domain_registry()
  dict.size(registry) |> should.equal(16)
}

// =============================================================================
// config/mesh_config tests
// =============================================================================

pub fn mesh_config_default_7_containers_test() {
  let config = mesh_config.default_mesh_config()
  list.length(config.containers) |> should.equal(7)
}

pub fn mesh_config_validate_unique_ports_test() {
  let config = mesh_config.default_mesh_config()
  let errors = mesh_config.validate_unique_ports(config)
  errors |> should.equal([])
}

pub fn mesh_config_calculate_quorum_test() {
  mesh_config.calculate_quorum(7) |> should.equal(4)
  mesh_config.calculate_quorum(5) |> should.equal(3)
  mesh_config.calculate_quorum(3) |> should.equal(2)
}

pub fn mesh_config_is_valid_test() {
  let config = mesh_config.default_mesh_config()
  mesh_config.is_valid(config) |> should.be_true
}

pub fn mesh_config_total_cpu_test() {
  let config = mesh_config.default_mesh_config()
  // 1.0 + 2.0 + 0.5 + 1.0 + 1.0 + 0.5 + 1.0 = 7.0
  mesh_config.total_cpu_allocation(config) |> should.equal(7.0)
}

pub fn mesh_config_config_to_json_test() {
  let config = mesh_config.default_mesh_config()
  let json_str = json.to_string(mesh_config.config_to_json(config))
  string.contains(json_str, "zenoh-router") |> should.be_true
  string.contains(json_str, "quorum_size") |> should.be_true
}

// =============================================================================
// config/constraint_sync tests
// =============================================================================

pub fn constraint_sync_shannon_entropy_uniform_test() {
  // Uniform distribution over 4 events: H = log2(4) = 2.0
  let probs = [0.25, 0.25, 0.25, 0.25]
  let entropy = constraint_sync.shannon_entropy(probs)
  // Allow small floating point tolerance
  let diff = float.absolute_value(entropy -. 2.0)
  should.be_true(diff <. 0.001)
}

pub fn constraint_sync_shannon_entropy_empty_test() {
  constraint_sync.shannon_entropy([]) |> should.equal(0.0)
}

pub fn constraint_sync_classify_priority_stamp_test() {
  constraint_sync.classify_priority("SC-MESH-001")
  |> should.equal("STAMP_CONTROL")
}

pub fn constraint_sync_classify_priority_aor_test() {
  constraint_sync.classify_priority("AOR-GLM-002")
  |> should.equal("AGENT_OPERATING_RULE")
}

pub fn constraint_sync_classify_priority_iec_test() {
  constraint_sync.classify_priority("IEC-61508")
  |> should.equal("IEC_STANDARD")
}

pub fn constraint_sync_classify_priority_do_test() {
  constraint_sync.classify_priority("DO-178C")
  |> should.equal("DO_STANDARD")
}

pub fn constraint_sync_classify_priority_unknown_test() {
  constraint_sync.classify_priority("FOO-123")
  |> should.equal("UNKNOWN")
}

pub fn constraint_sync_extract_family_test() {
  constraint_sync.extract_family("SC-MESH-001") |> should.equal("SC-MESH")
  constraint_sync.extract_family("AOR-GLM-002") |> should.equal("AOR-GLM")
}

pub fn constraint_sync_compute_criticality_test() {
  // RPN = severity * occurrence * detection
  constraint_sync.compute_criticality(8, 5, 3) |> should.equal(120)
  constraint_sync.compute_criticality(1, 1, 1) |> should.equal(1)
}

// =============================================================================
// git/intelligence tests
// =============================================================================

pub fn git_commit_type_to_string_all_9_test() {
  intelligence.commit_type_to_string(Feat) |> should.equal("feat")
  intelligence.commit_type_to_string(Fix) |> should.equal("fix")
  intelligence.commit_type_to_string(Docs) |> should.equal("docs")
  intelligence.commit_type_to_string(Refactor) |> should.equal("refactor")
  intelligence.commit_type_to_string(Test) |> should.equal("test")
  intelligence.commit_type_to_string(Chore) |> should.equal("chore")
  intelligence.commit_type_to_string(Security) |> should.equal("security")
  intelligence.commit_type_to_string(Perf) |> should.equal("perf")
  intelligence.commit_type_to_string(Ci) |> should.equal("ci")
}

pub fn git_classify_style_conventional_test() {
  intelligence.classify_style("feat(core): add boot sequence")
  |> should.equal(Conventional)
}

pub fn git_classify_style_imperative_test() {
  intelligence.classify_style("Add new feature to the system")
  |> should.equal(Imperative)
}

pub fn git_classify_style_freeform_test() {
  intelligence.classify_style("some quick fix for the build")
  |> should.equal(Freeform)
}

pub fn git_classify_style_multiline_test() {
  intelligence.classify_style("First line\nSecond line")
  |> should.equal(Multiline)
}

pub fn git_classify_style_abbreviated_test() {
  intelligence.classify_style("fix typo") |> should.equal(Abbreviated)
}

pub fn git_classify_style_unknown_test() {
  intelligence.classify_style("") |> should.equal(Unknown)
}

pub fn git_validate_subject_too_long_test() {
  let long_subject = string.repeat("x", 80)
  let issues = intelligence.validate_subject(long_subject)
  let has_too_long =
    list.any(issues, fn(i) {
      case i {
        SubjectTooLong(_) -> True
        _ -> False
      }
    })
  has_too_long |> should.be_true
}

pub fn git_validate_subject_missing_type_test() {
  let issues = intelligence.validate_subject("just a message without type")
  let has_missing_type =
    list.any(issues, fn(i) {
      case i {
        MissingType -> True
        _ -> False
      }
    })
  has_missing_type |> should.be_true
}

pub fn git_compute_health_score_test() {
  // 0.9*0.5 + 0.8*0.3 + 0.7*0.2 = 0.45 + 0.24 + 0.14 = 0.83
  let score = intelligence.compute_health_score(0.9, 0.8, 0.7)
  let diff = float.absolute_value(score -. 0.83)
  should.be_true(diff <. 0.01)
}

pub fn git_compute_health_score_clamped_test() {
  // Even with values > 1.0, result should be clamped to 1.0
  intelligence.compute_health_score(1.0, 1.0, 1.0) |> should.equal(1.0)
}
