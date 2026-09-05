(* The full-fractal controller sweep: each leg must be differential (a healthy
   input and a faulty input yield DIFFERENT alerts), regressions dominate, and
   unsensed levels are visible. Pure throughout. *)

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

let has_sub text needle =
  let n = String.length needle and l = String.length text in
  let rec loop i = i + n <= l && (String.sub text i n = needle || loop (i + 1)) in
  n = 0 || loop 0

let is_green (leg : Control_plane.leg) = leg.Control_plane.alert = Homeostasis.Green
let is_p0 (leg : Control_plane.leg) =
  match leg.Control_plane.alert with Homeostasis.P0 _ -> true | _ -> false
let is_p1 (leg : Control_plane.leg) =
  match leg.Control_plane.alert with Homeostasis.P1 _ -> true | _ -> false
let is_p2 (leg : Control_plane.leg) =
  match leg.Control_plane.alert with Homeostasis.P2 _ -> true | _ -> false
let detail (leg : Control_plane.leg) =
  match leg.Control_plane.alert with
  | Homeostasis.Green -> ""
  | Homeostasis.P2 d | Homeostasis.P1 d | Homeostasis.P0 d -> d

(* Healthy history: two scenarios, both stable-passing across two runs. *)
let healthy =
  [ ("model_routing.gemini_adapter.tool_schema", "gemini.schema", true);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", true);
    ("model_routing.gemini_adapter.tool_schema", "gemini.schema", true);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", true) ]

(* gemini.schema passed in run 1, fails in run 2: a cross-run regression. *)
let regressed =
  [ ("model_routing.gemini_adapter.tool_schema", "gemini.schema", true);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", true);
    ("model_routing.gemini_adapter.tool_schema", "gemini.schema", false);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", true) ]

(* budget.exhaust flaps: pass, fail, pass. *)
let flapping =
  [ ("agent_loop.interrupt_control.budget", "budget.exhaust", true);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", false);
    ("agent_loop.interrupt_control.budget", "budget.exhaust", true) ]

let () =
  (* L0 *)
  check "L0 healthy frontier is green"
    (is_green (Control_plane.l0_frontier ~counts:[ 5; 6; 7 ] ~total:8));
  check "L0 shrink is P0" (is_p0 (Control_plane.l0_frontier ~counts:[ 6; 5 ] ~total:8));
  (* L1 *)
  let l1_healthy = Control_plane.l1_regressions ~history:healthy in
  let l1_bad = Control_plane.l1_regressions ~history:regressed in
  check "L1 healthy is green" (is_green l1_healthy);
  check "L1 regression is P0" (is_p0 l1_bad);
  check "L1 names the family" (has_sub (detail l1_bad) "model_routing");
  check "L1 names the scenario" (has_sub (detail l1_bad) "gemini.schema");
  check "L1 differential: healthy and regressed differ"
    (l1_healthy.Control_plane.alert <> l1_bad.Control_plane.alert);
  (* L2 *)
  let l2_flap = Control_plane.l2_flaps ~history:flapping in
  check "L2 healthy is green" (is_green (Control_plane.l2_flaps ~history:healthy));
  check "L2 flap is P1 quarantine candidate" (is_p1 l2_flap);
  check "L2 names the flapping scenario" (has_sub (detail l2_flap) "budget.exhaust");
  check "L2 recovery (fail then pass) is a P2 note"
    (is_p2
       (Control_plane.l2_flaps
          ~history:[ ("a.b.c", "s.one", false); ("a.b.c", "s.one", true) ]));
  (* L3 *)
  check "L3 oracle present is green" (is_green (Control_plane.l3_contract_oracle ~available:true));
  check "L3 oracle absent is P1"
    (is_p1 (Control_plane.l3_contract_oracle ~available:false));
  (* L4 *)
  check "L4 current receipts are green"
    (is_green
       (Control_plane.l4_receipt_currency ~receipts_revision:(Some "abc123") ~current:"abc123"));
  check "L4 no receipts yet is green here (coverage is L6's finding)"
    (is_green (Control_plane.l4_receipt_currency ~receipts_revision:None ~current:"abc123"));
  (let stale =
     Control_plane.l4_receipt_currency ~receipts_revision:(Some "abc123def") ~current:"fff999aaa"
   in
   check "L4 stale receipts are P2 lead-time" (is_p2 stale);
   check "L4 names both revisions"
     (has_sub (detail stale) "abc123d" && has_sub (detail stale) "fff999a"));
  (* L6 *)
  check "L6 full coverage is green"
    (is_green (Control_plane.l6_observation_coverage ~recorded:28 ~corpus:28));
  check "L6 gap is P2"
    (is_p2 (Control_plane.l6_observation_coverage ~recorded:27 ~corpus:28));
  check "L6 MORE recorded than corpus is P1 (stale corpus registry sensor)"
    (is_p1 (Control_plane.l6_observation_coverage ~recorded:29 ~corpus:28));
  (* LX *)
  check "LX satisfied envelope is green" (is_green (Control_plane.lx_envelope ~satisfied:true));
  check "LX unsatisfied envelope is P0"
    (is_p0 (Control_plane.lx_envelope ~satisfied:false))

let () =
  (* Windowing (the c3i last-10 rule): ancient history must age out, or a
     recovery note from months ago is permanent noise (muda). *)
  let ancient_recovery =
    ("a.b.c", "s.old", false)
    :: List.init 10 (fun _ -> ("a.b.c", "s.old", true))
  in
  check "an old transition beyond the window ages out (no permanent note)"
    (is_green (Control_plane.l2_flaps ~history:ancient_recovery));
  let ancient_pass_then_fail_now =
    ("a.b.c", "s.reg", true)
    :: List.init 9 (fun _ -> ("a.b.c", "s.reg", false))
    @ [ ("a.b.c", "s.reg", false) ]
  in
  check
    "a pass older than the window no longer counts as regression evidence \
     (the window is the sensor's memory)"
    (is_green (Control_plane.l1_regressions ~history:ancient_pass_then_fail_now));
  check "a recent regression inside the window still fires"
    (is_p0
       (Control_plane.l1_regressions
          ~history:
            (List.init 5 (fun _ -> ("a.b.c", "s.r2", true))
            @ [ ("a.b.c", "s.r2", false) ])))

let () =
  (* Composition: worst + render + unsensed visibility. *)
  let sweep =
    Control_plane.
      { legs =
          [ l0_frontier ~counts:[ 7; 7 ] ~total:8;
            l1_regressions ~history:regressed;
            l2_flaps ~history:healthy ];
        unsensed = [ ("L5 trace", "normalizer-version sensor queued") ] }
  in
  check "worst finds the P0 through the sweep" (Control_plane.worst sweep = (match (Control_plane.l1_regressions ~history:regressed).Control_plane.alert with a -> a));
  let lines = Control_plane.render sweep in
  check "render emits one line per leg plus unsensed"
    (List.length lines = 4);
  check "render shows the unsensed level and reason"
    (List.exists (fun line -> has_sub line "L5 trace" && has_sub line "queued") lines);
  check "worst of an empty sweep is Green"
    (Control_plane.worst { Control_plane.legs = []; unsensed = [] } = Homeostasis.Green)

let () =
  Printf.printf "control_plane: passed: %d failed: %d\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_control_plane" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_control_plane ]);
  exit (Suite_telemetry.exit_code self)
