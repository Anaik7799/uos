//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Egress Privacy & Secret Redactor (SC-SEC-001, CHK-07)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/egress_redactor</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <topology>Fail-Closed Egress Secret Redactor & Safety Filter</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SEC-001, SC-JIDOKA-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/list
import gleam/regexp
import gleam/string

pub const denied_os_nvme_serial: String = "25503L801736"

pub const redacted_serial_placeholder: String = "[REDACTED_SYSTEM_OS_SERIAL]"

pub const redacted_token_placeholder: String = "[REDACTED_SECRET_TOKEN]"

pub type EgressVerdict {
  EgressPermitted(sanitized_text: String)
  EgressBlocked(reason: String)
}

/// Redact known system hardware secrets and credentials from outbound text.
pub fn redact_system_secrets(text: String) -> String {
  let text1 = string.replace(text, denied_os_nvme_serial, redacted_serial_placeholder)
  let text2 = case regexp.from_string("sk-or-v1-[A-Za-z0-9_\\-]+") {
    Ok(re) -> regexp.replace(re, text1, redacted_token_placeholder)
    Error(_) -> text1
  }
  let text3 = case regexp.from_string("ghp_[A-Za-z0-9_]+") {
    Ok(re) -> regexp.replace(re, text2, redacted_token_placeholder)
    Error(_) -> text2
  }
  let text4 = case regexp.from_string("ssh-ed25519 [A-Za-z0-9+/=]+") {
    Ok(re) -> regexp.replace(re, text3, redacted_token_placeholder)
    Error(_) -> text3
  }
  text4
}

/// Inspect prompt for catastrophic destructive commands and redact secrets.
/// Fails closed if the operator intent is to wipe, destroy, or format critical storage.
pub fn sanitize_outbound_prompt(prompt: String) -> Result(String, String) {
  let lower = string.lowercase(prompt)
  let has_destructive =
    list.any(
      [
        "wipe nvme",
        "wipe bay 0",
        "format disk",
        "format nvme",
        "destroy root",
        "shred /dev/nvme0",
        "rm -rf /",
      ],
      fn(pattern) { string.contains(lower, pattern) },
    )

  case has_destructive {
    True ->
      Error("egress_safety_violation: destructive_action_veto: attempt to wipe hardware storage blocked by Prajna gate")
    False -> {
      let sanitized = redact_system_secrets(prompt)
      Ok(sanitized)
    }
  }
}

/// Assess egress verdict with typed output for supervisory telemetry.
pub fn evaluate_egress(text: String) -> EgressVerdict {
  case sanitize_outbound_prompt(text) {
    Ok(clean) -> EgressPermitted(clean)
    Error(err) -> EgressBlocked(err)
  }
}
