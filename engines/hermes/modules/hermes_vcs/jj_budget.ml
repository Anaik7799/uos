type t = { max_attempts : int; timeout_ms : int; max_output_bytes : int }

type profile = Observation | Local_mutation | History_rewrite | Recovery | Remote

let maximum_attempts = 8
let maximum_timeout_ms = 300_000
let maximum_output_bytes = 1_048_576

let valid value =
  value.max_attempts > 0 && value.max_attempts <= maximum_attempts
  && value.timeout_ms > 0 && value.timeout_ms <= maximum_timeout_ms
  && value.max_output_bytes > 0 && value.max_output_bytes <= maximum_output_bytes

let make ~max_attempts ~timeout_ms ~max_output_bytes =
  let value = { max_attempts; timeout_ms; max_output_bytes } in
  if valid value then Ok value
  else Error (Jj_error.make Jj_error.Invalid_budget ~detail:"outside-declared-bounds")

let for_profile = function
  | Observation -> { max_attempts = 1; timeout_ms = 10_000; max_output_bytes = 65_536 }
  | Local_mutation -> { max_attempts = 1; timeout_ms = 30_000; max_output_bytes = 65_536 }
  | History_rewrite -> { max_attempts = 1; timeout_ms = 60_000; max_output_bytes = 131_072 }
  | Recovery -> { max_attempts = 1; timeout_ms = 60_000; max_output_bytes = 131_072 }
  | Remote -> { max_attempts = 1; timeout_ms = 120_000; max_output_bytes = 262_144 }

let profile_key profile =
  let name, value =
    match profile with
    | Observation -> "observation", for_profile Observation
    | Local_mutation -> "local-mutation", for_profile Local_mutation
    | History_rewrite -> "history-rewrite", for_profile History_rewrite
    | Recovery -> "recovery", for_profile Recovery
    | Remote -> "remote", for_profile Remote
  in
  Jj_id.length_frame
    [ name; string_of_int value.max_attempts; string_of_int value.timeout_ms;
      string_of_int value.max_output_bytes ]

let source_digest =
  Jj_id.length_frame
    [ "jj-budget-authority-v1"; Jj_error.source_digest;
      "bounds"; string_of_int maximum_attempts;
      string_of_int maximum_timeout_ms; string_of_int maximum_output_bytes;
      "profiles";
      Jj_id.length_frame
        (List.map profile_key
           [ Observation; Local_mutation; History_rewrite; Recovery; Remote ]) ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
