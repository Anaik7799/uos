import cepaf_gleam/fpp/sysml_validator.{
  DanglingPartRef, InPort, OutPort, PortMismatch, SysMLConnection, SysMLPackage,
  SysMLPart, SysMLPort, SysMLRequirement, UnsatisfiedRequirement,
  canonical_uos_sysml_package, report_to_json, validate_package,
}
import gleam/json
import gleeunit/should

pub fn canonical_uos_sysml_validation_test() {
  let pkg = canonical_uos_sysml_package()
  let rep = validate_package(pkg)
  rep.valid |> should.equal(True)
  rep.total_parts |> should.equal(3)
  rep.total_requirements |> should.equal(5)
  rep.satisfaction_ratio |> should.equal(1.0)
  rep.errors |> should.equal([])
}

pub fn dangling_connection_test() {
  let p1 =
    SysMLPart("p1", "Part 1", [SysMLPort("out_p", OutPort, "Sig", "[1]")], [], [])
  let conn =
    SysMLConnection("c1", "p1", "out_p", "missing_p", "in_p", "Direct")
  let pkg = SysMLPackage("TestPkg", [p1], [conn], [])
  let rep = validate_package(pkg)
  rep.valid |> should.equal(False)
  case rep.errors {
    [DanglingPartRef(id, missing)] -> {
      id |> should.equal("c1")
      missing |> should.equal("missing_p")
    }
    _ -> should.fail()
  }
}

pub fn unsatisfied_requirement_test() {
  let req =
    SysMLRequirement("REQ-1", "Safety", "Fail closed", [], [])
  let pkg = SysMLPackage("TestPkg", [], [], [req])
  let rep = validate_package(pkg)
  rep.valid |> should.equal(False)
  rep.satisfaction_ratio |> should.equal(0.0)
  case rep.errors {
    [UnsatisfiedRequirement(id, _)] -> id |> should.equal("REQ-1")
    _ -> should.fail()
  }
}

pub fn port_type_mismatch_test() {
  let p1 =
    SysMLPart("p1", "Part 1", [SysMLPort("p1_port", OutPort, "TypeA", "[1]")], [], [])
  let p2 =
    SysMLPart("p2", "Part 2", [SysMLPort("p2_port", InPort, "TypeB", "[1]")], [], [])
  let conn =
    SysMLConnection("c1", "p1", "p1_port", "p2", "p2_port", "Direct")
  let pkg = SysMLPackage("TestPkg", [p1, p2], [conn], [])
  let rep = validate_package(pkg)
  rep.valid |> should.equal(False)
  case rep.errors {
    [PortMismatch(id, f, t, _)] -> {
      id |> should.equal("c1")
      f |> should.equal("TypeA")
      t |> should.equal("TypeB")
    }
    _ -> should.fail()
  }
}

pub fn report_json_test() {
  let pkg = canonical_uos_sysml_package()
  let rep = validate_package(pkg)
  let j = report_to_json(rep)
  should.be_true(j != json.null())
}
