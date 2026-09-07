//// =============================================================================
//// [UOS-ARCH-SUP-GEN-001] UOS HOLONIC PROCESS SUPERVISOR & SYSTEMD GENERATOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>uos_swarm/sup_generator</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <topology>Holon Process Fabric Generator</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HOLON-GEN-001, SC-HOLON-NAME-001, SC-OTP-001, SC-ZERO-MUDA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================
////
//// SUP-GENERATOR (Task of uos/holonic-mapping/20260907-1505 and DES-UOS-HOLONIC-MAPPING-001):
//// Bridges static architectural code into a supervised process fabric by:
//// 1. CA-gen-sup: Generating the 4-domain OTP supervision child specs (Apps, Engines,
////    Services, Intelligence) directly from the validated holarchy (`holon.holarchy()`).
//// 2. CA-gen-unit: Generating systemd service unit files to `ops/systemd/` for host-managed
////    background daemons (`process_class == "systemd"`).
////
//// Invariant SC-HOLON-GEN-001: The generator reads only the validated holarchy; any
//// holon marked `barred` or `absent` is strictly barred from active supervision.
////

import gleam/int
import gleam/list
import gleam/string
import uos_swarm/holon.{type Holon, Control, DataPlane, Messaging, Structure}

pub type Domain {
  AppsDomain
  EnginesDomain
  ServicesDomain
  IntelligenceDomain
}

pub fn domain_to_string(d: Domain) -> String {
  case d {
    AppsDomain -> "AppsDomain"
    EnginesDomain -> "EnginesDomain"
    ServicesDomain -> "ServicesDomain"
    IntelligenceDomain -> "IntelligenceDomain"
  }
}

pub type Child {
  Child(
    id: String,
    name: String,
    domain: Domain,
    process_class: String,
    status: String,
    level: Int,
    restart: String,
  )
}

pub type SystemdUnit {
  SystemdUnit(
    id: String,
    file_name: String,
    description: String,
    unit_type: String,
    content: String,
  )
}

pub type GeneratedPlan {
  GeneratedPlan(
    sup_tree_name: String,
    otp_children: List(Child),
    systemd_units: List(SystemdUnit),
    total_candidates_scanned: Int,
    total_filtered_barred: Int,
    total_filtered_absent: Int,
    total_filtered_superseded: Int,
    total_active_processes: Int,
  )
}

/// Classifies a process holon into one of the four UOS Root Supervisor Domains
/// based on its plane, whole, domain, and id.
pub fn classify_domain(h: Holon) -> Domain {
  let is_app =
    h.plane == Control
    || h.plane == Structure
    || h.whole == option.Some("indrajaal-gleam-web")
    || string.contains(h.id, "web")
    || string.contains(h.id, "wisp")
    || string.contains(h.id, "ui")
    || string.contains(h.id, "iam")
    || string.contains(h.id, "vault")
    || string.contains(h.id, "prajna")

  let is_engine =
    h.whole == option.Some("hermes")
    || h.whole == option.Some("zigvm")
    || string.contains(h.id, "zigvm")
    || string.contains(h.id, "hermes")
    || string.contains(h.id, "oracle")
    || string.contains(h.id, "kernel")
    || string.contains(h.id, "rete")

  let is_service =
    h.plane == DataPlane
    || h.plane == Messaging
    || string.contains(h.id, "max")
    || string.contains(h.id, "inference")
    || string.contains(h.id, "stream")
    || string.contains(h.id, "zenoh")
    || string.contains(h.id, "telemetry")
    || string.contains(h.id, "planning")
    || string.contains(h.id, "freshness")
    || string.contains(h.id, "metrics")

  case is_app, is_engine, is_service {
    True, _, _ -> AppsDomain
    _, True, _ -> EnginesDomain
    _, _, True -> ServicesDomain
    False, False, False -> IntelligenceDomain
  }
}

import gleam/option

/// Verifies whether a holon is claimable and eligible for active supervision.
/// Rejects barred, absent, and deferred holons fail-closed.
pub fn is_eligible_process(h: Holon) -> Bool {
  case h.status {
    "integrated" -> True
    "imported-not-wired" -> True
    _ -> False
  }
}

/// Generates the complete supervisor plan and systemd unit manifests from the validated holarchy.
/// Enforces SC-HOLON-GEN-001: fails closed if holarchy validation fails.
pub fn generate(holarchy: List(Holon)) -> Result(GeneratedPlan, String) {
  case holon.validate(holarchy) {
    Error(err) -> Error("holarchy validation failed: " <> err)
    Ok(_) -> {
      let total_scanned = list.length(holarchy)

      let barred_count =
        list.count(holarchy, fn(h) { h.status == "barred" })
      let absent_count =
        list.count(holarchy, fn(h) { h.status == "absent" })
      let superseded_count =
        list.count(holarchy, fn(h) { h.status == "superseded" })

      // Filter eligible OTP child holons
      let otp_children =
        holarchy
        |> list.filter(fn(h) {
          h.process_class == "otp-child" && is_eligible_process(h)
        })
        |> list.map(fn(h) {
          Child(
            id: h.id,
            name: h.name,
            domain: classify_domain(h),
            process_class: h.process_class,
            status: h.status,
            level: h.level,
            restart: "permanent",
          )
        })

      // Generate Systemd units for eligible systemd holons
      let systemd_units =
        holarchy
        |> list.filter(fn(h) {
          h.process_class == "systemd" && is_eligible_process(h)
        })
        |> list.map(render_systemd_unit)

      let active_count = list.length(otp_children) + list.length(systemd_units)

      Ok(GeneratedPlan(
        sup_tree_name: "UOSRootSupervisor",
        otp_children: otp_children,
        systemd_units: systemd_units,
        total_candidates_scanned: total_scanned,
        total_filtered_barred: barred_count,
        total_filtered_absent: absent_count,
        total_filtered_superseded: superseded_count,
        total_active_processes: active_count,
      ))
    }
  }
}

/// Renders a single Systemd service unit from a systemd process holon.
pub fn render_systemd_unit(h: Holon) -> SystemdUnit {
  let file_name = case string.ends_with(h.name, ".service") || string.ends_with(h.name, ".target") {
    True -> h.name
    False ->
      case string.ends_with(h.id, ".service") || string.ends_with(h.id, ".target") {
        True -> h.id
        False -> h.id <> ".service"
      }
  }

  let unit_type = case string.ends_with(file_name, ".target") {
    True -> "target"
    False -> "service"
  }

  let content = case unit_type {
    "target" ->
      "[Unit]\n"
      <> "Description=" <> h.name <> " (" <> h.sanskrit <> ")\n"
      <> "Documentation=http://nas-1.tail55d152.ts.net:4100/zk\n"
      <> "After=network.target\n\n"
      <> "[Install]\n"
      <> "WantedBy=default.target\n"

    _ ->
      "[Unit]\n"
      <> "Description=" <> h.name <> " (" <> h.sanskrit <> ")\n"
      <> "Documentation=http://nas-1.tail55d152.ts.net:4100/zk\n"
      <> "PartOf=c3i.target\n"
      <> "After=network.target c3i-zenoh-router-1.service\n\n"
      <> "[Service]\n"
      <> "Type=simple\n"
      <> "Environment=UOS_ROOT=/home/an/NAS-setup/uos\n"
      <> "Environment=UOS_SA_PLAN_DB=/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3\n"
      <> "WorkingDirectory=/home/an/NAS-setup/uos\n"
      <> "ExecStart=/home/an/NAS-setup/uos/bin/" <> h.id <> "\n"
      <> "Restart=on-failure\n"
      <> "RestartSec=2s\n"
      <> "LimitNOFILE=65535\n"
      <> "# Zero-Muda: zero Bevy, zero Graphite, host NVMe 25503L801736 interlock\n\n"
      <> "[Install]\n"
      <> "WantedBy=c3i.target\n"
  }

  SystemdUnit(
    id: h.id,
    file_name: file_name,
    description: h.name,
    unit_type: unit_type,
    content: content,
  )
}

/// FFI bindings to pure Erlang filesystem utilities in uos_swarm_ffi
@external(erlang, "uos_swarm_ffi", "ensure_dir")
fn ffi_ensure_dir(path: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "file_write")
fn ffi_file_write(path: String, content: String) -> Result(Nil, String)

/// Writes all generated systemd units to the specified directory.
pub fn write_systemd_units(
  units: List(SystemdUnit),
  output_dir: String,
) -> Result(Int, String) {
  let _ = ffi_ensure_dir(output_dir)
  let results =
    list.map(units, fn(u) {
      let target_path = output_dir <> "/" <> u.file_name
      ffi_file_write(target_path, u.content)
    })

  let errors =
    list.filter_map(results, fn(r) {
      case r {
        Error(e) -> Ok(e)
        Ok(_) -> Error(Nil)
      }
    })

  case errors {
    [] -> Ok(list.length(units))
    [first, ..] -> Error("Failed to write unit file: " <> first)
  }
}

/// Groups generated OTP children by domain for root supervisor wiring.
pub fn group_by_domain(children: List(Child)) -> List(#(Domain, List(Child))) {
  let apps = list.filter(children, fn(c) { c.domain == AppsDomain })
  let engines = list.filter(children, fn(c) { c.domain == EnginesDomain })
  let services = list.filter(children, fn(c) { c.domain == ServicesDomain })
  let intelligence =
    list.filter(children, fn(c) { c.domain == IntelligenceDomain })

  [
    #(AppsDomain, apps),
    #(EnginesDomain, engines),
    #(ServicesDomain, services),
    #(IntelligenceDomain, intelligence),
  ]
}

/// Validates the generated plan against OTP 29 and Zero-Muda invariants.
pub fn validate_plan(plan: GeneratedPlan) -> Result(Int, String) {
  let grouped = group_by_domain(plan.otp_children)
  let total_children = list.length(plan.otp_children)

  case total_children >= 8 {
    False -> Error("insufficient OTP children count: " <> int.to_string(total_children))
    True -> {
      // Ensure each of the 4 domains has at least one child
      let empty_domains =
        list.filter(grouped, fn(pair) { pair.1 == [] })
      case empty_domains {
        [] -> Ok(total_children)
        [first, ..] ->
          Error("empty supervisor domain: " <> domain_to_string(first.0))
      }
    }
  }
}
