let () =
 try
  match Array.to_list Sys.argv with
  | [_;"validate";workspace;bundle;ev;revision] ->
   let now,clock_start=Receipt_validator.observe_clock() in
   let began=Receipt_validator.mono() in
   let result=Receipt_validator.validate ~workspace ~bundle ~expected_ev:(int_of_string ev) ~expected_revision:revision ~now in
   let finished,clock_end=Receipt_validator.observe_clock() in
   let elapsed=Receipt_validator.mono()-.began in
   let final=Receipt_validator.finalize_observation ~now ~finished ~elapsed ~clock_start ~clock_end result in
   print_endline(Yojson.Basic.to_string final)
  | _->failwith "usage: ev_receipt validate WORKSPACE RELATIVE_BUNDLE EV_NUMBER IMMUTABLE_40_HEX_REVISION"
 with error ->
  print_endline(Yojson.Basic.to_string(`Assoc["schema",`String "uos.ev-consistency.v1";"status",`String "HOLD";"authority",`String "NONE";"error",`String(Printexc.to_string error)]));exit 1
