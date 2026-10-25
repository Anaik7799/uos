import cepaf_gleam/harness/restoration_observer as observer
import gleam/erlang/process

pub fn inactive_missing_and_mixed_services_are_not_healthy_test() {
  let active = "ActiveState=active\nActiveState=active\nActiveState=active\nActiveState=active\nActiveState=active\n"
  assert observer.services_active(active)
  assert !observer.services_active("")
  assert !observer.services_active("ActiveState=active\n")
  assert !observer.services_active(active <> "ActiveState=failed\n")
  assert !observer.services_active("ActiveState=active\nActiveState=active\nActiveState=failed\nActiveState=active\nActiveState=active\n")
}
pub fn observer_refuses_private_path_escape_test() {
  assert observer.load("../grant.json", "review.json") == Error("private_filenames")
  assert observer.load("grant.json", "../review.json") == Error("private_filenames")
}
pub fn stopped_worker_is_observed_without_restart_wait_test() {
  let pid = process.spawn_unlinked(fn() { process.sleep(10) })
  assert observer.wait_for_worker(pid, 1000) == Error("observer_worker_stopped")
}
pub fn live_worker_wait_is_bounded_test() {
  let pid = process.spawn_unlinked(fn() { process.sleep(1000) })
  let result = observer.wait_for_worker(pid, 10)
  process.kill(pid)
  assert result == Error("observer_process_window_expired")
}
