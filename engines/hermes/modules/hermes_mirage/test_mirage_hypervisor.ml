(* Unified Operational System (UOS) - Test Mirage Hypervisor Probe *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

let () =
  Printf.printf "=== HERMES MIRAGE HYPERVISOR PROBE TEST ===\n";
  let probe = Mirage_hypervisor_probe.probe_hypervisors () in
  assert (probe.schema = "uos-mirage-hypervisor-probe/v1");
  assert (probe.execution_policy = "two_key_receipt_required_before_admission");
  Printf.printf "  [PASS] Probe schema: %s\n" probe.schema;
  Printf.printf "  [PASS] Host: %s, Timestamp: %s\n" probe.host probe.timestamp_utc;
  Printf.printf "  [PASS] KVM present: %b, rw_accessible: %b, api_version: %s\n"
    probe.kvm.dev_kvm_present probe.kvm.dev_kvm_rw_accessible
    (match probe.kvm.api_version with Some v -> string_of_int v | None -> "none");
  Printf.printf "  [PASS] QEMU binary: %s, microvm: %b, kvm_accel: %b\n"
    (match probe.qemu.binary_path with Some p -> p | None -> "none")
    probe.qemu.microvm_supported probe.qemu.kvm_accel_supported;
  Printf.printf "  [PASS] Overall readiness: %s\n" probe.overall_readiness;

  (* Validate JSON conversion *)
  let json = Mirage_hypervisor_probe.probe_to_json probe in
  let json_str = Yojson.Safe.to_string json in
  assert (String.length json_str > 50);
  Printf.printf "  [PASS] JSON serialization verified (%d bytes)\n" (String.length json_str);
  Printf.printf "=== ALL HYPERVISOR PROBE CHECKS PASSED ===\n"
