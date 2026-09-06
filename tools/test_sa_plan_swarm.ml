#use "topfind";;
#require "core,sqlite3,yojson,bos.setup";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/.sa_plan.objs/byte";;
#directory "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan";;
#load "sa_plan.cma";;
#use "sa_plan_swarm.ml";;

open Core

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let ok = function Ok value -> value | Error message -> failwith message

let now = ref 1_000_000L
let tick () =
  now := Int64.(!now + 1_000L);
  !now
let lease_ns = 1_320_000_000_000L

let evidence_path = ref ""
let evidence_digest = ref ""

let write_file path contents =
  let channel = Stdlib.open_out_bin path in
  Fun.protect ~finally:(fun () -> Stdlib.close_out_noerr channel)
    (fun () -> Stdlib.output_string channel contents)

let error_is expected = function
  | Error message -> String.equal message expected
  | Ok _ -> false

let with_input_file suffix contents f =
  let path = Stdlib.Filename.temp_file "uos-sa-plan-swarm-input-" suffix in
  Fun.protect ~finally:(fun () -> Stdlib.Sys.remove path)
    (fun () -> write_file path contents; f path)

let checked_input_tests () =
  let valid_json =
    {|{"schema":"uos.manual-execution-receipt.v1","task_id":"E01","candidate":{"change_id":"candidate-a","commit_id":"c0ffee"},"status":"PASSED"}|}
  in
  List.iter
    [ "MALFORMED", "{", "JSON must be valid execution JSON";
      "NONOBJECT", "[]", "JSON must be an object";
      "SCHEMA", {|{"schema":"other"}|}, "unsupported receipt schema" ]
    ~f:(fun (label, contents, expected) ->
      with_input_file ".json" contents (fun path ->
        require ("SWARM-CLI-" ^ label ^ "-REFUSAL") (error_is expected (read path))));
  with_input_file ".json" (String.make (evidence_size_ceiling + 1) ' ') (fun path ->
    require "SWARM-CLI-OVERSIZE-REFUSAL"
      (error_is "evidence file exceeds its hash quota" (read path)));
  with_input_file ".txt" valid_json (fun path ->
    require "SWARM-CLI-EXTENSION-REFUSAL"
      (error_is "receipt input extension must be .json" (read path)));
  let forbidden = Stdlib.Filename.temp_file "uos-other-input-" ".json" in
  Fun.protect ~finally:(fun () -> Stdlib.Sys.remove forbidden) (fun () ->
    write_file forbidden valid_json;
    require "SWARM-CLI-ALLOWLIST-REFUSAL"
      (error_is "evidence path is outside the canonical allowlist" (read forbidden)));
  with_input_file ".json"
    (valid_json ^ String.make (evidence_size_ceiling - String.length valid_json) ' ')
    (fun path ->
      require "SWARM-CLI-EXACT-QUOTA-ACCEPTED"
        (match read path with Ok bytes -> String.length bytes = evidence_size_ceiling | Error _ -> false));
  with_input_file ".json" valid_json (fun path ->
    let bytes, observed = ok (descriptor_bytes ~validate:validate_evidence_path path) in
    require "SWARM-RECEIPT-EVIDENCE-CHECKED-READ-ACCEPTED"
      (Result.is_ok (verify_evidence_item (`Assoc [
        "kind", `String "receipt"; "path", `String path; "sha256", `String observed ])));
    write_file path "[]";
    require "SWARM-PARSER-USES-CHECKED-BYTES"
      (String.equal observed (Digestif.SHA256.digest_string bytes |> Digestif.SHA256.to_hex)
       && Result.is_ok (validate_receipt_evidence bytes)
       && error_is "JSON must be an object" (read path)));
  List.iter ["{", "JSON must be valid execution JSON";
             "[]", "JSON must be an object";
             {|{"schema":"other"}|}, "receipt evidence has an unsupported schema"]
    ~f:(fun (contents, expected) ->
      with_input_file ".json" contents (fun path ->
        let digest = ok (bounded_sha256 path) in
        require "SWARM-RECEIPT-EVIDENCE-INVALID-JSON-REFUSAL"
          (error_is expected (verify_evidence_item (`Assoc [
            "kind", `String "receipt"; "path", `String path; "sha256", `String digest ])))));
  with_input_file ".txt" (String.make (evidence_size_ceiling + 100) 'x') (fun path ->
    let fd = Core_unix.openfile path ~mode:[Core_unix.O_RDONLY; Core_unix.O_NONBLOCK] in
    Fun.protect ~finally:(fun () -> Core_unix.close fd) (fun () ->
      let result = read_bounded_descriptor fd ~quota:evidence_size_ceiling in
      let position = Core_unix.lseek fd 0L ~mode:Core_unix.SEEK_CUR in
      require "SWARM-READ-QUOTA-PLUS-ONE-SENTINEL"
        (error_is "evidence exceeded its hash quota" result
         && Int64.equal position (Int64.of_int (evidence_size_ceiling + 1)))));
  (* The validator callback deterministically substitutes the final component
     between the path check and open, without any production test hook. *)
  List.iter [false; true] ~f:(fun fifo ->
    with_input_file ".json" valid_json (fun path ->
      let first = ref true in
      let validate path =
        Result.map (validate_evidence_path path) ~f:(fun stat ->
          if !first then (
            first := false;
            if fifo then (
              Stdlib.Sys.remove path;
              Core_unix.mkfifo path ~perm:0o600)
            else with_input_file ".json" (valid_json ^ " ") (fun replacement ->
              (* Keep the temporary pathname present for its cleanup. *)
              Core_unix.rename ~src:replacement ~dst:path;
              write_file replacement ""));
          stat)
      in
      require
        (if fifo then "SWARM-FIFO-SWAP-NONBLOCKING-REFUSAL" else "SWARM-INODE-SWAP-BEFORE-READ-REFUSAL")
        (error_is
           (if fifo then "evidence must be a regular file"
            else "evidence path changed before descriptor validation")
           (descriptor_bytes ~validate path))));
  with_input_file ".json" valid_json (fun path ->
    let calls = ref 0 in
    let validate path =
      incr calls;
      if !calls = 2 then write_file path (valid_json ^ " ");
      validate_evidence_path path
    in
    require "SWARM-POSTREAD-MUTATION-REFUSAL"
      (error_is "evidence changed while being hashed" (descriptor_bytes ~validate path)))

let receipt ~task ~attempt ~candidate ~stage ~status ~dependencies ~evidence =
  let owner = "worker-a" in
  let evidence =
    List.map evidence ~f:(fun _ ->
      `Assoc
        [ "kind", `String "artifact";
          "path", `String !evidence_path;
          "sha256", `String !evidence_digest ])
  in
  Yojson.Basic.to_string
    (`Assoc
      [ "schema", `String "uos.manual-execution-receipt.v1";
        "manifest_sha256", `String manifest_digest;
        "task_id", `String task;
        "attempt", `String attempt;
        "candidate", `Assoc [ "change_id", `String candidate; "commit_id", `String "c0ffee" ];
        "run", `Assoc [ "owner", `String owner; "attempt", `String attempt ];
        "stage", `String stage;
        "status", `String status;
        "dependencies", `Assoc dependencies;
        "evidence", `List evidence ])

let with_store f =
  let path = Stdlib.Filename.temp_file "uos-sa-plan-swarm-test-" ".sqlite3" in
  let artifact =
    Stdlib.Filename.temp_file "uos-sa-plan-swarm-artifact-" ".txt"
  in
  write_file artifact "synthetic candidate-bound test artifact\n";
  evidence_path := artifact;
  evidence_digest := ok (bounded_sha256 artifact);
  Fun.protect
    ~finally:(fun () ->
      if Stdlib.Sys.file_exists artifact then Stdlib.Sys.remove artifact;
      if Stdlib.Sys.file_exists path then Stdlib.Sys.remove path)
    (fun () -> f path)

let () =
  checked_input_tests ();
  with_store (fun db ->
    let store = ok (S.open_db db) in
    let manifest = manifest_for_test () in
    let vector =
      Stdlib.Filename.temp_file "uos-sa-plan-swarm-vector-" ".txt"
    in
    write_file vector "abc";
    Fun.protect
      ~finally:(fun () ->
        if Stdlib.Sys.file_exists vector then Stdlib.Sys.remove vector)
      (fun () ->
        require "SWARM-DESCRIPTOR-SHA256-VECTOR"
          (match bounded_sha256 vector with
           | Ok digest ->
               String.equal digest
                 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
           | Error _ -> false));
    let oversized =
      Stdlib.Filename.temp_file "uos-sa-plan-swarm-oversized-" ".txt"
    in
    write_file oversized (String.make (evidence_size_ceiling + 1) 'x');
    Fun.protect
      ~finally:(fun () ->
        if Stdlib.Sys.file_exists oversized then Stdlib.Sys.remove oversized)
      (fun () ->
        require "SWARM-DESCRIPTOR-SHA256-OVERSIZE-REFUSAL"
          (Result.is_error (bounded_sha256 oversized)));
    let forbidden =
      Stdlib.Filename.temp_file "uos-sa-plan-swarm-forbidden-" ".txt"
    in
    write_file forbidden "synthetic forbidden sentinel\n";
    let traversal =
      "/tmp/uos-sa-plan-swarm-artifact-escape/../"
      ^ Stdlib.Filename.basename forbidden
    in
    let malformed_artifact path =
      `Assoc
        [ "kind", `String "artifact";
          "path", `String path;
          "sha256", `String !evidence_digest ]
    in
    require "SWARM-EVIDENCE-TRAVERSAL-REFUSAL"
      (Result.is_error (verify_evidence_item (malformed_artifact traversal)));
    let symlink =
      Stdlib.Filename.temp_file "uos-sa-plan-swarm-symlink-" ".txt"
    in
    Stdlib.Sys.remove symlink;
    Core_unix.symlink ~target:forbidden ~link_name:symlink;
    Fun.protect
      ~finally:(fun () ->
        if Stdlib.Sys.file_exists symlink then Stdlib.Sys.remove symlink;
        if Stdlib.Sys.file_exists forbidden then Stdlib.Sys.remove forbidden)
      (fun () ->
        require "SWARM-EVIDENCE-SYMLINK-REFUSAL"
          (Result.is_error (verify_evidence_item (malformed_artifact symlink))));
    register_master_for_test store manifest ~now_ns:(tick ());
    require "SWARM-DEPENDENCY-REFUSAL"
      (Result.is_error
         (register_attempt store manifest ~task_id:"E02" ~attempt:"a1"
            ~owner:"worker-a" ~preflight:
              (receipt ~task:"E02" ~attempt:"a1" ~candidate:"candidate-a"
                 ~stage:"preflight" ~status:"PASSED" ~dependencies:[]
                 ~evidence:[ "receipt" ]) ~now_ns:(tick ())));
    let e01_preflight =
      receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
        ~stage:"preflight" ~status:"PASSED"
        ~dependencies:[ "PLAN00", `String "PASSED" ] ~evidence:[ "plan00-receipt" ]
    in
    let first =
      ok
        (register_attempt store manifest ~task_id:"E01" ~attempt:"a1"
           ~owner:"worker-a" ~preflight:e01_preflight ~now_ns:(tick ()))
    in
    List.iter [ "{", "JSON must be valid execution JSON";
                "[]", "JSON must be an object";
                String.make (evidence_size_ceiling + 1) ' ', "JSON exceeds its read quota" ]
      ~f:(fun (raw, expected) ->
        require "SWARM-REGISTER-INVALID-JSON-IS-ERROR"
          (error_is expected (register_attempt store manifest ~task_id:"E01" ~attempt:"a1"
             ~owner:"worker-a" ~preflight:raw ~now_ns:(tick ())));
        require "SWARM-STAGE-INVALID-JSON-IS-ERROR" (error_is expected (bound first "verification" raw));
        require "SWARM-FINISH-INVALID-JSON-IS-ERROR"
          (error_is expected (finish_attempt store first ~owner:"worker-a" ~lease_id:"unused"
             ~receipt:raw ~now_ns:(tick ()))));
    let replay =
      ok
        (register_attempt store manifest ~task_id:"E01" ~attempt:"a1"
           ~owner:"worker-a" ~preflight:e01_preflight ~now_ns:(tick ()))
    in
    require "SWARM-SAFE-REGISTER-REPLAY" (String.equal first.plan_id replay.plan_id);
    let e07 = ok (find_task manifest "E07") in
    let e07_attempt = { first with task = e07 } in
    require "SWARM-EXTERNAL-FEDERATION-UNSUPPORTED"
      (match external_receipts e07_attempt (`Assoc []) with
       | Error message -> String.is_prefix message ~prefix:"UNSUPPORTED_EXTERNAL_STORE:"
       | Ok () -> false);
    require "SWARM-DUPLICATE-CONFLICT-REFUSAL"
      (Result.is_error
         (register_attempt store manifest ~task_id:"E01" ~attempt:"a1"
            ~owner:"worker-a" ~preflight:
              (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-b"
                 ~stage:"preflight" ~status:"PASSED"
                 ~dependencies:[ "PLAN00", `String "PASSED" ]
                 ~evidence:[ "different-candidate" ]) ~now_ns:(tick ()))); 
    require "SWARM-REGISTERED-OWNER-REFUSAL"
      (Result.is_error (stored store manifest "E01" "a1" "worker-b"));
    ignore
      (ok
         (S.claim_task store ~plan_id:manifest.plan_id ~task_id:"E01"
            ~worker:"worker-a" ~now_ns:(tick ()) ~lease_ns));
    let started = ok (start_attempt store first ~now_ns:(tick ()) ~lease_ns) in
    require "SWARM-STARTS-FENCED-ATTEMPT"
      (Int64.(started.fence > 0L) && String.equal started.owner "worker-a");
    require "SWARM-STALE-OWNER-REFUSAL"
      (Result.is_error
         (record_attempt store first ~owner:"worker-b" ~lease_id:started.lease_id
            ~stage:"verification" ~receipt:
              (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                 ~stage:"verification" ~status:"PASSED"
                 ~dependencies:[ "PLAN00", `String "PASSED" ] ~evidence:[ "test" ])
            ~now_ns:(tick ())));
    require "SWARM-EXPIRED-LEASE-REFUSAL"
      (Result.is_error
         (record_attempt store first ~owner:"worker-a" ~lease_id:started.lease_id
            ~stage:"verification" ~receipt:
              (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                 ~stage:"verification" ~status:"PASSED"
                 ~dependencies:[ "PLAN00", `String "PASSED" ] ~evidence:[ "test" ])
            ~now_ns:Int64.(started.expires_at_ns + 1L)));
    let restart_now = Int64.(started.expires_at_ns + 2L) in
    ignore
      (ok
         (S.claim_task store ~plan_id:manifest.plan_id ~task_id:"E01"
            ~worker:"worker-a" ~now_ns:restart_now ~lease_ns));
    let restarted =
      ok
        (start_attempt store first ~now_ns:restart_now
           ~lease_ns)
    in
    require "SWARM-EXPIRED-REPLAY-GETS-NEW-FENCE" Int64.(restarted.fence > started.fence);
    List.iter
      [ "red-test", "EXPECTED_FAILURE";
        "implementation", "PASSED";
        "verification", "PASSED";
        "review", "PASSED" ]
      ~f:(fun (stage, status) ->
        ok
          (record_attempt store first ~owner:"worker-a" ~lease_id:restarted.lease_id
             ~stage
             ~receipt:
               (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                  ~stage ~status
                  ~dependencies:[ "PLAN00", `String "PASSED" ]
             ~evidence:[ "local-receipt" ])
             ~now_ns:Int64.(restarted.expires_at_ns - 20L)));
    require "SWARM-LEASE-EQUALITY-IS-LIVE"
      (Result.is_ok
         (current_lease store first ~owner:"worker-a"
            ~lease_id:restarted.lease_id ~now_ns:restarted.expires_at_ns));
    require "SWARM-CLI-MINIMUM-LEASE-SECONDS"
      (match lease_ns_of_seconds 1_320L with
       | Ok lease -> Int64.equal lease lease_ns
       | Error _ -> false);
    require "SWARM-COMPLETION-MISSING-EVIDENCE-REFUSED"
      (Result.is_error
         (finish_attempt store first ~owner:"worker-a" ~lease_id:restarted.lease_id
            ~receipt:
              (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                 ~stage:"finish" ~status:"PASSED"
                 ~dependencies:[ "PLAN00", `String "PASSED" ] ~evidence:[])
            ~now_ns:restarted.expires_at_ns));
    let finished =
      ok
        (finish_attempt store first ~owner:"worker-a" ~lease_id:restarted.lease_id
           ~receipt:
             (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                ~stage:"finish" ~status:"PASSED"
                ~dependencies:[ "PLAN00", `String "PASSED" ]
                ~evidence:[ "bounded-test-receipt" ]) ~now_ns:Int64.(restarted.expires_at_ns - 1L))
    in
    require "SWARM-FINISHES-SUPPORT-ONLY" (Poly.equal finished.state S.Job_completed);
    require "SWARM-ORIGINAL-TASK-UNTOUCHED"
      (match ok (S.find_task store ~plan_id:manifest.plan_id ~id_or_name:"E01") with
       | Some task -> String.equal task.state "executing"
       | None -> false);
    require "SWARM-FINISH-REPLAY-REFUSAL"
      (Result.is_error
         (finish_attempt store first ~owner:"worker-a" ~lease_id:restarted.lease_id
            ~receipt:
              (receipt ~task:"E01" ~attempt:"a1" ~candidate:"candidate-a"
                 ~stage:"finish" ~status:"PASSED"
                 ~dependencies:[ "PLAN00", `String "PASSED" ]
                 ~evidence:[ "bounded-test-receipt" ]) ~now_ns:(tick ())));
    S.close store)
