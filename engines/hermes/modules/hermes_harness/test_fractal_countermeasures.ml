(* Battle-testing the fractal countermeasures.

   Two things make this table trustworthy rather than decorative: it is COMPLETE
   (every hazard that can grant false parity, and every resource hazard, has a
   response) and it is SAFE (nothing destructive is marked automatic). Both are
   enforced here, so a new hazard with no countermeasure, or a countermeasure
   that would auto-delete evidence, fails the suite. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

let contains text needle =
  let length = String.length text and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= length
    && (String.sub text index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  let open Fractal_countermeasures in
  check (countermeasures <> []) "UNIT countermeasures exist" "";
  check (for_hazard "HZ-RES-TEMP" <> None) "UNIT lookup finds a countermeasure" "";
  check (for_hazard "HZ-RES-KERNEL" <> None)
    "UNIT kernel supervision shortfall has a countermeasure" "";
  check (for_hazard "HZ-NOPE" = None) "UNIT lookup rejects unknown" "";
  List.iter
    (fun countermeasure ->
      check (String.length (render countermeasure) > 10) "UNIT render is non-trivial"
        countermeasure.hazard)
    countermeasures

(* -------------------------------------------------------- STRUCTURE layer *)
(* Completeness and safety -- the two invariants that make this an artifact. *)

let structure_layer () =
  let open Fractal_countermeasures in
  (* Completeness: no required hazard is left without a response. This is derived
     from the hazard analysis, so adding an H-1 or resource hazard without a
     countermeasure fails here. *)
  check (uncovered () = []) "STRUCTURE every required hazard has a countermeasure"
    (String.concat "," (uncovered ()));

  (* Every countermeasure names a hazard that actually exists in the analysis: a
     typo'd id would make the table lie. *)
  List.iter
    (fun countermeasure ->
      check
        (Fractal_diagnostic.hazard countermeasure.hazard <> None)
        "STRUCTURE a countermeasure names a real hazard" countermeasure.hazard)
    countermeasures;

  (* Safety: the destructive or trust-changing responses must be Manual. Auto
     freeing disk, auto-writing the store, or auto-fetching the reference would
     each be a worse failure than the shortfall. *)
  List.iter
    (fun id ->
      match for_hazard id with
      | Some countermeasure ->
          check (not (is_automatic countermeasure))
            ("STRUCTURE " ^ id ^ " is manual, not auto (it is destructive/trust-changing)")
            id
      | None -> check false ("STRUCTURE " ^ id ^ " has a countermeasure") "")
    [ "HZ-RES-DISK"; "HZ-RES-DB"; "HZ-RES-REF"; "HZ-RES-KERNEL" ];

  (* At least one response IS safe to automate, or the automatic/manual
     distinction is doing no work. *)
  check
    (List.exists is_automatic countermeasures)
    "STRUCTURE at least one countermeasure is automatic" "";

  (* Ids are unique: two responses to one hazard is an ambiguous instruction. *)
  let ids = List.map (fun c -> c.hazard) countermeasures in
  check
    (List.length (List.sort_uniq compare ids) = List.length ids)
    "STRUCTURE countermeasure hazards are unique" ""

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  let open Fractal_countermeasures in
  List.iter
    (fun countermeasure ->
      match countermeasure.action with
      | Automatic { command; rationale } ->
          check
            (String.trim command <> "" && String.length rationale > 20)
            "PROPERTY an automatic action states a command and why it is safe"
            countermeasure.hazard
      | Manual reason ->
          check (String.length reason > 20) "PROPERTY a manual action gives substantive advice"
            countermeasure.hazard)
    countermeasures;

  (* The detect field is always populated: a countermeasure you cannot recognise
     the trigger for is not actionable. *)
  List.iter
    (fun countermeasure ->
      check (String.length countermeasure.detect > 20) "PROPERTY a countermeasure states its trigger"
        countermeasure.hazard)
    countermeasures

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  let open Fractal_countermeasures in
  (* Given a full temp filesystem, when the countermeasure is consulted, then it
     is automatic: relocating scratch to the project disk destroys nothing. *)
  (match for_hazard "HZ-RES-TEMP" with
  | Some countermeasure ->
      check (is_automatic countermeasure) "BDD a full temp fs has a safe automatic response" "";
      check (contains (render countermeasure) "TMPDIR")
        "BDD the temp countermeasure relocates TMPDIR" (render countermeasure)
  | None -> check false "BDD a full temp fs has a countermeasure" "");

  (* Given a full project disk, the response is manual and says why it is not
     automated: the harness must not delete files. *)
  (match for_hazard "HZ-RES-DISK" with
  | Some { action = Manual reason; _ } ->
      check (contains reason "never" || contains reason "delete")
        "BDD the disk countermeasure refuses to auto-delete" reason
  | _ -> check false "BDD a full disk has a manual countermeasure" "");

  (* Kernel isolation cannot be provisioned safely by changing the running
     process.  The response is an explicit platform/worker decision, never an
     automatic permission or limit mutation. *)
  (match for_hazard "HZ-RES-KERNEL" with
  | Some { action = Manual reason; _ } ->
      check
        (contains reason "kernel" || contains reason "platform"
        || contains reason "worker")
        "BDD a missing kernel capability has manual platform guidance" reason
  | _ -> check false "BDD a missing kernel capability has a manual countermeasure" "")

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  let open Fractal_countermeasures in
  (* The completeness detector must actually fire on a gap, or it is proving
     nothing. A synthetic required-set with an uncovered id is flagged. *)
  let synthetic = [ "HZ-RES-TEMP"; "HZ-FAKE-999" ] in
  let missing = List.filter (fun id -> for_hazard id = None) synthetic in
  check (missing = [ "HZ-FAKE-999" ]) "CHAOS a missing countermeasure is detected"
    (String.concat "," missing);

  (* Lookup of a clearly-bogus id is None, not a crash. *)
  check (for_hazard "" = None) "CHAOS empty-id lookup is None" ""

let () =
  print_endline "fractal countermeasures suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("structure", structure_layer); ("property", property_layer);
      ("bdd", bdd_layer); ("chaos", chaos_layer) ];
  Printf.printf "\ncountermeasures: %d   passed: %d   failed: %d\n"
    (List.length Fractal_countermeasures.countermeasures)
    !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_fractal_countermeasures" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_fractal_countermeasures ]);
  exit (Suite_telemetry.exit_code self)
