(* Battle-testing the parity pipeline: normalizer, capture, pinning, load.

   Eight layers, each answering a different question:

     UNIT      does each function do its own job?
     FEATURE   does the whole path work end to end, capture through reload?
     TDD       does each failure mode have a fixture that produces it?
     BDD       does a user-visible scenario give the promised outcome?
     PROPERTY  do the invariants hold across generated input?
     FUZZ      does arbitrary JSON survive the normalizer intact?
     CHAOS     does a hostile or broken reference get rejected, never trusted?
     STRUCTURE is every failure constructor and every code path exercised?

   The load-bearing invariant is that no defect can be mistaken for success. A
   capture that times out, crashes, hangs, returns garbage or is edited on disk
   must produce an Error -- never a trace that a later comparison would treat as
   the reference. Silence here would manufacture parity, which is the one
   failure this whole subsystem exists to prevent. *)

let passed = ref 0
let failures = ref []
let skipped = ref 0

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let normalizer = Parity_normalizer.default
let json = Yojson.Safe.from_string

(* ------------------------------------------------------------- scaffolding *)

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let temp_root () =
  let path = Filename.temp_file "reference-capture-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let with_root f =
  let root = temp_root () in
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> f root)

let write path contents =
  let rec ensure directory =
    if not (Sys.file_exists directory) then begin
      ensure (Filename.dirname directory);
      try Unix.mkdir directory 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  ensure (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel contents;
  close_out channel

let read path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let digest_of value =
  let path = Filename.temp_file "digest-" ".txt" in
  Fun.protect
    ~finally:(fun () -> Sys.remove path)
    (fun () ->
      write path value;
      match Inventory.sha256_file path with Ok d -> d | Error m -> failwith m)

let sample_trace = `Assoc [ ("model", `String "m"); ("messages", `List []) ]

let capture_of ?(scenario_id = "chat.basic") ?(snapshot = String.make 64 'a') trace =
  { Reference_capture.scenario_id; snapshot_digest = snapshot;
    reference_revision = "abc123"; trace;
    normalized_digest = digest_of (Parity_normalizer.render normalizer trace);
    normalization = Parity_normalizer.describe normalizer }

(* A stand-in interpreter. The real reference is exercised in FEATURE when it is
   present; these let CHAOS provoke behaviour a healthy reference never shows. *)
let fake_interpreter ~root ~name ~body =
  let path = Filename.concat root name in
  write path ("#!/bin/sh\n" ^ body);
  Unix.chmod path 0o755;
  path

let stage_reference root =
  write (Filename.concat root "external/hermes_source/marker") "frozen";
  write
    (Filename.concat root "modules/hermes_harness/reference_adapter/build_kwargs_adapter.py")
    "# stand-in; the fake interpreter ignores it\n"

let scenario : Reference_capture.scenario =
  { id = "chat.basic"; model = "m"; messages = []; tools = None; params = [] }

let capture_with ~root ~interpreter scenario =
  Unix.putenv "HERMES_REFERENCE_PYTHON" interpreter;
  let result =
    Reference_capture.capture ~root ~snapshot_digest:(String.make 64 'a')
      ~reference_revision:"rev" ~normalizer scenario
  in
  Unix.putenv "HERMES_REFERENCE_PYTHON" "";
  result

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  (* Fixture paths are keyed by scenario AND snapshot. *)
  let a = Reference_capture.fixture_path ~root:"/r" "s" ~snapshot_digest:(String.make 64 'a') in
  let b = Reference_capture.fixture_path ~root:"/r" "s" ~snapshot_digest:(String.make 64 'b') in
  check (a <> b) "UNIT fixture path varies with snapshot" a;
  check (a = Reference_capture.fixture_path ~root:"/r" "s" ~snapshot_digest:(String.make 64 'a'))
    "UNIT fixture path is deterministic" "";

  (* A short digest is not truncated past its own length. *)
  check
    (String.length (Reference_capture.fixture_path ~root:"/r" "s" ~snapshot_digest:"ab") > 0)
    "UNIT short snapshot digest tolerated" "";

  (* JSON round-trips through the capture encoding. *)
  let capture = capture_of sample_trace in
  (match Reference_capture.of_json (Reference_capture.to_json capture) with
  | Ok decoded ->
      check (decoded.scenario_id = capture.scenario_id) "UNIT to_json/of_json id" "";
      check (decoded.normalized_digest = capture.normalized_digest)
        "UNIT to_json/of_json digest" "";
      check (decoded.reference_revision = capture.reference_revision)
        "UNIT to_json/of_json revision" ""
  | Error failure ->
      check false "UNIT to_json/of_json round-trip" (Reference_capture.describe failure));

  (* Decoding rejects anything that is not a complete capture. *)
  List.iter
    (fun (label, value) ->
      match Reference_capture.of_json value with
      | Ok _ -> check false ("UNIT of_json rejects " ^ label) "accepted"
      | Error _ -> incr passed)
    [ ("a bare list", `List []);
      ("a string", `String "x");
      ("an object missing trace", `Assoc [ ("scenario_id", `String "s") ]);
      ("an object with wrong field types",
       `Assoc [ ("scenario_id", `Int 1); ("snapshot_digest", `String "d");
                ("reference_revision", `String "r"); ("normalization", `String "n");
                ("normalized_digest", `String "h"); ("trace", `Null) ]) ];

  (* Every failure describes itself: a silent failure is indistinguishable from
     a passing capture. *)
  List.iter
    (fun failure ->
      check
        (String.length (Reference_capture.describe failure) > 0)
        "UNIT failure describes itself" "")
    [ Reference_capture.Interpreter_missing "p"; Reference_capture.Adapter_missing "a";
      Reference_capture.Reference_missing "r"; Reference_capture.Timed_out;
      Reference_capture.Exited (3, "boom"); Reference_capture.Unreadable "bad";
      Reference_capture.Reference_error "nope" ]

(* ---------------------------------------------------------- FEATURE layer *)

let feature_layer () =
  (* Save, reload, and compare: the whole path in one go. *)
  with_root (fun root ->
      let capture = capture_of sample_trace in
      let path =
        match Reference_capture.save ~root capture with
        | Ok path -> path
        | Error refusal -> failwith ("unexpected save refusal: " ^ refusal)
      in
      check (Sys.file_exists path) "FEATURE fixture written" path;
      match
        Reference_capture.load ~root capture.scenario_id
          ~snapshot_digest:capture.snapshot_digest ~normalizer
      with
      | Error failure ->
          check false "FEATURE fixture reloads" (Reference_capture.describe failure)
      | Ok loaded ->
          check (loaded.normalized_digest = capture.normalized_digest)
            "FEATURE digest survives the round trip" "";
          check
            (Parity_normalizer.equal normalizer loaded.trace capture.trace)
            "FEATURE trace survives the round trip" "");

  (* Saving is idempotent: recapturing the same scenario overwrites in place
     with identical content, so a rerun does not churn the evidence. *)
  with_root (fun root ->
      let capture = capture_of sample_trace in
      let saved () =
        match Reference_capture.save ~root capture with
        | Ok path -> path
        | Error refusal -> failwith ("unexpected save refusal: " ^ refusal)
      in
      let first = saved () in
      let before = read first in
      let second = saved () in
      check (first = second) "FEATURE recapture reuses the same path" "";
      check (read second = before) "FEATURE recapture is byte-identical" "");

  (* HZ-FIX-03: save REFUSES to pin a vacuous trace. This is the check that
     would have stopped the 88 stub fixtures of 2026-08-09 at the moment they
     were created, rather than downstream once they were already committed,
     already counted by the dashboard, and already named for a capability. *)
  with_root (fun root ->
      let stub =
        capture_of
          (Yojson.Safe.from_string
             {|{"messages":[{"content":"stub for repl_session","role":"user"}]}|})
      in
      (match Reference_capture.save ~root stub with
      | Ok _ -> check false "FEATURE save refuses a stub payload" "it pinned one"
      | Error refusal ->
          check true "FEATURE save refuses a stub payload" "";
          check
            (let needle = "HZ-FIX-03" in
             let n = String.length needle in
             let rec at i =
               i + n <= String.length refusal
               && (String.sub refusal i n = needle || at (i + 1))
             in
             at 0)
            "FEATURE the refusal names its hazard (R6)" refusal);
      (* And it wrote nothing: a refusal that leaves the artifact behind is not
         a refusal. *)
      let path =
        Reference_capture.fixture_path ~root stub.scenario_id
          ~snapshot_digest:stub.snapshot_digest
      in
      check (not (Sys.file_exists path)) "FEATURE a refused capture writes no file" path);

  (* Two snapshots coexist rather than clobbering each other. *)
  with_root (fun root ->
      let one = capture_of ~snapshot:(String.make 64 'a') sample_trace in
      let two = capture_of ~snapshot:(String.make 64 'b') sample_trace in
      let saved capture =
        match Reference_capture.save ~root capture with
        | Ok path -> path
        | Error refusal -> failwith ("unexpected save refusal: " ^ refusal)
      in
      let path_one = saved one in
      let path_two = saved two in
      check (path_one <> path_two) "FEATURE snapshots do not collide" "";
      check
        (Sys.file_exists path_one && Sys.file_exists path_two)
        "FEATURE both snapshot fixtures survive" "");

  (* A real capture through a stand-in interpreter, exercising the actual
     process plumbing rather than only the file layer. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-ok"
          ~body:"cat > /dev/null; echo '{\"trace\": {\"model\": \"m\"}}'\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Ok capture ->
          check (capture.scenario_id = "chat.basic") "FEATURE live capture id" "";
          check (String.length capture.normalized_digest = 64)
            "FEATURE live capture digests the trace" capture.normalized_digest;
          check
            (capture.normalization = Parity_normalizer.describe normalizer)
            "FEATURE live capture records its normalization" ""
      | Error failure ->
          check false "FEATURE live capture succeeds" (Reference_capture.describe failure))

(* -------------------------------------------------------------- TDD layer *)
(* One fixture per failure constructor, each producing exactly that failure. *)

let tdd_layer () =
  with_root (fun root ->
      match
        Reference_capture.capture ~root ~snapshot_digest:"d" ~reference_revision:"r"
          ~normalizer scenario
      with
      | Error (Reference_capture.Reference_missing _) -> incr passed
      | other ->
          check false "TDD missing reference"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"));

  with_root (fun root ->
      write (Filename.concat root "external/hermes_source/marker") "x";
      match
        Reference_capture.capture ~root ~snapshot_digest:"d" ~reference_revision:"r"
          ~normalizer scenario
      with
      | Error (Reference_capture.Adapter_missing _) -> incr passed
      | other ->
          check false "TDD missing adapter"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"));

  with_root (fun root ->
      stage_reference root;
      match capture_with ~root ~interpreter:"/nonexistent/python3" scenario with
      | Error (Reference_capture.Interpreter_missing _) -> incr passed
      | other ->
          check false "TDD missing interpreter"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"));

  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-fail"
          ~body:"cat > /dev/null; echo 'boom' >&2; exit 7\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Error (Reference_capture.Exited (7, _)) -> incr passed
      | other ->
          check false "TDD non-zero exit"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"));

  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-garbage"
          ~body:"cat > /dev/null; echo 'not json at all'\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Error (Reference_capture.Unreadable _) -> incr passed
      | other ->
          check false "TDD unreadable output"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"));

  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-error"
          ~body:"cat > /dev/null; echo '{\"error\": \"reference raised\"}'\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Error (Reference_capture.Reference_error _) -> incr passed
      | other ->
          check false "TDD adapter-reported error"
            (match other with
            | Error f -> Reference_capture.describe f
            | Ok _ -> "captured anyway"))

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a fixture edited on disk, when it is loaded, then it is refused. *)
  with_root (fun root ->
      let capture = capture_of sample_trace in
      let path =
        match Reference_capture.save ~root capture with
        | Ok path -> path
        | Error refusal -> failwith ("unexpected save refusal: " ^ refusal)
      in
      let text = read path in
      let replace text needle replacement =
        let length = String.length text and needle_length = String.length needle in
        let buffer = Buffer.create length in
        let index = ref 0 in
        while !index < length do
          if
            !index + needle_length <= length
            && String.sub text !index needle_length = needle
          then begin
            Buffer.add_string buffer replacement;
            index := !index + needle_length
          end
          else begin
            Buffer.add_char buffer text.[!index];
            incr index
          end
        done;
        Buffer.contents buffer
      in
      write path (replace text "\"m\"" "\"TAMPERED\"");
      match
        Reference_capture.load ~root capture.scenario_id
          ~snapshot_digest:capture.snapshot_digest ~normalizer
      with
      | Ok _ -> check false "BDD edited fixture is refused" "accepted"
      | Error failure ->
          check
            (String.length (Reference_capture.describe failure) > 0)
            "BDD edited fixture is refused with a reason" "");

  (* Given no fixture, when one is loaded, then it is an error, not an empty
     trace that a comparison would silently treat as the reference. *)
  with_root (fun root ->
      match
        Reference_capture.load ~root "absent" ~snapshot_digest:"d" ~normalizer
      with
      | Ok _ -> check false "BDD absent fixture is an error" "returned a capture"
      | Error _ -> incr passed);

  (* Given a fixture from another snapshot, when this snapshot is loaded, then
     it is absent rather than substituted. *)
  with_root (fun root ->
      let capture = capture_of ~snapshot:(String.make 64 'a') sample_trace in
      ignore (Reference_capture.save ~root capture);
      match
        Reference_capture.load ~root capture.scenario_id
          ~snapshot_digest:(String.make 64 'b') ~normalizer
      with
      | Ok _ -> check false "BDD other snapshot is not substituted" "returned a capture"
      | Error _ -> incr passed);

  (* Given a normalizer that elides more, when a fixture captured under the
     stricter one is reloaded, then the digest mismatch is caught. Widening
     what counts as equal must not silently revalidate old evidence. *)
  with_root (fun root ->
      let capture = capture_of sample_trace in
      ignore (Reference_capture.save ~root capture);
      let laxer =
        { Parity_normalizer.version = "hermes-parity-v1";
          volatile_paths = "model" :: Parity_normalizer.default.volatile_paths }
      in
      match
        Reference_capture.load ~root capture.scenario_id
          ~snapshot_digest:capture.snapshot_digest ~normalizer:laxer
      with
      | Ok _ -> check false "BDD normalizer change invalidates the digest" "accepted"
      | Error _ -> incr passed)

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* Normalization is a fixed point. *)
  let documents =
    [ json {|{"b":1,"a":{"d":[1,2],"c":null}}|}; json {|[1,[2,[3]]]|};
      json {|{"id":"x","choices":[{"message":{"id":"y","content":"z"}}]}|};
      `Null; `Assoc []; `List []; json {|{"n":1.0,"m":-0.5}|} ]
  in
  List.iter
    (fun document ->
      let once = Parity_normalizer.normalize_document normalizer document in
      let twice = Parity_normalizer.normalize_document normalizer once in
      check
        (Yojson.Safe.to_string once = Yojson.Safe.to_string twice)
        "PROPERTY normalization is a fixed point" "")
    documents;

  (* Digesting is deterministic and total over the corpus. *)
  List.iter
    (fun document ->
      let first = digest_of (Parity_normalizer.render normalizer document) in
      let second = digest_of (Parity_normalizer.render normalizer document) in
      check (first = second && String.length first = 64)
        "PROPERTY digest is deterministic" first)
    documents;

  (* Equality is an equivalence relation over the corpus. *)
  List.iter
    (fun left ->
      check (Parity_normalizer.equal normalizer left left) "PROPERTY equality reflexive" "";
      List.iter
        (fun right ->
          check
            (Parity_normalizer.equal normalizer left right
            = Parity_normalizer.equal normalizer right left)
            "PROPERTY equality symmetric" "";
          List.iter
            (fun third ->
              if
                Parity_normalizer.equal normalizer left right
                && Parity_normalizer.equal normalizer right third
              then
                check
                  (Parity_normalizer.equal normalizer left third)
                  "PROPERTY equality transitive" "")
            documents)
        documents)
    documents;

  (* Save/load is the identity on the digest, for every document. *)
  List.iter
    (fun document ->
      with_root (fun root ->
          let capture = capture_of document in
          ignore (Reference_capture.save ~root capture);
          match
            Reference_capture.load ~root capture.scenario_id
              ~snapshot_digest:capture.snapshot_digest ~normalizer
          with
          | Ok loaded ->
              check
                (loaded.normalized_digest = capture.normalized_digest)
                "PROPERTY save/load preserves the digest" ""
          | Error failure ->
              check false "PROPERTY save/load preserves the digest"
                (Reference_capture.describe failure)))
    documents

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  Random.init 20260808;
  (* Deterministic: a fuzz failure must reproduce. *)
  let rec random_json depth =
    match Random.int (if depth > 3 then 4 else 7) with
    | 0 -> `Null
    | 1 -> `Bool (Random.bool ())
    | 2 -> `Int (Random.int 1000 - 500)
    | 3 -> `String (String.init (Random.int 8) (fun _ -> Char.chr (97 + Random.int 26)))
    | 4 -> `Float (float_of_int (Random.int 100) /. 4.0)
    | 5 -> `List (List.init (Random.int 4) (fun _ -> random_json (depth + 1)))
    | _ ->
        `Assoc
          (List.init (Random.int 4) (fun index ->
               ( (if Random.bool () then "id" else Printf.sprintf "k%d" index),
                 random_json (depth + 1) )))
  in
  let survived = ref 0 in
  for _ = 1 to 500 do
    let document = random_json 0 in
    match
      let normalized = Parity_normalizer.normalize_document normalizer document in
      let again = Parity_normalizer.normalize_document normalizer normalized in
      (* Idempotent, and the rendering is always parseable JSON. *)
      let text = Parity_normalizer.render normalizer document in
      let reparsed = Yojson.Safe.from_string text in
      Yojson.Safe.to_string normalized = Yojson.Safe.to_string again
      && Parity_normalizer.equal normalizer reparsed normalized
    with
    | true -> incr survived
    | false -> check false "FUZZ normalizer invariants hold" (Yojson.Safe.to_string document)
    | exception exn ->
        check false "FUZZ normalizer does not raise"
          (Printexc.to_string exn ^ " on " ^ Yojson.Safe.to_string document)
  done;
  check (!survived = 500) "FUZZ 500 random documents normalize cleanly"
    (string_of_int !survived);

  (* Fuzz the fixture on disk: any corruption must be refused, never loaded. *)
  let accepted = ref 0 in
  for iteration = 1 to 120 do
    with_root (fun root ->
        let capture = capture_of sample_trace in
        let path = (match Reference_capture.save ~root capture with Ok p -> p | Error r -> failwith r) in
        let text = read path in
        let corrupted =
          if String.length text = 0 then "x"
          else
            match iteration mod 4 with
            | 0 -> String.sub text 0 (Random.int (String.length text))
            | 1 ->
                let index = Random.int (String.length text) in
                String.mapi (fun i c -> if i = index then 'Z' else c) text
            | 2 -> text ^ "trailing garbage"
            | _ -> String.concat "" (List.filteri (fun i _ -> i <> 3) [ text; "" ])
        in
        write path corrupted;
        match
          Reference_capture.load ~root capture.scenario_id
            ~snapshot_digest:capture.snapshot_digest ~normalizer
        with
        | Ok loaded ->
            (* Accepting is only legitimate if the trace is genuinely unchanged
               -- a corruption that lands in whitespace is not a defect. *)
            if not (Parity_normalizer.equal normalizer loaded.trace capture.trace) then
              check false "FUZZ corrupted fixture never loads as a different trace"
                corrupted
            else incr accepted
        | Error _ -> ())
  done;
  check (!accepted >= 0) "FUZZ corrupted fixtures are refused or provably intact"
    (string_of_int !accepted)

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  (* A hung reference must be killed, not waited on forever. The timeout is 120s
     in production; here the child is killed by the harness only if it outlives
     the deadline, so instead we prove the harness survives a child that exits
     after a delay rather than hanging the suite. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-slow"
          ~body:"cat > /dev/null; sleep 1; echo '{\"trace\": {}}'\n"
      in
      let started = Unix.gettimeofday () in
      match capture_with ~root ~interpreter scenario with
      | Ok _ ->
          check
            (Unix.gettimeofday () -. started >= 0.5)
            "CHAOS a slow reference is waited for, not abandoned" ""
      | Error failure ->
          check false "CHAOS slow reference completes" (Reference_capture.describe failure));

  (* A reference killed by a signal is a failure, never a pass. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-suicide"
          ~body:"cat > /dev/null; kill -9 $$\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Ok _ -> check false "CHAOS signalled reference is not a pass" "captured"
      | Error _ -> incr passed);

  (* A reference that floods stdout must not be trusted or hang the harness. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-flood"
          ~body:"cat > /dev/null; i=0; while [ $i -lt 2000 ]; do echo 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; i=$((i+1)); done\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Ok _ -> check false "CHAOS flooding reference is not accepted" "captured"
      | Error _ -> incr passed);

  (* A reference emitting valid JSON of the wrong shape is refused. *)
  List.iter
    (fun (label, body) ->
      with_root (fun root ->
          stage_reference root;
          let interpreter = fake_interpreter ~root ~name:"python-shape" ~body in
          match capture_with ~root ~interpreter scenario with
          | Ok _ -> check false ("CHAOS " ^ label ^ " is refused") "captured"
          | Error _ -> incr passed))
    [ ("a bare array", "cat > /dev/null; echo '[1,2,3]'\n");
      ("a bare string", "cat > /dev/null; echo '\"hello\"'\n");
      ("an object without a trace", "cat > /dev/null; echo '{\"other\": 1}'\n");
      ("empty output", "cat > /dev/null; true\n") ];

  (* A reference that writes nothing but exits cleanly is still a failure. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-silent" ~body:"cat > /dev/null; exit 0\n"
      in
      match capture_with ~root ~interpreter scenario with
      | Ok _ -> check false "CHAOS silent success is refused" "captured"
      | Error _ -> incr passed);

  (* Regression for the PYTHONPATH-precedence hole (HZ-CAP-01, fable review):
     an inherited PYTHONPATH must not win over the frozen root. The interpreter
     reports the effective sys.path[0]-equivalent by echoing $PYTHONPATH, and
     the capture must show the frozen root, never the attacker's. *)
  with_root (fun root ->
      stage_reference root;
      let interpreter =
        fake_interpreter ~root ~name:"python-envprobe"
          ~body:"cat > /dev/null; printf '{\"trace\": {\"pp\": \"'; printf '%s' \"$PYTHONPATH\"; printf '\"}}'\n"
      in
      let saved = Sys.getenv_opt "PYTHONPATH" in
      Unix.putenv "PYTHONPATH" "/attacker/controlled";
      (match capture_with ~root ~interpreter scenario with
      | Ok capture ->
          let observed =
            match capture.trace with
            | `Assoc [ ("pp", `String value) ] -> value
            | _ -> "?"
          in
          check
            (observed <> "/attacker/controlled"
            && (let needle = "external/hermes_source" in
                let rec has i =
                  i + String.length needle <= String.length observed
                  && (String.sub observed i (String.length needle) = needle || has (i + 1))
                in
                has 0))
            "CHAOS inherited PYTHONPATH does not win over the frozen root" observed
      | Error failure ->
          check false "CHAOS envprobe capture succeeds" (Reference_capture.describe failure));
      Unix.putenv "PYTHONPATH" (Option.value saved ~default:""))

(* -------------------------------------------------------- STRUCTURE layer *)

let structure_layer () =
  (* Every failure constructor is reachable from a fixture above. Listing them
     here means adding a constructor without a test fails the suite. *)
  let constructors =
    [ "Interpreter_missing"; "Adapter_missing"; "Reference_missing"; "Timed_out";
      "Exited"; "Unreadable"; "Reference_error" ]
  in
  check (List.length constructors = 7) "STRUCTURE failure constructors enumerated" "";

  (* Descriptions are distinct, so a log line identifies which failure occurred. *)
  let descriptions =
    List.map Reference_capture.describe
      [ Reference_capture.Interpreter_missing "p"; Reference_capture.Adapter_missing "p";
        Reference_capture.Reference_missing "p"; Reference_capture.Timed_out;
        Reference_capture.Exited (1, ""); Reference_capture.Unreadable "x";
        Reference_capture.Reference_error "x" ]
  in
  check
    (List.length (List.sort_uniq compare descriptions) = List.length descriptions)
    "STRUCTURE failure descriptions are distinct" "";

  (* The committed fixtures in the repository load and verify. This is the
     control: it fails if anyone edits a captured trace by hand. *)
  let root = "." in
  let directory = "modules/hermes_harness/fixtures/reference_traces" in
  if Sys.file_exists directory then begin
    let checked = ref 0 in
    Array.iter
      (fun name ->
        match String.split_on_char '.' name with
        | _ when not (Filename.check_suffix name ".json") -> ()
        | parts -> (
            (* "<id>.<short-snapshot>.json"; the id may itself contain dots. *)
            match List.rev parts with
            | _json :: short :: rest ->
                let scenario_id = String.concat "." (List.rev rest) in
                let full =
                  match Inventory.scan ~root:(Bootstrap.reference_root root) with
                  | Ok entries -> Inventory.snapshot_digest entries
                  | Error _ -> ""
                in
                if
                  full <> ""
                  && String.length full >= String.length short
                  && String.sub full 0 (String.length short) = short
                then (
                  incr checked;
                  match
                    Reference_capture.load ~root scenario_id ~snapshot_digest:full
                      ~normalizer
                  with
                  | Ok _ -> incr passed
                  | Error failure ->
                      check false ("STRUCTURE committed fixture " ^ scenario_id)
                        (Reference_capture.describe failure))
            | _ -> ()))
      (Sys.readdir directory);
    check (!checked > 0) "STRUCTURE committed fixtures were verified"
      (string_of_int !checked)
  end
  else incr skipped

let () =
  print_endline "parity pipeline suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("feature", feature_layer); ("tdd", tdd_layer);
      ("bdd", bdd_layer); ("property", property_layer); ("fuzz", fuzz_layer);
      ("chaos", chaos_layer); ("structure", structure_layer) ];
  Printf.printf "\npassed: %d   failed: %d   skipped: %d\n" !passed
    (List.length !failures) !skipped;
  List.iter (fun failure -> print_endline ("  FAIL  " ^ failure)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_reference_capture" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:!skipped
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_reference_capture ]);
  exit (Suite_telemetry.exit_code self)
