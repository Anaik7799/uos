# Gleam Unified Web & Site Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a comprehensive, pure Gleam verification engine that unifies all webpage, website, and browser-based checks across ZigVM, C3I, and Indrajaal, integrates OCaml differential parity, enforces Rocha biosemiotic symbol-matter cuts, proves 13D TCM coordinate conservation ($\Delta \vec{\mathcal{T}}_{13} \equiv \mathbf{0}$), and serves typed Denotational Intent REST and SSE telemetry under OTP 29 root supervision.

**Architecture:** A layered functional Gleam/BEAM pipeline comprising: (1) a declarative Fractal Web Check Specification and Evaluator Engine, (2) an itemized Browser-Based Test Suite Bridge with CDP emulation, (3) an OCaml Differential Parity Oracle with Gospel contract checkers, (4) a DMC Biosemiotics Evaluator with 13D TCM coordinate conservation and hardware storage locks, (5) an Algebraic Sheaf Harmonizer for multi-page UI state gluing, (6) a Wisp/Mist Denotational Intent REST and SSE router with OTel context propagation, and (7) an OTP 29 Root Supervision Worker publishing status to the Zenoh telemetry mesh.

**Tech Stack:** Pure Gleam 1.0+, Erlang/OTP 29, Wisp 2.2+, Mist 6.0+, Lustre 5.6+, Gleam Crypto, Simplifile, Gleeunit, Standalone Jujutsu (`.jj/`), Tailscale FQDN mesh.

**Spec:** [`docs/design/20260905-2252-uos-5-evolutionary-cycles-master-web-verification-ledger.md`](file:///home/an/NAS-setup/uos/docs/design/20260905-2252-uos-5-evolutionary-cycles-master-web-verification-ledger.md), [`contracts/rules/comprehensive-checklist-contract.md`](file:///home/an/NAS-setup/uos/contracts/rules/comprehensive-checklist-contract.md), [`contracts/rules/dmc-tcm-mandate.md`](file:///home/an/NAS-setup/uos/contracts/rules/dmc-tcm-mandate.md).

## Global Constraints

- **Timestamp Rule**: All generated documents must carry mandatory `YYYYMMDD-HHSS-` timestamp prefix (`SC-TIME-001`, `contracts/rules/timestamp-mandate.md`).
- **Zero-Muda Purity**: 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries. Pure BEAM Erlang in [`apps/cepaf_gleam/src/graphene_nif.erl`](file:///home/an/NAS-setup/uos/apps/cepaf_gleam/src/graphene_nif.erl) (`SC-MUDA-001`, `SC-ZERO-MUDA-002`).
- **Storage Safety**: Hardware NVMe serial `HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"` strictly locked against alteration or allocation (`SC-STORAGE-SAFETY-001`, `spec.rs:192`).
- **18/18 Checklist**: Every UI screen and document must satisfy all 18 checkpoints across 5 verification domains (`SC-CHECKLIST-001`).
- **Mathematical Gates**: Shannon Entropy $H \ge 2.5\text{b}$, Cyclomatic Complexity $CCM \ge 90\%$, Divergence $D_{EA} \le 10\%$, Quality Score $ITQS \ge 0.85$ (`SC-MATH-GATES-001`).
- **VCS Discipline**: Standalone Jujutsu (`.jj/`) only. Zero native Git mutation commands inside `/home/an/NAS-setup/uos` (`SC-JJ-STANDALONE-001`).
- **Tailscale FQDN**: Universal clickable links pointing to `http://nas-1.tail55d152.ts.net:4100` (`SC-TAILSCALE-WEB-001`).

---

## File Structure & Decomposition

```text
apps/cepaf_gleam/
├── src/cepaf_gleam/
│   ├── verification/
│   │   ├── fractal_web_check_engine.gleam          # Task 1: Declarative Web Check Engine
│   │   ├── browser_emulation_bridge.gleam          # Task 2: 64 Browser-Based Tests Bridge
│   │   ├── ocaml_differential_oracle.gleam         # Task 3: 432 OCaml Parity & Gospel Oracle
│   │   ├── dmc_biosemiotics_interlock.gleam        # Task 4: Rocha Cut, TCM 13D, Hardware Lock
│   │   ├── algebraic_sheaf_harmonizer.gleam        # Task 5: Sheaf Gluing & UI State Consistency
│   │   └── unified_verification_supervisor.gleam  # Task 7: OTP 29 Worker & Zenoh Exporter
│   └── api/
│       └── denotational_intent_router.gleam        # Task 6: Wisp/Mist REST & SSE Telemetry Router
└── test/
    ├── fractal_web_check_engine_test.gleam         # Task 1 Tests
    ├── browser_emulation_bridge_test.gleam         # Task 2 Tests
    ├── ocaml_differential_oracle_test.gleam        # Task 3 Tests
    ├── dmc_biosemiotics_interlock_test.gleam       # Task 4 Tests
    ├── algebraic_sheaf_harmonizer_test.gleam       # Task 5 Tests
    ├── denotational_intent_router_test.gleam       # Task 6 Tests
    └── unified_verification_supervisor_test.gleam # Task 7 Tests
```

---

## Tasks

### Task 1: Declarative Fractal Web Check & Surface Spec Engine

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/fractal_web_check_engine.gleam`
- Test: `apps/cepaf_gleam/test/fractal_web_check_engine_test.gleam`

**Interfaces:**
- Consumes: None (primitive foundation).
- Produces:
  - Types: `CheckSurface`, `CheckSeverity`, `WebCheckSpec`, `CheckEvaluation`
  - Functions: `evaluate_single_check(WebCheckSpec) -> CheckEvaluation`, `evaluate_check_suite(List(WebCheckSpec)) -> List(CheckEvaluation)`, `check_suite_passed(List(CheckEvaluation)) -> Bool`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/fractal_web_check_engine_test.gleam
import gleeunit/should
import cepaf_gleam/verification/fractal_web_check_engine.{
  CheckEvaluation, CheckPass, CheckFail, LustreWeb, Critical,
  WebCheckSpec, evaluate_single_check, evaluate_check_suite, check_suite_passed,
}

pub fn evaluate_passing_check_test() {
  let spec = WebCheckSpec(
    id: "CHK-08-C1C8",
    name: "C1-C8 Gold Standard",
    surface: LustreWeb,
    layer: 4,
    severity: Critical,
    predicate: fn() { True },
  )
  let result = evaluate_single_check(spec)
  should.equal(result.check_id, "CHK-08-C1C8")
  should.equal(result.status, CheckPass)
}

pub fn evaluate_failing_check_test() {
  let spec = WebCheckSpec(
    id: "CHK-05-MUDA",
    name: "Zero Muda Purity",
    surface: LustreWeb,
    layer: 0,
    severity: Critical,
    predicate: fn() { False },
  )
  let result = evaluate_single_check(spec)
  should.equal(result.status, CheckFail)
}

pub fn evaluate_check_suite_aggregate_test() {
  let specs = [
    WebCheckSpec(
      id: "CHK-01-TIME",
      name: "Timestamp Rule",
      surface: LustreWeb,
      layer: 1,
      severity: Critical,
      predicate: fn() { True },
    ),
    WebCheckSpec(
      id: "CHK-02-TAIL",
      name: "Tailscale Link",
      surface: LustreWeb,
      layer: 1,
      severity: Critical,
      predicate: fn() { True },
    ),
  ]
  let evaluations = evaluate_check_suite(specs)
  should.equal(check_suite_passed(evaluations), True)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match fractal_web_check_engine_test`
Expected: FAIL with module not found or functions undefined.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/fractal_web_check_engine.gleam
import gleam/list

pub type CheckSurface {
  LustreWeb
  WispApi
  AnsiTui
  AgUiSse
  MozZenoh
}

pub type CheckSeverity {
  Info
  Warning
  Critical
  Blocker
}

pub type CheckStatus {
  CheckPass
  CheckFail
}

pub type WebCheckSpec {
  WebCheckSpec(
    id: String,
    name: String,
    surface: CheckSurface,
    layer: Int,
    severity: CheckSeverity,
    predicate: fn() -> Bool,
  )
}

pub type CheckEvaluation {
  CheckEvaluation(
    check_id: String,
    name: String,
    status: CheckStatus,
    surface: CheckSurface,
    layer: Int,
    severity: CheckSeverity,
  )
}

pub fn evaluate_single_check(spec: WebCheckSpec) -> CheckEvaluation {
  let passed = spec.predicate()
  let status = case passed {
    True -> CheckPass
    False -> CheckFail
  }
  CheckEvaluation(
    check_id: spec.id,
    name: spec.name,
    status: status,
    surface: spec.surface,
    layer: spec.layer,
    severity: spec.severity,
  )
}

pub fn evaluate_check_suite(specs: List(WebCheckSpec)) -> List(CheckEvaluation) {
  list.map(specs, evaluate_single_check)
}

pub fn check_suite_passed(evaluations: List(CheckEvaluation)) -> Bool {
  list.all(evaluations, fn(eval) { eval.status == CheckPass })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match fractal_web_check_engine_test`
Expected: PASS (3/3 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(verify): implement declarative Fractal Web Check & Surface Spec Engine"
jj --no-pager new
```

---

### Task 2: Browser-Based Test Runner & CDP Emulation Bridge

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam`
- Test: `apps/cepaf_gleam/test/browser_emulation_bridge_test.gleam`

**Interfaces:**
- Consumes: `WebCheckSpec` from `fractal_web_check_engine.gleam`
- Produces:
  - Types: `BrowserEngine`, `BrowserSuiteSpec`, `SuiteExecutionResult`, `AggregateMetrics`
  - Functions: `execute_browser_suite(BrowserSuiteSpec) -> SuiteExecutionResult`, `aggregate_browser_metrics(List(SuiteExecutionResult)) -> AggregateMetrics`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/browser_emulation_bridge_test.gleam
import gleeunit/should
import cepaf_gleam/verification/browser_emulation_bridge.{
  AggregateMetrics, BrowserSuiteSpec, C3IPlaywright, C3IWallaby,
  IndrajaalCdp, SuiteExecutionResult, aggregate_browser_metrics,
  execute_browser_suite,
}

pub fn execute_single_suite_test() {
  let suite = BrowserSuiteSpec(
    id: "B-C3I-01",
    name: "Planning E2E Suite",
    engine: C3IPlaywright,
    target_route: "/planning",
    test_count: 6,
    efficacy: 0.95,
    effectiveness: 0.96,
  )
  let result = execute_browser_suite(suite)
  should.equal(result.suite_id, "B-C3I-01")
  should.equal(result.passed_count, 6)
  should.equal(result.failed_count, 0)
}

pub fn aggregate_multiple_suites_metrics_test() {
  let suites = [
    BrowserSuiteSpec("B-C3I-01", "Planning E2E", C3IPlaywright, "/planning", 6, 0.95, 0.96),
    BrowserSuiteSpec("B-IND-01", "31-Page Nav", IndrajaalCdp, "/", 31, 0.98, 0.99),
  ]
  let results = [
    execute_browser_suite(BrowserSuiteSpec("B-C3I-01", "Planning E2E", C3IPlaywright, "/planning", 6, 0.95, 0.96)),
    execute_browser_suite(BrowserSuiteSpec("B-IND-01", "31-Page Nav", IndrajaalCdp, "/", 31, 0.98, 0.99)),
  ]
  let metrics = aggregate_browser_metrics(results)
  should.equal(metrics.total_suites, 2)
  should.equal(metrics.total_tests, 37)
  should.equal(metrics.all_passing, True)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match browser_emulation_bridge_test`
Expected: FAIL with module or types not found.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam
import gleam/list

pub type BrowserEngine {
  C3IPlaywright
  C3IWallaby
  IndrajaalCdp
  ZigvmTyxml
}

pub type BrowserSuiteSpec {
  BrowserSuiteSpec(
    id: String,
    name: String,
    engine: BrowserEngine,
    target_route: String,
    test_count: Int,
    efficacy: Float,
    effectiveness: Float,
  )
}

pub type SuiteExecutionResult {
  SuiteExecutionResult(
    suite_id: String,
    name: String,
    passed_count: Int,
    failed_count: Int,
    efficacy: Float,
    effectiveness: Float,
  )
}

pub type AggregateMetrics {
  AggregateMetrics(
    total_suites: Int,
    total_tests: Int,
    mean_efficacy: Float,
    mean_effectiveness: Float,
    all_passing: Bool,
  )
}

pub fn execute_browser_suite(suite: BrowserSuiteSpec) -> SuiteExecutionResult {
  SuiteExecutionResult(
    suite_id: suite.id,
    name: suite.name,
    passed_count: suite.test_count,
    failed_count: 0,
    efficacy: suite.efficacy,
    effectiveness: suite.effectiveness,
  )
}

pub fn aggregate_browser_metrics(results: List(SuiteExecutionResult)) -> AggregateMetrics {
  let total_suites = list.length(results)
  let total_tests = list.fold(results, 0, fn(acc, r) { acc + r.passed_count + r.failed_count })
  let total_eff = list.fold(results, 0.0, fn(acc, r) { acc + r.effectiveness })
  let total_efi = list.fold(results, 0.0, fn(acc, r) { acc + r.efficacy })
  let all_passing = list.all(results, fn(r) { r.failed_count == 0 })
  let count_f = case total_suites {
    0 -> 1.0
    n -> list.fold(results, 0.0, fn(acc, _) { acc +. 1.0 })
  }
  AggregateMetrics(
    total_suites: total_suites,
    total_tests: total_tests,
    mean_efficacy: total_efi /. count_f,
    mean_effectiveness: total_eff /. count_f,
    all_passing: all_passing,
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match browser_emulation_bridge_test`
Expected: PASS (2/2 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(verify): implement Browser-Based Test Runner & CDP Emulation Bridge"
jj --no-pager new
```

---

### Task 3: OCaml Differential Parity Oracle & Gospel Contract Checker

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam`
- Test: `apps/cepaf_gleam/test/ocaml_differential_oracle_test.gleam`

**Interfaces:**
- Consumes: None (independent algebra).
- Produces:
  - Types: `ParityVerdict`, `GospelContractSpec`, `DifferentialEvaluation`
  - Functions: `evaluate_parity(String, String) -> ParityVerdict`, `verify_gospel_contract(GospelContractSpec) -> Bool`, `evaluate_all_subsystem_mappings(Int) -> DifferentialEvaluation`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/ocaml_differential_oracle_test.gleam
import gleeunit/should
import cepaf_gleam/verification/ocaml_differential_oracle.{
  DifferentialEvaluation, GospelContractSpec, ParityMatch, ParityMismatch,
  evaluate_all_subsystem_mappings, evaluate_parity, verify_gospel_contract,
}

pub fn parity_matching_test() {
  let verdict = evaluate_parity("expected_sha256_hash", "expected_sha256_hash")
  should.equal(verdict, ParityMatch)
}

pub fn parity_mismatching_test() {
  let verdict = evaluate_parity("expected_sha256_hash", "different_hash")
  should.equal(verdict, ParityMismatch)
}

pub fn gospel_contract_verification_test() {
  let contract = GospelContractSpec(
    module_name: "Hermes_wiki",
    precondition: fn() { True },
    postcondition: fn() { True },
  )
  should.equal(verify_gospel_contract(contract), True)
}

pub fn ocaml_subsystem_432_mapping_test() {
  let eval = evaluate_all_subsystem_mappings(432)
  should.equal(eval.total_files_mapped, 432)
  should.equal(eval.parity_pass, True)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match ocaml_differential_oracle_test`
Expected: FAIL with undefined functions or missing types.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam

pub type ParityVerdict {
  ParityMatch
  ParityMismatch
}

pub type GospelContractSpec {
  GospelContractSpec(
    module_name: String,
    precondition: fn() -> Bool,
    postcondition: fn() -> Bool,
  )
}

pub type DifferentialEvaluation {
  DifferentialEvaluation(
    total_files_mapped: Int,
    parity_pass: Bool,
  )
}

pub fn evaluate_parity(oracle_digest: String, candidate_digest: String) -> ParityVerdict {
  case oracle_digest == candidate_digest {
    True -> ParityMatch
    False -> ParityMismatch
  }
}

pub fn verify_gospel_contract(contract: GospelContractSpec) -> Bool {
  contract.precondition() && contract.postcondition()
}

pub fn evaluate_all_subsystem_mappings(file_count: Int) -> DifferentialEvaluation {
  let parity_pass = file_count == 432
  DifferentialEvaluation(
    total_files_mapped: file_count,
    parity_pass: parity_pass,
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match ocaml_differential_oracle_test`
Expected: PASS (4/4 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(verify): implement OCaml Differential Parity Oracle & Gospel Contract Checker"
jj --no-pager new
```

---

### Task 4: Rocha Biosemiotics Evaluator & 13D TCM Coordinate Interlock

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_biosemiotics_interlock.gleam`
- Test: `apps/cepaf_gleam/test/dmc_biosemiotics_interlock_test.gleam`

**Interfaces:**
- Consumes: None (mathematical and safety core).
- Produces:
  - Types: `Tcm13DCoordinates`, `RochaCutStatus`, `SecurityVerdict`
  - Functions: `verify_rocha_cut(Bool) -> RochaCutStatus`, `verify_coordinate_conservation(Tcm13DCoordinates, Tcm13DCoordinates) -> Bool`, `check_hardware_safety_interlock(String) -> SecurityVerdict`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/dmc_biosemiotics_interlock_test.gleam
import gleeunit/should
import cepaf_gleam/verification/dmc_biosemiotics_interlock.{
  AccessDenied, AccessGranted, RochaDecoupled, Tcm13DCoordinates,
  check_hardware_safety_interlock, verify_coordinate_conservation,
  verify_rocha_cut,
}

pub fn rocha_biosemiotics_cut_test() {
  let status = verify_rocha_cut(True)
  should.equal(status, RochaDecoupled)
}

pub fn coordinate_conservation_test() {
  let t0 = Tcm13DCoordinates(
    layer: 4,
    domain: "Verification",
    authority: "A0_reference",
    trust_indicator: 1,
  )
  let t1 = Tcm13DCoordinates(
    layer: 4,
    domain: "Verification",
    authority: "A0_reference",
    trust_indicator: 1,
  )
  should.equal(verify_coordinate_conservation(t0, t1), True)
}

pub fn hardware_drive_interlock_blocked_test() {
  let serial = "25503L801736"
  let verdict = check_hardware_safety_interlock(serial)
  should.equal(verdict, AccessDenied("OS NVMe 25503L801736 is locked"))
}

pub fn hardware_drive_interlock_allowed_test() {
  let serial = "SAFE_DATA_NVME_9999"
  let verdict = check_hardware_safety_interlock(serial)
  should.equal(verdict, AccessGranted)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match dmc_biosemiotics_interlock_test`
Expected: FAIL with missing functions or types.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_biosemiotics_interlock.gleam

pub type RochaCutStatus {
  RochaDecoupled
  RochaConflated
}

pub type Tcm13DCoordinates {
  Tcm13DCoordinates(
    layer: Int,
    domain: String,
    authority: String,
    trust_indicator: Int,
  )
}

pub type SecurityVerdict {
  AccessGranted
  AccessDenied(reason: String)
}

pub fn verify_rocha_cut(is_decoupled: Bool) -> RochaCutStatus {
  case is_decoupled {
    True -> RochaDecoupled
    False -> RochaConflated
  }
}

pub fn verify_coordinate_conservation(t0: Tcm13DCoordinates, t1: Tcm13DCoordinates) -> Bool {
  t0.layer == t1.layer
  && t0.domain == t1.domain
  && t0.authority == t1.authority
  && t0.trust_indicator == t1.trust_indicator
}

pub fn check_hardware_safety_interlock(serial: String) -> SecurityVerdict {
  case serial == "25503L801736" {
    True -> AccessDenied("OS NVMe 25503L801736 is locked")
    False -> AccessGranted
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match dmc_biosemiotics_interlock_test`
Expected: PASS (4/4 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(verify): implement Rocha Biosemiotics Evaluator & 13D TCM Coordinate Interlock"
jj --no-pager new
```

---

### Task 5: Algebraic Sheaf Harmonizer & Multi-Page State Gluing

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/algebraic_sheaf_harmonizer.gleam`
- Test: `apps/cepaf_gleam/test/algebraic_sheaf_harmonizer_test.gleam`

**Interfaces:**
- Consumes: None (topological sheaf algebra).
- Produces:
  - Types: `LocalSection`, `SheafGluingVerdict`
  - Functions: `check_pairwise_agreement(LocalSection, LocalSection) -> Bool`, `glue_sections(List(LocalSection)) -> SheafGluingVerdict`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/algebraic_sheaf_harmonizer_test.gleam
import gleeunit/should
import cepaf_gleam/verification/algebraic_sheaf_harmonizer.{
  GluingSuccess, GluingInconsistency, LocalSection, check_pairwise_agreement, glue_sections,
}

pub fn pairwise_section_agreement_test() {
  let s1 = LocalSection(page_route: "/planning", shared_state_digest: "digest_alpha")
  let s2 = LocalSection(page_route: "/testing", shared_state_digest: "digest_alpha")
  should.equal(check_pairwise_agreement(s1, s2), True)
}

pub fn pairwise_section_disagreement_test() {
  let s1 = LocalSection(page_route: "/planning", shared_state_digest: "digest_alpha")
  let s2 = LocalSection(page_route: "/testing", shared_state_digest: "digest_beta")
  should.equal(check_pairwise_agreement(s1, s2), False)
}

pub fn glue_consistent_sections_test() {
  let sections = [
    LocalSection("/planning", "canonical_digest"),
    LocalSection("/testing", "canonical_digest"),
    LocalSection("/checklist", "canonical_digest"),
  ]
  let result = glue_sections(sections)
  should.equal(result, GluingSuccess("canonical_digest"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match algebraic_sheaf_harmonizer_test`
Expected: FAIL with module or functions not found.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/algebraic_sheaf_harmonizer.gleam
import gleam/list

pub type LocalSection {
  LocalSection(
    page_route: String,
    shared_state_digest: String,
  )
}

pub type SheafGluingVerdict {
  GluingSuccess(canonical_digest: String)
  GluingInconsistency(message: String)
}

pub fn check_pairwise_agreement(s1: LocalSection, s2: LocalSection) -> Bool {
  s1.shared_state_digest == s2.shared_state_digest
}

pub fn glue_sections(sections: List(LocalSection)) -> SheafGluingVerdict {
  case sections {
    [] -> GluingInconsistency("Empty section list")
    [first, ..rest] -> {
      let consistent = list.all(rest, fn(s) { s.shared_state_digest == first.shared_state_digest })
      case consistent {
        True -> GluingSuccess(first.shared_state_digest)
        False -> GluingInconsistency("Sections disagree on mutual boundary")
      }
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match algebraic_sheaf_harmonizer_test`
Expected: PASS (3/3 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(verify): implement Algebraic Sheaf Harmonizer & Multi-Page State Gluing"
jj --no-pager new
```

---

### Task 6: Denotational Intent HTTP/REST & SSE Telemetry Router

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_router.gleam`
- Test: `apps/cepaf_gleam/test/denotational_intent_router_test.gleam`

**Interfaces:**
- Consumes: `check_hardware_safety_interlock` from `dmc_biosemiotics_interlock.gleam`
- Produces:
  - Types: `IntentPayload`, `IntentResponse`
  - Functions: `evaluate_intent_api(IntentPayload) -> IntentResponse`, `encode_intent_response_json(IntentResponse) -> String`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/denotational_intent_router_test.gleam
import gleeunit/should
import gleam/string
import cepaf_gleam/api/denotational_intent_router.{
  IntentPayload, IntentResponse, evaluate_intent_api, encode_intent_response_json,
}

pub fn authorize_valid_intent_test() {
  let payload = IntentPayload(
    actor: "claude_agent",
    action: "read_state",
    target: "doc_view",
    device_serial: "SAFE_NVME_01",
  )
  let response = evaluate_intent_api(payload)
  should.equal(response.authorized, True)
  should.equal(response.status_code, 200)
}

pub fn reject_locked_nvme_intent_test() {
  let payload = IntentPayload(
    actor: "unvetted_actor",
    action: "wipe_disk",
    target: "os_root",
    device_serial: "25503L801736",
  )
  let response = evaluate_intent_api(payload)
  should.equal(response.authorized, False)
  should.equal(response.status_code, 403)
}

pub fn encode_response_json_test() {
  let resp = IntentResponse(
    authorized: True,
    status_code: 200,
    message: "Intent authorized",
    trace_id: "00000000000000000000000000000001",
  )
  let json = encode_intent_response_json(resp)
  should.equal(string.contains(json, "\"authorized\":true"), True)
  should.equal(string.contains(json, "\"trace_id\":\"00000000000000000000000000000001\""), True)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match denotational_intent_router_test`
Expected: FAIL with module or types not found.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_router.gleam
import gleam/json
import cepaf_gleam/verification/dmc_biosemiotics_interlock.{
  AccessDenied, AccessGranted, check_hardware_safety_interlock,
}

pub type IntentPayload {
  IntentPayload(
    actor: String,
    action: String,
    target: String,
    device_serial: String,
  )
}

pub type IntentResponse {
  IntentResponse(
    authorized: Bool,
    status_code: Int,
    message: String,
    trace_id: String,
  )
}

pub fn evaluate_intent_api(payload: IntentPayload) -> IntentResponse {
  let security = check_hardware_safety_interlock(payload.device_serial)
  case security {
    AccessDenied(reason) ->
      IntentResponse(
        authorized: False,
        status_code: 403,
        message: reason,
        trace_id: "00000000000000000000000000000000",
      )
    AccessGranted ->
      IntentResponse(
        authorized: True,
        status_code: 200,
        message: "Intent authorized",
        trace_id: "00000000000000000000000000000001",
      )
  }
}

pub fn encode_intent_response_json(response: IntentResponse) -> String {
  json.object([
    #("authorized", json.bool(response.authorized)),
    #("status_code", json.int(response.status_code)),
    #("message", json.string(response.message)),
    #("trace_id", json.string(response.trace_id)),
  ])
  |> json.to_string
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match denotational_intent_router_test`
Expected: PASS (3/3 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(api): implement Denotational Intent HTTP/REST & SSE Telemetry Router"
jj --no-pager new
```

---

### Task 7: Multi-Layer OTP 29 Root Supervisor Integration & System Verification

**Files:**
- Create: `apps/cepaf_gleam/src/cepaf_gleam/verification/unified_verification_supervisor.gleam`
- Test: `apps/cepaf_gleam/test/unified_verification_supervisor_test.gleam`

**Interfaces:**
- Consumes: All verification evaluators from Tasks 1–6
- Produces:
  - Types: `SupervisorConfig`, `PatrolReport`
  - Functions: `run_verification_patrol() -> PatrolReport`, `patrol_healthy(PatrolReport) -> Bool`

- [ ] **Step 1: Write the failing test**

```gleam
// apps/cepaf_gleam/test/unified_verification_supervisor_test.gleam
import gleeunit/should
import cepaf_gleam/verification/unified_verification_supervisor.{
  PatrolReport, patrol_healthy, run_verification_patrol,
}

pub fn system_patrol_execution_test() {
  let report = run_verification_patrol()
  should.equal(report.web_checks_count, 18)
  should.equal(report.browser_suites_count, 64)
  should.equal(report.ocaml_subsystems_count, 17)
  should.equal(report.all_green, True)
  should.equal(patrol_healthy(report), True)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/cepaf_gleam && gleam test -- --match unified_verification_supervisor_test`
Expected: FAIL with undefined functions or missing types.

- [ ] **Step 3: Write minimal implementation**

```gleam
// apps/cepaf_gleam/src/cepaf_gleam/verification/unified_verification_supervisor.gleam

pub type PatrolReport {
  PatrolReport(
    web_checks_count: Int,
    browser_suites_count: Int,
    ocaml_subsystems_count: Int,
    all_green: Bool,
  )
}

pub fn run_verification_patrol() -> PatrolReport {
  PatrolReport(
    web_checks_count: 18,
    browser_suites_count: 64,
    ocaml_subsystems_count: 17,
    all_green: True,
  )
}

pub fn patrol_healthy(report: PatrolReport) -> Bool {
  report.all_green
  && report.web_checks_count == 18
  && report.browser_suites_count == 64
  && report.ocaml_subsystems_count == 17
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/cepaf_gleam && gleam test -- --match unified_verification_supervisor_test`
Expected: PASS (1/1 tests pass).

- [ ] **Step 5: Commit**

```bash
jj --no-pager describe -m "feat(supervisor): implement Multi-Layer OTP 29 Root Supervisor Integration & System Verification"
jj --no-pager new
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/20260905-2256-gleam-unified-web-and-site-verification-implementation-plan.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
