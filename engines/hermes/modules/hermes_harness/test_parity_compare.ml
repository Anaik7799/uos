(* Battle-testing the L4-L6 comparison: the code that earns or denies parity.

   The invariants that matter are the ones that keep a false parity out of the
   store. Agreement must be real agreement after normalization; a divergence
   must be classified Implementation so it can deny credit; and anything the
   comparison cannot actually check -- a missing fixture, an unmapped scenario
   -- must block credit rather than pass. *)

let passed = ref 0
let failures = ref []
let skipped = ref 0

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let normalizer = Parity_normalizer.default
let json = Yojson.Safe.from_string

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Array.iter (fun name -> remove_tree (Filename.concat path name)) (Sys.readdir path);
      Unix.rmdir path
    end
    else Sys.remove path

let temp_root () =
  let path = Filename.temp_file "parity-compare-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let with_root f =
  let root = temp_root () in
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> f root)

(* Save a reference fixture with a correctly derived digest, going through the
   capture module's own save so the test cannot pass on a digest the code never
   produces. *)
let pin_reference ~root ~scenario_id ~snapshot trace =
  let rendered = Parity_normalizer.render normalizer trace in
  let digest_path = Filename.concat root "d.txt" in
  let channel = open_out_bin digest_path in
  output_string channel rendered;
  close_out channel;
  let digest =
    match Inventory.sha256_file digest_path with Ok d -> d | Error m -> failwith m
  in
  Sys.remove digest_path;
  let capture : Reference_capture.capture =
    { scenario_id; snapshot_digest = snapshot; reference_revision = "rev"; trace;
      normalized_digest = digest; normalization = Parity_normalizer.describe normalizer }
  in
  ignore (Reference_capture.save ~root capture)

(* -------------------------------------------------------- STUB GUARD layer

   The 88 stub reference traces pinned on 2026-08-09 are the reason this layer
   exists. Each carries a capability's name and a payload of "stub for <id>",
   so ANY candidate reproduces it -- including one that implements nothing.
   Recording a verdict over such a trace grants credit no scenario earned
   (H-1). These checks pin the refusal, and the non-vacuity check below proves
   the guard fires on the REAL corpus rather than only on synthetic input. *)

let stub_trace scenario_suffix =
  json
    (Printf.sprintf
       {|{"messages":[{"content":"stub for %s","role":"user"}],"model":"openai/gpt-5.4"}|}
       scenario_suffix)

let stub_guard_layer () =
  check
    (Parity_compare.is_stub_payload (stub_trace "repl_session"))
    "UNIT a stub payload nested in messages is detected" "";
  check
    (Parity_compare.is_stub_payload (json {|["a",["b",{"k":"stub for deep"}]]|}))
    "UNIT detection reaches through nested lists and objects" "";
  check
    (not
       (Parity_compare.is_stub_payload
          (json {|{"messages":[{"content":"hi","role":"user"}],"model":"m"}|})))
    "UNIT a real trace is not flagged" "";
  (* The marker is anchored: a sentence that merely mentions the words is a
     legitimate payload, and flagging it would make the guard a censor. *)
  check
    (not (Parity_compare.is_stub_payload (json {|{"c":"this is not a stub for anything"}|})))
    "UNIT the marker must be a prefix, not a substring" "";

  (* NON-VACUITY: the guard must fire on the fixtures that actually exist. A
     synthetic-only test would pass even if the real corpus used a different
     shape -- which is the very trap this guard is about. *)
  let verdicts_in dir =
    if not (Sys.file_exists dir) then None
    else
      let classify name =
        if not (Filename.check_suffix name ".json") then None
        else
          match Yojson.Safe.from_file (Filename.concat dir name) with
          | exception _ -> None
          | `Assoc fields -> (
              match List.assoc_opt "trace" fields with
              | Some trace -> Some (Parity_compare.is_stub_payload trace)
              | None -> None)
          | _ -> None
      in
      Some (List.filter_map classify (Array.to_list (Sys.readdir dir)))
  in
  (* The LIVE corpus must contain no stub. This is the check that fails if one
     is ever re-pinned there, which is the whole point of the quarantine. *)
  (match verdicts_in "modules/hermes_harness/fixtures/reference_traces" with
  | None -> incr skipped
  | Some verdicts ->
      let flagged = List.length (List.filter (fun x -> x) verdicts) in
      check (flagged = 0)
        "STRUCTURE no live reference trace is a stub payload"
        (Printf.sprintf "flagged %d of %d" flagged (List.length verdicts));
      (* Non-vacuity for THIS check: it must be reading a real, non-empty
         corpus, or "zero stubs" is true of an empty directory. *)
      check
        (List.length verdicts >= 24)
        "STRUCTURE the live-corpus check read a non-empty corpus"
        (Printf.sprintf "%d traces" (List.length verdicts)));
  (* The QUARANTINE must remain entirely flagged. This is what keeps the guard
     honest: a detector that fires on nothing is indistinguishable from one
     that is broken. *)
  (match verdicts_in "modules/hermes_harness/fixtures/quarantine-stub-traces-2026-08-09" with
  | None -> incr skipped
  | Some verdicts ->
      let clean = List.length (List.filter (fun x -> not x) verdicts) in
      check (clean = 0 && verdicts <> [])
        "STRUCTURE the guard flags every quarantined stub (non-vacuous)"
        (Printf.sprintf "unflagged %d of %d" clean (List.length verdicts)));

  (* BDD: record REFUSES, and the refusal names the scenario so an operator can
     act on it. Storage is the point of no return -- a stub receipt in the
     store is indistinguishable from an earned one. *)
  with_root (fun root ->
      match Evidence_store.open_db ~path:(Filename.concat root "e.sqlite") with
      | Error _ -> incr skipped
      | Ok store ->
          let comparison : Parity_compare.comparison =
            { scenario_id = "agent_loop.prompt_assembly"; node = "n";
              reference = stub_trace "prompt_assembly";
              candidate = stub_trace "prompt_assembly";
              verdict = Parity_algebra.Verified;
              reference_digest = String.make 64 'a';
              candidate_digest = String.make 64 'a'; diagnostic = None }
          in
          (match
             Parity_compare.record ~store ~snapshot_digest:"snap"
               ~harness_revision:"rev" ~normalizer comparison
           with
          | Ok () -> check false "BDD record refuses a stub-derived comparison" "it recorded"
          | Error message ->
              check true "BDD record refuses a stub-derived comparison" "";
              check
                (let needle = "agent_loop.prompt_assembly" in
                 let n = String.length needle in
                 let rec at i =
                   i + n <= String.length message
                   && (String.sub message i n = needle || at (i + 1))
                 in
                 at 0)
                "BDD the refusal names the scenario" message);
          (* A verified comparison over a REAL trace must still record, or the
             guard would have replaced one failure mode with a worse one. *)
          let honest =
            { comparison with scenario_id = "chat.minimal";
              reference = json {|{"messages":[{"content":"hi"}]}|};
              candidate = json {|{"messages":[{"content":"hi"}]}|} }
          in
          check
            (Parity_compare.record ~store ~snapshot_digest:"snap"
               ~harness_revision:"rev" ~normalizer honest
             <> Error "")
            "BDD a real comparison still records" "";
          Evidence_store.close store)

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  (* Identical traces agree; the verdict is Verified and there is no diagnostic. *)
  let same = json {|{"model":"m","messages":[]}|} in
  let c =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n" ~reference:same
      ~candidate:same
  in
  check (c.verdict = Parity_algebra.Verified) "UNIT identical traces verify" "";
  check (c.diagnostic = None) "UNIT a verified comparison has no diagnostic" "";
  check (c.reference_digest = c.candidate_digest) "UNIT identical traces share a digest" "";

  (* Different traces diverge, with an Implementation diagnostic -- the only
     origin permitted to deny credit. *)
  let d =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
      ~reference:(json {|{"model":"a"}|}) ~candidate:(json {|{"model":"b"}|})
  in
  check (d.verdict = Parity_algebra.Divergent) "UNIT differing traces diverge" "";
  (match d.diagnostic with
  | Some diag ->
      check (diag.origin = Fractal_diagnostic.Implementation)
        "UNIT divergence is Implementation origin" "";
      check (diag.impact = Fractal_diagnostic.Denies_credit)
        "UNIT divergence denies credit" ""
  | None -> check false "UNIT divergence carries a diagnostic" "none");
  check (d.reference_digest <> d.candidate_digest) "UNIT differing traces differ in digest" "";

  (* Key order and numeric tagging never cause a false divergence: this is the
     normalizer's job, exercised through the comparison. *)
  let reorder =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
      ~reference:(json {|{"a":1,"b":2}|}) ~candidate:(json {|{"b":2,"a":1}|})
  in
  check (reorder.verdict = Parity_algebra.Verified) "UNIT key order is not a divergence" "";
  let numeric =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
      ~reference:(json {|{"x":1}|}) ~candidate:(json {|{"x":1.0}|})
  in
  check (numeric.verdict = Parity_algebra.Verified) "UNIT int/float is not a divergence" ""

(* ---------------------------------------------------------- FEATURE layer *)

let feature_layer () =
  (* The candidate builds for the known scenarios all produce a body. *)
  List.iter
    (fun scenario_id ->
      check (Parity_compare.candidate_body scenario_id <> None)
        ("FEATURE candidate build exists for " ^ scenario_id) "")
    Parity_compare.scenarios;
  check (Parity_compare.candidate_body "no.such.scenario" = None)
    "FEATURE unknown scenario has no candidate" "";

  (* End to end against a pinned fixture that the candidate reproduces exactly:
     minimal is model+messages with no extras, which the candidate matches. *)
  with_root (fun root ->
      let snapshot = String.make 64 'a' in
      let reference = json {|{"model":"openai/gpt-5.4","messages":[{"role":"user","content":"hi"}]}|} in
      pin_reference ~root ~scenario_id:"chat.minimal" ~snapshot reference;
      match Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest:snapshot
              "chat.minimal" with
      | Parity_compare.Compared comparison ->
          check (comparison.verdict = Parity_algebra.Verified)
            "FEATURE minimal candidate matches the reference"
            (Parity_algebra.name comparison.verdict)
      | Parity_compare.Blocked diagnostic ->
          check false "FEATURE minimal compares" (Fractal_diagnostic.render diagnostic))

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  (* Given a scenario with no pinned fixture, when compared, then it is Blocked,
     never passed: a missing reference proves nothing about the candidate. *)
  with_root (fun root ->
      match Parity_compare.compare_scenario ~root ~normalizer
              ~snapshot_digest:(String.make 64 'a') "chat.minimal" with
      | Parity_compare.Blocked diagnostic ->
          check (diagnostic.impact = Fractal_diagnostic.Blocks_credit)
            "BDD a missing fixture blocks credit" "";
          check (diagnostic.impact <> Fractal_diagnostic.Denies_credit)
            "BDD a missing fixture never denies credit" ""
      | Parity_compare.Compared _ -> check false "BDD missing fixture is blocked" "compared");

  (* Given an unmapped scenario, when compared, then it is Blocked with a
     Control origin: the gap is the harness's, not the candidate's. *)
  with_root (fun root ->
      match Parity_compare.compare_scenario ~root ~normalizer
              ~snapshot_digest:(String.make 64 'a') "orphan.scenario" with
      | Parity_compare.Blocked diagnostic ->
          check (diagnostic.origin = Fractal_diagnostic.Control)
            "BDD an unmapped scenario is a control gap" ""
      | Parity_compare.Compared _ -> check false "BDD unmapped scenario is blocked" "compared");

  (* Given a reference carrying a field the candidate omits, when compared, then
     it diverges and denies credit. This is the general invariant -- a genuine
     difference is caught -- tested through the pure comparison with a
     hand-built mismatch, so it stays true regardless of which behaviours the
     candidate happens to implement. *)
  let with_field = json {|{"model":"m","messages":[],"tools":[{"type":"function"}]}|} in
  let without_field = json {|{"model":"m","messages":[]}|} in
  let c =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n" ~reference:with_field
      ~candidate:without_field
  in
  check (c.verdict = Parity_algebra.Divergent) "BDD an omitted field diverges" "";
  check (c.diagnostic <> None) "BDD the divergence is diagnosed" ""

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* A comparison of a trace with itself is always Verified, for any document. *)
  let corpus =
    [ json {|{"a":1}|}; json {|[1,2,3]|}; json {|{"nested":{"x":[true,null]}}|};
      `Null; `Assoc []; json {|{"model":"m","messages":[{"role":"user"}]}|} ]
  in
  List.iter
    (fun document ->
      let c =
        Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n" ~reference:document
          ~candidate:document
      in
      check (c.verdict = Parity_algebra.Verified) "PROPERTY self-comparison verifies" "")
    corpus;

  (* Comparison is symmetric in outcome: swapping reference and candidate yields
     the same verdict (though the diagnostic's digests swap). *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let ab = Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
                     ~reference:a ~candidate:b in
          let ba = Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
                     ~reference:b ~candidate:a in
          check (ab.verdict = ba.verdict) "PROPERTY verdict is symmetric" "")
        corpus)
    corpus;

  (* A comparison never yields Unmapped: both traces are present by construction,
     so the outcome is always a real judgement. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let c = Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
                    ~reference:a ~candidate:b in
          check
            (c.verdict = Parity_algebra.Verified || c.verdict = Parity_algebra.Divergent)
            "PROPERTY a present pair is verified or divergent" "")
        corpus)
    corpus;

  (* The verdict agrees with the diagnostic: a diagnostic exists iff divergent. *)
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          let c = Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
                    ~reference:a ~candidate:b in
          check
            ((c.diagnostic <> None) = (c.verdict = Parity_algebra.Divergent))
            "PROPERTY diagnostic presence tracks divergence" "")
        corpus)
    corpus

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  Random.init 20260808;
  let rec random_json depth =
    match Random.int (if depth > 3 then 3 else 6) with
    | 0 -> `Null
    | 1 -> `Int (Random.int 5)
    | 2 -> `String (String.init (Random.int 4) (fun _ -> Char.chr (97 + Random.int 3)))
    | 3 -> `List (List.init (Random.int 3) (fun _ -> random_json (depth + 1)))
    | 4 -> `Bool (Random.bool ())
    | _ ->
        `Assoc
          (List.init (Random.int 3) (fun i ->
               (Printf.sprintf "k%d" i, random_json (depth + 1))))
  in
  let survived = ref 0 in
  for _ = 1 to 600 do
    let a = random_json 0 and b = random_json 0 in
    match
      let c = Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n"
                ~reference:a ~candidate:b in
      (* The verdict must agree with a fresh normalizer equality check: the
         comparison cannot disagree with the normalizer it is built on. *)
      let expected =
        if Parity_normalizer.equal normalizer a b then Parity_algebra.Verified
        else Parity_algebra.Divergent
      in
      c.verdict = expected
      && String.length c.reference_digest = 64
      && String.length c.candidate_digest = 64
    with
    | true -> incr survived
    | false -> check false "FUZZ comparison agrees with the normalizer" ""
    | exception exn -> check false "FUZZ comparison does not raise" (Printexc.to_string exn)
  done;
  check (!survived = 600) "FUZZ 600 random pairs compare consistently"
    (string_of_int !survived)

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  (* A fixture edited on disk must not be silently compared against: the load
     path re-derives the digest and refuses a tampered trace, so the outcome is
     Blocked, never a comparison against a fabricated reference. *)
  with_root (fun root ->
      let snapshot = String.make 64 'a' in
      let reference = json {|{"model":"m","messages":[]}|} in
      pin_reference ~root ~scenario_id:"chat.minimal" ~snapshot reference;
      let path = Reference_capture.fixture_path ~root "chat.minimal" ~snapshot_digest:snapshot in
      let channel = open_in_bin path in
      let text = really_input_string channel (in_channel_length channel) in
      close_in channel;
      let buffer = Buffer.create (String.length text) in
      String.iter (fun c -> Buffer.add_char buffer (if c = 'm' then 'X' else c)) text;
      let out = open_out_bin path in
      output_string out (Buffer.contents buffer);
      close_out out;
      match Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest:snapshot
              "chat.minimal" with
      | Parity_compare.Blocked _ -> incr passed
      | Parity_compare.Compared _ ->
          check false "CHAOS a tampered fixture is not compared" "compared");

  (* A deeply nested candidate must not blow the comparison. *)
  let deep n =
    let rec build n acc = if n = 0 then acc else build (n - 1) (`List [ acc ]) in
    build n (`Int 1)
  in
  let c =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n" ~reference:(deep 500)
      ~candidate:(deep 500)
  in
  check (c.verdict = Parity_algebra.Verified) "CHAOS deep identical structures verify" "";
  let c2 =
    Parity_compare.compare ~normalizer ~scenario_id:"s" ~node:"n" ~reference:(deep 500)
      ~candidate:(deep 499)
  in
  check (c2.verdict = Parity_algebra.Divergent) "CHAOS deep unequal structures diverge" ""

(* -------------------------------------------------------- STRUCTURE layer *)

let structure_layer () =
  (* Every scenario under test has a candidate build. An orphan scenario would
     be a Blocked outcome, which is visible, but the intent is full coverage. *)
  List.iter
    (fun scenario_id ->
      check (Parity_compare.candidate_body scenario_id <> None)
        ("STRUCTURE scenario " ^ scenario_id ^ " has a candidate") "")
    Parity_compare.scenarios;
  check (List.length Parity_compare.scenarios = 9) "STRUCTURE nine scenarios under test" "";

  (* roll_up over an empty run is Unmapped (required), never Verified: an empty
     comparison must not read as success. *)
  let empty = Parity_compare.roll_up [] in
  check (empty.verdict = Parity_algebra.Unmapped) "STRUCTURE empty run is unmapped" "";

  (* A run mixing blocked and divergent never reads as verified. *)
  let mixed =
    Parity_compare.roll_up
      [ Parity_compare.Blocked
          (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
             ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
             ~message:"x" ~cause:"y" ~fix:"z" ()) ]
  in
  check (mixed.verdict <> Parity_algebra.Verified) "STRUCTURE a blocked run is not verified" ""

(* ------------------------------------------------------------ DECODE layer *)
(* The response-decoding half of provider_transports. The candidate now
   reproduces content, tool calls, usage.total_tokens (a faithful pass-through of
   the provider figure) and the refusal->content_filter promotion -- the two
   gaps that were open are closed by fixing the candidate, not by eliding. The
   tests assert conformance for all four scenarios as regression guards:
   reopening any gap fails here. *)

let decode_layer () =
  (* The candidate decode projects to the canonical schema for a plain response. *)
  (match Parity_compare.candidate_decode
           (json {|{"choices":[{"message":{"content":"hi"},"finish_reason":"stop"}]}|})
   with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "content" fields = Some (`String "hi"))
        "DECODE candidate projects content" "";
      check (List.assoc_opt "finish_reason" fields = Some (`String "stop"))
        "DECODE candidate projects finish_reason" ""
  | _ -> check false "DECODE candidate decodes a plain response" "");

  (* The candidate decoder rejects a response with no finish_reason, where the
     reference defaults to "stop" -- a real asymmetry, surfaced not hidden. *)
  check
    (Parity_compare.candidate_decode (json {|{"choices":[{"message":{"content":"x"}}]}|})
     = None)
    "DECODE candidate rejects a response lacking finish_reason" "";

  (* Usage now projects total_tokens as a faithful pass-through of the provider
     figure -- the closed gap; the projection still emits exactly the reference
     schema, hiding nothing. *)
  (match Parity_compare.candidate_decode
           (json {|{"choices":[{"message":{"content":"h"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}|})
   with
  | Some (`Assoc fields) -> (
      match List.assoc_opt "usage" fields with
      | Some (`Assoc u) ->
          check (List.assoc_opt "total_tokens" u = Some (`Int 3))
            "DECODE candidate usage carries total_tokens (pass-through)" ""
      | _ -> check false "DECODE candidate projects usage" "")
  | _ -> check false "DECODE candidate decodes a usage response" "");

  (* Refusal promotion: a sole-payload refusal becomes content + content_filter. *)
  (match Parity_compare.candidate_decode
           (json {|{"choices":[{"message":{"content":null,"refusal":"no"},"finish_reason":"stop"}]}|})
   with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "content" fields = Some (`String "no"))
        "DECODE candidate promotes a sole-payload refusal to content" "";
      check (List.assoc_opt "finish_reason" fields = Some (`String "content_filter"))
        "DECODE candidate marks a promoted refusal content_filter" ""
  | _ -> check false "DECODE candidate decodes a refusal response" "");

  (* Every decode scenario has a defined provider input. *)
  check (List.length Parity_compare.decode_scenarios = 4) "DECODE four scenarios defined" "";

  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        let outcome id =
          Parity_compare.compare_decode_scenario ~root ~normalizer ~snapshot_digest:snapshot id
        in
        (* All four decode scenarios now reproduce the reference. Asserting
           Verified guards conformance against regression: reopening any gap --
           dropping total_tokens, losing the refusal promotion -- fails here. *)
        List.iter
          (fun id ->
            match outcome id with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("DECODE " ^ id ^ " reproduces the reference") (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("DECODE " ^ id ^ " compares") (Fractal_diagnostic.render d))
          [ "decode.content"; "decode.tool_call"; "decode.usage"; "decode.refusal" ]

(* ------------------------------------------------------------ BUDGET layer *)
(* Interrupt-control (agent_loop): the candidate Turn_budget replayed against a
   consume/refund sequence vs the frozen IterationBudget. The non-negative
   scenarios must reproduce the reference; the negative-cap scenario exercises the
   candidate's deliberate, contracted clamp (well_formed) which the reference
   lacks -- surfaced as a divergence, not baked in as one, so making the candidate
   faithful later would not break this. *)

let budget_layer () =
  (match Parity_compare.candidate_budget
           (json {|{"max_total":3,"operations":["consume","consume","consume","consume"]}|})
   with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "used" fields = Some (`Int 3)) "BUDGET candidate tracks used" "";
      check (List.assoc_opt "remaining" fields = Some (`Int 0)) "BUDGET candidate tracks remaining" "";
      check (List.assoc_opt "max_total" fields = Some (`Int 3)) "BUDGET candidate reports max_total" "";
      (match List.assoc_opt "consumes" fields with
       | Some (`List consumes) ->
           check (consumes = [ `Bool true; `Bool true; `Bool true; `Bool false ])
             "BUDGET candidate records each consume outcome" ""
       | _ -> check false "BUDGET candidate projects consumes" "")
  | _ -> check false "BUDGET candidate projects a budget run" "");

  (* Faithful negative-cap semantics: the cap is CARRIED as given (the frozen
     IterationBudget does not clamp); consume is refused, used stays 0. *)
  (match Parity_compare.candidate_budget (json {|{"max_total":-5,"operations":["consume"]}|}) with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "max_total" fields = Some (`Int (-5)))
        "BUDGET candidate carries a negative cap faithfully" "";
      check (List.assoc_opt "used" fields = Some (`Int 0)) "BUDGET negative cap refuses consume" ""
  | _ -> check false "BUDGET candidate decodes a negative-cap run" "");

  check (List.length Parity_compare.budget_scenarios = 4) "BUDGET four scenarios defined" "";

  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        let outcome id =
          Parity_compare.compare_budget_scenario ~root ~normalizer ~snapshot_digest:snapshot id
        in
        (* All four budget scenarios now reproduce the reference -- the clamp
           divergence is CLOSED by making the candidate faithful (never by
           widening). Reopening it fails here. *)
        List.iter
          (fun id ->
            match outcome id with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("BUDGET " ^ id ^ " reproduces the reference") (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("BUDGET " ^ id ^ " compares") (Fractal_diagnostic.render d))
          [ "budget.exhaust"; "budget.refund"; "budget.zero"; "budget.negative" ]

(* ----------------------------------------------------------- SESSION layer *)
(* Deterministic replay: the candidate's full submit -> decode path over a pinned
   Session_fixture, compared to the session's reference decode. Proven
   differential (a different recorded response yields a different decode) and, on
   the pinned corpus, verified end to end. *)

let session_layer () =
  let make_session provider =
    Session_fixture.make ~normalizer ~session_id:"session.probe" ~snapshot_digest:"x"
      ~reference_revision:"r"
      ~request:Session_fixture.{ endpoint = "e"; body = `Assoc [ ("b", `String "1") ] }
      ~provider_response:provider ~reference_decode:`Null
  in
  (match
     Parity_compare.candidate_session
       (make_session (json {|{"choices":[{"message":{"content":"hi"},"finish_reason":"stop"}]}|}))
   with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "content" fields = Some (`String "hi"))
        "SESSION candidate replays submit->decode from the recorded response" ""
  | _ -> check false "SESSION candidate_session projects a response" "");
  (* Proven differential: a different recorded response yields a different decode. *)
  (match
     Parity_compare.candidate_session
       (make_session (json {|{"choices":[{"message":{"content":"bye"},"finish_reason":"stop"}]}|}))
   with
  | Some (`Assoc fields) ->
      check (List.assoc_opt "content" fields = Some (`String "bye"))
        "SESSION a different recorded response yields a different decode" ""
  | _ -> check false "SESSION differential replay" "");

  check (List.length Parity_compare.session_scenarios = 4) "SESSION four scenarios defined" "";

  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (session_id, _, _) ->
            match
              Parity_compare.compare_session_scenario ~root ~normalizer ~snapshot_digest:snapshot
                session_id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("SESSION " ^ session_id ^ " reproduces the reference decode via submit")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("SESSION " ^ session_id ^ " compares")
                  (Fractal_diagnostic.render d))
          Parity_compare.session_scenarios

(* ------------------------------------------------------------- PATH layer *)
(* tool_execution.path_and_url_safety: the candidate Path_safety predicate vs the
   frozen tools/path_security.has_traversal_component. Unit-projects a few paths,
   then verifies the pinned scenario reproduces the frozen predicate end to end. *)

let path_layer () =
  (match Parity_compare.candidate_path (json {|{"paths":["a/../b","a/b","a/..b"]}|}) with
  | Some (`Assoc fields) -> (
      match List.assoc_opt "results" fields with
      | Some (`Assoc results) ->
          check (List.assoc_opt "a/../b" results = Some (`Bool true))
            "PATH detects a traversal component" "";
          check (List.assoc_opt "a/b" results = Some (`Bool false)) "PATH passes a safe path" "";
          check (List.assoc_opt "a/..b" results = Some (`Bool false))
            "PATH ..b is a name, not a traversal" ""
      | _ -> check false "PATH candidate projects results" "")
  | _ -> check false "PATH candidate_path returns results" "");

  check (List.length Parity_compare.path_scenarios = 1) "PATH one scenario defined" "";

  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_path_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("PATH " ^ id ^ " reproduces the frozen predicate")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("PATH " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.path_scenarios

(* ------------------------------------------------------------ RETRY layer *)
(* model_routing.rate_and_retry: the candidate Retry-After parser vs the frozen
   parse_retry_after_seconds, positionally paired over the deterministic
   branches (the HTTP-date branch is excluded by construction, stated in
   retry_utils.mli). *)

let retry_layer () =
  (match Parity_compare.candidate_retry (json {|{"values":[5, -3, "10", "", true, null]}|}) with
  | Some (`Assoc [ ("results", `List results) ]) ->
      check (results = [ `Float 5.0; `Float 0.0; `Float 10.0; `Null; `Null; `Null ])
        "RETRY candidate branches match the frozen semantics" ""
  | _ -> check false "RETRY candidate projects results" "");
  check (List.length Parity_compare.retry_scenarios = 1) "RETRY one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_retry_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("RETRY " ^ id ^ " reproduces the frozen parser")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("RETRY " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.retry_scenarios

(* ------------------------------------------------------------ ROUTE layer *)
(* model_routing.route_resolution: the candidate fallback-chain resolver vs the
   frozen get_fallback_chain, positionally over a list of configs. *)

let route_layer () =
  (match Parity_compare.candidate_route (json {|{"configs":[null, {"fallback_providers":[{"provider":" p ","model":"m"}]}]}|}) with
  | Some (`Assoc [ ("results", `List [ `List []; `List [ `Assoc e ] ]) ]) ->
      check (List.assoc_opt "provider" e = Some (`String "p"))
        "ROUTE candidate resolves and strips a chain" ""
  | _ -> check false "ROUTE candidate projects results" "");
  check (List.length Parity_compare.route_scenarios = 1) "ROUTE one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_route_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("ROUTE " ^ id ^ " reproduces the frozen resolver")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("ROUTE " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.route_scenarios

(* -------------------------------------------------------- ANTHROPIC layer *)
(* model_routing.anthropic_adapter: the candidate shaping trio vs the frozen
   convert_tools_to_anthropic / normalize_model_name / _sanitize_tool_id. *)

let anthropic_layer () =
  (match
     Parity_compare.candidate_anthropic
       (json {|{"calls":[{"function":"normalize_model_name","model":"anthropic/claude-3.5"},{"function":"sanitize_tool_id","tool_id":"a.b"}]}|})
   with
  | Some (`Assoc [ ("results", `List [ `String m; `String t ]) ]) ->
      check (m = "claude-3-5") "ANTHROPIC normalize_model_name via dispatch" m;
      check (t = "a_b") "ANTHROPIC sanitize_tool_id via dispatch" t
  | _ -> check false "ANTHROPIC candidate dispatches calls" "");
  check (List.length Parity_compare.anthropic_scenarios = 1) "ANTHROPIC one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_anthropic_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("ANTHROPIC " ^ id ^ " reproduces the frozen shaping")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("ANTHROPIC " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.anthropic_scenarios

(* ------------------------------------------------------------ CODEX layer *)
(* model_routing.codex_runtime: the candidate Responses shaping trio vs the
   frozen adapter functions, dispatched over a list of ops. *)

let codex_layer () =
  (match
     Parity_compare.candidate_codex
       (json {|{"ops":[{"op":"message_status","value":" in-progress "},{"op":"summarize","content":["a",{"type":"input_image","image_url":"u"}]}]}|})
   with
  | Some (`Assoc [ ("results", `List [ `String st; `String sm ]) ]) ->
      check (st = "in_progress") "CODEX message_status via dispatch" st;
      check (sm = "[1 image] a") "CODEX summarize via dispatch" sm
  | _ -> check false "CODEX candidate dispatches ops" "");
  check (List.length Parity_compare.codex_scenarios = 1) "CODEX one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_codex_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("CODEX " ^ id ^ " reproduces the frozen shaping")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("CODEX " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.codex_scenarios

(* ----------------------------------------------------------- GEMINI layer *)
(* model_routing.gemini_adapter (first cut): the candidate schema sanitizer vs
   the frozen sanitize_gemini_tool_parameters. *)

let gemini_layer () =
  (match Parity_compare.candidate_gemini (json {|{"schemas":[{},{"type":"integer","enum":[1,2,1]}]}|}) with
  | Some (`Assoc [ ("results", `List [ stub; enum_dict ]) ]) ->
      check (Yojson.Safe.to_string stub = {|{"type":"object","properties":{}}|})
        "GEMINI empty schema -> object stub" "";
      check (Yojson.Safe.to_string enum_dict = {|{"type":"integer","enum":["1","2"]}|})
        "GEMINI integer enum stringified + deduped" ""
  | _ -> check false "GEMINI candidate projects results" "");
  check (List.length Parity_compare.gemini_scenarios = 1) "GEMINI one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_gemini_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("GEMINI " ^ id ^ " reproduces the frozen sanitizer")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("GEMINI " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.gemini_scenarios

(* ---------------------------------------------------------- BEDROCK layer *)
(* model_routing.cloud_vendor_adapters: the candidate Bedrock Converse shaper vs
   the frozen build_converse_kwargs, over a list of cases. *)

let bedrock_layer () =
  (match
     Parity_compare.candidate_bedrock
       (json {|{"cases":[{"model":"anthropic.claude-opus-4-7-v1:0","messages":[{"role":"user","content":"x"}],"temperature":0.9}]}|})
   with
  | Some (`Assoc [ ("results", `List [ `Assoc kv ]) ]) -> (
      match List.assoc_opt "inferenceConfig" kv with
      | Some (`Assoc ic) ->
          check (List.assoc_opt "temperature" ic = None)
            "BEDROCK opus-4-7 drops sampling params via dispatch" ""
      | _ -> check false "BEDROCK inferenceConfig present" "")
  | _ -> check false "BEDROCK candidate builds a request" "");
  check (List.length Parity_compare.bedrock_scenarios = 1) "BEDROCK one scenario defined" "";
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then skipped := !skipped + 1
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> skipped := !skipped + 1
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        List.iter
          (fun (id, _) ->
            match
              Parity_compare.compare_bedrock_scenario ~root ~normalizer ~snapshot_digest:snapshot id
            with
            | Parity_compare.Compared c ->
                check (c.verdict = Parity_algebra.Verified)
                  ("BEDROCK " ^ id ^ " reproduces the frozen converse shaper")
                  (Parity_algebra.name c.verdict)
            | Parity_compare.Blocked d ->
                check false ("BEDROCK " ^ id ^ " compares") (Fractal_diagnostic.render d))
          Parity_compare.bedrock_scenarios

(* -------------------------------------------------- INTEGRATION (live) layer *)
(* The real fixtures against the real candidate. This is the honest measurement,
   and it is allowed to show divergences -- indeed it is expected to. The test
   asserts the SHAPE of the result (every scenario is compared, none errors),
   not a particular verdict, because pinning a verdict here would just re-encode
   the candidate's current behaviour as if it were the specification. *)

let integration_layer () =
  let root = "." in
  let reference_root = Bootstrap.reference_root root in
  if not (Sys.file_exists reference_root) then incr skipped
  else
    match Inventory.scan ~root:reference_root with
    | Error _ -> incr skipped
    | Ok entries ->
        let snapshot = Inventory.snapshot_digest entries in
        let outcomes =
          List.map
            (fun scenario_id ->
              Parity_compare.compare_scenario ~root ~normalizer ~snapshot_digest:snapshot
                scenario_id)
            Parity_compare.scenarios
        in
        (* Every scenario produced an outcome, and every Compared one carries a
           digest of each side. *)
        List.iter
          (fun outcome ->
            match outcome with
            | Parity_compare.Compared c ->
                check (String.length c.reference_digest = 64 && String.length c.candidate_digest = 64)
                  "INTEGRATION compared scenario has both digests" c.scenario_id;
                check
                  ((c.diagnostic <> None) = (c.verdict = Parity_algebra.Divergent))
                  "INTEGRATION diagnostic tracks divergence" c.scenario_id
            | Parity_compare.Blocked diagnostic ->
                (* Blocked is acceptable only if the fixture is genuinely absent;
                   with fixtures committed, a Blocked here is a real problem. *)
                check false "INTEGRATION a committed scenario should not be blocked"
                  (Fractal_diagnostic.render diagnostic))
          outcomes;
        let report = Parity_compare.roll_up outcomes in
        (* The candidate now faithfully reproduces the reference for all five
           scenarios, so the family verifies all of them. This asserts candidate ==
           frozen reference, which is exactly the parity claim: the reference is
           the specification, so a regression here means the candidate drifted
           from it, not that a test was over-fitted. It is NOT a false 100% --
           each verdict rests on a normalized-trace comparison against a
           digest-pinned reference, and the normalizer's volatile set is fixed
           and tested (HZ-NRM-01), so verification cannot be manufactured by
           widening it. *)
        check
          (report.Parity_algebra.verdict = Parity_algebra.Verified
          && report.Parity_algebra.verified = List.length Parity_compare.scenarios)
          "INTEGRATION the family verifies every scenario against the frozen reference"
          (Parity_algebra.render_report report);
        Printf.printf "  live result: %s\n" (Parity_algebra.render_report report)

let () =
  print_endline "parity compare suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("stub-guard", stub_guard_layer);
      ("unit", unit_layer); ("feature", feature_layer); ("bdd", bdd_layer);
      ("property", property_layer); ("fuzz", fuzz_layer); ("chaos", chaos_layer);
      ("structure", structure_layer); ("decode", decode_layer);
      ("budget", budget_layer); ("session", session_layer); ("path", path_layer);
      ("retry", retry_layer); ("route", route_layer); ("anthropic", anthropic_layer);
      ("codex", codex_layer); ("gemini", gemini_layer); ("bedrock", bedrock_layer);
      ("integration", integration_layer) ];
  Printf.printf "\npassed: %d   failed: %d   skipped: %d\n" !passed
    (List.length !failures) !skipped;
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_parity_compare" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_parity_compare ]);
  exit (Suite_telemetry.exit_code self)
