//// =============================================================================
//// [UOS-SYSML-FPP] OMG SYSML V2 / KERML & FPP COMPOSITION VALIDATOR
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/fpp/sysml_validator</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Aerospace System Architecture & Formal Verification</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-FPP-001, SC-SYSML-001, SC-GLM-UI-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/json.{type Json}
import gleam/list

pub type PortDirection {
  InPort
  OutPort
  InOutPort
}

pub fn port_dir_to_string(d: PortDirection) -> String {
  case d {
    InPort -> "in"
    OutPort -> "out"
    InOutPort -> "inout"
  }
}

pub type SysMLPort {
  SysMLPort(
    name: String,
    direction: PortDirection,
    type_name: String,
    multiplicity: String,
  )
}

pub type SysMLRequirement {
  SysMLRequirement(
    id: String,
    name: String,
    text: String,
    satisfied_by: List(String),
    verified_by: List(String),
  )
}

pub type SysMLPart {
  SysMLPart(
    id: String,
    name: String,
    ports: List(SysMLPort),
    sub_parts: List(String),
    requirements: List(String),
  )
}

pub type SysMLConnection {
  SysMLConnection(
    id: String,
    from_part: String,
    from_port: String,
    to_part: String,
    to_port: String,
    protocol: String,
  )
}

pub type SysMLPackage {
  SysMLPackage(
    package_name: String,
    parts: List(SysMLPart),
    connections: List(SysMLConnection),
    requirements: List(SysMLRequirement),
  )
}

pub type ValidationError {
  PortMismatch(
    conn_id: String,
    from_type: String,
    to_type: String,
    reason: String,
  )
  UnsatisfiedRequirement(req_id: String, req_name: String)
  UnconnectedPort(part_id: String, port_name: String)
  DanglingPartRef(conn_id: String, missing_part: String)
}

pub fn error_to_string(err: ValidationError) -> String {
  case err {
    PortMismatch(id, f, t, r) ->
      "PortMismatch [" <> id <> "]: " <> f <> " -> " <> t <> " (" <> r <> ")"
    UnsatisfiedRequirement(id, name) ->
      "UnsatisfiedRequirement [" <> id <> "]: " <> name
    UnconnectedPort(part, port) ->
      "UnconnectedPort in " <> part <> ": " <> port
    DanglingPartRef(id, part) ->
      "DanglingPartRef [" <> id <> "]: missing part " <> part
  }
}

pub type ValidationReport {
  ValidationReport(
    valid: Bool,
    total_parts: Int,
    total_connections: Int,
    total_requirements: Int,
    errors: List(ValidationError),
    satisfaction_ratio: Float,
  )
}

/// Validate SysML package model integrity.
pub fn validate_package(pkg: SysMLPackage) -> ValidationReport {
  let part_ids = list.map(pkg.parts, fn(p) { p.id })

  // Check dangling connections
  let conn_errors: List(ValidationError) =
    pkg.connections
    |> list.filter_map(fn(c) {
      let from_exists = list.contains(part_ids, c.from_part)
      let to_exists = list.contains(part_ids, c.to_part)
      case from_exists, to_exists {
        False, _ -> Ok(DanglingPartRef(c.id, c.from_part))
        _, False -> Ok(DanglingPartRef(c.id, c.to_part))
        True, True -> {
          let from_p = list.find(pkg.parts, fn(p) { p.id == c.from_part })
          let to_p = list.find(pkg.parts, fn(p) { p.id == c.to_part })
          case from_p, to_p {
            Ok(p1), Ok(p2) -> {
              let port1 = list.find(p1.ports, fn(pt) { pt.name == c.from_port })
              let port2 = list.find(p2.ports, fn(pt) { pt.name == c.to_port })
              case port1, port2 {
                Ok(pt1), Ok(pt2) -> {
                  case pt1.type_name == pt2.type_name {
                    True -> Error(Nil)
                    False ->
                      Ok(PortMismatch(
                        c.id,
                        pt1.type_name,
                        pt2.type_name,
                        "Type divergence",
                      ))
                  }
                }
                _, _ ->
                  Ok(PortMismatch(
                    c.id,
                    c.from_port,
                    c.to_port,
                    "Port not declared on part",
                  ))
              }
            }
            _, _ -> Error(Nil)
          }
        }
      }
    })

  // Check requirement satisfaction & verification
  let req_errors: List(ValidationError) =
    pkg.requirements
    |> list.filter_map(fn(r) {
      case r.satisfied_by == [] || r.verified_by == [] {
        True -> Ok(UnsatisfiedRequirement(r.id, r.name))
        False -> Error(Nil)
      }
    })

  let all_errors = list.append(conn_errors, req_errors)
  let total_reqs = list.length(pkg.requirements)
  let satisfied_count = total_reqs - list.length(req_errors)

  let ratio = case total_reqs {
    0 -> 1.0
    tot ->
      int.to_float(satisfied_count)
      |> fn(s) { s /. int.to_float(tot) }
  }

  ValidationReport(
    valid: all_errors == [],
    total_parts: list.length(pkg.parts),
    total_connections: list.length(pkg.connections),
    total_requirements: total_reqs,
    errors: all_errors,
    satisfaction_ratio: ratio,
  )
}

/// Construct canonical UOS C3I SysML Package Model.
pub fn canonical_uos_sysml_package() -> SysMLPackage {
  let p_root =
    SysMLPart(
      id: "part-uos-sup",
      name: "UOS OTP 29 Root Supervisor",
      ports: [
        SysMLPort("telemetry_out", OutPort, "C3ITelemetryEvent", "[1..*]"),
        SysMLPort("command_in", InPort, "SystemCommand", "[1..*]"),
        SysMLPort("rpc_out", OutPort, "LengthDelimitedRpc", "[1..*]"),
      ],
      sub_parts: ["part-max-inference", "part-hermes-engine", "part-zigvm-vfs"],
      requirements: ["REQ-OTP29-ROOT", "REQ-ZERO-MUDA"],
    )

  let p_max =
    SysMLPart(
      id: "part-max-inference",
      name: "Modular MAX / Mojo Inference Tier",
      ports: [
        SysMLPort("rpc_in", InPort, "LengthDelimitedRpc", "[1]"),
        SysMLPort("tensor_out", OutPort, "TensorStream", "[1..*]"),
      ],
      sub_parts: [],
      requirements: ["REQ-MAX-ISOLATED", "REQ-ZERO-MUDA"],
    )

  let p_hermes =
    SysMLPart(
      id: "part-hermes-engine",
      name: "Hermes OCaml Formal Verifier",
      ports: [
        SysMLPort("gospel_in", InPort, "GospelQuery", "[1..*]"),
        SysMLPort("oracle_out", OutPort, "ParityVerdict", "[1..*]"),
      ],
      sub_parts: [],
      requirements: ["REQ-GOSPEL-ORACLE", "REQ-Z3-BOUNDED"],
    )

  let reqs = [
    SysMLRequirement(
      id: "REQ-OTP29-ROOT",
      name: "OTP 29 4-Domain Root Supervision",
      text: "System shall supervise Apps, Engines, Services, and Intelligence under multi-layer trees.",
      satisfied_by: ["part-uos-sup"],
      verified_by: ["test_uos_sup.gleam", "test_doctor_gate"],
    ),
    SysMLRequirement(
      id: "REQ-ZERO-MUDA",
      name: "Zero-Muda Purity Constraint",
      text: "System shall contain 0 Bevy, 0 Graphite, 0 foreign NIFs.",
      satisfied_by: ["part-uos-sup", "part-max-inference"],
      verified_by: ["test_zero_muda_doctor", "checklist_chk05"],
    ),
    SysMLRequirement(
      id: "REQ-MAX-ISOLATED",
      name: "Modular MAX Quarantine",
      text: "Python runtime is strictly quarantined to services/inference/max daemon.",
      satisfied_by: ["part-max-inference"],
      verified_by: ["test_max_quarantine", "checklist_chk15"],
    ),
    SysMLRequirement(
      id: "REQ-GOSPEL-ORACLE",
      name: "Hermes Gospel Differential Verification",
      text: "Formal rules evaluate Gospel contracts with bounded Z3 solvers.",
      satisfied_by: ["part-hermes-engine"],
      verified_by: ["test_parity_compare.exe", "test_ocaml_worker_pool"],
    ),
    SysMLRequirement(
      id: "REQ-Z3-BOUNDED",
      name: "Z3 Bounded Execution Ceiling",
      text: "All SMT queries terminate within 1200ms with process-tree reaping.",
      satisfied_by: ["part-hermes-engine"],
      verified_by: ["test_z3_bounded", "test_sa_plan_safety"],
    ),
  ]

  let conns = [
    SysMLConnection(
      id: "conn-sup-max",
      from_part: "part-uos-sup",
      from_port: "rpc_out",
      to_part: "part-max-inference",
      to_port: "rpc_in",
      protocol: "StdioLengthDelimitedRpc",
    ),
  ]

  SysMLPackage(
    package_name: "UnifiedOperationalSystem.Architecture",
    parts: [p_root, p_max, p_hermes],
    connections: conns,
    requirements: reqs,
  )
}

pub fn report_to_json(rep: ValidationReport) -> Json {
  json.object([
    #("valid", json.bool(rep.valid)),
    #("total_parts", json.int(rep.total_parts)),
    #("total_connections", json.int(rep.total_connections)),
    #("total_requirements", json.int(rep.total_requirements)),
    #("satisfaction_ratio", json.float(rep.satisfaction_ratio)),
    #(
      "errors",
      json.array(rep.errors, fn(e) { json.string(error_to_string(e)) }),
    ),
  ])
}
