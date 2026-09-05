let failures = ref []
let outcome = ref (0, 0)
let check name condition = if not condition then failures := name :: !failures
let ok = function Ok value -> value | Error _ -> failwith "bounded fixture refused"

let contains ~needle haystack =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec search index =
    if needle_length = 0 then true
    else if index + needle_length > haystack_length then false
    else if String.sub haystack index needle_length = needle then true
    else search (index + 1)
  in
  search 0

let digest seed =
  Digestif.SHA256.digest_string seed |> Digestif.SHA256.to_hex
  |> Jj_secret_scan.digest |> ok

let executable text = Jj_id.Executable.make text |> ok
let receipt_id text = Jj_id.Receipt.make text |> ok
let request_id text = Jj_id.Request.make text |> ok

let () =
  let detector =
    Jj_secret_scan.detector_authority ~identity:(executable "detector-main")
      ~ruleset:(digest "ruleset") in
  let location =
    Jj_secret_scan.redacted_location ~scope:Jj_secret_scan.Patch_payload
      ~ordinal:7 |> ok in
  let finding =
    Jj_secret_scan.finding ~detector ~category:Jj_secret_scan.Access_token
      ~location ~confidence:Jj_secret_scan.Certain ~evidence:(digest "evidence") in
  let scan = Jj_secret_scan.scan ~findings:[ finding ] |> ok in
  check "C1 finding is bounded and scan summary discloses no matched bytes"
    (Jj_secret_scan.finding_count scan = 1
     && not (String.contains (Jj_secret_scan.safe_summary scan) '/'));
  check "C2 digest syntax and location bounds fail closed"
    (Result.is_error (Jj_secret_scan.digest "ABC")
     && Result.is_error
          (Jj_secret_scan.redacted_location ~scope:Jj_secret_scan.Source_object
             ~ordinal:(-1))
     && Result.is_error
          (Jj_secret_scan.redacted_location ~scope:Jj_secret_scan.Source_object
             ~ordinal:1_000_001));
  check "C3 exact duplicate findings refuse"
    (Result.is_error (Jj_secret_scan.scan ~findings:[ finding; finding ]));
  let finding2 =
    Jj_secret_scan.finding ~detector ~category:Jj_secret_scan.Private_key
      ~location ~confidence:Jj_secret_scan.Probable ~evidence:(digest "evidence-2") in
  let scan_reversed = Jj_secret_scan.scan ~findings:[ finding2; finding ] |> ok in
  let scan_forward = Jj_secret_scan.scan ~findings:[ finding; finding2 ] |> ok in
  check "C4 scan identity is deterministic under injected finding order"
    (Jj_secret_scan.digest_to_hex (Jj_secret_scan.canonical_digest scan_reversed)
     = Jj_secret_scan.digest_to_hex (Jj_secret_scan.canonical_digest scan_forward));
  let base_finding_digest = Jj_secret_scan.For_test.finding_digest finding in
  let finding_mutations =
    [ Jj_secret_scan.For_test.Detector_identity;
      Jj_secret_scan.For_test.Detector_ruleset;
      Jj_secret_scan.For_test.Category;
      Jj_secret_scan.For_test.Location_scope;
      Jj_secret_scan.For_test.Location_ordinal;
      Jj_secret_scan.For_test.Confidence;
      Jj_secret_scan.For_test.Evidence_digest ] in
  check "C5 every safe finding field changes its identity"
    (List.for_all
       (fun mutation ->
         base_finding_digest <>
         Jj_secret_scan.For_test.finding_digest_with_mutation finding mutation)
       finding_mutations);
  let secret = "token-super-secret-do-not-serialize" in
  let patch =
    Jj_receipt_core.sensitive_payload ~kind:Jj_receipt_core.Patch ~bytes:secret
    |> ok in
  let patch_summary = Jj_receipt_core.normalize_payload patch in
  check "C6 ephemeral payload normalizes to bounded digest-only metadata"
    (Jj_receipt_core.payload_byte_length patch_summary = String.length secret
     && Jj_receipt_core.payload_kind patch_summary = Jj_receipt_core.Patch
     && Jj_secret_scan.digest_to_hex
          (Jj_receipt_core.payload_digest patch_summary) <> secret);
  check "C7 empty and oversized sensitive payloads refuse without detail"
    (Jj_receipt_core.sensitive_payload ~kind:Jj_receipt_core.Description
       ~bytes:"" = Error Jj_receipt_core.Empty_payload
     && Result.is_error
          (Jj_receipt_core.sensitive_payload ~kind:Jj_receipt_core.Description
             ~bytes:(String.make 1_048_577 'x')));
  let recovery =
    Jj_receipt_core.recovery_anchor ~identity:(receipt_id "recovery-main")
      ~prefix:(digest "prefix") ~cut:(digest "cut")
      ~disposition:(digest "disposition")
      ~retention:Jj_receipt_core.Until_reconciled in
  let receipt =
    Jj_receipt_core.make ~receipt_id:(receipt_id "receipt-main")
      ~request_id:(request_id "request-main") ~operation:Jj_operation.Describe
      ~kind:Jj_receipt_core.Recovery
      ~disposition:Jj_receipt_core.First_applied
      ~request_digest:(digest "request") ~target_digest:(digest "target")
      ~before_digest:(digest "before") ~after_digest:(digest "after")
      ~readback_id:(receipt_id "readback-main")
      ~readback_digest:(digest "readback") ~secret_scan:scan
      ~payloads:[ patch_summary ] ~recovery:(Some recovery) |> ok in
  check "C8 durable summary excludes secret bytes and retains recovery metadata"
    (not (contains ~needle:secret (Jj_receipt_core.safe_summary receipt))
     && Jj_receipt_core.recovery_anchor_retained receipt);
  let receipt_replay =
    Jj_receipt_core.make ~receipt_id:(receipt_id "receipt-main")
      ~request_id:(request_id "request-main") ~operation:Jj_operation.Describe
      ~kind:Jj_receipt_core.Recovery
      ~disposition:Jj_receipt_core.First_applied
      ~request_digest:(digest "request") ~target_digest:(digest "target")
      ~before_digest:(digest "before") ~after_digest:(digest "after")
      ~readback_id:(receipt_id "readback-main")
      ~readback_digest:(digest "readback") ~secret_scan:scan
      ~payloads:[ patch_summary ] ~recovery:(Some recovery) |> ok in
  check "C9 receipt identity is deterministic"
    (Jj_secret_scan.digest_to_hex (Jj_receipt_core.canonical_digest receipt)
     = Jj_secret_scan.digest_to_hex
         (Jj_receipt_core.canonical_digest receipt_replay));
  check "C10 duplicate durable payload summaries refuse"
    (Result.is_error
       (Jj_receipt_core.make ~receipt_id:(receipt_id "receipt-duplicate")
          ~request_id:(request_id "request-duplicate")
          ~operation:Jj_operation.Describe ~kind:Jj_receipt_core.Observation
          ~disposition:Jj_receipt_core.No_effect
          ~request_digest:(digest "request-duplicate")
          ~target_digest:(digest "target-duplicate")
          ~before_digest:(digest "before-duplicate")
          ~after_digest:(digest "after-duplicate")
          ~readback_id:(receipt_id "readback-duplicate")
          ~readback_digest:(digest "readback-duplicate") ~secret_scan:scan
          ~payloads:[ patch_summary; patch_summary ] ~recovery:None));
  let receipt_digest =
    Jj_secret_scan.digest_to_hex (Jj_receipt_core.canonical_digest receipt) in
  let receipt_mutations =
    [ Jj_receipt_core.For_test.Receipt_id;
      Jj_receipt_core.For_test.Request_id;
      Jj_receipt_core.For_test.Operation;
      Jj_receipt_core.For_test.Receipt_kind;
      Jj_receipt_core.For_test.Disposition;
      Jj_receipt_core.For_test.Request_digest;
      Jj_receipt_core.For_test.Target_digest;
      Jj_receipt_core.For_test.Before_digest;
      Jj_receipt_core.For_test.After_digest;
      Jj_receipt_core.For_test.Readback_id;
      Jj_receipt_core.For_test.Readback_digest;
      Jj_receipt_core.For_test.Secret_scan_digest;
      Jj_receipt_core.For_test.Payload_kind;
      Jj_receipt_core.For_test.Payload_length;
      Jj_receipt_core.For_test.Payload_digest;
      Jj_receipt_core.For_test.Recovery_identity;
      Jj_receipt_core.For_test.Recovery_prefix;
      Jj_receipt_core.For_test.Recovery_cut;
      Jj_receipt_core.For_test.Recovery_disposition;
      Jj_receipt_core.For_test.Recovery_retention ] in
  check "C11 every durable receipt field changes its canonical identity"
    (List.for_all
       (fun mutation ->
         receipt_digest <>
         Jj_receipt_core.For_test.canonical_digest_with_mutation receipt mutation)
       receipt_mutations);
  check "C12 authorities publish fixed-size nonempty digests"
    (String.length Jj_secret_scan.source_digest = 64
     && String.length Jj_receipt_core.source_digest = 64);
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 12 - failed in
  outcome := (passed, failed)
