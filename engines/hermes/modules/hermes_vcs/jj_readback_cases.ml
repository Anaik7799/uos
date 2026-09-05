let failures = ref []
let outcome = ref (0, 0)

let check name condition =
  if not condition then failures := name :: !failures

let get = function Ok value -> value | Error _ -> failwith "test fixture rejected"

let digest_a = String.make 64 'a'
let digest_b = String.make 64 'b'
let digest_c = String.make 64 'c'

let request value = get (Jj_id.Request.make value)
let event value = get (Jj_id.Event.make value)

let decoded ~operation ~request_id ~event_id ~postcondition_id ~state_digest
    ~output_bytes ~recovery_anchor =
  { Jj_readback.operation_key = (Jj_operation.declaration operation).key;
    request_id; event_id; postcondition_id; state_digest; output_bytes;
    recovery_anchor }

let expectation ?recovery_anchor operation =
  get
    (Jj_readback.expect ~operation ~request:(request "request-main")
       ~event:(event "event-main") ~expected_state_digest:digest_a
       ~recovery_anchor)

let valid_decoded ?recovery_anchor operation raw =
  decoded ~operation ~request_id:"request-main" ~event_id:"event-main"
    ~postcondition_id:(Jj_readback.postcondition_id operation)
    ~state_digest:digest_a ~output_bytes:(String.length raw) ~recovery_anchor

let decoder value ~max_output_bytes:_ _ = Ok value

let is_error expected = function Error actual -> actual = expected | Ok _ -> false

let () =
  check "R1 exact 34-operation postcondition denominator is total and injective"
    (let ids = List.map Jj_readback.postcondition_id Jj_operation.all in
     List.length ids = 34
     && List.length (List.sort_uniq String.compare ids) = 34);

  check "R2 operation declarations determine exact recovery-anchor shape"
    (Result.is_error
       (Jj_readback.expect ~operation:Jj_operation.Bookmark_set
          ~request:(request "request-main") ~event:(event "event-main")
          ~expected_state_digest:digest_a ~recovery_anchor:None)
     && Result.is_error
          (Jj_readback.expect ~operation:Jj_operation.Version
             ~request:(request "request-main") ~event:(event "event-main")
             ~expected_state_digest:digest_a
             ~recovery_anchor:(Some (Jj_readback.Before_state digest_b)))
     && Result.is_error
          (Jj_readback.expect ~operation:Jj_operation.Partition_recover
             ~request:(request "request-main") ~event:(event "event-main")
             ~expected_state_digest:digest_a
             ~recovery_anchor:(Some (Jj_readback.Before_state digest_b)))
     && Result.is_ok
          (Jj_readback.expect ~operation:Jj_operation.Partition_recover
             ~request:(request "request-main") ~event:(event "event-main")
             ~expected_state_digest:digest_a
             ~recovery_anchor:(Some (Jj_readback.Partition_anchor digest_b))));

  check "R3 digest inputs are exact lower-case SHA-256 values"
    (Result.is_error
       (Jj_readback.expect ~operation:Jj_operation.Version
          ~request:(request "request-main") ~event:(event "event-main")
          ~expected_state_digest:"not-a-digest" ~recovery_anchor:None));

  let operation = Jj_operation.Bookmark_set in
  let anchor = Jj_readback.Before_state digest_b in
  let expected = expectation ~recovery_anchor:anchor operation in
  let raw = "bounded-readback" in
  let good = valid_decoded ~recovery_anchor:anchor operation raw in

  check "R4 a successful child and exact postcondition jointly admit mutation"
    (Result.is_ok
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder good) raw));

  check "R5 child termination alone is insufficient"
    (let wrong = { good with state_digest = digest_c } in
     is_error Jj_readback.Postcondition_mismatch
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder wrong) raw));

  check "R6 exact postcondition alone is insufficient without successful termination"
    (is_error Jj_readback.Child_not_successful
       (Jj_readback.verify expected ~child:Jj_readback.Not_reaped
          ~decode:(decoder good) raw)
     && is_error Jj_readback.Child_not_successful
          (Jj_readback.verify expected ~child:(Jj_readback.Exited_nonzero 1)
             ~decode:(decoder good) raw));

  check "R7 request and event identities must both match exactly"
    (let wrong_request = { good with request_id = "request-other" } in
     let wrong_event = { good with event_id = "event-other" } in
     is_error Jj_readback.Identity_mismatch
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder wrong_request) raw)
     && is_error Jj_readback.Identity_mismatch
          (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
             ~decode:(decoder wrong_event) raw));

  check "R8 operation identity and operation-specific postcondition are exact"
    (let wrong_operation =
       { good with operation_key =
           (Jj_operation.declaration Jj_operation.Describe).key }
     in
     let wrong_postcondition =
       { good with postcondition_id =
           Jj_readback.postcondition_id Jj_operation.Describe }
     in
     is_error Jj_readback.Identity_mismatch
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder wrong_operation) raw)
     && is_error Jj_readback.Postcondition_mismatch
          (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
             ~decode:(decoder wrong_postcondition) raw));

  check "R9 exact recovery anchor is mandatory in readback"
    (let missing = { good with recovery_anchor = None } in
     let substituted =
       { good with recovery_anchor = Some (Jj_readback.Before_state digest_c) }
     in
     is_error Jj_readback.Recovery_anchor_mismatch
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder missing) raw)
     && is_error Jj_readback.Recovery_anchor_mismatch
          (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
             ~decode:(decoder substituted) raw));

  check "R10 decoder byte count is exact"
    (let wrong = { good with output_bytes = String.length raw - 1 } in
     is_error Jj_readback.Output_length_mismatch
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero
          ~decode:(decoder wrong) raw));

  check "R11 oversized output is refused before invoking the decoder"
    (let calls = ref 0 in
     let decode ~max_output_bytes:_ _ = incr calls; Ok good in
     let oversized =
       String.make ((Jj_operation.declaration operation).budget.max_output_bytes + 1) 'x'
     in
     is_error Jj_readback.Output_too_large
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero ~decode oversized)
     && !calls = 0);

  check "R12 decoder refusal is fail-closed"
    (let decode ~max_output_bytes:_ _ = Error "malformed" in
     is_error Jj_readback.Decoder_refused
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero ~decode raw));

  check "R13 injected decoder must be deterministic"
    (let calls = ref 0 in
     let decode ~max_output_bytes:_ _ =
       incr calls;
       if !calls = 1 then Ok good else Ok { good with state_digest = digest_c }
     in
     is_error Jj_readback.Nondeterministic_decoder
       (Jj_readback.verify expected ~child:Jj_readback.Exited_zero ~decode raw));

  check "R14 observation admits exact readback without a recovery anchor"
    (let observed = expectation Jj_operation.Version in
     let value = valid_decoded Jj_operation.Version raw in
     Result.is_ok
       (Jj_readback.verify observed ~child:Jj_readback.Exited_zero
          ~decode:(decoder value) raw));

  check "R15 receipt identity and digest are deterministic"
    (match
       Jj_readback.verify expected ~child:Jj_readback.Exited_zero
         ~decode:(decoder good) raw,
       Jj_readback.verify expected ~child:Jj_readback.Exited_zero
         ~decode:(decoder good) raw
     with
     | Ok left, Ok right ->
         String.equal (Jj_readback.receipt_digest left)
           (Jj_readback.receipt_digest right)
         && String.equal (Jj_readback.receipt_operation_key left)
              (Jj_operation.declaration operation).key
     | Error _, _ | _, Error _ -> false);

  check "R16 partition recovery requires and preserves its exact partition anchor"
    (let recovery_anchor = Jj_readback.Partition_anchor digest_b in
     let recovery = expectation ~recovery_anchor Jj_operation.Partition_recover in
     let value = valid_decoded ~recovery_anchor Jj_operation.Partition_recover raw in
     Result.is_ok
       (Jj_readback.verify recovery ~child:Jj_readback.Exited_zero
          ~decode:(decoder value) raw));

  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 16 - failed in
  outcome := (passed, failed)
