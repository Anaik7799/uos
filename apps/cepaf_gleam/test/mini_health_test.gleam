
import cepaf_gleam/telegram/mini_health as h
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/option.{None,Some}
import gleam/string
import gleeunit/should
@external(erlang,"mini_boundary_test_ffi","set_clock")
fn set_clock(times: List(Int)) -> Nil
@external(erlang,"mini_boundary_test_ffi","clock")
fn clock() -> Int
fn sample() {
  "{\"schema\":\"uos.mini.device-observation.v1\",\"observed_at\":1000,\"source\":\"linux_sysfs\",\"complete\":true,\"truncated\":false,\"excluded_virtual_blocks\":0,\"devices\":[{\"id\":\"temperature:hwmon1:temp1\",\"kind\":\"temperature\",\"label\":\"NVMe temp\",\"state\":\"observed\",\"reading\":30000,\"unit\":\"milli_celsius\",\"high\":50000,\"critical\":80000,\"grade\":\"normal\",\"thresholds_valid\":true}]}"
}
pub fn observed_device_and_no_fleet_health_claim_test() {
  let assert Ok(api.Observed(1000,"local_device_observations",f))=h.project(sample(),1000,"linux_sysfs")
  dict.get(f,"Device count") |> should.equal(Ok("1"))
  let assert Ok(scope)=dict.get(f,"Scope")
  string.contains(scope,"no remote fleet") |> should.be_true
  dict.get(f,"Runtime admission") |> should.equal(Ok("NOT_GRANTED"))
}
pub fn threshold_boundaries_and_unknown_test() {
  h.temperature_grade(Some(49999),Some(50000),Some(80000)) |> should.equal("normal")
  h.temperature_grade(Some(50000),Some(50000),Some(80000)) |> should.equal("warning")
  h.temperature_grade(Some(80000),Some(50000),Some(80000)) |> should.equal("critical")
  h.temperature_grade(Some(30000),None,None) |> should.equal("unknown")
  h.temperature_grade(None,Some(50000),Some(80000)) |> should.equal("unknown")
  h.temperature_grade(Some(30000),Some(90000),Some(80000)) |> should.equal("unknown")
}
pub fn wrong_source_stale_future_refused_test() {
  h.project(sample(),1006,"linux_sysfs") |> should.be_error
  h.project(sample(),999,"linux_sysfs") |> should.be_error
  h.project(sample(),1000,"private_fixture") |> should.be_error
  h.project(string.replace(sample(),"linux_sysfs","invented"),1000,"linux_sysfs") |> should.be_error
}
pub fn forged_grade_invalid_values_refused_test() {
  h.project(string.replace(sample(),"\"normal\"","\"critical\""),1000,"linux_sysfs") |> should.be_error
  h.project(string.replace(sample(),"30000","900000"),1000,"linux_sysfs") |> should.be_error
  h.project(string.replace(sample(),"milli_celsius","fahrenheit"),1000,"linux_sysfs") |> should.be_error
}
pub fn duplicate_id_and_oversize_refused_test() {
  let raw=sample()
  let assert [head,row]=string.split(raw,"\"devices\":[")
  let row=string.drop_end(row,2)
  h.project(head<>"\"devices\":["<>row<>","<>row<>"]}",1000,"linux_sysfs") |> should.be_error
  h.project(string.repeat("x",32769),1000,"linux_sysfs") |> should.be_error
}
pub fn backward_or_slow_clock_refused_test() {
  let io=h.Io(fn(_) { Ok(sample()) },fn() { 0 },fn() { 1000 })
  h.observe(io) |> should.be_ok
  set_clock([1000,999])
  h.observe(h.Io(..io,monotonic_ms:clock)) |> should.be_error
  set_clock([1000,3800])
  h.observe(h.Io(..io,monotonic_ms:clock)) |> should.be_error
  h.observe(h.Io(fn(_) { Error("missing") },fn(){0},fn(){1000})) |> should.be_error
}
pub fn worker_path_and_digest_closed_test() {
  let sha=string.repeat("a",64)
  h.valid_worker("/home/an/NAS-setup/uos/var/recovery-runtime/test/mini_health_snapshot.exe",sha) |> should.be_true
  h.valid_worker("/tmp/mini_health_snapshot.exe",sha) |> should.be_false
  h.valid_worker("/home/an/NAS-setup/uos/var/recovery-runtime/../mini_health_snapshot.exe",sha) |> should.be_false
  h.valid_worker("/home/an/NAS-setup/uos/var/recovery-runtime/test/mini_health_snapshot.exe","bad") |> should.be_false
}

pub fn invalid_thresholds_cannot_report_normal_test() {
  let raw=sample() |> string.replace("\"thresholds_valid\":true","\"thresholds_valid\":false")
  h.project(raw,1000,"linux_sysfs") |> should.be_error
  let raw=raw |> string.replace("\"normal\"","\"unknown\"") |> string.replace("\"observed\"","\"invalid_thresholds\"")
  h.project(raw,1000,"linux_sysfs") |> should.be_ok
  h.project(string.replace(sample(),"50000","0"),1000,"linux_sysfs") |> should.be_error
}

pub fn valid_critical_threshold_survives_invalid_high_test() {
 let raw=sample() |> string.replace("30000","90000") |> string.replace("\"high\":50000","\"high\":null") |> string.replace("\"normal\"","\"critical\"") |> string.replace("\"thresholds_valid\":true","\"thresholds_valid\":false") |> string.replace("\"observed\"","\"invalid_thresholds\"")
 h.project(raw,1000,"linux_sysfs") |> should.be_ok
}
