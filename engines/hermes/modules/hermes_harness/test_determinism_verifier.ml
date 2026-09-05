(* The load-bearing property: the verifier must CATCH a non-deterministic
   producer. A gate that always reports "stable" is worse than none. So the test
   drives a deliberately flaky producer and asserts it is flagged, plus that a
   genuinely stable producer passes with a real digest. *)

let normalizer = Parity_normalizer.default

let () =
  let open Determinism_verifier in
  (* A stable producer: same value every call. *)
  (match check ~normalizer (fun () -> `Assoc [ ("x", `Int 1); ("y", `String "z") ]) with
  | Stable digest ->
      assert (String.length digest = 64);
      assert (to_diagnostic ~scenario_id:"s" ~node:"n" (Stable digest) = None)
  | Unstable _ -> failwith "a stable producer must be Stable");

  (* A flaky producer: a different value each call. The verifier must flag it. *)
  let counter = ref 0 in
  let flaky () =
    incr counter;
    `Assoc [ ("n", `Int !counter) ]
  in
  (match check ~normalizer flaky with
  | Unstable { first; second } ->
      assert (first <> second);
      (match to_diagnostic ~scenario_id:"flaky" ~node:"hermes.apparatus" (Unstable { first; second }) with
      | Some d ->
          assert (d.Fractal_diagnostic.origin = Fractal_diagnostic.Control);
          assert (d.Fractal_diagnostic.impact = Fractal_diagnostic.Blocks_credit);
          assert (Fractal_diagnostic.hazard d.Fractal_diagnostic.hazard <> None)
      | None -> failwith "an unstable verdict must produce a diagnostic")
  | Stable _ -> failwith "the verifier must catch a flaky producer");

  print_endline "determinism_verifier: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_determinism_verifier" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_determinism_verifier ]);
  exit (Suite_telemetry.exit_code self)
