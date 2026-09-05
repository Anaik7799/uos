(* Closed-protocol and isolated-worker laws for the linked Smtml/Z3 adapter.

   The protocol is deliberately independent of Run_analysis: the dashboard
   prepares one immutable request, writes exactly its query bytes to stdin, and
   validates a bounded transcript.  The worker is a separate process.  No
   channel, descriptor, callback, solver handle, or reusable session crosses
   this interface. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let contains text needle =
  let text_length = String.length text and needle_length = String.length needle in
  let rec search offset =
    offset + needle_length <= text_length
    && (String.sub text offset needle_length = needle || search (offset + 1))
  in
  needle_length = 0 || search 0

let trivial_query = "(set-logic QF_UF)\n(assert true)\n(check-sat)\n"

let limits () =
  Run_analysis_z3_worker_protocol.make_limits
    ~virtual_memory_bytes:536_870_912L ~cpu_seconds:2
    ~maximum_query_bytes:4096 ~maximum_output_bytes:16_384

let prepared () =
  match limits () with
  | Error errors -> Error errors
  | Ok limits ->
      Run_analysis_z3_worker_protocol.prepare
        ~obligation_id:"test-linked-trivial"
        ~worker_executable_digest:
          (Run_analysis_z3_worker_protocol.digest_bytes
             "canonical-worker-object-fixture")
        ~query:trivial_query ~limits

let unit_layer () =
  let open Run_analysis_z3_worker_protocol in
  (match limits () with
  | Ok limits ->
      check (limits.virtual_memory_bytes = 536_870_912L)
        "UNIT limits retain the virtual-memory ceiling" "";
      check (limits.cpu_seconds = 2) "UNIT limits retain the CPU ceiling" "";
      check
        (limits.maximum_query_bytes = 4096 && limits.maximum_output_bytes = 16_384)
        "UNIT limits retain both byte bounds" "";
      check (String.length (sha256_to_hex limits.limits_digest) = 64)
        "UNIT limits have a canonical SHA-256 identity" ""
  | Error errors ->
      List.iter
        (fun label -> check false label (String.concat "; " errors))
        [ "UNIT limits retain the virtual-memory ceiling";
          "UNIT limits retain the CPU ceiling";
          "UNIT limits retain both byte bounds";
          "UNIT limits have a canonical SHA-256 identity" ]);
  List.iter
    (fun (label, result) -> check (Result.is_error result) label "accepted")
    [ ( "UNIT zero virtual memory is rejected",
        make_limits ~virtual_memory_bytes:0L ~cpu_seconds:2
          ~maximum_query_bytes:4096 ~maximum_output_bytes:16_384 );
      ( "UNIT zero CPU is rejected",
        make_limits ~virtual_memory_bytes:536_870_912L ~cpu_seconds:0
          ~maximum_query_bytes:4096 ~maximum_output_bytes:16_384 );
      ( "UNIT zero query budget is rejected",
        make_limits ~virtual_memory_bytes:536_870_912L ~cpu_seconds:2
          ~maximum_query_bytes:0 ~maximum_output_bytes:16_384 );
      ( "UNIT undersized output budget is rejected",
        make_limits ~virtual_memory_bytes:536_870_912L ~cpu_seconds:2
          ~maximum_query_bytes:4096 ~maximum_output_bytes:1 ) ];
  let exit_codes =
    [ exit_code Completed_exit; exit_code Unsupported_exit;
      exit_code Rejected_exit; exit_code Failed_exit ]
  in
  check (List.hd exit_codes = 0) "UNIT completed exit is zero" "";
  check
    (List.for_all (fun code -> code <> 0) (List.tl exit_codes))
    "UNIT every non-completed typed exit is non-zero" "";
  check
    (List.length (List.sort_uniq compare exit_codes) = List.length exit_codes)
    "UNIT typed exits have distinct codes" ""

let request_layer () =
  let open Run_analysis_z3_worker_protocol in
  match prepared () with
  | Error errors ->
      List.iter
        (fun label -> check false label (String.concat "; " errors))
        [ "REQUEST preparation succeeds"; "REQUEST stdin is byte-exact";
          "REQUEST fixed argv round-trips";
          "REQUEST argv binds the worker executable digest";
          "REQUEST substituted worker executable digest is rejected";
          "REQUEST an appended argv option is rejected";
          "REQUEST exact stdin is admitted";
          "REQUEST one-byte mutation is rejected"; "REQUEST truncation is rejected";
          "REQUEST appended second script is rejected" ]
  | Ok prepared ->
      check true "REQUEST preparation succeeds" "";
      check (String.equal (stdin_bytes prepared) trivial_query)
        "REQUEST stdin is byte-exact" "";
      let projected = argv prepared in
      (match decode_argv projected with
      | Error error ->
          check false "REQUEST fixed argv round-trips" (render_error error);
          check false "REQUEST argv binds the worker executable digest" "decode failed";
          check false "REQUEST substituted worker executable digest is rejected"
            "decode failed";
          check false "REQUEST an appended argv option is rejected" "decode failed";
          check false "REQUEST exact stdin is admitted" "decode failed";
          check false "REQUEST one-byte mutation is rejected" "decode failed";
          check false "REQUEST truncation is rejected" "decode failed";
          check false "REQUEST appended second script is rejected" "decode failed"
      | Ok request ->
          check
            (String.equal (sha256_to_hex request.request_digest)
               (sha256_to_hex prepared.request.request_digest))
            "REQUEST fixed argv round-trips" "";
          check
            (String.equal
               (sha256_to_hex request.worker_executable_digest)
               (sha256_to_hex prepared.request.worker_executable_digest))
            "REQUEST argv binds the worker executable digest" "";
          let substituted_worker = Array.copy projected in
          let rec substitute index =
            if index + 1 >= Array.length substituted_worker then ()
            else if
              String.equal substituted_worker.(index)
                "--worker-executable-digest"
            then substituted_worker.(index + 1) <- String.make 64 '0'
            else substitute (index + 1)
          in
          substitute 0;
          check (Result.is_error (decode_argv substituted_worker))
            "REQUEST substituted worker executable digest is rejected" "";
          check
            (Result.is_error
               (decode_argv (Array.append projected [| "--unexpected" |])))
            "REQUEST an appended argv option is rejected" "";
          check (Result.is_ok (admit_stdin request trivial_query))
            "REQUEST exact stdin is admitted" "";
          let mutated = Bytes.of_string trivial_query in
          Bytes.set mutated 1 'x';
          check (Result.is_error (admit_stdin request (Bytes.to_string mutated)))
            "REQUEST one-byte mutation is rejected" "";
          check
            (Result.is_error
               (admit_stdin request
                  (String.sub trivial_query 0 (String.length trivial_query - 1))))
            "REQUEST truncation is rejected" "";
          check
            (Result.is_error (admit_stdin request (trivial_query ^ "(check-sat)\n")))
            "REQUEST appended second script is rejected" "")

let resource_layer () =
  let open Run_analysis_z3_worker_protocol in
  let identity : Resource_envelope.executable_identity = { device = 7; inode = 11 } in
  let resources = resource_requirements ~worker_path:"/worker" ~expected:identity in
  let exact_count =
    List.fold_left
      (fun count -> function Resource_envelope.Exact_executable _ -> count + 1 | _ -> count)
      0 resources
  in
  let capabilities =
    List.filter_map
      (function Resource_envelope.Kernel_capability capability -> Some capability | _ -> None)
      resources
  in
  check (exact_count = 1) "RESOURCE one exact worker object is required" "";
  check
    (List.sort_uniq compare capabilities
     = List.sort compare
         Resource_envelope.
           [ Proc_self_fd_executable; Rlimit_as; Process_group_signalling ])
    "RESOURCE all three independent kernel capabilities are required" "";
  let observations =
    List.map
      (function
        | Resource_envelope.Exact_executable _ as resource ->
            Resource_envelope.evaluate resource
              (Resource_envelope.Unknown "object unavailable")
        | Resource_envelope.Kernel_capability _ as resource ->
            Resource_envelope.evaluate resource
              (Resource_envelope.Unknown "kernel unavailable")
        | resource -> Resource_envelope.evaluate resource (Resource_envelope.Unknown "unknown"))
      resources
  in
  check (not (Resource_envelope.satisfied observations))
    "RESOURCE Unknown fails the complete worker envelope closed" ""

let evidence_layer () =
  let open Run_analysis_z3_worker_protocol in
  let refusal =
    make_refusal ~request_digest:None
      (Unsupported_capability Resource_envelope.Rlimit_as)
      ~detail:"RLIMIT_AS unavailable"
  in
  let encoded = encode_refusal refusal in
  check (String.length encoded <= 4096) "EVIDENCE refusal is bounded" encoded;
  check (contains encoded "unsupported-capability:rlimit-as")
    "EVIDENCE refusal names the exact unsupported capability" encoded;
  match decode_frame ~maximum_bytes:4096 encoded with
  | Ok (Refusal decoded) ->
      check (decoded.reason = refusal.reason && decoded.refusal_digest = refusal.refusal_digest)
        "EVIDENCE refusal round-trips without gaining authority" ""
  | Ok (Handshake _ | Result _) ->
      check false "EVIDENCE refusal round-trips without gaining authority"
        "decoded as successful evidence"
  | Error error ->
      check false "EVIDENCE refusal round-trips without gaining authority"
        (render_error error)

let structure_layer () =
  let source =
    let channel = open_in "modules/hermes_ops_dashboard/run_analysis_z3_worker_protocol.mli" in
    Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        really_input_string channel (in_channel_length channel))
  in
  List.iter
    (fun forbidden ->
      check (not (contains source forbidden))
        ("STRUCTURE protocol exposes no " ^ forbidden) "")
    [ "Unix.file_descr"; "in_channel"; "out_channel"; "callback" ];
  check (contains source "type request = private")
    "STRUCTURE request construction is closed" "";
  check (contains source "type handshake = private")
    "STRUCTURE handshake construction is closed" "";
  check (contains source "type result = private")
    "STRUCTURE result construction is closed" "";
  List.iter
    (fun forbidden ->
      check (not (contains source forbidden))
        ("STRUCTURE parent cannot " ^ forbidden) "")
    [ "val make_handshake"; "val make_result"; "val encode_frame" ];
  List.iter
    (fun private_declaration ->
      check (contains source private_declaration)
        ("STRUCTURE evidence carrier is closed: " ^ private_declaration) "")
    [ "type limit_observation = private"; "type applied_limit = private";
      "type worker_object = private"; "type capture_receipt = private" ]

let () =
  print_endline "run_analysis linked-Z3 worker protocol suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("request", request_layer); ("resource", resource_layer);
      ("evidence", evidence_layer); ("structure", structure_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun failure -> print_endline ("  FAIL  " ^ failure)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_run_analysis_z3_worker_protocol"
      ~passed:!passed ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
