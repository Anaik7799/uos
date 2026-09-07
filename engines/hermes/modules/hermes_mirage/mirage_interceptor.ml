(** MirageOS Zero-Trust Tool Interceptor Unikernel (EV-87) *)

type intercept_verdict =
  | Admitted of string
  | Trapped_null_byte
  | Trapped_sql_injection of string
  | Trapped_unauthorized

let contains_null_byte s =
  String.contains s '\000'

let contains_raw_sql s =
  let upper = String.uppercase_ascii s in
  let dangerous_patterns = [
    "DROP TABLE"; "DELETE FROM"; "TRUNCATE";
    "UNION SELECT"; "INSERT INTO"; "UPDATE ";
    "--"; ";--"
  ] in
  List.find_opt (fun pat ->
    let pat_len = String.length pat in
    let s_len = String.length upper in
    let rec check idx =
      if idx + pat_len > s_len then false
      else if String.sub upper idx pat_len = pat then true
      else check (idx + 1)
    in
    check 0
  ) dangerous_patterns

let inspect_payload payload =
  if contains_null_byte payload then
    Trapped_null_byte
  else match contains_raw_sql payload with
  | Some pat -> Trapped_sql_injection pat
  | None ->
      let digest = Digestif.SHA256.(to_hex (digest_string payload)) in
      Admitted digest

let sign_admission_receipt ~secret_seed message =
  if String.length secret_seed < 32 then
    Error "secret seed must be at least 32 bytes for Ed25519"
  else
    try
      let seed_32 = String.sub secret_seed 0 32 in
      let priv = Mirage_crypto_ec.Ed25519.priv_of_octets seed_32 in
      match priv with
      | Ok k ->
          let signature = Mirage_crypto_ec.Ed25519.sign ~key:k message in
          Ok signature
      | Error _ -> Error "failed to generate Ed25519 key from seed"
    with _ -> Error "exception in Ed25519 signing"

let verify_admission_receipt ~public_key_octets message ~signature =
  try
    match Mirage_crypto_ec.Ed25519.pub_of_octets public_key_octets with
    | Ok pub ->
        Mirage_crypto_ec.Ed25519.verify ~key:pub signature ~msg:message
    | Error _ -> false
  with _ -> false
