import cepaf_gleam/fpp/sysml_validator.{
  DanglingPartRef, InOutPort, InPort, OutPort, PortMismatch, SysMLConnection, SysMLPackage,
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
    SysMLPart(
      "p1",
      "Part 1",
      [SysMLPort("out_p", OutPort, "Sig", "[1]")],
      [],
      [],
    )
  let conn = SysMLConnection("c1", "p1", "out_p", "missing_p", "in_p", "Direct")
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
  let req = SysMLRequirement("REQ-1", "Safety", "Fail closed", [], [])
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
    SysMLPart(
      "p1",
      "Part 1",
      [SysMLPort("p1_port", OutPort, "TypeA", "[1]")],
      [],
      [],
    )
  let p2 =
    SysMLPart(
      "p2",
      "Part 2",
      [SysMLPort("p2_port", InPort, "TypeB", "[1]")],
      [],
      [],
    )
  let conn = SysMLConnection("c1", "p1", "p1_port", "p2", "p2_port", "Direct")
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

pub fn dangling_subpart_rejected_test() {
  let root = SysMLPart("root", "Root", [], ["missing"], [])
  validate_package(SysMLPackage("P", [root], [], [])).valid |> should.be_false
}

pub fn dangling_part_requirement_rejected_test() {
  let root = SysMLPart("root", "Root", [], [], ["REQ-missing"])
  validate_package(SysMLPackage("P", [root], [], [])).valid |> should.be_false
}

pub fn unresolved_satisfaction_does_not_count_test() {
  let req = SysMLRequirement("REQ-1", "Safety", "test", ["missing", "also-missing"], ["test-path"])
  let rep = validate_package(SysMLPackage("P", [], [], [req]))
  rep.valid |> should.be_false
  rep.satisfaction_ratio |> should.equal(0.0)
}

pub fn duplicate_part_id_rejected_test() {
  let first = SysMLPart("same", "First", [], [], [])
  let second = SysMLPart("same", "Second", [], [], [])
  validate_package(SysMLPackage("P", [first, second], [], [])).valid |> should.be_false
}

pub fn duplicate_requirement_id_rejected_test() {
  let p = SysMLPart("part", "Part", [], [], [])
  let r1 = SysMLRequirement("R", "One", "", ["part"], ["test"])
  let r2 = SysMLRequirement("R", "Two", "", ["part"], ["test"])
  validate_package(SysMLPackage("P", [p], [], [r1, r2])).valid |> should.be_false
}

pub fn duplicate_port_name_rejected_test() {
  let p = SysMLPart("part", "Part", [
    SysMLPort("same", InPort, "T", "[1]"),
    SysMLPort("same", OutPort, "T", "[1]"),
  ], [], [])
  validate_package(SysMLPackage("P", [p], [], [])).valid |> should.be_false
}

pub fn duplicate_connection_id_rejected_test() {
  let from = SysMLPart("from", "From", [SysMLPort("p", OutPort, "T", "[1]")], [], [])
  let to = SysMLPart("to", "To", [SysMLPort("p", InPort, "T", "[1]")], [], [])
  let c = SysMLConnection("same", "from", "p", "to", "p", "direct")
  validate_package(SysMLPackage("P", [from, to], [c, c], [])).valid |> should.be_false
}

fn direction_valid(from_direction, to_direction) {
  let from = SysMLPart("from", "From", [SysMLPort("p", from_direction, "T", "[1]")], [], [])
  let to = SysMLPart("to", "To", [SysMLPort("p", to_direction, "T", "[1]")], [], [])
  let c = SysMLConnection("c", "from", "p", "to", "p", "direct")
  validate_package(SysMLPackage("P", [from, to], [c], [])).valid
}

pub fn connection_directions_checked_test() {
  direction_valid(OutPort, InPort) |> should.be_true
  direction_valid(InOutPort, InPort) |> should.be_true
  direction_valid(OutPort, InOutPort) |> should.be_true
  direction_valid(InPort, InPort) |> should.be_false
  direction_valid(OutPort, OutPort) |> should.be_false
  direction_valid(InPort, OutPort) |> should.be_false
}

pub fn empty_requirement_set_is_vacuously_complete_test() {
  let rep = validate_package(SysMLPackage("P", [], [], []))
  rep.valid |> should.be_true
  rep.satisfaction_ratio |> should.equal(1.0)
}
