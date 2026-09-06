import cepaf_gleam/verification/evidence_truth
import gleam/io

@external(erlang, "uos_ffi", "file_exists")
pub fn file_exists(path: String) -> Bool

@external(erlang, "uos_ffi", "file_contains")
pub fn file_contains(path: String, pattern: String) -> Bool

@external(erlang, "uos_ffi", "matches_timestamp_format")
pub fn matches_timestamp_format(filename: String) -> Bool

@external(erlang, "uos_ffi", "get_arguments")
pub fn get_arguments() -> List(String)

pub type UosCommand {
  Status
  Gate(name: String)
  Doctor
  DmcCheck
  TcmCheck
  TimestampCheck
  KmCheck
  WebLinks
  Checklist
  RochaCheck
  SelfcheckVfs
  SelfcheckSaPlan
  SelfcheckHermesBionic
  SelfcheckOmniMatrix
  Selfcheck15Cycles
  SelfcheckC3iKnowledge
  SelfcheckWave3Cycles
  SelfcheckWave4Cycles
  SelfcheckVerticalSlice
  VerifyAll
  Evidence(fixture_path: String)
  Help
}

pub fn parse_args(args: List(String)) -> UosCommand {
  case args {
    ["status"] -> Status
    ["gate", name] -> Gate(name)
    ["doctor"] -> Doctor
    ["dmc-check"] -> DmcCheck
    ["tcm-check"] -> TcmCheck
    ["timestamp-check"] -> TimestampCheck
    ["km-check"] -> KmCheck
    ["web-links"] | ["tailscale-links"] -> WebLinks
    ["checklist"] -> Checklist
    ["rocha-check"] | ["rocha"] -> RochaCheck
    ["selfcheck-vfs"] | ["--selfcheck-vfs"] | ["vfs-check"] -> SelfcheckVfs
    ["selfcheck-sa-plan"] | ["--selfcheck-sa-plan"] | ["sa-plan-check"] | ["sa-plan"] ->
      SelfcheckSaPlan
    ["selfcheck-hermes-bionic"] | ["--selfcheck-hermes-bionic"] | ["hermes-bionic-check"] | ["hermes-bionic"] | ["bionic"] ->
      SelfcheckHermesBionic
    ["selfcheck-omni-matrix"] | ["--selfcheck-omni-matrix"] | ["omni-matrix-check"] | ["omni-check"] | ["omni"] ->
      SelfcheckOmniMatrix
    ["selfcheck-15-cycles"] | ["--selfcheck-15-cycles"] | ["15-cycles"] | ["cycles"] ->
      Selfcheck15Cycles
    ["selfcheck-c3i-knowledge"] | ["--selfcheck-c3i-knowledge"] | ["c3i-knowledge-check"] | ["c3i-knowledge"] | ["knowledge"] ->
      SelfcheckC3iKnowledge
    ["selfcheck-wave3-cycles"] | ["--selfcheck-wave3-cycles"] | ["wave3-cycles"] | ["wave3"] ->
      SelfcheckWave3Cycles
    ["selfcheck-wave4-cycles"] | ["--selfcheck-wave4-cycles"] | ["wave4-cycles"] | ["wave4"] ->
      SelfcheckWave4Cycles
    ["selfcheck-vertical-slice"] | ["--selfcheck-vertical-slice"] | ["vertical-slice"] | ["slice"] ->
      SelfcheckVerticalSlice
    ["verify-all"] | ["verify"] -> VerifyAll
    ["evidence", "evaluate", "--fixture", path]
    | ["verification", "evaluate", "--fixture", path]
    | ["verification-evaluate", "--fixture", path] -> Evidence(path)
    ["evidence", "evaluate"] | ["verification-evaluate"] -> Evidence("")
    _ -> Help
  }
}


pub fn execute(cmd: UosCommand) -> Int {
  case cmd {
    Evidence(path) -> {
      let decision = case path {
        "" -> evidence_truth.unrun()
        _ -> evidence_truth.evaluate_fixture_file(path)
      }
      io.println(evidence_truth.to_json(decision))
      decision.exit_code
    }
    Status -> {
      io.println("UOS evidence status: UNRUN (invoke verification-evaluate --fixture <path>)")
      0
    }
    Help -> {
      io.println("Usage: uos verification-evaluate --fixture <path>")
      0
    }
    _ -> {
      io.println(evidence_truth.to_json(evidence_truth.unrun()))
      1
    }
  }
}
pub fn main() {
  let args = get_arguments()
  let cmd = case args {
    [] -> Status
    a -> parse_args(a)
  }
  execute(cmd)
}
