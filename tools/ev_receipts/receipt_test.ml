(* Synthetic receipts exercise consistency only. No fixture is admission evidence.
   Removing any input guard should make its named negative case fail. *)
open Yojson.Basic.Util
let obj xs = `Assoc xs
let s x = `String x
let i x = `Int x
let arr xs = `List xs
let strings xs = arr(List.map s xs)
let replace k v = function `Assoc xs -> obj((k,v)::List.remove_assoc k xs)|_->assert false
let sha b = Cryptokit.hash_string(Cryptokit.Hash.sha256())b |> Cryptokit.transform_string(Cryptokit.Hexa.encode())
let read p = let c=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->really_input_string c (in_channel_length c))
let write p b = let c=open_out_bin p in output_string c b;close_out c
let workspace=Sys.argv.(1)
let revision="337f99137673d7866b958a38bd490fb876b2880f"
let now=Unix.gettimeofday()
let prefix="tools/ev_receipts/_fixture-"^Printf.sprintf "%.0f"(Unix.gettimeofday() *. 1000000.)
let path p=workspace^"/"^p
let ()=Unix.mkdir(path prefix)0o700
let reference p b = write(path p)b;obj["path",s p;"sha256",s(sha b)]
let source="tools/km_provenance/dune-project"
let policy="contracts/rules/20260908-0912-provenance-integrity-contract.md"
let source_ref=obj["path",s source;"sha256",s(sha(read(path source)))]
let policy_ref=obj["path",s policy;"sha256",s(sha(read(path policy)))]
let manifest=arr[source_ref]
let outputs kind=reference(prefix^"/"^kind^".out")("SYNTHETIC "^kind^" output\n")
let command=strings["synthetic-check";"--fixture"]
let clock=obj["source",s "chronyc tracking";"observed_at",`Float(now-.20.);"stratum",i 3;"offset_seconds",`Float 0.001;"uncertainty_seconds",`Float 0.01;"reference_age_seconds",`Float 10.]
let receipt kind = obj[
 "schema",s "uos.ev-receipt.v1";"kind",s kind;"ev",i 1;"revision",s revision;
 "scope",strings[source];"source_manifest_sha256",s(sha(Yojson.Basic.to_string ~std:false manifest));
 "policy_sha256",member "sha256" policy_ref;"acceptance_ids",strings["EV01-CHECK-1"];
 "invocation",obj["id",s("synthetic-"^kind);"command",command;"started_at",`Float(now-.10.);"finished_at",`Float(now-.5.);
 "exit_code",i 0;"timed_out",`Bool false;"output_overflow",`Bool false;"status",s "PASS";
 "executed_checks",i 1;"failed_checks",i 0;"skipped_checks",i 0;"output",outputs kind];
 "clock",clock;"toolchain",obj["name",s "SYNTHETIC";"version",s "fixture-v1";"executable_sha256",s(String.make 64 'a')];
 "negative_controls",arr[obj["id",s "reject-false";"command",command;"started_at",`Float(now-.9.);"finished_at",`Float(now-.8.);
 "expected_exit_code",i 1;"actual_exit_code",i 1;"timed_out",`Bool false;"output_overflow",`Bool false;"output",outputs(kind^"-negative")]];
 "formal_result",(if kind="formal" then obj["verifier",s "SYNTHETIC";"result",s "PASS";"sorry_count",i 0;"unsupported_count",i 0;"undeclared_axioms",strings[]] else `Null)]
let runtime=receipt "runtime"
let formal=receipt "formal"
let receipt_ref kind value=reference(prefix^"/"^kind^".json")(let raw=Yojson.Basic.to_string ~std:false value in let marker="\"NONFINITE_SENTINEL\"" in let rec rewrite n = if n+String.length marker>String.length raw then raw else if String.sub raw n (String.length marker)=marker then String.sub raw 0 n ^ "1e999" ^ String.sub raw (n+String.length marker) (String.length raw-n-String.length marker) else rewrite(n+1) in rewrite 0)
let make_bundle r f = obj["schema",s "uos.ev-bundle.v1";"ev",i 1;"revision",s revision;"scope",strings[source];"acceptance_ids",strings["EV01-CHECK-1"];
 "source_manifest",manifest;"policy",policy_ref;"runtime",receipt_ref "runtime" r;"formal",receipt_ref "formal" f]
let valid ()=make_bundle runtime formal
let failures=ref 0 and checks=ref 0
let check name expected bytes =
 incr checks;
 write(path(prefix^"/bundle.json"))bytes;
 let result=try let v=Receipt_validator.validate ~workspace ~bundle:(prefix^"/bundle.json") ~expected_ev:1 ~expected_revision:revision ~now in
 member "status" v=s "EVIDENCE_CONSISTENT" && member "authority" v=s "NONE" with _->false in
 if result=expected then Printf.printf "PASS %s\n%!" name else (incr failures;Printf.printf "FAIL %s expected_accept=%b observed_accept=%b\n%!" name expected result)
let test name f=check name false(Yojson.Basic.to_string ~std:false(f(valid())))
let receipt_test name f=test name(fun _->make_bundle(f runtime)formal)
let invocation_test name k v=receipt_test name(fun r->replace "invocation"(replace k v(member "invocation" r))r)
let ()=
 check "valid_synthetic_bundle" true(Yojson.Basic.to_string ~std:false(valid()));
 test "wrong_revision" (replace "revision"(s(String.make 40 '0')));
 test "wrong_ev" (replace "ev"(i 110));
 test "empty_coverage" (replace "acceptance_ids"(strings[]));
 test "duplicate_coverage" (replace "acceptance_ids"(strings["A";"A"]));
 test "unknown_key" (replace "unexpected" `Null);
 test "missing_key" (function `Assoc xs->obj(List.remove_assoc "policy" xs)|_->assert false);
 test "duplicate_key" (function `Assoc xs->obj(("ev",i 1)::xs)|_->assert false);
 test "same_receipt_two_keys" (fun b->replace "formal"(member "runtime" b)b);
 test "wrong_source_hash" (replace "source_manifest"(arr[replace "sha256"(s(String.make 64 'b'))source_ref]));
 test "undeclared_scope" (replace "scope"(strings["tools/km_provenance/km_ev.ml"]));
 receipt_test "wrong_receipt_revision" (replace "revision"(s(String.make 40 'c')));
 receipt_test "wrong_receipt_coverage" (replace "acceptance_ids"(strings["other"]));
 receipt_test "missing_negative_controls" (replace "negative_controls"(arr[]));
 receipt_test "unknown_receipt_key" (replace "extra" `Null);
 invocation_test "failed_exit" "exit_code"(i 1);
 invocation_test "timed_out" "timed_out"(`Bool true);
 invocation_test "output_overflow" "output_overflow"(`Bool true);
 invocation_test "unrun" "executed_checks"(i 0);
 invocation_test "skipped" "skipped_checks"(i 1);
 invocation_test "failed_check" "failed_checks"(i 1);
 invocation_test "unverified_status" "status"(s "UNRUN");
 invocation_test "stale" "started_at"(`Float(now-.7200.));
 invocation_test "future" "finished_at"(`Float(now+.1.));
 invocation_test "reversed_time" "started_at"(`Float now);
 invocation_test "nonfinite_time" "finished_at"(s "NONFINITE_SENTINEL");
 receipt_test "bad_clock" (fun r->replace "clock"(replace "offset_seconds"(`Float 3.)clock)r);
 test "formal_sorry" (fun _->make_bundle runtime (replace "formal_result"(replace "sorry_count"(i 1)(member "formal_result" formal))formal));
 test "formal_unsupported" (fun _->make_bundle runtime (replace "formal_result"(replace "unsupported_count"(i 1)(member "formal_result" formal))formal));
 test "formal_axiom" (fun _->make_bundle runtime (replace "formal_result"(replace "undeclared_axioms"(strings["fabricated"])(member "formal_result" formal))formal));
 test "tampered_receipt_bytes" (fun b->write(path(prefix^"/runtime.json"))"{}";b);
 test "tampered_output" (fun b->write(path(prefix^"/runtime.out"))"tampered";b);
 ignore(outputs "runtime");
 test "path_traversal" (fun b->replace "runtime"(replace "path"(s "../outside")(member "runtime" b))b);
 test "absolute_path" (fun b->replace "runtime"(replace "path"(s "/etc/passwd")(member "runtime" b))b);
 Unix.symlink "/etc/passwd"(path(prefix^"/escape"));
 test "escaping_symlink" (fun b->replace "runtime"(replace "path"(s(prefix^"/escape"))(member "runtime" b))b);
 test "directory_reference" (fun b->replace "runtime"(replace "path"(s prefix)(member "runtime" b))b);
 check "malformed_json" false "{";
 check "oversize_json" false(String.make 1048577 ' ');
 Printf.printf "SYNTHETIC consistency tests: checks=%d failed=%d; admission_authority=NONE\n%!" !checks !failures;
 if !failures>0 then exit 1
let () =
 let clock_case name expected body =
  let got=try Receipt_validator.validate_clock_text ~now body;true with _->false in
  if got<>expected then (Printf.printf "FAIL %s\n%!" name;incr failures) else Printf.printf "PASS %s\n%!" name in
 let good=Printf.sprintf "B97DBE7A,185.125.190.122,3,%.6f,-0.0004,0.0002,0.0003,-6.2,0.01,0.3,0.03,0.001,1000,Normal\n" (now-.10.) in
 clock_case "live_clock_csv_positive" true good;
 clock_case "live_clock_unsynchronized" false "0,0,0,0,0,0,0,0,0,0,0,0,0,Not synchronised";
 clock_case "live_clock_malformed" false "no daemon";
 clock_case "live_clock_nonfinite" false(Printf.sprintf "0,0,3,%.6f,nan,0,0,0,0,0,0,0,0,Normal"now);
 clock_case "live_clock_future_ref" false(Printf.sprintf "0,0,3,%.6f,0,0,0,0,0,0,0,0,0,Normal"(now+.60.));
 clock_case "live_clock_stale_ref" false "0,0,3,1,0,0,0,0,0,0,0,0,0,Normal";
 if !failures>0 then exit 1
let () =
 let source_bytes="SYNTHETIC source absent from immutable candidate\n" in
 let fake_source=prefix^"/source.ml" in
 let fake_manifest=arr[reference fake_source source_bytes] in
 test "consistent_labels_untracked_source" (fun _ ->
  let adapt r=r |> replace "scope"(strings[fake_source]) |> replace "source_manifest_sha256"(s(sha(Yojson.Basic.to_string fake_manifest))) in
  make_bundle(adapt runtime)(adapt formal) |> replace "scope"(strings[fake_source]) |> replace "source_manifest" fake_manifest);
 test "consistent_labels_untracked_policy" (fun _ ->
  let p=reference(prefix^"/policy.md")"SYNTHETIC policy\n" in
  make_bundle(replace "policy_sha256"(member "sha256" p)runtime)(replace "policy_sha256"(member "sha256" p)formal) |> replace "policy" p);
 receipt_test "negative_control_accepted" (fun r->replace "negative_controls" (arr[replace "actual_exit_code"(i 0)(List.hd(to_list(member "negative_controls" r)))])r);
 receipt_test "duplicate_nested_key" (fun r->replace "clock"(match clock with `Assoc xs->obj(("stratum",i 3)::xs)|_->assert false)r);
 receipt_test "shared_invocation_id" (fun r->replace "invocation"(replace "id"(s "synthetic-formal")(member "invocation" r))r);
 Unix.mkfifo(path(prefix^"/fifo"))0o600;
 test "fifo_refused_before_open" (fun b->replace "runtime"(replace "path"(s(prefix^"/fifo"))(member "runtime" b))b);
 Unix.symlink "/tmp"(path(prefix^"/outside-directory"));
 test "symlink_parent_refused" (fun b->replace "runtime"(replace "path"(s(prefix^"/outside-directory/out.json"))(member "runtime" b))b);
 check "deep_json" false(String.make 40 '[' ^ "0" ^String.make 40 ']');
 let bounded name f = incr checks;let refused=try f();false with _->true in
  if refused then Printf.printf "PASS %s\n%!" name else(incr failures;Printf.printf "FAIL %s\n%!"name) in
 bounded "reader_timeout"(fun()->ignore(Receipt_validator.run ~seconds:0.03 ~limit:1024 "/usr/bin/sleep" ["1"]));
 bounded "reader_output_quota"(fun()->ignore(Receipt_validator.run ~seconds:1. ~limit:32 "/usr/bin/printf" ["%1000s";"x"]));
 bounded "reader_exit_failure"(fun()->ignore(Receipt_validator.run ~seconds:1. ~limit:1024 "/usr/bin/false" []));
 (* Restore a complete synthetic bundle for a separate real CLI invocation. *)
 ignore(outputs "runtime");ignore(outputs "formal");ignore(outputs "runtime-negative");ignore(outputs "formal-negative");
 let good=valid() in write(path(prefix^"/bundle.json"))(Yojson.Basic.to_string good);
 Printf.printf "SYNTHETIC fixture_bundle=%s\nTOTAL checks=%d (plus 6 clock cases) failed=%d; authority=NONE\n%!"(prefix^"/bundle.json") !checks !failures;
 if !failures>0 then exit 1
let () =
 check "repeated_command_arguments_are_valid" true(Yojson.Basic.to_string(make_bundle
  (replace "invocation"(replace "command"(strings["check";"--label";"check"])(member "invocation" runtime))runtime)formal));
 if !failures>0 then exit 1
let ()=Printf.printf "FINAL consistency cases=%d clock cases=6 failed=%d; all receipts SYNTHETIC; authority=NONE\n%!" !checks !failures
(* Review regression: immutable IDs must not be interpreted as user aliases. *)
let () =
 let selected="5f66dfa699a4d16f96cd218376f2b23c5b59db33" in
 let config=path(prefix^"/jj-alias.toml") in
 write config("[revset-aliases]\n\""^selected^"\" = \""^revision^"\"\n");
 let previous=Sys.getenv_opt "JJ_CONFIG" in
 Unix.putenv "JJ_CONFIG" config;
 let result=Fun.protect ~finally:(fun()->Unix.putenv "JJ_CONFIG"(Option.value ~default:"" previous))(fun()->
  try let bytes=Receipt_validator.candidate_bytes workspace selected "tools/ev_receipts/receipt_validator.ml" in
   sha bytes="b08a77ba8d14016a0c0db7fcb34403b6533be8b60017812ce50f701999373875" with _->false) in
 if not result then (incr failures;print_endline "FAIL immutable_revision_ignores_conflicting_symbol_alias")
 else print_endline "PASS immutable_revision_ignores_conflicting_symbol_alias";
 if !failures>0 then exit 1
let review_cases=ref 1
let review_case label expected f =
 incr review_cases;
 let accepted=try f();true with _->false in
 if accepted=expected then Printf.printf "PASS %s\n%!"label
 else(incr failures;Printf.printf "FAIL %s expected_accept=%b observed_accept=%b\n%!"label expected accepted)
let review_rejection label expected f =
 incr review_cases;
 let observed=try f();"accepted" with Failure message->message|e->Printexc.to_string e in
 if observed=expected then Printf.printf "PASS %s reason=%s\n%!"label observed
 else(incr failures;Printf.printf "FAIL %s expected=%s observed=%s\n%!"label expected observed)
let () =
 let result=obj["valid_until",`Float 1000.;"status",s "EVIDENCE_CONSISTENT";"authority",s "NONE"] in
 let final finished elapsed = ignore(Receipt_validator.finalize_observation ~now:999.8 ~finished ~elapsed ~clock_start:"first" ~clock_end:"second" result) in
 review_case "final_clock_before_expiry" true(fun()->final 999.9 0.1);
 review_case "final_clock_delay_crosses_expiry" false(fun()->final 1000.2 0.4);
 review_case "final_clock_nonfinite" false(fun()->final infinity infinity);
 let at=ref 0. in
 let budget=Receipt_validator.make_budget ~clock:(fun()-> !at) ~seconds:1. ~bytes:20 () in
 review_case "aggregate_accounts_candidate_and_rehash" false(fun()->
  Receipt_validator.charge budget 8;Receipt_validator.charge budget 8;Receipt_validator.charge budget 8);
 let budget=Receipt_validator.make_budget ~clock:(fun()-> !at) ~seconds:1. ~bytes:20 () in
 review_case "aggregate_exact_boundary" true(fun()->Receipt_validator.charge budget 20);
 review_case "deadline_between_metadata_and_content" false(fun()->
  Receipt_validator.check_budget budget; (* metadata observation complete *)
  at:=1.1;Receipt_validator.check_budget budget (* no content reader may start *));
 if !failures>0 then exit 1
let () =
 let large_receipt kind offset original =
  let template=List.hd(to_list(member "negative_controls" original)) in
  let controls=List.init 4(fun n->
   let output=reference(prefix^"/"^kind^"-large-"^string_of_int n^".out")
     (String.make 1048576(Char.chr(Char.code 'A'+offset+n))) in
   template |> replace "id"(s("negative-"^string_of_int n)) |> replace "output" output) in
  replace "negative_controls"(arr controls)original in
 let large=make_bundle(large_receipt "runtime" 0 runtime)(large_receipt "formal" 4 formal) in
 write(path(prefix^"/large-bundle.json"))(Yojson.Basic.to_string large);
 review_rejection "aggregate_includes_actual_final_rehash" "aggregate content byte quota" (fun()->
  ignore(Receipt_validator.validate ~workspace ~bundle:(prefix^"/large-bundle.json") ~expected_ev:1 ~expected_revision:revision ~now));
 let metadata_size=String.length("file "^source^"\n") in
 review_rejection "candidate_content_refused_after_metadata_exhausts_bytes" "reader budget exhausted" (fun()->
  let budget=Receipt_validator.make_budget ~bytes:(41+metadata_size)() in
  ignore(Receipt_validator.candidate_bytes ~budget workspace revision source));
 review_rejection "candidate_deadline_between_actual_metadata_and_content" "validation deadline" (fun()->
  let current=ref None in
  let clock()=match !current with Some b when b.Receipt_validator.remaining_bytes<=4096-41-metadata_size->2.|_->0. in
  let budget=Receipt_validator.make_budget ~clock ~seconds:1. ~bytes:4096 () in
  current:=Some budget;
  ignore(Receipt_validator.candidate_bytes ~budget workspace revision source));
 (* Restore the small fixture after the large-bundle falsifier. *)
 ignore(valid());
 Printf.printf "REVIEW FINAL original_cases=56 review_cases=%d failed=%d authority=NONE\n%!" !review_cases !failures;
 if !failures>0 then exit 1
