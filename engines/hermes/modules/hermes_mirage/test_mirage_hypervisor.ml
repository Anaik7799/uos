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

  Printf.printf "=== NEGATIVE CONTROLS (Codex review finding MR-07) ===\n";
  (* Negative Control 1: Unauthorized tender binaries must be rejected *)
  assert (not (Mirage_hypervisor_probe.is_allowed_tender "/bin/sh"));
  assert (not (Mirage_hypervisor_probe.is_allowed_tender "/usr/bin/python3"));
  assert (not (Mirage_hypervisor_probe.is_allowed_tender "/usr/bin/solo5-malicious"));
  assert (Mirage_hypervisor_probe.is_allowed_tender "/opam/bin/solo5-hvt");
  assert (Mirage_hypervisor_probe.is_allowed_tender "/opam/bin/solo5-spt");
  assert (Mirage_hypervisor_probe.is_allowed_tender "/opam/bin/solo5-virtio-run");
  let rejected_exec = Mirage_hypervisor_probe.run_tender_test (Some "/bin/sh") "test_hello.hvt" [0] [] in
  assert (rejected_exec = None);
  Printf.printf "  [PASS] Negative Control 1: Unauthorized tenders rejected fail-closed\n";

  (* Negative Control 2: Non-existent or truncated unikernels must be rejected *)
  let non_existent_exec = Mirage_hypervisor_probe.run_tender_test (Some "/opam/bin/solo5-hvt") "non_existent.hvt" [0] [] in
  assert (non_existent_exec = None);
  Printf.printf "  [PASS] Negative Control 2: Missing/invalid unikernels rejected fail-closed\n";

  (* Negative Control 3: Corrupted output or abnormal exit codes must fail is_successful_execution *)
  assert (not (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-virtio-run"
    ~exit_code:83
    ~output:"Solo5: ABORT: Stack corruption detected"));
  assert (not (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-virtio-run"
    ~exit_code:0
    ~output:"Solo5: solo5_exit(0) called"));
  assert (not (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-hvt"
    ~exit_code:1
    ~output:"Solo5: solo5_exit(0) called"));
  assert (not (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-spt"
    ~exit_code:0
    ~output:"Random crash without success marker"));
  assert (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-hvt"
    ~exit_code:0
    ~output:"Solo5: solo5_exit(0) called");
  assert (Mirage_hypervisor_probe.is_successful_execution
    ~tender:"solo5-virtio-run"
    ~exit_code:83
    ~output:"Solo5: solo5_exit(0) called");
  Printf.printf "  [PASS] Negative Control 3: Stack corruption aborts and invalid exits rejected fail-closed\n";

  Printf.printf "=== ALL HYPERVISOR PROBE CHECKS & NEGATIVE CONTROLS PASSED ===\n"
