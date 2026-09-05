type bounds = { timeout_ms : int; maximum_memory_bytes : int64; maximum_output_bytes : int; maximum_attempts : int }
type t = { reproduction : string; failure_signature : string; deterministic_seed : string option; bounds : bounds; required_controls : string list; mutation_targets : string list; concurrency_checks : string list; verify_original : bool; verify_dependency_cone : bool }
let nonempty value = String.trim value <> ""
let unique values = List.length values = List.length (List.sort_uniq String.compare values)

let validate item =
  let gaps = ref [] in
  let add message = gaps := message :: !gaps in
  if not (nonempty item.reproduction) then add "reproduction command is empty";
  if not (nonempty item.failure_signature) then add "failure signature is empty";
  if item.bounds.timeout_ms <= 0 || item.bounds.timeout_ms > 300_000 then
    add "timeout is outside the bounded campaign";
  if item.bounds.maximum_memory_bytes <= 0L
     || item.bounds.maximum_memory_bytes > 1_073_741_824L then
    add "memory bound is outside the private sub-1-GiB envelope";
  if item.bounds.maximum_output_bytes <= 0
     || item.bounds.maximum_output_bytes > 1_048_576 then
    add "output bound is outside the 1-MiB envelope";
  if item.bounds.maximum_attempts <= 0 || item.bounds.maximum_attempts > 10 then
    add "attempt count is unbounded";
  if List.length item.required_controls < 2 then
    add "positive and negative controls are both required";
  if List.length item.mutation_targets < 2 then
    add "at least two mutation targets are required";
  if not (unique item.required_controls) then add "controls are not unique";
  if not (unique item.mutation_targets) then add "mutation targets are not unique";
  if not item.verify_original then add "original symptom rerun is required";
  if not item.verify_dependency_cone then
    add "reverse dependency cone verification is required";
  List.rev !gaps

let canonical item =
  String.concat "|"
    [ item.reproduction; item.failure_signature;
      Option.value ~default:"nondeterministic-disclosed" item.deterministic_seed;
      string_of_int item.bounds.timeout_ms;
      Int64.to_string item.bounds.maximum_memory_bytes;
      string_of_int item.bounds.maximum_output_bytes;
      string_of_int item.bounds.maximum_attempts;
      String.concat "," item.required_controls;
      String.concat "," item.mutation_targets;
      String.concat "," item.concurrency_checks;
      string_of_bool item.verify_original;
      string_of_bool item.verify_dependency_cone ]
