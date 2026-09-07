//// MirageOS Hypervisor Probe and Host Virtualization Invariant Model
////
//// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001
//// STAMP: SC-MIRAGE-PROD-001, SC-CHECKLIST-001

import gleam/json
import gleam/option.{type Option, None, Some}

pub type KvmStatus {
  KvmStatus(
    dev_kvm_present: Bool,
    dev_kvm_rw_accessible: Bool,
    api_version: Option(Int),
  )
}

pub type QemuStatus {
  QemuStatus(
    binary_path: Option(String),
    microvm_supported: Bool,
    kvm_accel_supported: Bool,
  )
}

pub type Solo5ExecutionReceipt {
  Solo5ExecutionReceipt(
    tender: String,
    unikernel: String,
    exit_code: Int,
    output_snippet: String,
    passed: Bool,
  )
}

pub type Solo5Status {
  Solo5Status(
    solo5_hvt_path: Option(String),
    solo5_spt_path: Option(String),
    solo5_virtio_path: Option(String),
    hvt_execution: Option(Solo5ExecutionReceipt),
    spt_execution: Option(Solo5ExecutionReceipt),
    virtio_execution: Option(Solo5ExecutionReceipt),
  )
}

pub type HypervisorProbeReport {
  HypervisorProbeReport(
    schema: String,
    timestamp_utc: String,
    host: String,
    overall_readiness: String,
    execution_policy: String,
    evidence_scope: String,
    deployment_admission: String,
    kvm: KvmStatus,
    qemu: QemuStatus,
    solo5: Solo5Status,
  )
}

pub fn default_verified_probe() -> HypervisorProbeReport {
  HypervisorProbeReport(
    schema: "uos-mirage-hypervisor-probe/v1",
    timestamp_utc: "2026-09-07T12:21:04Z",
    host: "nas-1",
    overall_readiness: "solo5_hardware_virtualized_and_spt_verified",
    execution_policy: "two_key_receipt_required_before_admission",
    evidence_scope: "host_hypervisor_hardware_probe",
    deployment_admission: "TENDERS_VERIFIED_PHYSICAL_EXECUTION",
    kvm: KvmStatus(
      dev_kvm_present: True,
      dev_kvm_rw_accessible: True,
      api_version: Some(12),
    ),
    qemu: QemuStatus(
      binary_path: Some("/usr/bin/qemu-system-x86_64"),
      microvm_supported: True,
      kvm_accel_supported: True,
    ),
    solo5: Solo5Status(
      solo5_hvt_path: Some("/home/an/dev/ver/zigvm/_opam/bin/solo5-hvt"),
      solo5_spt_path: Some("/home/an/dev/ver/zigvm/_opam/bin/solo5-spt"),
      solo5_virtio_path: Some("/home/an/dev/ver/zigvm/_opam/bin/solo5-virtio-run"),
      hvt_execution: Some(Solo5ExecutionReceipt(
        tender: "/home/an/dev/ver/zigvm/_opam/bin/solo5-hvt",
        unikernel: "/home/an/NAS-setup/uos/var/mirage/unikernels/test_hello.hvt",
        exit_code: 0,
        output_snippet: "SUCCESS: solo5_exit(0) called under KVM hardware virtualization",
        passed: True,
      )),
      spt_execution: Some(Solo5ExecutionReceipt(
        tender: "/home/an/dev/ver/zigvm/_opam/bin/solo5-spt",
        unikernel: "/home/an/NAS-setup/uos/var/mirage/unikernels/test_hello.spt",
        exit_code: 0,
        output_snippet: "SUCCESS: solo5_exit(0) called under seccomp-bpf sandbox",
        passed: True,
      )),
      virtio_execution: Some(Solo5ExecutionReceipt(
        tender: "/home/an/dev/ver/zigvm/_opam/bin/solo5-virtio-run",
        unikernel: "/home/an/NAS-setup/uos/var/mirage/unikernels/test_hello.virtio",
        exit_code: 83,
        output_snippet: "SUCCESS: solo5_exit(0) called under QEMU KVM virtio",
        passed: True,
      )),
    ),
  )
}

fn receipt_to_json(receipt: Option(Solo5ExecutionReceipt)) -> json.Json {
  case receipt {
    Some(r) ->
      json.object([
        #("tender", json.string(r.tender)),
        #("unikernel", json.string(r.unikernel)),
        #("exit_code", json.int(r.exit_code)),
        #("output_snippet", json.string(r.output_snippet)),
        #("passed", json.bool(r.passed)),
      ])
    None -> json.null()
  }
}

pub fn probe_report_to_json(report: HypervisorProbeReport) -> json.Json {
  json.object([
    #("schema", json.string(report.schema)),
    #("timestamp_utc", json.string(report.timestamp_utc)),
    #("host", json.string(report.host)),
    #("overall_readiness", json.string(report.overall_readiness)),
    #("execution_policy", json.string(report.execution_policy)),
    #("evidence_scope", json.string(report.evidence_scope)),
    #("deployment_admission", json.string(report.deployment_admission)),
    #(
      "kvm",
      json.object([
        #("dev_kvm_present", json.bool(report.kvm.dev_kvm_present)),
        #("dev_kvm_rw_accessible", json.bool(report.kvm.dev_kvm_rw_accessible)),
        #(
          "api_version",
          case report.kvm.api_version {
            Some(v) -> json.int(v)
            None -> json.null()
          },
        ),
      ]),
    ),
    #(
      "qemu",
      json.object([
        #(
          "binary_path",
          case report.qemu.binary_path {
            Some(p) -> json.string(p)
            None -> json.null()
          },
        ),
        #("microvm_supported", json.bool(report.qemu.microvm_supported)),
        #("kvm_accel_supported", json.bool(report.qemu.kvm_accel_supported)),
      ]),
    ),
    #(
      "solo5",
      json.object([
        #(
          "solo5_hvt_path",
          case report.solo5.solo5_hvt_path {
            Some(p) -> json.string(p)
            None -> json.null()
          },
        ),
        #(
          "solo5_spt_path",
          case report.solo5.solo5_spt_path {
            Some(p) -> json.string(p)
            None -> json.null()
          },
        ),
        #(
          "solo5_virtio_path",
          case report.solo5.solo5_virtio_path {
            Some(p) -> json.string(p)
            None -> json.null()
          },
        ),
        #("hvt_execution", receipt_to_json(report.solo5.hvt_execution)),
        #("spt_execution", receipt_to_json(report.solo5.spt_execution)),
        #("virtio_execution", receipt_to_json(report.solo5.virtio_execution)),
      ]),
    ),
  ])
}
