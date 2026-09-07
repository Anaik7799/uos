import cepaf_gleam/ops/solo5_sandbox.{
  SandboxVerified, SandboxViolation, Solo5Config, TargetSpt,
  cold_start_estimate_ms, default_config, platform_to_string, verify_sandbox,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn default_config_verified_test() {
  let cfg = default_config("mig08-metrics")
  platform_to_string(cfg.platform) |> should.equal("solo5-hvt")
  platform_to_string(TargetSpt) |> should.equal("solo5-spt")

  let status = verify_sandbox(cfg)
  case status {
    SandboxVerified(cold_start, mem) -> {
      mem |> should.equal(16)
      // Fast OODA Observation: Cold start must be under 15ms
      { cold_start <. 15.0 } |> should.be_true
    }
    SandboxViolation(_) -> should.fail()
  }
}

pub fn memory_ceiling_violation_test() {
  let cfg = Solo5Config(..default_config("bloated-vm"), memory_limit_mb: 128)
  let status = verify_sandbox(cfg)
  case status {
    SandboxViolation(reason) -> {
      should.be_true(reason != "")
    }
    _ -> should.fail()
  }
}

pub fn seccomp_disabled_violation_test() {
  let cfg = Solo5Config(..default_config("unsafe-vm"), seccomp_enabled: False)
  let status = verify_sandbox(cfg)
  case status {
    SandboxViolation(reason) -> {
      should.be_true(reason != "")
    }
    _ -> should.fail()
  }
}

pub fn cold_start_scaling_test() {
  let cs_16 = cold_start_estimate_ms(16)
  let cs_32 = cold_start_estimate_ms(32)
  { cs_16 <. cs_32 } |> should.be_true
  { cs_16 <. 15.0 } |> should.be_true
}
