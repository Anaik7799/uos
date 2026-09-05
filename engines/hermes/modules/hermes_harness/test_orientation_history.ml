(* The store's laws. R3 is the contract: history is append-only, an identical
   replay is a no-op, a divergent replay is refused and the refusal names the
   hazard. Every property carries a negative control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let contains text needle =
  let n = String.length needle in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
  in
  at 0

let with_store f =
  let path = Filename.temp_file "orientation-" ".sqlite3" in
  Sys.remove path;
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      match Orientation_history.open_store path with
      | Error m -> check false ("open_store :: " ^ m)
      | Ok store ->
          Fun.protect ~finally:(fun () -> Orientation_history.close store) (fun () -> f store))


(* ------------------------------------------------- calibration samples *)

let () =
  with_store (fun store ->
      let rec_sample id p o realised =
        Orientation_history.record_sample store ~sample_id:id ~path_changed:p
          ~output_changed:o ~predicted:"silent-divergence" ~realised
          ~labelled_by:"test" ~recorded_at:"2026-08-12T00:00:00Z"
      in
      (match rec_sample "s1" true false "silent-divergence" with
      | Error m -> check false ("sample write :: " ^ m)
      | Ok () -> incr passed);
      (* Idempotent replay, same discipline as the history (R3). *)
      (match rec_sample "s1" true false "silent-divergence" with
      | Error m -> check false ("sample replay :: " ^ m)
      | Ok () -> incr passed);
      (match rec_sample "s2" false true "regressed" with
      | Error m -> check false ("second sample :: " ^ m)
      | Ok () -> incr passed);
      match Orientation_history.samples store with
      | Error m -> check false ("samples read :: " ^ m)
      | Ok rows ->
          check (List.length rows = 2) "SAMPLES both rows survive, replay added none";
          check
            (List.mem (true, false, "silent-divergence") rows
             && List.mem (false, true, "regressed") rows)
            "SAMPLES features and label round-trip";
          (* The point of storing FEATURES rather than a stored verdict: the
             caller re-predicts with the CURRENT model, so model drift is
             detectable. Scoring here proves the wiring end to end. *)
          let samples =
            List.filter_map
              (fun (p, o, realised) ->
                let ev =
                  { Expect_posterior.site = "s"; cause = "c"; path_changed = p;
                    output_changed = o; churn = 0.5; mutation_kill_rate = 1.0 }
                in
                match
                  Expect_posterior.update ~prior:Expect_posterior.uniform_prior ev
                with
                | Ok predicted ->
                    let state =
                      List.find_opt
                        (fun s -> Expect_posterior.state_name s = realised)
                        Expect_posterior.states
                    in
                    Option.map
                      (fun realised -> { Expect_posterior.predicted; realized = realised })
                      state
                | Error _ -> None)
              rows
          in
          check (List.length samples = 2) "SAMPLES every row re-predicts under the live model";
          (match Expect_posterior.calibrate samples with
          | Error m -> check false ("calibrate :: " ^ m)
          | Ok c ->
              check (c.Expect_posterior.samples = 2) "CALIBRATION scores the stored samples";
              check (c.Expect_posterior.accuracy = 1.0)
                "CALIBRATION well-labelled samples score perfect accuracy";
              check c.Expect_posterior.beats_uniform
                "CALIBRATION a correct model beats the uniform baseline"))
let () =
  Printf.printf "=== orientation history ===\n";
  with_store (fun store ->
      let record = Orientation_history.record store ~head:"abc123" ~recorded_at:"2026-08-12T00:00:00Z" in
      (* Write, then read back — durability is a read, not a return code (R22). *)
      (match record ~pass_id:"pass-1" ~key:"battery" ~value:"57/57" with
      | Error m -> check false ("first write :: " ^ m)
      | Ok () -> incr passed);
      (* IDEMPOTENT REPLAY: same (pass, key, payload) is a no-op. *)
      (match record ~pass_id:"pass-1" ~key:"battery" ~value:"57/57" with
      | Error m -> check false ("idempotent replay :: " ^ m)
      | Ok () -> incr passed);
      (* DIVERGENT REPLAY: refused, and the refusal names the discipline. *)
      (match record ~pass_id:"pass-1" ~key:"battery" ~value:"56/57" with
      | Ok () -> check false "R3 a divergent replay must be refused"
      | Error m ->
          check true "R3 a divergent replay is refused";
          check (contains m "HZ-CTL-01") "R3 the refusal names its hazard");
      (* A second pass updates STATE while history keeps both. *)
      (match record ~pass_id:"pass-2" ~key:"battery" ~value:"58/58" with
      | Error m -> check false ("second pass :: " ^ m)
      | Ok () -> incr passed);
      (match Orientation_history.state store with
      | Error m -> check false ("state :: " ^ m)
      | Ok rows ->
          check
            (List.exists (fun (k, v, p, _) -> k = "battery" && v = "58/58" && p = "pass-2") rows)
            "STATE carries the latest pass's value";
          check
            (not (List.exists (fun (_, v, _, _) -> v = "57/57") rows))
            "STATE does not carry the superseded value");
      (match Orientation_history.history store ~pass_id:"pass-1" with
      | Error m -> check false ("history :: " ^ m)
      | Ok rows ->
          check
            (List.exists (fun (k, v, _, _) -> k = "battery" && v = "57/57") rows)
            "HISTORY preserves the superseded value under its pass");
      (match Orientation_history.counts store with
      | Error m -> check false ("counts :: " ^ m)
      | Ok (state_n, history_n, passes) ->
          check (state_n = 1 && history_n = 2 && passes = 2)
            (Printf.sprintf "COUNTS balance (state %d, history %d, passes %d)" state_n
               history_n passes));
      (* Determinism: two reads render identically. *)
      (match (Orientation_history.state store, Orientation_history.state store) with
      | Ok a, Ok b -> check (a = b) "READ is deterministic"
      | _ -> check false "READ determinism"));
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_orientation_history" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_orientation_history ]);
  exit (Suite_telemetry.exit_code self)
