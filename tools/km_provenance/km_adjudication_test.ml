(* Independent falsification tests for Km_adjudication.Adjudicator.
   Candidate-only. These tests do not constitute full-task acceptance. *)
open Km_adjudication
module J = Yojson.Safe
module U = Yojson.Safe.Util

let total = ref 0
let failed = ref 0

let check name cond =
  incr total;
  if cond then Printf.printf "PASS %03d %s\n%!" !total name
  else begin incr failed; Printf.printf "FAIL %03d %s\n%!" !total name end

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  m = 0 || go 0

let adj = Adjudicator.adjudicate
let is_err s = match adj s with Error _ -> true | Ok _ -> false
let err_has s sub = match adj s with Error m -> contains m sub | Ok _ -> false
let ok_json s = match adj s with Ok j -> j | Error m -> failwith ("expected Ok: " ^ m)
let is_ok s = match adj s with Ok _ -> true | Error _ -> false

let c40 = String.make 40 'a'
let s64 = String.make 64 'b'
let q s = "\"" ^ s ^ "\""

let ev_json ?(kind = "code_present") ?(loc = "src/x.ml") ?(cand = "null")
    ?(sha = "null") ?(tick = "null") ?(utc = "null") () =
  Printf.sprintf
    {|{"kind":"%s","locator":"%s","candidate_commit":%s,"source_map_sha256":%s,"tick_us":%s,"utc_us":%s}|}
    kind loc cand sha tick utc

let claim_json ?(extra = "") ev adr evs =
  Printf.sprintf {|{"ev":%d,"adr":%d,"evidence":[%s]%s}|} ev adr
    (String.concat "," evs) extra

let report ?(extra = "") ?(cand = q c40) ?(sha = q s64) claims =
  Printf.sprintf {|{"candidate_commit":%s,"source_map_sha256":%s,"claims":[%s]%s}|}
    cand sha (String.concat "," claims) extra

let std_claims ?(f = fun ev -> claim_json ev (ev - 23) []) () =
  List.init 16 (fun i -> f (94 + i))

let valid () = report (std_claims ())
let with_claim ev raw = report (std_claims ~f:(fun e -> if e = ev then raw else claim_json e (e - 23) []) ())
let with_ev ev evs = with_claim ev (claim_json ev (ev - 23) evs)

let claims_of j = U.to_list (U.member "claims" j)
let findings_of c = List.map U.to_string (U.to_list (U.member "advisory_findings" c))
let claim_at j ev = List.find (fun c -> U.to_int (U.member "ev" c) = ev) (claims_of j)
let ev_findings ev evs = findings_of (claim_at (ok_json (with_ev ev evs)) ev)

let read_file p =
  let ic = open_in_bin p in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let () =
  (* ---- positive baseline ---- *)
  let v = valid () in
  check "valid 16-claim fixture accepted" (is_ok v);
  let j = ok_json v in
  check "schema id" (U.to_string (U.member "schema" j) = "uos.provenance-adjudication.v1");
  check "authority is REPORT_ONLY_CALLER_ASSERTIONS" (U.to_string (U.member "authority" j) = "REPORT_ONLY_CALLER_ASSERTIONS");
  check "sovereignty_authority false" (U.member "sovereignty_authority" j = `Bool false);
  check "protected EV93 ceiling: admitted_ev_ceiling = 93" (U.member "admitted_ev_ceiling" j = `Int 93);
  check "application_admitted false" (U.member "application_admitted" j = `Bool false);
  check "system_admitted false" (U.member "system_admitted" j = `Bool false);
  check "freshness UNVERIFIED" (U.member "freshness" j = `String "UNVERIFIED");
  check "readback_verified false" (U.member "readback_verified" j = `Bool false);
  check "candidate commit echoed as asserted" (U.member "candidate_commit_asserted" j = `String c40);
  check "source map sha echoed as asserted" (U.member "source_map_sha256_asserted" j = `String s64);
  check "output has exactly the expected top-level keys"
    (List.sort compare (List.map fst (U.to_assoc j))
     = List.sort compare ["schema";"authority";"sovereignty_authority";"admitted_ev_ceiling";
                          "application_admitted";"system_admitted";"freshness";"readback_verified";
                          "candidate_commit_asserted";"source_map_sha256_asserted";"claims"]);
  check "16 output claims" (List.length (claims_of j) = 16);
  check "output claims ordered EV94..109 with ADR=EV-23"
    (List.mapi (fun i c -> U.to_int (U.member "ev" c) = 94 + i && U.to_int (U.member "adr" c) = 71 + i) (claims_of j)
     |> List.for_all Fun.id);
  check "every claim NOT_ADMITTED"
    (List.for_all (fun c -> U.member "historical_status" c = `String "NOT_ADMITTED") (claims_of j));
  check "EV93 absent from output claims" (not (List.exists (fun c -> U.to_int (U.member "ev" c) <= 93) (claims_of j)));
  check "every claim: no secret bytes read/hashed"
    (List.for_all (fun c -> U.member "secret_bytes_read" c = `Bool false && U.member "secret_bytes_hashed" c = `Bool false) (claims_of j));
  check "every claim: evidence_status caller_assertion_unverified, forensic pending"
    (List.for_all (fun c -> U.member "evidence_status" c = `String "caller_assertion_unverified"
                            && U.member "forensic_state" c = `String "pending_forensic_analysis") (claims_of j));
  check "per-claim output key set exact"
    (List.for_all (fun c -> List.sort compare (List.map fst (U.to_assoc c))
        = List.sort compare ["ev";"adr";"historical_status";"recommendation";"forensic_state";
                             "evidence_status";"advisory_findings";"secret_bytes_read";"secret_bytes_hashed"]) (claims_of j));
  check "empty-evidence claims have no findings" (List.for_all (fun c -> findings_of c = []) (claims_of j));
  (* Observed behaviour: the core never emits a non-null recommendation. Spec-gap flagged in report. *)
  check "OBSERVED: recommendation is null for every claim (core emits no ordinary recommendation)"
    (List.for_all (fun c -> U.member "recommendation" c = `Null) (claims_of j));
  check "deterministic: same input gives equal output" (J.equal (ok_json v) (ok_json v));
  let ordinary = with_ev 100 [ev_json ~kind:"code_present" (); ev_json ~kind:"superseded" ()] in
  check "ordinary code_present/superseded evidence accepted, admission flags stay false"
    (let o = ok_json ordinary in
     U.member "application_admitted" o = `Bool false && U.member "system_admitted" o = `Bool false
     && U.member "admitted_ev_ceiling" o = `Int 93);
  check "ordinary kinds yield unverified findings"
    (ev_findings 100 [ev_json ~kind:"code_present" (); ev_json ~kind:"superseded" ()]
     = ["code_present assertion unverified"; "superseded assertion unverified"]);

  (* ---- unknown keys at three levels ---- *)
  check "unknown key at root refused" (err_has (report ~extra:{|,"x":1|} (std_claims ())) "unknown");
  check "unknown key in claim refused"
    (err_has (with_claim 94 (claim_json ~extra:{|,"x":1|} 94 71 [])) "unknown");
  check "unknown key in evidence refused"
    (err_has (with_ev 94 [{|{"kind":"code_present","locator":"a","candidate_commit":null,"source_map_sha256":null,"tick_us":null,"utc_us":null,"x":1}|}]) "unknown");
  (* missing allowed keys *)
  check "missing root key refused"
    (is_err (Printf.sprintf {|{"candidate_commit":"%s","claims":[%s]}|} c40 (String.concat "," (std_claims ()))));
  check "missing claim key (evidence) refused" (is_err (with_claim 94 {|{"ev":94,"adr":71}|}));
  check "missing evidence key (tick_us) refused"
    (is_err (with_ev 94 [{|{"kind":"code_present","locator":"a","candidate_commit":null,"source_map_sha256":null,"utc_us":null}|}]));
  (* repeated allowed keys *)
  check "repeated root key refused"
    (err_has (report ~extra:(Printf.sprintf {|,"candidate_commit":"%s"|} c40) (std_claims ())) "duplicate");
  check "repeated claim key refused"
    (err_has (with_claim 94 (claim_json ~extra:{|,"ev":94|} 94 71 [])) "duplicate");
  check "repeated evidence key refused"
    (err_has (with_ev 94 [{|{"kind":"code_present","kind":"fabrication","locator":"a","candidate_commit":null,"source_map_sha256":null,"tick_us":null,"utc_us":null}|}]) "duplicate");

  (* ---- malformed JSON / caps ---- *)
  List.iter (fun (n, s) -> check ("malformed/non-object input refused: " ^ n) (is_err s))
    ["empty", ""; "garbage", "not json"; "truncated", String.sub v 0 (String.length v - 1);
     "trailing junk", v ^ " x"; "array top", "[]"; "null top", "null"; "string top", "\"a\"";
     "unterminated string", {|{"a":"|}; "unbalanced close", "}"];
  check "nesting 65 refused with nesting message" (err_has (String.make 65 '[' ^ String.make 65 ']') "nesting");
  check "nesting 64 passes depth cap (fails later as non-object)"
    (match adj (String.make 64 '[' ^ String.make 64 ']') with Error m -> not (contains m "nesting exceeds") | Ok _ -> false);
  check "braces inside strings do not count toward nesting"
    (is_ok (with_ev 94 [ev_json ~loc:(String.make 100 '[') ()]));
  check "escaped quote in string handled by nesting scanner"
    (is_ok (with_ev 94 [ev_json ~loc:{|a\"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[|} ()]));
  let pad n = String.make n ' ' in
  let at_cap = v ^ pad (262144 - String.length v) in
  let over_cap = v ^ pad (262145 - String.length v) in
  check "input of exactly 262144 bytes accepted" (String.length at_cap = 262144 && is_ok at_cap);
  check "input of 262145 bytes refused with byte-cap message" (String.length over_cap = 262145 && err_has over_cap "262144");

  (* ---- claim set ---- *)
  check "15 claims refused"
    (is_err (report (List.init 15 (fun i -> claim_json (94 + i) (71 + i) []))));
  check "17 claims refused"
    (is_err (report (std_claims () @ [claim_json 94 71 []])));
  check "zero claims refused" (is_err (report []));
  check "duplicate EV refused (EV95 replaced by EV94)"
    (err_has (with_claim 95 (claim_json 94 71 [])) "duplicate EV");
  check "duplicate ADR with consistent offset impossible; ADR dup via mismatch refused"
    (is_err (with_claim 95 (claim_json 95 71 [])));
  check "EV 93 refused (range)" (err_has (with_claim 94 (claim_json 93 70 [])) "range");
  check "EV 110 refused (range)" (err_has (with_claim 109 (claim_json 110 87 [])) "range");
  check "ADR 70 refused" (is_err (with_claim 94 (claim_json 94 70 [])));
  check "ADR 87 refused" (is_err (with_claim 109 (claim_json 109 87 [])));
  check "ADR mapping mismatch (EV94->ADR72) refused" (err_has (with_claim 94 (claim_json 94 72 [])) "ev-23");
  check "ADR swap pair refused (EV94->ADR72, EV95->ADR71)"
    (is_err (report (std_claims ~f:(fun e -> if e = 94 then claim_json 94 72 [] else if e = 95 then claim_json 95 71 [] else claim_json e (e - 23) []) ())));
  check "EV as string refused" (is_err (with_claim 94 {|{"ev":"94","adr":71,"evidence":[]}|}));
  check "EV as float refused" (is_err (with_claim 94 {|{"ev":94.0,"adr":71,"evidence":[]}|}));
  check "EV as huge int refused" (is_err (with_claim 94 {|{"ev":99999999999999999999,"adr":71,"evidence":[]}|}));
  check "claim not an object refused" (is_err (with_claim 94 "1"));
  check "claims not a list refused"
    (is_err (Printf.sprintf {|{"candidate_commit":"%s","source_map_sha256":"%s","claims":{}}|} c40 s64));
  check "evidence not a list refused" (is_err (with_claim 94 {|{"ev":94,"adr":71,"evidence":{}}|}));
  check "evidence element not an object refused" (is_err (with_ev 94 ["1"]));
  check "16 evidence items accepted" (is_ok (with_ev 94 (List.init 16 (fun _ -> ev_json ()))));
  check "17 evidence items refused" (is_err (with_ev 94 (List.init 17 (fun _ -> ev_json ()))));

  (* ---- top-level / evidence value validation ---- *)
  check "candidate_commit 39 hex refused" (is_err (report ~cand:(q (String.make 39 'a')) (std_claims ())));
  check "candidate_commit uppercase hex refused" (is_err (report ~cand:(q (String.make 40 'A')) (std_claims ())));
  check "candidate_commit non-hex refused" (is_err (report ~cand:(q (String.make 40 'g')) (std_claims ())));
  check "candidate_commit null refused at root" (is_err (report ~cand:"null" (std_claims ())));
  check "source_map_sha256 63 hex refused" (is_err (report ~sha:(q (String.make 63 'b')) (std_claims ())));
  check "source_map_sha256 uppercase refused" (is_err (report ~sha:(q (String.make 64 'B')) (std_claims ())));
  check "evidence bad candidate_commit refused" (is_err (with_ev 94 [ev_json ~cand:(q "abc") ()]));
  check "evidence bad source_map_sha256 refused" (is_err (with_ev 94 [ev_json ~sha:(q "abc") ()]));
  check "evidence candidate_commit as number refused" (is_err (with_ev 94 [ev_json ~cand:"5" ()]));
  check "invalid evidence kind refused" (is_err (with_ev 94 [ev_json ~kind:"sovereign_approved" ()]));
  check "empty locator refused" (is_err (with_ev 94 [ev_json ~loc:"" ()]));
  check "locator 1024 bytes accepted" (is_ok (with_ev 94 [ev_json ~loc:(String.make 1024 'x') ()]));
  check "locator 1025 bytes refused" (is_err (with_ev 94 [ev_json ~loc:(String.make 1025 'x') ()]));
  check "locator with NUL (\\u0000) refused" (err_has (with_ev 94 [ev_json ~loc:{|a\u0000b|} ()]) "NUL");

  (* ---- clocks ---- *)
  let bad_clocks = ["\"\""; "\"01\""; "\"00\""; "\"-1\""; "\"1.5\""; "\"1e3\""; "\" 1\""; "\"1 \""; "\"+1\"";
                    "\"0x1\""; "\"12345678901234567\""; "\"\xd9\xa1\""; "5"; "true"] in
  List.iter (fun c ->
    check ("malformed tick_us refused: " ^ String.escaped c) (is_err (with_ev 94 [ev_json ~tick:c ()]));
    check ("malformed utc_us refused: " ^ String.escaped c) (is_err (with_ev 94 [ev_json ~utc:c ()]))) bad_clocks;
  List.iter (fun c ->
    check ("canonical clock accepted (tick): " ^ c) (is_ok (with_ev 94 [ev_json ~tick:(q c) ()])))
    ["0"; "7"; "10"; "1234567890123456"];
  check "both stamps equal -> forged_clock finding"
    (ev_findings 94 [ev_json ~tick:(q "100") ~utc:(q "100") ()]
     = ["forged_clock_evidence: tick_us equals utc_us"; "code_present assertion unverified"]);
  check "both stamps present and different -> no clock finding"
    (ev_findings 94 [ev_json ~tick:(q "100") ~utc:(q "101") ()] = ["code_present assertion unverified"]);
  check "only tick present -> no clock finding"
    (ev_findings 94 [ev_json ~tick:(q "100") ()] = ["code_present assertion unverified"]);
  check "only utc present -> no clock finding"
    (ev_findings 94 [ev_json ~utc:(q "100") ()] = ["code_present assertion unverified"]);
  check "both stamps omitted (null) -> no clock finding"
    (ev_findings 94 [ev_json ()] = ["code_present assertion unverified"]);
  check "both stamps '0' equal -> forged_clock finding"
    (List.mem "forged_clock_evidence: tick_us equals utc_us" (ev_findings 94 [ev_json ~tick:(q "0") ~utc:(q "0") ()]));

  (* ---- per-claim findings isolation ---- *)
  let other = String.make 40 'c' in
  let evs = [ev_json ~kind:"fabrication" ~cand:(q other) ~sha:(q (String.make 64 'd')) ~tick:(q "5") ~utc:(q "5") ()] in
  let j2 = ok_json (with_ev 100 evs) in
  check "findings for the targeted claim are exact and ordered"
    (findings_of (claim_at j2 100)
     = ["evidence candidate_commit differs from top-level candidate_commit";
        "evidence source_map_sha256 differs from top-level source_map_sha256";
        "forged_clock_evidence: tick_us equals utc_us";
        "caller asserts fabrication (cannot prove)"]);
  check "other 15 claims have no findings (isolation)"
    (List.for_all (fun c -> U.to_int (U.member "ev" c) = 100 || findings_of c = []) (claims_of j2));
  check "matching evidence commit/sha produce no difference findings"
    (ev_findings 94 [ev_json ~cand:(q c40) ~sha:(q s64) ()] = ["code_present assertion unverified"]);
  let j3 = ok_json (report (std_claims ~f:(fun e ->
      if e = 94 then claim_json 94 71 [ev_json ~kind:"fabrication" ()]
      else if e = 109 then claim_json 109 86 [ev_json ~kind:"superseded" ()]
      else claim_json e (e - 23) []) ())) in
  check "two claims with evidence keep separate findings"
    (findings_of (claim_at j3 94) = ["caller asserts fabrication (cannot prove)"]
     && findings_of (claim_at j3 109) = ["superseded assertion unverified"]
     && List.for_all (fun c -> let e = U.to_int (U.member "ev" c) in e = 94 || e = 109 || findings_of c = []) (claims_of j3));
  check "findings do not change recommendation or admission"
    (U.member "recommendation" (claim_at j2 100) = `Null && U.member "historical_status" (claim_at j2 100) = `String "NOT_ADMITTED");

  (* ---- fake sovereign-review / admission strings ---- *)
  List.iter (fun (k, vv) ->
    check ("fake root key refused: " ^ k) (is_err (report ~extra:(Printf.sprintf {|,"%s":%s|} k vv) (std_claims ()))))
    ["sovereign_review", {|"APPROVED"|}; "system_admitted", "true"; "application_admitted", "true";
     "admitted_ev_ceiling", "109"; "sovereignty_authority", "true"; "admission", {|"ADMITTED"|}];
  List.iter (fun k ->
    check ("fake claim key refused: " ^ k)
      (is_err (with_claim 94 (claim_json ~extra:(Printf.sprintf {|,"%s":"ADMITTED"|} k) 94 71 []))))
    ["recommendation"; "historical_status"; "sovereign_review"; "admitted"];
  check "fake review string as evidence kind refused" (is_err (with_ev 94 [ev_json ~kind:"SOVEREIGN_REVIEW_PASSED" ()]));
  check "fake review string in candidate_commit refused" (is_err (report ~cand:(q "SOVEREIGN_REVIEW_PASSED") (std_claims ())));
  check "fake review string in tick_us refused" (is_err (with_ev 94 [ev_json ~tick:(q "SOVEREIGN_REVIEW_PASSED") ()]));
  let fake_loc = "SOVEREIGN_REVIEW_PASSED system_admitted=true ADMITTED EV109" in
  let fake_out = adj (with_ev 94 [ev_json ~loc:fake_loc ()]) in
  check "fake admission text as opaque locator does not grant admission"
    (match fake_out with
     | Ok o -> U.member "system_admitted" o = `Bool false && U.member "application_admitted" o = `Bool false
               && U.member "admitted_ev_ceiling" o = `Int 93
               && List.for_all (fun c -> U.member "historical_status" c = `String "NOT_ADMITTED") (claims_of o)
     | Error _ -> true);
  check "locator text is not echoed into output"
    (match fake_out with Ok o -> not (contains (J.to_string o) "SOVEREIGN_REVIEW") | Error _ -> true);

  (* ---- secret incidents: presence-only, opaque paths ---- *)
  let secret_paths = ["/nonexistent/uos/secret/key.pem"; "../../../etc/shadow"; "~/.ssh/id_rsa"; "/proc/self/mem";
                      "/dev/zero"; "file:///etc/passwd"; "$(cat /etc/shadow)"; "a/\\u202e/b"] in
  List.iter (fun p ->
    let s = with_ev 105 [ev_json ~kind:"incident_presence" ~loc:p ()] in
    check ("incident_presence locator accepted as opaque value: " ^ p) (is_ok s);
    (match adj s with
     | Ok o ->
         let c = claim_at o 105 in
         check ("incident_presence presence-only flags for: " ^ p)
           (U.member "secret_bytes_read" c = `Bool false && U.member "secret_bytes_hashed" c = `Bool false
            && findings_of c = ["incident_presence locator presence-only (not read/hashed)"]);
         check ("incident locator not echoed in output: " ^ p) (not (contains (J.to_string o) "etc/shadow") && not (contains (J.to_string o) "id_rsa"))
     | Error _ -> ())) secret_paths;
  check "incident_presence with bad path still no file IO error (nonexistent path yields Ok, no 'unexpected error')"
    (is_ok (with_ev 105 [ev_json ~kind:"incident_presence" ~loc:"/definitely/not/here" ()]));
  check "incident_presence plus other claims: other claims still secret-clean"
    (let o = ok_json (with_ev 105 [ev_json ~kind:"incident_presence" ()]) in
     List.for_all (fun c -> U.member "secret_bytes_read" c = `Bool false) (claims_of o));

  (* ---- core inspection (static) — NOT runtime syscall proof ---- *)
  let src_opt = List.find_opt Sys.file_exists ["km_adjudication.ml"; "tools/km_provenance/km_adjudication.ml"] in
  (match src_opt with
   | None -> check "core source available for static inspection" false
   | Some p ->
       let src = read_file p in
       check "core source available for static inspection" true;
       List.iter (fun tok ->
         check ("static inspection: core source lacks IO token " ^ tok) (not (contains src tok)))
         ["open_in"; "open_out"; "Unix."; "Sys."; "In_channel"; "Out_channel"; "Filename."; "Printf.";
          "print_"; "prerr_"; "read_line"; "input_line"; "Digest."; "Cryptokit"; "Sqlite3"; "Str.";
          "Stdlib.exit"; "exit "; "Random."; "Gc."; "Bytes.unsafe"; "Obj."; "Marshal."; "Lazy.";
          "Yojson.Safe.from_file"; "Yojson.Safe.to_file"; "from_channel"; "to_channel"]);
  check "observed determinism: 3 repeated calls agree on error input (not a proof of purity or totality)"
    (adj "{" = adj "{" && adj "{" = adj "{");

  (* ---- nonstandard JSON (Yojson extensions) must be refused ---- *)
  check "comment-prefixed valid JSON refused (block comment)" (is_err ("/* c */" ^ v));
  check "comment-prefixed valid JSON refused (line comment)" (is_err ("// c\n" ^ v));
  check "comment-prefixed refusal names nonstandard json" (err_has ("/* c */" ^ v) "nonstandard");
  check "NaN refused" (is_err (with_claim 94 {|{"ev":NaN,"adr":71,"evidence":[]}|}));
  check "Infinity refused" (is_err (with_claim 94 {|{"ev":Infinity,"adr":71,"evidence":[]}|}));
  check "single-quoted string refused" (is_err (report ~cand:("'" ^ c40 ^ "'") (std_claims ())));
  check "trailing comma in object refused" (is_err (String.sub v 0 (String.length v - 1) ^ ",}"));
  check "trailing comma in array refused" (is_err (report ~extra:"" ["1,"]));
  check "leading-zero number refused" (is_err (with_claim 94 {|{"ev":094,"adr":71,"evidence":[]}|}));
  check "raw control character in string refused" (is_err (with_ev 94 [ev_json ~loc:"a\x01b" ()]));
  check "bad escape in string refused" (is_err (with_ev 94 [ev_json ~loc:{|a\qb|} ()]));
  check "bad unicode escape refused" (is_err (with_ev 94 [ev_json ~loc:{|a\u12g4b|} ()]));
  check "unquoted key refused" (is_err ("{candidate_commit:1}"));
  check "tab/newline/CR whitespace accepted" (is_ok ("\t\r\n" ^ v ^ "\n"));
  check "form-feed whitespace refused" (is_err ("\012" ^ v));

  (* ---- explicit typed ADVISORY API vs the Lean model ---- *)
  let module A = Advisory in
  let ok_or_fail = function Ok x -> x | Error m -> failwith ("expected Ok: " ^ m) in
  let is_error = function Error _ -> true | Ok _ -> false in
  let err_is r sub = match r with Error m -> contains m sub | Ok _ -> false in
  let recs = A.all_recommendations in
  check "advisory: exactly the three Lean recommendation variants" (List.length recs = 3);
  check "advisory: labels equal the Lean constructor names"
    (List.map A.recommendation_label recs
     = ["rejectedFabrication"; "codePresentRequiresFreshTwoKeyRebind"; "supersededBySaPlan"]);
  check "advisory: initial dossier = Lean initial (ceiling 93, flags false, NOT_ADMITTED, 16 claims, no recs/clocks)"
    ((A.ceiling A.initial) = 93 && not (A.application_admitted A.initial) && not (A.system_admitted A.initial)
     && (A.history A.initial) = A.Not_admitted && List.length (A.claims A.initial) = 16
     && (A.recs A.initial) = [] && (A.clocks A.initial) = [] && A.invariant_holds A.initial);
  check "advisory: claims are EV94..109 in order"
    (List.map A.Claim.ev (A.claims A.initial) = List.init 16 (fun i -> 94 + i));
  check "advisory: ADR = EV - 23 within 71..86 for every claim"
    (List.for_all (fun c -> A.Claim.adr c = A.Claim.ev c - 23 && A.Claim.adr c >= 71 && A.Claim.adr c <= 86) (A.claims A.initial));
  (* boundary and invalid EVs, all three variants *)
  List.iter (fun r ->
    let lbl = A.recommendation_label r in
    List.iter (fun ev ->
      let d = ok_or_fail (A.add_recommendation A.initial ev r) in
      let c = ok_or_fail (A.Claim.make ev) in
      check (Printf.sprintf "advisory: %s accepted for EV%d, appended exactly once" lbl ev)
        ((A.recs d) = [ (c, r) ]);
      check (Printf.sprintf "advisory: %s on EV%d preserves ceiling/flags/status/claims (Lean inv_addRec)" lbl ev)
        ((A.ceiling d) = 93 && not (A.application_admitted d) && not (A.system_admitted d)
         && (A.history d) = A.Not_admitted && (A.claims d) = (A.claims A.initial) && (A.clocks d) = (A.clocks A.initial)
         && A.invariant_holds d);
      check (Printf.sprintf "advisory: %s on EV%d keeps ADR mapping %d" lbl ev (ev - 23))
        (A.Claim.adr c = ev - 23)) [94; 109];
    List.iter (fun ev ->
      check (Printf.sprintf "advisory: %s rejected for invalid EV%d" lbl ev)
        (err_is (A.add_recommendation A.initial ev r) "invalid EV")) [93; 110; 0; -1; 1000]) recs;
  (* exhaustive sweep: accepted iff 94 <= ev <= 109 *)
  check "advisory: sweep EV -5..130 x 3 variants accepts exactly 94..109"
    (List.for_all (fun ev ->
       List.for_all (fun r ->
         match A.add_recommendation A.initial ev r with
         | Ok d -> ev >= 94 && ev <= 109 && (A.recs d) <> []
         | Error _ -> ev < 94 || ev > 109) recs) (List.init 136 (fun i -> i - 5)));
  (* unknown EV: valid range but absent from a restricted dossier *)
  let sub = ok_or_fail (A.dossier_of_evs [94; 109]) in
  check "advisory: restricted dossier has exactly its claims" (List.map A.Claim.ev (A.claims sub) = [94; 109]);
  check "advisory: EV in range but unknown to the dossier rejected"
    (err_is (A.add_recommendation sub 100 A.Rejected_fabrication) "unknown EV");
  check "advisory: known EV in restricted dossier accepted"
    (not (is_error (A.add_recommendation sub 109 A.Superseded_by_sa_plan)));
  check "advisory: dossier_of_evs rejects 93, 110, duplicates"
    (is_error (A.dossier_of_evs [93]) && is_error (A.dossier_of_evs [110]) && is_error (A.dossier_of_evs [94; 94]));
  (* append-only history across multiple steps, including repeated claim *)
  let d3 = ok_or_fail (A.add_recommendation A.initial 94 A.Rejected_fabrication) in
  let d3 = ok_or_fail (A.add_recommendation d3 94 A.Code_present_requires_fresh_two_key_rebind) in
  let d3 = ok_or_fail (A.add_recommendation d3 109 A.Superseded_by_sa_plan) in
  check "advisory: recommendations are append-only in call order (Lean recs ++ [(c,r)])"
    (List.map (fun (c, r) -> (A.Claim.ev c, A.recommendation_label r)) (A.recs d3)
     = [94, "rejectedFabrication"; 94, "codePresentRequiresFreshTwoKeyRebind"; 109, "supersededBySaPlan"]);
  check "advisory: invariant holds after multi-step history" (A.invariant_holds d3 && (A.ceiling d3) = 93);
  check "advisory: input dossier is unchanged by add (immutability)" ((A.recs A.initial) = []);
  (* clock anomalies never select or change recommendations *)
  let same = { A.utc = A.Utc 5; mono = A.Monotonic 5 } and diff = { A.utc = A.Utc 5; mono = A.Monotonic 7 } in
  check "advisory: equal raw clocks flag invalidClockEvidence" (A.clock_status same = A.Invalid_clock_evidence);
  check "advisory: different raw clocks valid" (A.clock_status diff = A.Valid);
  let dc = ok_or_fail (A.record_clock A.initial 94 same) in
  check "advisory: clock anomaly alone selects no recommendation" ((A.recs dc) = [] && List.length (A.clocks dc) = 1);
  check "advisory: clock anomaly preserves ceiling/flags/status (Lean clock_anomaly_cannot_promote)"
    ((A.ceiling dc) = 93 && not (A.application_admitted dc) && not (A.system_admitted dc)
     && (A.history dc) = A.Not_admitted && A.invariant_holds dc);
  check "advisory: clock evidence does not change existing explicit recommendations"
    (let dr = ok_or_fail (A.add_recommendation A.initial 100 A.Code_present_requires_fresh_two_key_rebind) in
     let d1 = ok_or_fail (A.record_clock dr 100 same) in
     let d2 = ok_or_fail (A.record_clock dr 100 diff) in
     (A.recs d1) = (A.recs dr) && (A.recs d2) = (A.recs dr) && (A.recs d1) = (A.recs d2));
  check "advisory: recording clocks before or after a recommendation yields equal recs"
    (let a = ok_or_fail (A.add_recommendation (ok_or_fail (A.record_clock A.initial 94 same)) 94 A.Superseded_by_sa_plan) in
     let b = ok_or_fail (A.record_clock (ok_or_fail (A.add_recommendation A.initial 94 A.Superseded_by_sa_plan)) 94 same) in
     (A.recs a) = (A.recs b));
  check "advisory: record_clock rejects invalid 93/110 and unknown EV"
    (is_error (A.record_clock A.initial 93 same) && is_error (A.record_clock A.initial 110 same)
     && err_is (A.record_clock sub 100 same) "unknown EV");
  (* JSON rendering of the advisory dossier *)
  let aj = A.to_json d3 in
  let aclaims = U.to_list (U.member "claims" aj) in
  check "advisory json: authority is advisory report-only, ceiling 93, flags false"
    (U.member "authority" aj = `String "REPORT_ONLY_ADVISORY_RECOMMENDATIONS"
     && U.member "admitted_ev_ceiling" aj = `Int 93 && U.member "application_admitted" aj = `Bool false
     && U.member "system_admitted" aj = `Bool false && U.member "readback_verified" aj = `Bool false
     && U.member "sovereignty_authority" aj = `Bool false);
  check "advisory json: all claims NOT_ADMITTED with ADR=EV-23 and advisory-only authority"
    (List.length aclaims = 16
     && List.for_all (fun c -> U.member "historical_status" c = `String "NOT_ADMITTED"
                               && U.to_int (U.member "adr" c) = U.to_int (U.member "ev" c) - 23
                               && U.member "recommendation_authority" c = `String "ADVISORY_ONLY") aclaims);
  let recs_of ev = List.map U.to_string (U.to_list (U.member "advisory_recommendations"
                     (List.find (fun c -> U.to_int (U.member "ev" c) = ev) aclaims))) in
  check "advisory json: recorded recommendations appear only under their claim"
    (recs_of 94 = ["rejectedFabrication"; "codePresentRequiresFreshTwoKeyRebind"]
     && recs_of 109 = ["supersededBySaPlan"] && recs_of 100 = []);
  check "advisory json: clock statuses recorded separately from recommendations"
    (let jc = A.to_json dc in
     let c94 = List.find (fun c -> U.to_int (U.member "ev" c) = 94) (U.to_list (U.member "claims" jc)) in
     U.to_list (U.member "clock_statuses" c94) = [`String "invalidClockEvidence"]
     && U.to_list (U.member "advisory_recommendations" c94) = []);
  check "default report is unchanged by the advisory API: every recommendation null"
    (List.for_all (fun c -> U.member "recommendation" c = `Null) (claims_of (ok_json (valid ()))));
  check "default report JSON never carries advisory fields"
    (not (contains (J.to_string (ok_json (valid ()))) "advisory_recommendations"));
  check "adjudicate refuses JSON asserting an advisory recommendation key"
    (is_err (with_claim 94 (claim_json ~extra:{|,"advisory_recommendations":["rejectedFabrication"]|} 94 71 [])));
  check "adjudicate refuses JSON asserting recommendation label as evidence kind"
    (is_err (with_ev 94 [ev_json ~kind:"rejectedFabrication" ()]));

  (* ---- raw UTF-8 scalar validation (regression: C0 80 and F4 90 80 80 were accepted) ---- *)
  let raw_loc bytes = with_ev 94 [ev_json ~loc:("a" ^ bytes ^ "b") ()] in
  let bs l = String.concat "" (List.map (fun i -> String.make 1 (Char.chr i)) l) in
  let utf8_bad name l =
    check ("utf8 refused: " ^ name) (err_has (raw_loc (bs l)) "invalid utf-8") in
  utf8_bad "overlong NUL C0 80" [0xC0; 0x80];
  utf8_bad "overlong 2-byte C1 BF" [0xC1; 0xBF];
  utf8_bad "above U+10FFFF F4 90 80 80" [0xF4; 0x90; 0x80; 0x80];
  utf8_bad "isolated continuation 80" [0x80];
  utf8_bad "isolated continuation BF" [0xBF];
  utf8_bad "truncated 2-byte C2" [0xC2];
  utf8_bad "truncated 3-byte E2 82" [0xE2; 0x82];
  utf8_bad "truncated 4-byte F0 9F 98" [0xF0; 0x9F; 0x98];
  utf8_bad "truncated 3-byte lead then ASCII" [0xE2; 0x41; 0x41];
  utf8_bad "overlong 3-byte E0 80 80" [0xE0; 0x80; 0x80];
  utf8_bad "overlong 3-byte E0 9F BF" [0xE0; 0x9F; 0xBF];
  utf8_bad "overlong 4-byte F0 80 80 80" [0xF0; 0x80; 0x80; 0x80];
  utf8_bad "overlong 4-byte F0 8F BF BF" [0xF0; 0x8F; 0xBF; 0xBF];
  utf8_bad "raw surrogate ED A0 80" [0xED; 0xA0; 0x80];
  utf8_bad "raw surrogate ED AD BF" [0xED; 0xAD; 0xBF];
  utf8_bad "raw surrogate ED BF BF" [0xED; 0xBF; 0xBF];
  utf8_bad "above U+10FFFF F4 BF BF BF" [0xF4; 0xBF; 0xBF; 0xBF];
  List.iter (fun b -> utf8_bad (Printf.sprintf "invalid lead byte %02X" b) [b; 0x80; 0x80; 0x80])
    [0xF5; 0xF6; 0xF7; 0xF8; 0xFB; 0xFC; 0xFD; 0xFE; 0xFF];
  check "utf8 refused outside strings too (raw byte after document)"
    (err_has (valid () ^ bs [0xC0; 0x80]) "invalid utf-8");
  check "utf8 refused in an object key position"
    (err_has (report ~extra:(",\"k" ^ bs [0xC0; 0x80] ^ "\":1") (std_claims ())) "invalid utf-8");
  check "utf8 byte cap still reported first for oversize invalid input"
    (err_has (valid () ^ String.make 262144 '\xC0') "262144");
  List.iter (fun (name, l) ->
    check ("utf8 boundary accepted in locator: " ^ name) (is_ok (raw_loc (bs l))))
    [ "U+007F", [0x7F]; "U+0080", [0xC2; 0x80]; "U+07FF", [0xDF; 0xBF];
      "U+0800", [0xE0; 0xA0; 0x80]; "U+D7FF", [0xED; 0x9F; 0xBF];
      "U+E000", [0xEE; 0x80; 0x80]; "U+FFFF", [0xEF; 0xBF; 0xBF];
      "U+10000", [0xF0; 0x90; 0x80; 0x80]; "U+10FFFF", [0xF4; 0x8F; 0xBF; 0xBF];
      "U+00E9 mixed ASCII", [0xC3; 0xA9]; "U+1F600", [0xF0; 0x9F; 0x98; 0x80] ];
  check "valid raw UTF-8 locator content is not echoed or treated as path access"
    (match adj (raw_loc (bs [0xC3; 0xA9])) with
     | Ok o -> U.member "system_admitted" o = `Bool false && U.member "admitted_ev_ceiling" o = `Int 93
     | Error _ -> false);
  check "raw U+0000 byte in string still refused (control character)" (is_err (raw_loc "\x00"));
  check "escaped NUL in locator still refused with NUL message"
    (err_has (with_ev 94 [ev_json ~loc:{|a\u0000b|} ()]) "NUL");

  (* ---- escaped Unicode: surrogate pairing ---- *)
  let esc_loc e = with_ev 94 [ev_json ~loc:e ()] in
  check "escaped lone high surrogate refused" (is_err (esc_loc {|a\ud800b|}));
  check "escaped lone high surrogate at end refused" (is_err (esc_loc {|a\udbff|}));
  check "escaped lone low surrogate refused" (is_err (esc_loc {|a\udc00b|}));
  check "escaped lone low surrogate DFFF refused" (is_err (esc_loc {|\udfff|}));
  check "escaped reversed pair (low then high) refused" (is_err (esc_loc {|\udc00\ud800|}));
  check "escaped high followed by non-surrogate escape refused" (is_err (esc_loc {|\ud800\u0041|}));
  check "escaped high followed by literal char refused" (is_err (esc_loc {|\ud800A|}));
  check "escaped high followed by high refused" (is_err (esc_loc {|\ud800\ud800|}));
  check "escaped high followed by truncated low escape refused" (is_err (esc_loc {|\ud800\udc0|}));
  check "escaped pair then extra lone low refused" (is_err (esc_loc {|\ud83d\ude00\ude00|}));
  check "escaped valid pair D83D DE00 accepted" (is_ok (esc_loc {|a\ud83d\ude00b|}));
  check "escaped valid pair uppercase hex accepted" (is_ok (esc_loc {|\uD83D\uDE00|}));
  check "escaped valid pair U+10000 accepted" (is_ok (esc_loc {|\ud800\udc00|}));
  check "escaped valid pair U+10FFFF accepted" (is_ok (esc_loc {|\udbff\udfff|}));
  check "escaped boundary U+D7FF accepted" (is_ok (esc_loc {|\ud7ff|}));
  check "escaped boundary U+E000 accepted" (is_ok (esc_loc {|\ue000|}));
  check "escaped U+FFFF accepted" (is_ok (esc_loc {|\uffff|}));
  check "escaped lone surrogate in key refused"
    (is_err (report ~extra:{|,"k\ud800":1|} (std_claims ())));

  (* ---- external API-level proof that dossier control state cannot be forged ----
     Ephemeral fixtures are compiled against the real km_adjudication.ml (a dune dep
     copied into the build dir). A positive control must compile with the same
     toolchain/include path, so a missing compiler cannot yield a false negative pass. *)
  let read_file f = let ic = open_in_bin f in let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
  let write_file f s = let oc = open_out_bin f in output_string oc s; close_out oc in
  let pinned_findlib = "/home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocamlfind" in
  let findlib =
    match Sys.getenv_opt "UOS_OCAMLFIND" with
    | Some p -> p
    | None -> if Sys.file_exists pinned_findlib then pinned_findlib else "ocamlfind" in
  let tmpdir = Filename.temp_dir ~perms:0o700 "uos-adv-compile-" "" in
  let src = "km_adjudication.ml" in
  let src_ok = Sys.file_exists src in
  if src_ok then write_file (Filename.concat tmpdir "km_adjudication.ml") (read_file src);
  let sh cmd = Sys.command cmd in
  let compile_in file out =
    sh (Printf.sprintf "cd %s && %s ocamlc -package yojson %s > %s 2>&1"
          (Filename.quote tmpdir) (Filename.quote findlib) file (Filename.quote out)) in
  let lib_rc = if src_ok then compile_in "-c km_adjudication.ml" "lib.log" else 99 in
  check "advisory compile: real km_adjudication.ml compiles in the fixture dir (toolchain present)" (lib_rc = 0);
  let fixture name body expect_ok err_needle =
    write_file (Filename.concat tmpdir (name ^ ".ml")) body;
    let log = name ^ ".log" in
    let rc = compile_in ("-I . -c " ^ name ^ ".ml") log in
    let msg = read_file (Filename.concat tmpdir log) in
    if expect_ok then
      check ("advisory compile: " ^ name ^ " compiles (positive control)") (lib_rc = 0 && rc = 0)
    else
      check ("advisory compile: " ^ name ^ " is rejected for the expected reason")
        (lib_rc = 0 && rc <> 0 && contains msg err_needle
         && not (contains msg "Unbound module") && not (contains msg "No such file")) in
  fixture "pos_control"
    "let d = Km_adjudication.Advisory.initial\n\
     let d2 = match Km_adjudication.Advisory.add_recommendation d 100 Km_adjudication.Advisory.Rejected_fabrication with Ok x -> x | Error _ -> d\n\
     let _ = (Km_adjudication.Advisory.ceiling d2, Km_adjudication.Advisory.application_admitted d2, Km_adjudication.Advisory.to_json d2)\n"
    true "";
  fixture "neg_record_update"
    "let forged = { Km_adjudication.Advisory.initial with Km_adjudication.Advisory.ceiling = 109; application_admitted = true }\n\
     let _ = Km_adjudication.Advisory.to_json forged\n"
    false "field";
  fixture "neg_record_construction"
    "let forged : Km_adjudication.Advisory.dossier = { Km_adjudication.Advisory.ceiling = 109; application_admitted = true; system_admitted = true;\n\
     history = Km_adjudication.Advisory.Not_admitted; claims = []; recs = []; clocks = [] }\n"
    false "field";
  fixture "neg_field_read"
    "let _ = Km_adjudication.Advisory.initial.Km_adjudication.Advisory.ceiling\n"
    false "field";
  ignore (sh (Printf.sprintf "rm -rf %s" (Filename.quote tmpdir)));

  Printf.printf "TOTAL=%d PASSED=%d FAILED=%d\n%!" !total (!total - !failed) !failed;
  if !failed > 0 then exit 1
