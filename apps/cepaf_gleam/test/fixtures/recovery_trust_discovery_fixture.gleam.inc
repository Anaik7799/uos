
// Appended ONLY to exact source in the private ordinary fixture package.
// No such constructor is present in production source or exposed by its API.
pub fn fixture_observe_fixed_launcher(
  guardian: String,
  guardian_sha: String,
  worker: String,
  worker_sha: String,
) -> Report {
  observe_bound(transport.reviewed_local_configuration(guardian, guardian_sha, worker, worker_sha, "/METADATA_ONLY_NO_LOCATOR"))
}
