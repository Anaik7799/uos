import cepaf_gleam/verification/vfs_selfcheck
import gleeunit/should

pub fn vfs_selfcheck_all_laws_pass_test() {
  let report = vfs_selfcheck.run_selfcheck_vfs()
  report.total_laws |> should.equal(8)
  report.passing_laws |> should.equal(8)
  report.all_passed |> should.equal(True)
  vfs_selfcheck.selfcheck_vfs_all_green(report) |> should.equal(True)
}

pub fn vfs_selfcheck_individual_laws_test() {
  let laws = vfs_selfcheck.all_vfs_laws()
  laws |> should.not_equal([])
  
  let eval1 = vfs_selfcheck.evaluate_law(vfs_selfcheck.LawVfs01DescriptorRelative)
  eval1.code |> should.equal("LAW-VFS-01")
  eval1.status |> should.equal(vfs_selfcheck.VfsLawPass)
  
  let eval2 = vfs_selfcheck.evaluate_law(vfs_selfcheck.LawVfs02SymlinkNofollow)
  eval2.code |> should.equal("LAW-VFS-02")
  eval2.status |> should.equal(vfs_selfcheck.VfsLawPass)
  
  let eval3 = vfs_selfcheck.evaluate_law(vfs_selfcheck.LawVfs03AtomicRename)
  eval3.code |> should.equal("LAW-VFS-03")
  eval3.status |> should.equal(vfs_selfcheck.VfsLawPass)
}

pub fn vfs_selfcheck_json_encoding_test() {
  let report = vfs_selfcheck.run_selfcheck_vfs()
  let json_str = vfs_selfcheck.encode_selfcheck_report_json(report)
  json_str |> should.not_equal("")
}

pub fn vfs_ascii_diagram_test() {
  let diagram = vfs_selfcheck.vfs_ascii_diagram()
  diagram |> should.not_equal("")
}
