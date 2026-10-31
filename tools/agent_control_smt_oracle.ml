(* Report-only independent integer oracle for the QF_LIA admission slice.
   Run Z3 in an isolated externally bounded process first; this checker never
   trusts a SAT verdict without evaluating every returned witness. UNSAT is
   additionally refutation-tested over a finite independent enumeration.
   No network, tasks, budget mutation, or provider effect is performed. *)
let fail msg = prerr_endline ("HOLD: " ^ msg); exit 2
let read path =
 let ch = open_in_bin path in
 Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
  let n = in_channel_length ch in
  if n > 65536 then fail "solver_output_bound";
  really_input_string ch n)
let tokenize s =
 let b = Buffer.create (String.length s * 2) in
 String.iter (fun c -> match c with
 | '(' | ')' -> Buffer.add_char b ' '; Buffer.add_char b c; Buffer.add_char b ' '
 | ' ' | '\n' | '\r' | '\t' -> Buffer.add_char b ' '
 | c -> Buffer.add_char b c) s;
 String.split_on_char ' ' (Buffer.contents b) |> List.filter ((<>) "")
let names = List.sort compare ["running_w";"uncertain_w";"running_r";"uncertain_r";
 "dw";"dr";"target";"liability";"now";"deadline";"lease"]
let model tokens =
 let rec fields acc = function
 | ")" :: rest ->
   if List.sort compare (List.map fst acc) <> names then fail "witness_keys";
   acc,rest
 | "(" :: k :: v :: ")" :: rest ->
   if List.mem_assoc k acc then fail "duplicate_witness_key";
   let n = try int_of_string v with _ -> fail "invalid_witness_integer" in
   if n < 0 || n > 10000000 then fail "witness_range";
   fields ((k,n)::acc) rest
 | _ -> fail "malformed_witness"
 in match tokens with "("::rest -> fields [] rest | _ -> fail "missing_witness"
let get m k = try List.assoc k m with _ -> fail "missing_witness_key"
let totals m = get m "running_w"+get m "uncertain_w",get m "running_r"+get m "uncertain_r"
let pre m =
 let w,r = totals m in let dw=get m "dw" and dr=get m "dr" in
 List.for_all (fun (_,v)->v>=0) m && w<=2 && r<=1 && w+r<=3
 && get m "target"<=3 && get m "liability"<=10000000
 && ((dw=1 && dr=0)||(dw=0 && dr=1))
let numeric_guard w r dw dr target liability now deadline lease =
 w+r<target && (dw<>1 || w<2) && (dr<>1 || r<1)
 && liability<=9750000 && now<deadline && now<lease
let guard m =
 let w,r=totals m in pre m && numeric_guard w r (get m "dw") (get m "dr")
 (get m "target") (get m "liability") (get m "now") (get m "deadline") (get m "lease")
let unsafe m =
 let w,r=totals m in let dw=get m "dw" and dr=get m "dr" in
 w+dw>2 || r+dr>1 || w+r+dw+dr>3 || get m "liability"+250000>10000000
 || get m "now">=get m "deadline" || get m "now">=get m "lease"
let parse tokens =
 let after = match tokens with
 | "GUARDED_UNSAFE"::"unsat"::"VALID_ADMISSION"::"sat"::rest -> rest
 | _ -> fail "unexpected_solver_status_or_order"
 in
 let valid,after=model after in
 let after=match after with "MUTANT_RUNNING_ONLY"::"sat"::rest->rest
 | _ -> fail "missing_running_mutant" in
 let running,after=model after in
 let after=match after with "MUTANT_CLOSED_EXPIRY"::"sat"::rest->rest
 | _ -> fail "missing_expiry_mutant" in
 let expiry,after=model after in
 if after<>[] then fail "unexpected_trailing_output";
 valid,running,expiry
let () =
 if Array.length Sys.argv<>2 then fail "usage: agent_control_smt_oracle.ml Z3_OUTPUT";
 let valid,running,expiry = parse (tokenize (read Sys.argv.(1))) in
 let valid_fixture = ["running_w",1;"uncertain_w",0;"running_r",1;
  "uncertain_r",0;"dw",1;"dr",0;"target",3;"liability",0;
  "now",0;"deadline",1;"lease",1] in
 if not (guard valid && not (unsafe valid)
  && List.for_all (fun (key,value)->get valid key=value) valid_fixture)
 then fail "invalid_positive_witness";
 let rw=get running "running_w" and rr=get running "running_r" in
 if not(pre running && numeric_guard rw rr (get running "dw") (get running "dr")
  (get running "target") (get running "liability") (get running "now")
  (get running "deadline") (get running "lease") && unsafe running && not(guard running))
 then fail "invalid_running_only_counterexample";
 let w,r=totals expiry in
 if not(pre expiry && w+r<get expiry "target"
  && (get expiry "dw"<>1 || w<2) && (get expiry "dr"<>1 || r<1)
  && get expiry "liability"<=9750000 && get expiry "now"=get expiry "deadline"
  && get expiry "now"<get expiry "lease" && not(guard expiry) && unsafe expiry)
 then fail "invalid_closed_expiry_counterexample";
 let checked=ref 0 and accepted=ref 0 in
 for w=0 to 2 do for r=0 to 1 do for dw=0 to 1 do
 for units=0 to 40 do for target=0 to 3 do
 for now=0 to 4 do for deadline=0 to 4 do for lease=0 to 4 do
  incr checked;
  let dr=1-dw and liability=units*250000 in
  if w+r<=3 && numeric_guard w r dw dr target liability now deadline lease then begin
   incr accepted;
   if w+dw>2 || r+dr>1 || w+r+1>3 || liability+250000>10000000
    || now>=deadline || now>=lease then fail "finite_refutation_found"
  end
 done done done done done done done done;
 if !accepted=0 then fail "vacuous_oracle";
 Printf.printf "{\"status\":\"PASS_REPORT_ONLY\",\"authority\":\"NONE\",\"sat_witnesses_evaluated\":3,\"finite_refutation_candidates\":%d,\"valid_admissions\":%d,\"finite_scope_only\":true}\n" !checked !accepted

