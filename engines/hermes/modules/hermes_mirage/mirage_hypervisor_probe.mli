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

type solo5_execution_receipt = {
  tender : string;
  unikernel : string;
  exit_code : int;
  output_snippet : string;
  passed : bool;
}

type solo5_status = {
  solo5_hvt_path : string option;
  solo5_spt_path : string option;
  solo5_virtio_path : string option;
  hvt_execution : solo5_execution_receipt option;
  spt_execution : solo5_execution_receipt option;
  virtio_execution : solo5_execution_receipt option;
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
  deployment_admission : string;
}

val probe_hypervisors : unit -> hypervisor_probe_result

val probe_to_json : hypervisor_probe_result -> Yojson.Safe.t

val is_allowed_tender : string -> bool

val is_successful_execution : tender:string -> exit_code:int -> output:string -> bool

val run_tender_test : string option -> string -> int list -> string list -> solo5_execution_receipt option
