(* The R30 adoption ratchet — the actuator the ACH said was missing.

   Counts test files under modules/ that do NOT reference Suite_telemetry and
   compares against the pin in baseline/r30-adoption.txt. EQUALITY-STRICT in
   both directions, on the rule-count precedent (test_ops_capability's
   List.init 30): a declared denominator moves WITH reality.

     current > pin   regression — a non-emitting suite was added, or emission
                     was removed. The count may only fall.
     current < pin   progress — lower the pin IN THE SAME COMMIT, or the
                     ratchet develops slack a later regression can hide in.
     current = pin   holds.

   R19: the pin is read fail-closed (absent or unparseable pin is a refusal,
   never a pass), the scan proves it is at the workspace root before trusting
   a relative path, and the verdict is the real exit code.

   This suite is ABOUT adoption, so it adopts: it emits its own AS-IS and
   PREDICTIVE block through the adapter it measures. Its blast radius is
   every suite, which is stated rather than enumerated. *)

let pin_path = "modules/hermes_harness/baseline/r30-adoption.txt"

let refuse message =
  prerr_endline ("test_r30_adoption: " ^ message);
  exit 1

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let contains text needle =
  let n = String.length needle in
  let rec at i =
    i + n <= String.length text && (String.sub text i n = needle || at (i + 1))
  in
  at 0

(* The census: every test_*.ml under modules/, and whether it references the
   adapter. Pure OCaml recursion — no shell (R1). *)
let census () =
  let emitting = ref 0 and silent = ref [] in
  let rec walk dir =
    match Sys.readdir dir with
    | exception Sys_error _ -> ()
    | entries ->
        Array.iter
          (fun name ->
            let path = Filename.concat dir name in
            if Sys.is_directory path then walk path
            else if
              String.length name > 8
              && String.sub name 0 5 = "test_"
              && Filename.check_suffix name ".ml"
            then
              let text = read_file path in
              (* TWO adapters, one census. The wiki converts through
                 Wiki_suite_telemetry — an R14 mirror, because the guard law
                 forbids hermes_harness_* inside wiki Dune files and preserves
                 the wiki-below-harness dependency direction. "Suite_telemetry" is NOT a
                 substring of "Wiki_suite_telemetry", so a single needle
                 counted 42 genuinely converted suites as silent: a gauge
                 measuring the wrong thing, which is the exact defect class
                 this session exists to refuse. Both names, explicitly. *)
              if contains text "Suite_telemetry" || contains text "Wiki_suite_telemetry"
              then incr emitting
              else silent := path :: !silent)
          entries
  in
  walk "modules";
  (!emitting, List.sort compare !silent)

let () =
  (* R19 clause 5: prove the cwd before trusting a relative scan. *)
  if not (Sys.file_exists "dune-project" && Sys.is_directory "modules") then
    refuse "not at the workspace root (no ./dune-project + ./modules); refusing to scan";
  let pin =
    if not (Sys.file_exists pin_path) then
      refuse ("no pin at " ^ pin_path ^ " — an absent pin must never read as a pass")
    else
      match int_of_string_opt (String.trim (read_file pin_path)) with
      | Some n when n >= 0 -> n
      | _ -> refuse ("unparseable pin in " ^ pin_path)
  in
  let emitting, silent = census () in
  let current = List.length silent in
  let verdict_failures =
    if current > pin then begin
      Printf.printf
        "RATCHET BREACHED: %d non-emitting suite(s) against a pin of %d — the count may \
         only fall. New or regressed:\n"
        current pin;
      (* Name candidates so the fix is a lookup, not a hunt: print a bounded
         sample of the silent set. *)
      List.iteri (fun i p -> if i < 10 then Printf.printf "  %s\n" p) silent;
      1
    end
    else if current < pin then begin
      Printf.printf
        "RATCHET SLACK: %d non-emitting suite(s) against a pin of %d — progress must \
         tighten the pin in the same commit. Set %s to %d.\n"
        current pin pin_path current;
      1
    end
    else begin
      Printf.printf "ratchet holds: %d non-emitting, %d emitting, pin %d\n" current
        emitting pin;
      0
    end
  in
  let self =
    Suite_telemetry.observe ~suite:"test_r30_adoption" ~passed:(if verdict_failures = 0 then 1 else 0)
      ~failed:verdict_failures ~skipped:0
  in
  print_string
    (Suite_telemetry.as_is self
    ^ Printf.sprintf
        "PREDICTIVE test_r30_adoption: every suite is in this gauge's cone (%d silent + %d \
         emitting); a wrong pin here miscounts R30 convergence itself\n"
        current emitting);
  exit (Suite_telemetry.exit_code self)
