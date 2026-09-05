let failures = ref []
let check name condition = if not condition then failures := name :: !failures

let hex_value = function
  | '0' .. '9' as value -> Char.code value - Char.code '0'
  | 'a' .. 'f' as value -> 10 + Char.code value - Char.code 'a'
  | _ -> failwith "non-hexadecimal test vector"

let octets hex =
  if String.length hex mod 2 <> 0 then failwith "odd hexadecimal test vector";
  String.init (String.length hex / 2) (fun index ->
      Char.chr
        ((hex_value hex.[index * 2] lsl 4)
         lor hex_value hex.[(index * 2) + 1]))

let get = function Ok value -> value | Error _ -> failwith "valid fixture refused"

let frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat "|"

let seed =
  octets "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"

let public =
  octets "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

let rfc_signature =
  octets
    ("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
     ^ "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")

let other_public =
  octets "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

let () =
  check "A1 algorithm, domain and byte bounds are frozen"
    (Dependability_approval_crypto.algorithm = "Ed25519"
     && Dependability_approval_crypto.domain_separator
        = "hermes.jj.approval.v1"
     && Dependability_approval_crypto.public_key_bytes = 32
     && Dependability_approval_crypto.signature_bytes = 64);
  check "A2 malformed public keys and signatures refuse before verification"
    (Result.is_error
       (Dependability_approval_crypto.public_key_of_octets
          (String.make 31 '\000'))
     && Result.is_error
          (Dependability_approval_crypto.public_key_of_octets
             (String.make 33 '\000'))
     && Result.is_error
          (Dependability_approval_crypto.public_key_of_octets
             (octets
                ("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
                 ^ "7f")))
     && Result.is_error
          (Dependability_approval_crypto.public_key_of_octets
             (String.make 32 '\000'))
     && Result.is_error
          (Dependability_approval_crypto.signature_of_octets
             (String.make 63 '\000'))
     && Result.is_error
          (Dependability_approval_crypto.signature_of_octets
             (String.make 65 '\000')));
  check "A3 canonical ticket framing rejects empty malformed and noncanonical bytes"
    (Result.is_error
       (Dependability_approval_crypto.canonical_signed_bytes
          ~canonical_ticket_bytes:"")
     && Result.is_error
          (Dependability_approval_crypto.canonical_signed_bytes
             ~canonical_ticket_bytes:"03:abc")
     && Result.is_error
          (Dependability_approval_crypto.canonical_signed_bytes
             ~canonical_ticket_bytes:"3:ab")
     && Result.is_error
          (Dependability_approval_crypto.canonical_signed_bytes
             ~canonical_ticket_bytes:"3:abc|"));
  check "A4 RFC 8032 section 7.1 verification provider is live"
    (String.length seed = 32 && String.length rfc_signature = 64
     && Dependability_approval_crypto.provider_self_test ());
  let ticket = frame [ "ticket-schema-v1"; "campaign-1"; "occurrence-1" ] in
  let signed =
    get
      (Dependability_approval_crypto.canonical_signed_bytes
         ~canonical_ticket_bytes:ticket)
  in
  let test_private =
    match Mirage_crypto_ec.Ed25519.priv_of_octets seed with
    | Ok value -> value
    | Error _ -> failwith "RFC 8032 test seed refused"
  in
  let signature_octets =
    Mirage_crypto_ec.Ed25519.sign ~key:test_private
      (frame
         [ Dependability_approval_crypto.domain_separator; ticket ])
  in
  let key = get (Dependability_approval_crypto.public_key_of_octets public) in
  let signature =
    get (Dependability_approval_crypto.signature_of_octets signature_octets)
  in
  check "A5 canonical domain-separated ticket verifies and yields bounded evidence"
    (match Dependability_approval_crypto.verify key signature signed with
     | Error _ -> false
     | Ok verified ->
         String.length
           (Dependability_approval_crypto.verified_digest verified) = 64);
  let changed =
    get
      (Dependability_approval_crypto.canonical_signed_bytes
         ~canonical_ticket_bytes:
           (frame [ "ticket-schema-v1"; "campaign-1"; "occurrence-2" ]))
  in
  let wrong_key =
    get (Dependability_approval_crypto.public_key_of_octets other_public)
  in
  check "A6 wrong message, wrong key and RFC non-domain signature refuse"
    (Result.is_error
       (Dependability_approval_crypto.verify key signature changed)
     && Result.is_error
          (Dependability_approval_crypto.verify wrong_key signature signed)
     && Result.is_error
          (Dependability_approval_crypto.verify key
             (get
                (Dependability_approval_crypto.signature_of_octets
                   rfc_signature))
             signed));
  let malleated = Bytes.of_string signature_octets in
  Bytes.set malleated 0 (Char.chr (Char.code (Bytes.get malleated 0) lxor 1));
  check "A7 malleated and truncated signatures cannot validate"
    (Result.is_error
       (Dependability_approval_crypto.verify key
          (get
             (Dependability_approval_crypto.signature_of_octets
                (Bytes.unsafe_to_string malleated)))
          signed)
     && Result.is_error
          (Dependability_approval_crypto.signature_of_octets
             (String.sub signature_octets 0 63)));
  check "A8 source digest binds the frozen validation-only contract"
    (String.length Dependability_approval_crypto.source_digest = 64);
  check "A9 public key identity is digest-only stable and key-distinguishing"
    (String.length (Dependability_approval_crypto.public_key_identity key) = 64
     && Dependability_approval_crypto.public_key_identity key
        <> Dependability_approval_crypto.public_key_identity wrong_key);

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 9 - failed in
  let self =
    Suite_telemetry.observe ~suite:"test_dependability_approval_crypto"
      ~passed ~failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[]);
  exit (Suite_telemetry.exit_code self)
