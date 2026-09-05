(* Beta-Binomial pass-rate inference. See the .mli. *)

type estimate = { runs : int; passes : int; mean : float; low : float; high : float }

(* Jeffreys prior: Beta(1/2, 1/2). A uniform prior nearly asserts that
   zero runs mean a coin flip; Jeffreys does not, and it does not claim
   certainty from one observation either. *)
let a0 = 0.5
let b0 = 0.5

(* Beta quantile by bisection on the regularised incomplete beta. Slow
   and exact enough; this is called once per report, not per frame. *)
let log_gamma x =
  (* Lanczos, adequate for the shapes here *)
  let g = 7.0 in
  let c =
    [| 0.99999999999980993; 676.5203681218851; -1259.1392167224028; 771.32342877765313;
       -176.61502916214059; 12.507343278686905; -0.13857109526572012; 9.9843695780195716e-6;
       1.5056327351493116e-7 |]
  in
  if x < 0.5 then
    log (Float.pi /. sin (Float.pi *. x)) -. (
      let lg y =
        let x' = y -. 1.0 in
        let a = ref c.(0) in
        let t = x' +. g +. 0.5 in
        for i = 1 to 8 do a := !a +. (c.(i) /. (x' +. float_of_int i)) done;
        (0.5 *. log (2.0 *. Float.pi)) +. ((x' +. 0.5) *. log t) -. t +. log !a
      in
      lg (1.0 -. x))
  else
    let x' = x -. 1.0 in
    let a = ref c.(0) in
    let t = x' +. g +. 0.5 in
    for i = 1 to 8 do a := !a +. (c.(i) /. (x' +. float_of_int i)) done;
    (0.5 *. log (2.0 *. Float.pi)) +. ((x' +. 0.5) *. log t) -. t +. log !a

let betacf a b x =
  let maxit = 300 and eps = 3e-14 and fpmin = 1e-300 in
  let qab = a +. b and qap = a +. 1.0 and qam = a -. 1.0 in
  let c = ref 1.0 and d = ref (1.0 -. (qab *. x /. qap)) in
  if abs_float !d < fpmin then d := fpmin;
  d := 1.0 /. !d;
  let h = ref !d in
  (try
     for m = 1 to maxit do
       let mf = float_of_int m in
       let m2 = 2.0 *. mf in
       let aa = mf *. (b -. mf) *. x /. ((qam +. m2) *. (a +. m2)) in
       d := 1.0 +. (aa *. !d);
       if abs_float !d < fpmin then d := fpmin;
       c := 1.0 +. (aa /. !c);
       if abs_float !c < fpmin then c := fpmin;
       d := 1.0 /. !d;
       h := !h *. !d *. !c;
       let aa = -.(a +. mf) *. (qab +. mf) *. x /. ((a +. m2) *. (qap +. m2)) in
       d := 1.0 +. (aa *. !d);
       if abs_float !d < fpmin then d := fpmin;
       c := 1.0 +. (aa /. !c);
       if abs_float !c < fpmin then c := fpmin;
       d := 1.0 /. !d;
       let del = !d *. !c in
       h := !h *. del;
       if abs_float (del -. 1.0) < eps then raise Exit
     done
   with Exit -> ());
  !h

let betai a b x =
  if x <= 0.0 then 0.0
  else if x >= 1.0 then 1.0
  else
    let bt =
      exp (log_gamma (a +. b) -. log_gamma a -. log_gamma b +. (a *. log x)
           +. (b *. log (1.0 -. x)))
    in
    if x < (a +. 1.0) /. (a +. b +. 2.0) then bt *. betacf a b x /. a
    else 1.0 -. (bt *. betacf b a (1.0 -. x) /. b)

let beta_quantile a b p =
  let lo = ref 0.0 and hi = ref 1.0 in
  for _ = 1 to 200 do
    let mid = 0.5 *. (!lo +. !hi) in
    if betai a b mid < p then lo := mid else hi := mid
  done;
  0.5 *. (!lo +. !hi)

let estimate ~runs ~passes =
  if runs < 0 || passes < 0 then Error "counts cannot be negative"
  else if passes > runs then Error "more passes than runs"
  else if runs = 0 then Error "no runs: nothing has been observed, so nothing is estimated"
  else
    let a = a0 +. float_of_int passes in
    let b = b0 +. float_of_int (runs - passes) in
    Ok { runs; passes;
         mean = a /. (a +. b);
         low = beta_quantile a b 0.05;
         high = beta_quantile a b 0.95 }

(* A stage that passed every observed run may still fail often enough to
   matter. This asks whether the evidence RULES OUT a failure rate above
   the threshold — which zero failures in three runs does not. *)
let rules_out_flakiness e ~threshold = e.low >= 1.0 -. threshold

let runs_needed ~threshold =
  let rec go n = if n > 5000 then n
    else match estimate ~runs:n ~passes:n with
      | Ok e when rules_out_flakiness e ~threshold -> n
      | _ -> go (n + 1)
  in
  go 1

let stan_model =
  {|// Emitted by Vision_infer. The posterior this model implies is
// computed analytically in OCaml; Stan's role is to CHECK that, not to
// produce it — an MCMC estimate would differ run to run and could not
// be an expect-tested value.
data {
  int<lower=0> runs;
  int<lower=0> passes;
}
parameters {
  real<lower=0, upper=1> rate;
}
model {
  rate ~ beta(0.5, 0.5);      // Jeffreys
  passes ~ binomial(runs, rate);
}
|}

let stanc_path = "vendor/cmdstan/bin/stanc"

let stan_available () = Sys.file_exists stanc_path

let stan_check () =
  if not (stan_available ()) then
    (* Unavailable is disclosed, never a quiet pass and never agreement *)
    Error ("cmdstan is not built: " ^ stanc_path ^ " is absent")
  else
    let tmp = Filename.temp_file "vision-rate" ".stan" in
    let oc = open_out tmp in
    output_string oc stan_model;
    close_out oc;
    let cmd = Printf.sprintf "timeout 60 %s --o=/dev/null %s 2>&1" stanc_path (Filename.quote tmp) in
    let ic = Unix.open_process_in cmd in
    let buf = Buffer.create 1024 in
    (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
    let st = try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127 in
    (try Sys.remove tmp with _ -> ());
    match st with
    | Unix.WEXITED 0 -> Ok "stanc accepts the model the analytic posterior implements"
    | _ -> Error ("stanc refused the model: " ^ String.trim (Buffer.contents buf))
