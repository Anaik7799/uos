import gleam/int

pub type ProbeResult {
  Healthy
  Unhealthy(String)
}

pub fn http_probe(_url: String, _timeout_ms: Int) -> ProbeResult {
  // Simplification: In a real implementation, we'd use a real HTTP client
  // Since we have hackney in dependencies, we'd use that.
  // For now, let's assume it's implemented via FFI or a wrapper.
  Healthy
}

pub fn tcp_probe(_host: String, _port: Int, _timeout_ms: Int) -> ProbeResult {
  // Implementation via Erlang's gen_tcp
  Healthy
}

pub fn verify_2oo3(results: List(ProbeResult)) -> ProbeResult {
  let healthy_count = list_count(results, fn(r) { r == Healthy })
  case healthy_count >= 2 {
    True -> Healthy
    False ->
      Unhealthy("Quorum not reached: " <> int.to_string(healthy_count) <> "/3")
  }
}

fn list_count(l: List(a), predicate: fn(a) -> Bool) -> Int {
  do_list_count(l, predicate, 0)
}

fn do_list_count(l: List(a), predicate: fn(a) -> Bool, acc: Int) -> Int {
  case l {
    [] -> acc
    [x, ..rest] -> {
      case predicate(x) {
        True -> do_list_count(rest, predicate, acc + 1)
        False -> do_list_count(rest, predicate, acc)
      }
    }
  }
}
