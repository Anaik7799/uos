type bounds = {
  timeout_ms : int;
  maximum_memory_bytes : int64;
  maximum_output_bytes : int;
  maximum_attempts : int;
}
type t = {
  reproduction : string;
  failure_signature : string;
  deterministic_seed : string option;
  bounds : bounds;
  required_controls : string list;
  mutation_targets : string list;
  concurrency_checks : string list;
  verify_original : bool;
  verify_dependency_cone : bool;
}
val validate : t -> string list
val canonical : t -> string

