import gleam/list
import gleeunit/should
import main

// Source predicates and historical receipt strings must never establish admission.
pub fn artifact_only_gates_refuse_admission_test() {
  list.each([
    "G-MAX-MOJO-MODELS",
    "G-SA-PLAN-JIDOKA",
    "G-HIVE-FORECAST",
    "G-MIRAGE-TENDERS",
    "G-MIRAGE-PROD",
    "G-MIRAGE-MIGRATE",
    "G-MIRAGE",
    "G-RAGA-SYNTHESIS",
    "G-CODEX-ASTRA-GAP-ZERO",
    "G-CODEX-ASTRA-DEEP",
    "G-CODEX-ASTRA-EXPANSION",
    "G-TEST-EXPANSION",
    "G-SCIVIZ-BDD",
    "G-ZIGVM-ADD",
    "G-ROCHA",
    "G-JOURNAL",
    "G-BURST-BENCH",
    "G-FEAT-IMPL",
    "G-ALL-FEAT",
    "G-CRIT-STPA-EVOL",
    "G-RISK-CAT",
    "G-COMP-CAT",
    "G-TOPOS-DOUBLE-CAT",
    "G-TRANS-CAT",
    "G-POODAVR-PREDICT",
    "G-POODAVR-FPRIME",
    "G-SUBSTRATE-CAT",
    "G-SYSTEMIC-CAT",
    "G-EVOLUTIONARY-CAT",
    "G-FRACTAL-HOLON",
    "G-CATEGORY-THEORY",
    "G-CLAUDE-VERIFY",
    "G-TRIAD-MATRIX",
    "G-CHECKLIST",
    "G-TAILSCALE-WEB",
    "G-KM-TRIAD",
    "G-CROSS-LANG",
    "G-ZERO-MUDA",
  ], fn(name) { main.execute(main.Gate(name)) |> should.equal(1) })
}

pub fn artifact_only_domains_refuse_admission_test() {
  list.each([main.DmcCheck, main.TcmCheck, main.Checklist, main.KmCheck, main.RochaCheck],
    fn(command) { main.execute(command) |> should.equal(1) })
}
