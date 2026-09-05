type t = {
  timeout_ms : int;
  max_eval_memory_mb : int;
  max_build_cores : int;
  max_log_bytes : int;
  allow_network_during_build : bool;
}

let default = {
  timeout_ms = 300_000; (* 5 minutes *)
  max_eval_memory_mb = 4096;
  max_build_cores = 8;
  max_log_bytes = 10 * 1024 * 1024; (* 10 MB *)
  allow_network_during_build = false;
}

let fast_eval = {
  timeout_ms = 30_000; (* 30 seconds *)
  max_eval_memory_mb = 2048;
  max_build_cores = 4;
  max_log_bytes = 1024 * 1024;
  allow_network_during_build = false;
}

let heavyweight_build = {
  timeout_ms = 3600_000; (* 1 hour *)
  max_eval_memory_mb = 16384;
  max_build_cores = 16;
  max_log_bytes = 50 * 1024 * 1024;
  allow_network_during_build = false;
}

let validate b =
  if b.timeout_ms <= 0 then Error "timeout_ms must be positive"
  else if b.max_eval_memory_mb <= 0 then Error "max_eval_memory_mb must be positive"
  else if b.max_build_cores <= 0 then Error "max_build_cores must be positive"
  else if b.max_log_bytes <= 0 then Error "max_log_bytes must be positive"
  else Ok ()
