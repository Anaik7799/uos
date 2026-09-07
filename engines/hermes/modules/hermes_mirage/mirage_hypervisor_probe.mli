(** Unified Operational System (UOS) - Hermes Mirage Hypervisor Capability Probe *)
(** Probes host hardware virtualization (/dev/kvm), QEMU microvm, and Solo5 tender environments *)
(** Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

type kvm_status = {
  dev_kvm_present : bool;
  dev_kvm_rw_accessible : bool;
  api_version : int option;
}

type qemu_status = {
  binary_path : string option;
  microvm_supported : bool;
  kvm_accel_supported : bool;
}

type solo5_status = {
  solo5_hvt_path : string option;
  solo5_spt_path : string option;
}

type hypervisor_probe_result = {
  schema : string;
  timestamp_utc : string;
  host : string;
  kvm : kvm_status;
  qemu : qemu_status;
  solo5 : solo5_status;
  overall_readiness : string;
  execution_policy : string;
}

val probe_hypervisors : unit -> hypervisor_probe_result

val probe_to_json : hypervisor_probe_result -> Yojson.Safe.t
