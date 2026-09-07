(* Host clock evidence, kept separate from UTC strings, Lamport order and lease fields. *)
open Priority
type observation = { offset:float; uncertainty:float; reference_age:float; stratum:int }
let finite f = require (Float.is_finite f) "nonfinite clock sample"; f
let parse ~now line =
  let xs=String.split_on_char ',' (String.trim line) in
  require (List.length xs=14) "unsupported chronyc tracking format";
  let f i=finite (float_of_string (List.nth xs i)) in
  let stratum=int_of_string (List.nth xs 2) in
  let offset=abs_float (f 4) and reference_age=now -. f 3 in
  let delay=f 10 and dispersion=f 11 in
  require (stratum>=1 && stratum<=15 && List.nth xs 13="Normal") "host clock unsynchronized";
  require (delay>=0. && dispersion>=0.) "invalid NTP uncertainty";
  let uncertainty=delay/.2. +. dispersion in
  require (reference_age>=0. && reference_age<=4096. && offset<2. && uncertainty<2.)
    "host clock outside reference-age/offset/uncertainty limits";
  {offset;uncertainty;reference_age;stratum}
let observe () =
  let ic=Unix.open_process_args_in "timeout" [|"timeout";"3s";"chronyc";"-c";"tracking"|] in
  let line=ref "" in
  let result=try
    let b=Buffer.create 256 in
    let rec loop n = if n>4096 then raise (Invalid "clock output exceeds bound")
      else match input_char ic with '\n'->() | c->Buffer.add_char b c;loop (n+1)
      | exception End_of_file -> () in
    loop 0;line:=Buffer.contents b;None
    with e->Some e in
  let status=Unix.close_process_in ic in
  Option.iter raise result;
  require (status=Unix.WEXITED 0) "chronyc unavailable or timed out";
  parse ~now:(Unix.gettimeofday ()) !line
let consistent ~wall_start ~elapsed ~wall_end =
  require (elapsed>=0. && elapsed<=30.) "preflight elapsed bound exceeded";
  require (abs_float ((wall_end-.wall_start)-.elapsed)<0.25)
    "wall clock stepped during preflight"
let to_json x = `Assoc ["source",`String "chronyc tracking";
  "abs_ntp_offset_seconds",`Float x.offset;"uncertainty_seconds",`Float x.uncertainty;
  "reference_age_seconds",`Float x.reference_age;"stratum",`Int x.stratum]

