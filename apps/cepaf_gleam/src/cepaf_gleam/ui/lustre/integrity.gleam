//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/integrity</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-VER-074</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Integrity page.
//// Displays hash chain verification, constitution hash, and Psi invariant status.

import gleam/option.{type Option, None, Some}

pub type IntegrityModel {
  IntegrityModel(
    constitution_hash: String,
    psi_results: List(PsiCheck),
    chain_valid: Bool,
    last_verified: String,
    loading: Bool,
    error: Option(String),
  )
}

pub type PsiCheck {
  PsiCheck(name: String, passed: Bool, detail: String)
}

pub type IntegrityMsg {
  VerificationLoaded(
    hash: String,
    checks: List(PsiCheck),
    chain_ok: Bool,
    timestamp: String,
  )
  RefreshIntegrity
  ErrorReceived(String)
}

pub fn init() -> IntegrityModel {
  IntegrityModel(
    constitution_hash: "",
    psi_results: default_psi_checks(),
    chain_valid: False,
    last_verified: "",
    loading: True,
    error: None,
  )
}

pub fn update(model: IntegrityModel, msg: IntegrityMsg) -> IntegrityModel {
  case msg {
    VerificationLoaded(hash, checks, chain_ok, ts) ->
      IntegrityModel(
        constitution_hash: hash,
        psi_results: checks,
        chain_valid: chain_ok,
        last_verified: ts,
        loading: False,
        error: None,
      )
    RefreshIntegrity -> IntegrityModel(..model, loading: True)
    ErrorReceived(e) -> IntegrityModel(..model, error: Some(e), loading: False)
  }
}

pub fn all_psi_passed(model: IntegrityModel) -> Bool {
  list_all_passed(model.psi_results)
}

fn list_all_passed(checks: List(PsiCheck)) -> Bool {
  case checks {
    [] -> True
    [c, ..rest] ->
      case c.passed {
        True -> list_all_passed(rest)
        False -> False
      }
  }
}

fn default_psi_checks() -> List(PsiCheck) {
  [
    PsiCheck(name: "Psi-0 Existence", passed: True, detail: "System alive"),
    PsiCheck(
      name: "Psi-1 Regeneration",
      passed: True,
      detail: "SQLite recoverable",
    ),
    PsiCheck(
      name: "Psi-2 History",
      passed: True,
      detail: "Append-only preserved",
    ),
    PsiCheck(
      name: "Psi-3 Verification",
      passed: True,
      detail: "Hash chain intact",
    ),
    PsiCheck(
      name: "Psi-4 Alignment",
      passed: True,
      detail: "Founder directive active",
    ),
    PsiCheck(
      name: "Psi-5 Truthfulness",
      passed: True,
      detail: "No deception in logs",
    ),
    PsiCheck(
      name: "Omega-0 Symbiotic",
      passed: True,
      detail: "Survival mandate active",
    ),
  ]
}
