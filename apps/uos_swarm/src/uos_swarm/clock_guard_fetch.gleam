//// Read-only bounded Zenoh projection fetch. Only a fresh HTTP 200 body is
//// returned; an older atomic projection remains diagnostic evidence only.

@external(erlang, "clock_guard_ffi", "fetch")
fn fetch_ffi(
  url: String,
  max_bytes: Int,
  timeout_ms: Int,
  projection: String,
) -> Result(String, String)

pub fn fetch(url: String, projection: String) -> Result(String, String) {
  fetch_ffi(url, 16_777_216, 3000, projection)
}
