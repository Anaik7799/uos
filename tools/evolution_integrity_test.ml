#use "evolution_cycles.ml";;
(* Synthetic fixtures test the checker; they are never runtime evidence. *)
let ()=
 let out=temp "uos-fifty-integrity-fixture-"in
 let overwrite p j=let oc=open_out_bin p in Fun.protect(fun()->output_string oc(json j))~finally:(fun()->close_out_noerr oc)in
 let change p key value=let a=read_file p 4194304|>Yojson.Safe.from_string|>assoc in overwrite p(jobj(List.map(fun(k,v)->k,if k=key then value else v)a))in
 write_new(out^"/FIXTURE-NOT-RUNTIME")"Synthetic checker tests; no board or runtime claims.\n";
 write_new(out^"/plan.json")(json(plans()));
 let done_ids=ref[]and remaining=ref focuses and previous=ref(String.make 64 '0')and sum=ref 0. in
 for n=1 to 50 do
  let focus=choose !done_ids [] !remaining and probability=outcome_probability(n-1)(n-1)in
  let f=jobj["schema",jstr"uos.local-forecast.v1";"focus",jstr focus.id;"event",jstr"check_returns_PASS";"authority",jstr"NONE";"probability",jfloat probability;"issued_utc_us",jstr(string_of_int(n*2))]in
  let fp=Printf.sprintf"%s/forecast-%02d.json"out n and ip=Printf.sprintf"%s/inbound-%02d.json"out n in
  write_new fp(json f);write_new ip"{\"test_fixture\":true}";
  let b=brier probability true in sum:= !sum+.b;
  let r=jobj["schema",jstr"uos.evolution-cycle.v2";"cycle",jint n;"logical_step",jint n;"focus",jstr focus.id;"plan",jstr"FIXTURE";"task",jstr"TEST";"attempt",jint 1;"owner",jstr"fixture";"session",jstr"fixture";"source_candidate",jstr(String.make 40 '0');"checker_revision",jstr(String.make 40 '1');"checker_hashes",jobj[];"domain",jstr focus.domain;"layer",jint focus.layer;"aspects",jarr(List.map jint focus.aspects);"factors",jarr(List.map jint focus.factors);"dependencies",jarr(List.map jstr focus.deps);"priority",jint(score focus.factors);"status",jstr"PASS";"authority",jstr"NONE";"system_admitted",jbool false;"utc_us",jstr(string_of_int(n*2+1));"previous_sha256",jstr !previous;"inbound_sha256",jstr(sha ip);"forecast_sha256",jstr(sha fp);"brier",jfloat b]in
  let rp=Printf.sprintf"%s/cycle-%02d.json"out n in write_new rp(json r);let hash=sha rp in
  write_new(Printf.sprintf"%s/envelope-%02d.json"out n)(json(transport_envelope r));
  write_new(Printf.sprintf"%s/publication-%02d.json"out n)(json(jobj["cycle",jint n;"key",jstr(Printf.sprintf"uos/tui/state/evolution/fixture/cycle/%02d"n);"authority",jstr"NONE";"zenoh_readback",jbool true;"payload_sha256",jstr hash;"test_fixture",jbool true]));
  previous:=hash;done_ids:=focus.id::!done_ids;remaining:=List.filter(fun x->x.id<>focus.id)!remaining
 done;
 write_new(out^"/summary.json")(json(jobj["schema",jstr"uos.evolution-summary.v2";"cycles",jint 50;"last_sha256",jstr !previous;"pass",jint 50;"fail",jint 0;"blocked",jint 0;"observed",jint 0;"scored_forecasts",jint 50;"sum_brier",jfloat !sum;"authority",jstr"NONE";"system_admitted",jbool false]));
 verify50 ~quiet:true out;
 let checks=ref 1 in
 let mutant file key value=
  let p=out^"/"^file in let original=read_file p 4194304 in change p key value;
  let rejected=try verify50 ~quiet:true out;false with _->true in
  let oc=open_out_bin p in output_string oc original;close_out oc;
  require rejected("accepted mutant "^file^":"^key);incr checks in
 List.iter(fun(k,v)->mutant "cycle-01.json" k v)
 ["focus",jstr"N50";"priority",jint 0;"domain",jstr"forged";"layer",jint 9;"aspects",jarr[];"factors",jarr[];"dependencies",jarr[jstr"absent"];"authority",jstr"ADMITTED";"system_admitted",jbool true;"brier",jfloat 0.;"status",jstr"UNKNOWN";"previous_sha256",jstr"bad";"logical_step",jint 0];
 mutant "cycle-02.json" "checker_revision"(jstr"different");
 mutant "forecast-01.json" "probability"(jfloat 1.);
 mutant "inbound-01.json" "test_fixture"(jbool false);
 mutant "publication-01.json" "zenoh_readback"(jbool false);
 mutant "publication-01.json" "key"(jstr"unowned");
 List.iter(fun(k,v)->mutant "summary.json" k v)
 ["pass",jint 49;"fail",jint 1;"cycles",jint 49;"scored_forecasts",jint 49;"sum_brier",jfloat 0.;"system_admitted",jbool true;"authority",jstr"ADMITTED"];
 verify50 ~quiet:true out;
 emit "fifty-integrity-negatives" "PASS"["checks",jint !checks;"evidence",jstr out;"fixture_only",jbool true];;
