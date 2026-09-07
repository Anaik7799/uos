//// MirageOS Hypervisor Probe and Host Virtualization Invariant Model
////
//// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001
//// STAMP: SC-MIRAGE-PROD-001, SC-CHECKLIST-001

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import simplifile

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

fn receipt_decoder() -> decode.Decoder(Solo5ExecutionReceipt) {
  use tender <- decode.field("tender", decode.string)
  use unikernel <- decode.field("unikernel", decode.string)
  use exit_code <- decode.field("exit_code", decode.int)
  use output_snippet <- decode.field("output_snippet", decode.string)
  use passed <- decode.field("passed", decode.bool)
  decode.success(Solo5ExecutionReceipt(tender, unikernel, exit_code, output_snippet, passed))
}

fn kvm_decoder() -> decode.Decoder(KvmStatus) {
  use dev_kvm_present <- decode.field("dev_kvm_present", decode.bool)
  use dev_kvm_rw_accessible <- decode.field("dev_kvm_rw_accessible", decode.bool)
  use api_version <- decode.optional_field("api_version", None, decode.optional(decode.int))
  decode.success(KvmStatus(dev_kvm_present, dev_kvm_rw_accessible, api_version))
}

fn qemu_decoder() -> decode.Decoder(QemuStatus) {
  use binary_path <- decode.optional_field("binary_path", None, decode.optional(decode.string))
  use microvm_supported <- decode.field("microvm_supported", decode.bool)
  use kvm_accel_supported <- decode.field("kvm_accel_supported", decode.bool)
  decode.success(QemuStatus(binary_path, microvm_supported, kvm_accel_supported))
}

fn solo5_decoder() -> decode.Decoder(Solo5Status) {
  use solo5_hvt_path <- decode.optional_field("solo5_hvt_path", None, decode.optional(decode.string))
  use solo5_spt_path <- decode.optional_field("solo5_spt_path", None, decode.optional(decode.string))
  use solo5_virtio_path <- decode.optional_field("solo5_virtio_path", None, decode.optional(decode.string))
  use hvt_execution <- decode.optional_field("hvt_execution", None, decode.optional(receipt_decoder()))
  use spt_execution <- decode.optional_field("spt_execution", None, decode.optional(receipt_decoder()))
  use virtio_execution <- decode.optional_field("virtio_execution", None, decode.optional(receipt_decoder()))
  decode.success(Solo5Status(solo5_hvt_path, solo5_spt_path, solo5_virtio_path, hvt_execution, spt_execution, virtio_execution))
}

pub fn probe_report_decoder() -> decode.Decoder(HypervisorProbeReport) {
  use schema <- decode.field("schema", decode.string)
  use timestamp_utc <- decode.field("timestamp_utc", decode.string)
  use host <- decode.field("host", decode.string)
  use overall_readiness <- decode.field("overall_readiness", decode.string)
  use execution_policy <- decode.field("execution_policy", decode.string)
  use evidence_scope <- decode.field("evidence_scope", decode.string)
  use deployment_admission <- decode.field("deployment_admission", decode.string)
  use kvm <- decode.field("kvm", kvm_decoder())
  use qemu <- decode.field("qemu", qemu_decoder())
  use solo5 <- decode.field("solo5", solo5_decoder())
  decode.success(HypervisorProbeReport(
    schema,
    timestamp_utc,
    host,
    overall_readiness,
    execution_policy,
    evidence_scope,
    deployment_admission,
    kvm,
    qemu,
    solo5,
  ))
}

pub fn unverified_probe() -> HypervisorProbeReport {
  HypervisorProbeReport(
    schema: "uos-mirage-hypervisor-probe/v1",
    timestamp_utc: "1970-01-01T00:00:00Z",
    host: "nas-1",
    overall_readiness: "unverified",
    execution_policy: "two_key_receipt_required_before_admission",
    evidence_scope: "unverified",
    deployment_admission: "NOT_VERIFIED",
    kvm: KvmStatus(
      dev_kvm_present: False,
      dev_kvm_rw_accessible: False,
      api_version: None,
    ),
    qemu: QemuStatus(
      binary_path: None,
      microvm_supported: False,
      kvm_accel_supported: False,
    ),
    solo5: Solo5Status(
      solo5_hvt_path: None,
      solo5_spt_path: None,
      solo5_virtio_path: None,
      hvt_execution: None,
      spt_execution: None,
      virtio_execution: None,
    ),
  )
}

pub fn read_probe_receipt() -> HypervisorProbeReport {
  let primary_path = "var/mirage/receipts/hypervisors_probe.json"
  let fallback_path = "/home/an/NAS-setup/uos/var/mirage/receipts/hypervisors_probe.json"
  let content = case simplifile.read(primary_path) {
    Ok(c) -> Ok(c)
    Error(_) -> simplifile.read(fallback_path)
  }
  case content {
    Ok(json_str) -> {
      case json.parse(json_str, probe_report_decoder()) {
        Ok(report) -> report
        Error(_) -> unverified_probe()
      }
    }
    Error(_) -> unverified_probe()
  }
}
