let () =
 try
  match Array.to_list Sys.argv with
  | [_;"validate";workspace;bundle;ev;revision] ->
   let now,clock_start=Receipt_validator.observe_clock() in
   let began=Receipt_validator.mono() in
   let result=Receipt_validator.validate ~workspace ~bundle ~expected_ev:(int_of_string ev) ~expected_revision:revision ~now in
   let finished,clock_end=Receipt_validator.observe_clock() in
   let elapsed=Receipt_validator.mono()-.began in
   Receipt_validator.require(abs_float((finished-.now)-.elapsed)<0.25) "host clock stepped during validation";
   let fields=Receipt_validator.assoc result in
   print_endline(Yojson.Basic.to_string(`Assoc(fields@[
    "observed_at",`Float now;"completed_at",`Float finished;"elapsed_seconds",`Float elapsed;
    "host_clock_start_sha256",`String clock_start;"host_clock_end_sha256",`String clock_end])))
  | _->failwith "usage: ev_receipt validate WORKSPACE RELATIVE_BUNDLE EV_NUMBER IMMUTABLE_40_HEX_REVISION"
 with error ->
  print_endline(Yojson.Basic.to_string(`Assoc["schema",`String "uos.ev-consistency.v1";"status",`String "HOLD";"authority",`String "NONE";"error",`String(Printexc.to_string error)]));exit 1
