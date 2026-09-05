(* Benchmark: the OCaml Hermes_rete engine vs the embedded Rust GRL engine over
   the drift-diagnosis workload, at increasing fact volumes. Performance and
   scalability evidence for the integration doc -- honest caveats: the Rust path
   pays JSON serialization both ways across the FFI and re-parses the GRL per
   call (a per-call knowledge-base build), while the OCaml path is in-process
   values; this measures the INTEGRATION as used, not the engines' cores. *)

let time label f =
  let start = Unix.gettimeofday () in
  let result = f () in
  let elapsed = Unix.gettimeofday () -. start in
  Printf.printf "  %-34s %8.3f ms\n" label (elapsed *. 1000.0);
  result

let ocaml_run n =
  let open Hermes_rete in
  let wm = WM.create () in
  for i = 1 to n do
    WM.insert wm "drift"
      [ ("target", Value.String (Printf.sprintf "hermes.x.t%d" i));
        ("actual", Value.String (if i mod 2 = 0 then "divergent" else "unmapped")) ]
  done;
  let fired = ref 0 in
  let rule =
    { name = "divergent";
      patterns =
        [ { pat_kind = "drift";
            conds = [ FieldCmp ("actual", Eq, Value.String "divergent") ];
            bind_name = Some "d" } ];
      action = (fun _ _ -> incr fired; Ok ()) }
  in
  (match fire_rules wm [ rule ] with Ok () -> () | Error e -> failwith e);
  !fired

let rust_run n =
  (* One fact object per call (the engine keys facts by name); driven n times --
     the integration's real per-drift usage shape. *)
  let grl =
    {|rule F "f" { when Drift.Actual == "divergent" then Drift.Advice = "fix"; }|}
  in
  let fired = ref 0 in
  for i = 1 to n do
    let facts =
      `Assoc
        [ ("Drift",
           `Assoc
             [ ("Actual", `String (if i mod 2 = 0 then "divergent" else "unmapped"));
               ("Advice", `String "none") ]) ]
    in
    match Rust_rules.eval ~grl ~facts with
    | Ok r -> if r.rules_fired > 0 then incr fired
    | Error e -> failwith e
  done;
  !fired

let () =
  Printf.printf "rule-engine benchmark (drift workload; median-free single shot, warm)\n\n";
  List.iter
    (fun n ->
      Printf.printf "n = %d drifts\n" n;
      let expect = n / 2 in
      let ocaml_fired = time (Printf.sprintf "ocaml hermes_rete (%d facts, 1 call)" n)
          (fun () -> ocaml_run n) in
      let rust_fired = time (Printf.sprintf "rust  grl engine  (%d calls via FFI)" n)
          (fun () -> rust_run n) in
      (* Result identity, the zigvm bench discipline: both engines agree on the
         number of divergent drifts before any timing is trusted. *)
      if ocaml_fired <> expect || rust_fired <> expect then begin
        Printf.printf "  RESULT MISMATCH ocaml=%d rust=%d expect=%d\n" ocaml_fired rust_fired
          expect;
        exit 1
      end;
      Printf.printf "\n")
    [ 10; 100; 1000 ];
  Printf.printf "result identity holds at every volume (ocaml = rust = n/2)\n"
