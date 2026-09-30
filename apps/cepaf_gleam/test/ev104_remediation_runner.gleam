import gleam/io
import ooda_shruti_copilot_test

pub fn main() {
  ooda_shruti_copilot_test.anomaly_injection_and_remediation_test()
  io.println("PASS anomaly_injection_and_remediation_test")
  ooda_shruti_copilot_test.unknown_remediation_id_leaves_state_unchanged_test()
  io.println("PASS unknown_remediation_id_leaves_state_unchanged_test")
  ooda_shruti_copilot_test.repeated_remediation_id_is_idempotent_test()
  io.println("PASS repeated_remediation_id_is_idempotent_test")
  ooda_shruti_copilot_test.unresolved_critical_anomaly_keeps_andon_active_test()
  io.println("PASS unresolved_critical_anomaly_keeps_andon_active_test")
}
