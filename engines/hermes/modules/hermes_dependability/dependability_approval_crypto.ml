type public_key = Mirage_crypto_ec.Ed25519.pub
type signature = string
type canonical_signed_bytes = string
type verified = string

type error =
  | Public_key_wrong_length
  | Public_key_malformed
  | Signature_wrong_length
  | Empty_ticket
  | Noncanonical_ticket
  | Signature_invalid

let algorithm = "Ed25519"
let domain_separator = "hermes.jj.approval.v1"
let public_key_bytes = 32
let signature_bytes = 64

let all_zero value =
  String.for_all (fun character -> character = '\000') value

let canonical_public_encoding value =
  let modulus_byte index =
    if index = 0 then 0xed else if index = 31 then 0x7f else 0xff
  in
  let rec compare index =
    if index < 0 then false
    else
      let observed =
        let byte = Char.code value.[index] in
        if index = 31 then byte land 0x7f else byte
      in
      let expected = modulus_byte index in
      if observed < expected then true
      else if observed > expected then false
      else compare (index - 1)
  in
  compare 31

let public_key_of_octets value =
  if String.length value <> public_key_bytes then Error Public_key_wrong_length
  else if all_zero value || not (canonical_public_encoding value) then
    Error Public_key_malformed
  else
    match Mirage_crypto_ec.Ed25519.pub_of_octets value with
    | Ok key -> Ok key
    | Error _ -> Error Public_key_malformed

let signature_of_octets value =
  if String.length value = signature_bytes then Ok value
  else Error Signature_wrong_length

let public_key_identity key =
  ("approval-public-key-identity-v1\000"
   ^ Mirage_crypto_ec.Ed25519.pub_to_octets key)
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let canonical_length_frame value =
  let length = String.length value in
  let rec decimal cursor accumulator digits =
    if cursor >= length then None
    else
      match value.[cursor] with
      | '0' .. '9' as character ->
          if digits = 1 && accumulator = 0 then None
          else
            let digit = Char.code character - Char.code '0' in
            if accumulator > (max_int - digit) / 10 then None
            else decimal (cursor + 1) ((accumulator * 10) + digit) (digits + 1)
      | ':' when digits > 0 -> Some (cursor + 1, accumulator)
      | _ -> None
  in
  let rec fields cursor =
    match decimal cursor 0 0 with
    | None -> false
    | Some (payload_start, payload_length) ->
        if payload_length > length - payload_start then false
        else
          let next = payload_start + payload_length in
          if next = length then true
          else value.[next] = '|' && next + 1 < length && fields (next + 1)
  in
  length > 0 && fields 0

let canonical_signed_bytes ~canonical_ticket_bytes =
  if canonical_ticket_bytes = "" then Error Empty_ticket
  else if not (canonical_length_frame canonical_ticket_bytes) then
    Error Noncanonical_ticket
  else
    Ok (length_frame [ domain_separator; canonical_ticket_bytes ])

let digest value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let verify key signature signed =
  let valid =
    try Mirage_crypto_ec.Ed25519.verify ~key signature ~msg:signed
    with _ -> false
  in
  if not valid then Error Signature_invalid
  else
    Ok
      (digest
         (length_frame
            [ "approval-signature-verification-v1";
              Mirage_crypto_ec.Ed25519.pub_to_octets key;
              signature; signed ]))

let verified_digest value = value

let hex_value = function
  | '0' .. '9' as value -> Some (Char.code value - Char.code '0')
  | 'a' .. 'f' as value -> Some (10 + Char.code value - Char.code 'a')
  | _ -> None

let octets hex =
  let length = String.length hex in
  if length mod 2 <> 0 then None
  else
    let output = Bytes.create (length / 2) in
    let rec loop index =
      if index = length / 2 then Some (Bytes.unsafe_to_string output)
      else
        match hex_value hex.[index * 2], hex_value hex.[(index * 2) + 1] with
        | Some high, Some low ->
            Bytes.set output index (Char.chr ((high lsl 4) lor low));
            loop (index + 1)
        | _ -> None
    in
    loop 0

let provider_self_test () =
  let public =
    octets
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  in
  let signature =
    octets
      ("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
       ^ "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
  in
  match public, signature with
  | Some public, Some signature ->
      begin match Mirage_crypto_ec.Ed25519.pub_of_octets public with
      | Ok key ->
          (try Mirage_crypto_ec.Ed25519.verify ~key signature ~msg:""
           with _ -> false)
      | Error _ -> false
      end
  | _ -> false

let source_digest =
  length_frame
    [ "approval-crypto-authority-v1"; algorithm; domain_separator;
      "provider:mirage-crypto-ec"; "provider-version:2.2.0";
      "rfc:8032"; "public-key-bytes:" ^ string_of_int public_key_bytes;
      "signature-bytes:" ^ string_of_int signature_bytes;
      "public-key-y:canonical-less-than-2^255-19";
      "public-key:all-zero-refused";
      "public-key-identity:domain-separated-sha256";
      "ticket:canonical-decimal-length-frame";
      "signed-message:length-frame(domain,ticket)";
      "operations:verify-only";
      length_frame
        [ "public-key-wrong-length"; "public-key-malformed";
          "signature-wrong-length"; "empty-ticket";
          "noncanonical-ticket"; "signature-invalid" ] ]
  |> digest
