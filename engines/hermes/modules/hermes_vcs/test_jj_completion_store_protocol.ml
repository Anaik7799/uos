let failures = ref []
let check name condition = if not condition then failures := name :: !failures
let ok = function Ok value -> value | Error _ -> failwith "bounded fixture refused"

let () =
  let completion = ok (Jj_id.Receipt.make "completion-main") in
  let source = ok (Jj_id.Receipt.make "source-main") in
  let head = ok (Jj_id.Operation.make "operation-main") in
  let campaign = ok (Jj_id.Intent.make "campaign-main") in
  let payload = ok (Jj_id.Receipt.make "payload-main") in
  let payload_other = ok (Jj_id.Receipt.make "payload-other") in
  let bookmark = ok (Jj_id.Bookmark.make "bookmark-main") in
  let readback = ok (Jj_id.Receipt.make "readback-main") in
  let lease_release = ok (Jj_id.Receipt.make "lease-release-main") in
  let reserve = ok (Jj_completion_store_protocol.prepare_reserve
    ~completion ~source ~head ~campaign ~payload) in
  let reserve_replay = ok (Jj_completion_store_protocol.prepare_reserve
    ~completion ~source ~head ~campaign ~payload) in
  let reserve_other = ok (Jj_completion_store_protocol.prepare_reserve
    ~completion ~source ~head ~campaign ~payload:payload_other) in
  let finalize = ok (Jj_completion_store_protocol.prepare_finalize
    ~completion ~source ~head ~campaign ~payload ~bookmark ~readback
    ~lease_release) in
  check "C1 reserve is the reservation role"
    (Jj_completion_store_protocol.kind reserve = Reserve
     && Jj_completion_store_protocol.role reserve = Completion_reservation);
  check "C2 finalize is the final role and binds dependencies"
    (Jj_completion_store_protocol.kind finalize = Finalize
     && Jj_completion_store_protocol.role finalize = Completion_final
     && not (String.equal
       (Jj_completion_store_protocol.canonical_digest reserve)
       (Jj_completion_store_protocol.canonical_digest finalize)));
  check "C3 identical replay is stable"
    (Jj_completion_store_protocol.compatible_replay reserve reserve_replay);
  check "C4 same identity with different request payload conflicts"
    (not (Jj_completion_store_protocol.compatible_replay reserve finalize));
  check "C5 protocol publishes a nonempty authority digest"
    (String.length Jj_completion_store_protocol.source_digest = 64);
  check "C6 reserve and finalize bind one common reservation payload"
    (String.equal
       (Jj_completion_store_protocol.reservation_payload_digest reserve)
       (Jj_completion_store_protocol.reservation_payload_digest finalize));
  check "C7 changing the reserved payload changes the common digest"
    (not (String.equal
       (Jj_completion_store_protocol.reservation_payload_digest reserve)
       (Jj_completion_store_protocol.reservation_payload_digest reserve_other)));
  List.iter (fun name -> Printf.printf "FAILED: %s\n" name) (List.rev !failures);
  let failed = List.length !failures in
  let passed = 7 - failed in
  let self = Suite_telemetry.observe ~suite:"test_jj_completion_store_protocol"
    ~passed ~failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_jj_protocol ]);
  exit (Suite_telemetry.exit_code self)
