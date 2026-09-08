(* Battle-testing the resource-envelope preflight.

   The property that matters is not "does it read df" but "can this ever let an
   operation proceed into a resource it has not got". The whole point is to turn
   a mid-run ENOSPC into a clean, named preflight refusal, so every layer here
   pushes on the fail-closed direction: an unknown resource, a mismatched
   observation, a hostile number must all resolve to UNMET, never to "fine".

   The pure core is exercised exhaustively and deterministically.  Operational
   observation is an R31-controlled effect and is intentionally unavailable in
   this module until an opaque owner receipt can be injected; the feature and
   chaos layers prove that this absence refuses rather than probing the host. *)

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

let starts_with value prefix =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

(* Byte helpers. On a 64-bit OCaml int these never overflow. *)
let mib n = n * 1024 * 1024
let gib n = n * 1024 * 1024 * 1024

let trace_id = String.make 32 'a'
let span_id = String.make 16 'b'

let sample_identity : Resource_envelope.executable_identity = { device = 17; inode = 29 }

let all_resource_shapes =
  [ Resource_envelope.Temp_space { bytes_needed = mib 200; margin = 0.20 };
    Resource_envelope.Disk_space { path = "."; bytes_needed = gib 1; margin = 0.20 };
    Resource_envelope.Binary { name = "sh"; env_var = None };
    Resource_envelope.Exact_executable { path = "/bin/sh"; expected = sample_identity };
    Resource_envelope.Kernel_capability Resource_envelope.Proc_self_fd_executable;
    Resource_envelope.Kernel_capability Resource_envelope.Rlimit_as;
    Resource_envelope.Kernel_capability Resource_envelope.Process_group_signalling;
    Resource_envelope.Writable "/nonexistent-writable-xyz/file";
    Resource_envelope.Frozen_reference { root = "/nonexistent-frozen-xyz" } ]

(* ------------------------------------------------------------- UNIT layer *)
(* The pure margin-and-floor arithmetic, at its exact boundaries. *)

let unit_layer () =
  let open Resource_envelope in
  (* A 10 GiB need with a 20% margin requires 12 GiB, and the floor is trivially
     satisfied at these sizes, so this isolates the margin condition. *)
  let big = Disk_space { path = "/x"; bytes_needed = gib 10; margin = 0.20 } in
  check (evaluate big (Space { available_bytes = gib 12 })).met
    "UNIT margin is met exactly at the threshold" "";
  check
    (not (evaluate big (Space { available_bytes = gib 12 - mib 200 })).met)
    "UNIT margin is unmet just below the threshold" "";
  check
    (contains (evaluate big (Space { available_bytes = gib 11 })).detail "headroom")
    "UNIT a margin shortfall names headroom"
    (evaluate big (Space { available_bytes = gib 11 })).detail;

  (* A small need with plenty of proportional headroom, but so little absolute
     space left that the floor -- not the percentage -- must refuse it. This is
     the case the design says a percentage margin alone would wave through. *)
  let small = Disk_space { path = "/x"; bytes_needed = mib 100; margin = 0.20 } in
  check
    (not (evaluate small (Space { available_bytes = mib 200 })).met)
    "UNIT the absolute floor refuses a small need with tiny space left" "";
  check
    (contains (evaluate small (Space { available_bytes = mib 200 })).detail "floor")
    "UNIT a floor shortfall names the floor"
    (evaluate small (Space { available_bytes = mib 200 })).detail;
  (* floor is 512 MiB: needed 100 MiB + floor 512 MiB = 612 MiB is the exact
     boundary at which the floor is satisfied. *)
  check
    (evaluate small (Space { available_bytes = mib 612 })).met
    "UNIT the floor is met exactly at need + floor" "";
  check
    (not (evaluate small (Space { available_bytes = mib 611 })).met)
    "UNIT one byte under the floor boundary is unmet" "";

  (* An unknown observation is never treated as satisfied. *)
  check
    (not (evaluate small (Unknown "df exited non-zero")).met)
    "UNIT an unknown observation is unmet" "";
  check
    (contains (evaluate small (Unknown "df exited non-zero")).detail "df exited non-zero")
    "UNIT an unknown observation carries its reason" "";

  check (floor_bytes = mib 512) "UNIT floor is 512 MiB" (string_of_int floor_bytes)

let numeric_domain_layer () =
  let open Resource_envelope in
  let verdict needed margin available =
    evaluate (Disk_space { path = "/numeric-fixture"; bytes_needed = needed; margin })
      (Space { available_bytes = available })
  in
  List.iter
    (fun (label, needed, margin, available) ->
      let result = verdict needed margin available in
      check (not result.met) ("NUMERIC " ^ label) result.detail;
      check (not (satisfied [result]))
        ("NUMERIC " ^ label ^ " never conveys authority") "")
    [ ("negative request", -1, 0.20, floor_bytes);
      ("negative margin", floor_bytes, -1.0, 2 * floor_bytes);
      ("negative infinite margin", floor_bytes, neg_infinity, 2 * floor_bytes);
      ("positive infinite margin", 0, infinity, floor_bytes);
      ("nan margin", 0, nan, floor_bytes);
      ("negative observed capacity", min_int, 0.20, -1);
      ("subtraction wrap", min_int, 0.0, max_int);
      ("invalid negative capacity", 0, 0.0, min_int) ];
  check (verdict 0 0.0 floor_bytes).met "NUMERIC zero request at floor" "";
  check (not (verdict 0 0.0 (floor_bytes - 1)).met)
    "NUMERIC zero request one byte below floor" "";
  check (verdict (max_int - floor_bytes) 0.0 max_int).met
    "NUMERIC full-width valid capacity remains supported" "";
  check (not (verdict max_int 0.0 max_int).met)
    "NUMERIC full-width request still needs floor" "";
  (* Capacity integer rounding must not hide a one-byte shortage. *)
  let needed = max_int / 4 in
  check (not (verdict needed 1.0 (needed * 2 - 1)).met)
    "NUMERIC exact large margin rejects one-byte shortage" "";
  check (verdict needed 1.0 (needed * 2)).met
    "NUMERIC exact large margin accepts equality" ""

(* Independent oracle: decompose IEEE-754 bits and compare integer products.
   It never calls Q.of_float or the implementation's resource arithmetic. *)
let numeric_oracle needed margin available =
  if needed < 0 || available < 0 || margin < 0.0
     || (match classify_float margin with FP_nan | FP_infinite -> true | _ -> false)
  then false
  else
    let bits = Int64.bits_of_float (1.0 +. margin) in
    let exponent = Int64.(to_int (logand (shift_right_logical bits 52) 0x7ffL)) - 1023 - 52 in
    let significand = Int64.(logor (logand bits 0xfffffffffffffL) 0x10000000000000L) in
    let request = Z.mul (Z.of_int needed) (Z.of_int64 significand) in
    let capacity = Z.of_int available in
    let capacity, request =
      if exponent < 0 then Z.shift_left capacity (-exponent), request
      else capacity, Z.shift_left request exponent in
    Z.compare capacity request >= 0
    && Z.compare (Z.sub (Z.of_int available) (Z.of_int needed))
         (Z.of_int Resource_envelope.floor_bytes) >= 0

let numeric_oracle_layer () =
  let open Resource_envelope in
  let values = [min_int; -1; 0; 1; floor_bytes - 1; floor_bytes; floor_bytes + 1;
    max_int / 4; max_int / 2; max_int - floor_bytes; max_int] in
  let margins = [neg_infinity; -1.0; -0.0; 0.0; Float.min_float; 0.20; 0.25;
    0.5; 1.0; 2.0; max_float; infinity; nan] in
  let compare_one needed margin available =
    let actual = evaluate (Temp_space {bytes_needed = needed; margin})
      (Space {available_bytes = available}) in
    let expected = numeric_oracle needed margin available in
    check (actual.met = expected) "ORACLE exact space decision"
      (Printf.sprintf "needed=%d margin=%.17g available=%d expected=%b actual=%b"
        needed margin available expected actual.met);
    check (not (satisfied [actual])) "ORACLE facts never mint receipts" ""
  in
  List.iter (fun needed -> List.iter (fun margin ->
    List.iter (compare_one needed margin) values) margins) values;
  (* Identically seeded generators feed oracle and final interpretations. *)
  List.iter (fun seed ->
    let initial = Random.State.make [|seed|] and final = Random.State.make [|seed|] in
    let generate state =
      let needed = Random.State.full_int state max_int in
      let available = Random.State.full_int state max_int in
      let margin = List.nth margins (Random.State.int state (List.length margins)) in
      needed, margin, available
    in
    for _ = 1 to 500 do
      let n, m, a = generate initial and n2, m2, a2 = generate final in
      let observed = evaluate (Disk_space {path="/seeded"; bytes_needed=n2; margin=m2})
        (Space {available_bytes=a2}) in
      check (observed.met = numeric_oracle n m a)
        ("TWIN-SEED " ^ string_of_int seed) ""
    done) [20260907; 1906]

let supervision_unit_layer () =
  let open Resource_envelope in
  let exact = Exact_executable { path = "/oracle"; expected = sample_identity } in
  let matching =
    Executable
      { identity = sample_identity; regular_file = true; executable = true }
  in
  check (evaluate exact matching).met
    "UNIT exact executable accepts the declared object identity" "";
  let exact_unmet observation = not (evaluate exact observation).met in
  check
    (exact_unmet
       (Executable
          { identity = { sample_identity with inode = sample_identity.inode + 1 };
            regular_file = true;
            executable = true }))
    "UNIT exact executable rejects an inode substitution" "";
  check
    (exact_unmet
       (Executable
          { identity = { sample_identity with device = sample_identity.device + 1 };
            regular_file = true;
            executable = true }))
    "UNIT exact executable rejects a device substitution" "";
  check
    (exact_unmet
       (Executable
          { identity = sample_identity; regular_file = false; executable = true }))
    "UNIT exact executable must be a regular file" "";
  check
    (exact_unmet
       (Executable
          { identity = sample_identity; regular_file = true; executable = false }))
    "UNIT exact executable must be executable" "";
  List.iter
    (fun capability ->
      let resource = Kernel_capability capability in
      check
        (evaluate resource (Capability { capability; supported = true })).met
        "UNIT a matching supported kernel capability is met"
        (describe_resource resource);
      check
        (not (evaluate resource (Capability { capability; supported = false })).met)
        "UNIT an unsupported kernel capability is unmet"
        (describe_resource resource);
      check (not (evaluate resource (Unknown "probe unavailable")).met)
        "UNIT an unknown kernel capability is unmet"
        (describe_resource resource))
    [ Proc_self_fd_executable; Rlimit_as; Process_group_signalling ];
  check
    (not
       (evaluate (Kernel_capability Rlimit_as)
          (Capability { capability = Process_group_signalling; supported = true }))
         .met)
    "UNIT one kernel capability observation cannot satisfy another" ""

(* ---------------------------------------------------------- FEATURE layer *)
(* The production observer is unavailable until a controlled owner injects an
   opaque receipt.  Every operational resource therefore refuses, regardless
   of whether an ungoverned raw probe would probably succeed. *)

let feature_layer () =
  let open Resource_envelope in
  List.iter
    (fun resource ->
      let result = check_one resource in
      check (not result.met && not result.receipt_bound)
        "FEATURE every unowned operational observation refuses"
        (render_check result);
      check (contains result.detail "owner injection")
        "FEATURE refusal discloses the missing controlled owner" result.detail)
    all_resource_shapes;
  let checks = preflight all_resource_shapes in
  check (List.length checks = List.length all_resource_shapes)
    "FEATURE preflight preserves the declared denominator" "";
  check (not (satisfied checks))
    "FEATURE a non-empty envelope cannot pass without receipts" "";
  check (List.length (unmet_checks checks) = List.length checks)
    "FEATURE every unavailable observation remains in the unmet denominator" ""

(* -------------------------------------------------------------- BDD layer *)

let bdd_layer () =
  let open Resource_envelope in
  let r = Temp_space { bytes_needed = gib 1; margin = 0.20 } in
  (* Given free space just under the margin threshold, when evaluated, then the
     envelope is refused and the reason is headroom. *)
  let just_under = evaluate r (Space { available_bytes = gib 1 + mib 100 }) in
  check (not just_under.met) "BDD space under the margin threshold is refused" "";

  (* Given free space above the margin but below the floor, the refusal names
     the floor -- the backstop the margin is not. *)
  let above_margin_below_floor =
    evaluate (Temp_space { bytes_needed = mib 50; margin = 0.20 })
      (Space { available_bytes = mib 100 })
  in
  check (not above_margin_below_floor.met) "BDD space below the floor is refused" "";
  check (contains above_margin_below_floor.detail "floor")
    "BDD the floor refusal says so" above_margin_below_floor.detail;

  (* Given df could not answer, the envelope refuses rather than assuming space. *)
  check (not (evaluate r (Unknown "statvfs failed")).met)
    "BDD an unanswerable resource is refused" "";

  check
    (not
       (evaluate (Kernel_capability Rlimit_as)
          (Capability { capability = Rlimit_as; supported = false }))
         .met)
    "BDD an unsupported address-space limit blocks before worker launch" "";

  (* Given ample space, the envelope is satisfied. *)
  check (evaluate r (Space { available_bytes = gib 100 })).met
    "BDD ample space is satisfied" ""

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  let open Resource_envelope in
  let observations =
    [ Space { available_bytes = 0 }; Space { available_bytes = gib 1 };
      Space { available_bytes = -1 }; Presence true; Presence false;
      Executable { identity = sample_identity; regular_file = true; executable = true };
      Capability { capability = Rlimit_as; supported = true };
      Unknown "x" ]
  in
  (* P1: evaluate is total -- no (resource, observation) pairing, however
     nonsensical (a Presence fact for a space resource), makes it raise. *)
  let raised = ref 0 in
  List.iter
    (fun resource ->
      List.iter
        (fun obs -> try ignore (evaluate resource obs) with _ -> incr raised)
        observations)
    all_resource_shapes;
  check (!raised = 0) "PROPERTY evaluate never raises" (string_of_int !raised);

  (* P2: an unknown observation is unmet for every resource. Nothing was learned,
     so nothing may proceed. *)
  List.iter
    (fun resource ->
      check (not (evaluate resource (Unknown "unknowable")).met)
        "PROPERTY unknown is always unmet" (describe_resource resource))
    all_resource_shapes;

  (* P3: a mismatched observation kind (a Presence for a space resource, or a
     Space for a presence resource) is unmet, never accidentally satisfied. *)
  check (not (evaluate (Temp_space { bytes_needed = 1; margin = 0.0 }) (Presence true)).met)
    "PROPERTY a presence fact cannot satisfy a space resource" "";
  check (not (evaluate (Binary { name = "sh"; env_var = None }) (Space { available_bytes = gib 9 })).met)
    "PROPERTY a space fact cannot satisfy a presence resource" "";
  check
    (not
       (evaluate (Exact_executable { path = "/x"; expected = sample_identity })
          (Presence true))
         .met)
    "PROPERTY presence alone cannot satisfy exact executable identity" "";
  check
    (not
       (evaluate (Kernel_capability Proc_self_fd_executable)
          (Executable
             { identity = sample_identity; regular_file = true; executable = true }))
         .met)
    "PROPERTY executable identity cannot satisfy a kernel capability" "";

  (* P4: evaluate is deterministic. *)
  List.iter
    (fun resource ->
      let a = evaluate resource (Unknown "z") and b = evaluate resource (Unknown "z") in
      check (a = b) "PROPERTY evaluate is deterministic" (describe_resource resource))
    all_resource_shapes;

  (* P5, load-bearing: a resource shortfall can never deny parity credit. It
     blocks (nothing was proved about the candidate); it must never read as a
     divergence. And it is never an Implementation defect. *)
  List.iter
    (fun resource ->
      let unmet_check = evaluate resource (Unknown "shortfall") in
      match to_diagnostics [ unmet_check ] with
      | [ d ] ->
          check (d.impact = Fractal_diagnostic.Blocks_credit)
            "PROPERTY a resource shortfall blocks, never denies"
            (Fractal_diagnostic.effect_name d.impact);
          check (d.origin <> Fractal_diagnostic.Implementation)
            "PROPERTY a resource shortfall is never an implementation defect"
            (Fractal_diagnostic.origin_name d.origin);
          check (Fractal_diagnostic.hazard d.hazard <> None)
            "PROPERTY a resource diagnostic names a real hazard" d.hazard;
          check (d.message <> "" && d.cause <> "" && d.fix <> "")
            "PROPERTY a resource diagnostic is complete" d.hazard
      | other ->
          check false "PROPERTY an unmet check yields exactly one diagnostic"
            (string_of_int (List.length other)))
    all_resource_shapes;

  (* P6: a met check produces no diagnostic -- silence is only for real success. *)
  let met_check = evaluate (Disk_space { path = "/x"; bytes_needed = 1; margin = 0.0 })
                    (Space { available_bytes = gib 100 }) in
  check met_check.met "PROPERTY the setup check is actually met" "";
  check (to_diagnostics [ met_check ] = []) "PROPERTY a met check yields no diagnostic" ""

(* ------------------------------------------------------------- OTEL layer *)

let otel_layer () =
  let open Resource_envelope in
  let unmet_check =
    evaluate (Temp_space { bytes_needed = gib 1; margin = 0.20 }) (Unknown "df failed")
  in
  match to_diagnostics [ unmet_check ] with
  | [ d ] ->
      let record =
        Fractal_diagnostic.to_otlp_log ~time_unix_nano:1L ~trace_id ~span_id d
      in
      let text = Yojson.Safe.to_string record in
      check (Yojson.Safe.from_string text = record) "OTEL resource record round-trips" "";
      List.iter
        (fun key -> check (contains text key) ("OTEL attribute " ^ key) "")
        [ "hermes.fractal.level"; "hermes.rca.origin"; "hermes.parity.effect";
          "hermes.hazard" ];
      (* A resource shortfall is a WARN (13): unproven, not broken. *)
      check (contains text "\"severityNumber\":13") "OTEL a shortfall is WARN severity" text
  | _ -> check false "OTEL setup produced no diagnostic" ""

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  let open Resource_envelope in
  Random.init 20260808;
  (* Random.int's bound must be < 2^30, so build wide/hostile magnitudes from a
     valid base rather than from max_int. *)
  let big () = Random.int 1_000_000_000 in
  let huge () = big () * (1 + Random.int 100) in
  let random_resource () =
    match Random.int 7 with
    | 0 -> Temp_space { bytes_needed = big () - big (); margin = Random.float 2.0 -. 0.5 }
    | 1 -> Disk_space { path = "/x"; bytes_needed = huge (); margin = Random.float 3.0 }
    | 2 -> Binary { name = String.init (Random.int 6) (fun _ -> Char.chr (97 + Random.int 5)); env_var = None }
    | 3 -> Writable (String.init (Random.int 6) (fun _ -> Char.chr (97 + Random.int 5)))
    | 4 -> Frozen_reference { root = "/x" }
    | 5 ->
        Exact_executable
          { path = "/x";
            expected = { device = big (); inode = big () } }
    | _ ->
        Kernel_capability
          (match Random.int 3 with
          | 0 -> Proc_self_fd_executable
          | 1 -> Rlimit_as
          | _ -> Process_group_signalling)
  in
  let random_obs () =
    match Random.int 6 with
    | 0 -> Space { available_bytes = big () - big () }
    | 1 -> Presence (Random.bool ())
    | 2 ->
        let choices = "abc \"\\\n" in
        Unknown (String.init (Random.int 8) (fun _ -> choices.[Random.int (String.length choices)]))
    | 3 ->
        Executable
          { identity = { device = big (); inode = big () };
            regular_file = Random.bool ();
            executable = Random.bool () }
    | 4 ->
        Capability
          { capability =
              (match Random.int 3 with
              | 0 -> Proc_self_fd_executable
              | 1 -> Rlimit_as
              | _ -> Process_group_signalling);
            supported = Random.bool () }
    | _ -> Space { available_bytes = 0 }
  in
  let survived = ref 0 in
  for _ = 1 to 500 do
    let resource = random_resource () and obs = random_obs () in
    match
      let c = evaluate resource obs in
      let _ = render_check c in
      let diags = to_diagnostics [ c ] in
      (* Every diagnostic produced must encode to OTLP without raising, whatever
         hostile content the resource path or reason contributed. *)
      List.for_all
        (fun d ->
          let e = Fractal_diagnostic.to_otlp_log ~time_unix_nano:0L ~trace_id ~span_id d in
          Yojson.Safe.from_string (Yojson.Safe.to_string e) = e)
        diags
    with
    | true -> incr survived
    | false -> check false "FUZZ a diagnostic failed to encode" ""
    | exception exn -> check false "FUZZ evaluate/encode raised" (Printexc.to_string exn)
  done;
  check (!survived = 500) "FUZZ 500 hostile resource evaluations survive"
    (string_of_int !survived)

(* ------------------------------------------------------------ CHAOS layer *)
(* Hostile declarations still refuse without raw IO.  This pins the interim
   R31 behavior: absence of a controlled observer is not permission to fall
   back to Sys, Unix, a shell command, or a direct filesystem probe. *)

let chaos_layer () =
  let open Resource_envelope in
  let no_crash label resource =
    match check_one resource with
    | c ->
        check (not c.met && not c.receipt_bound) label (render_check c);
        check (contains c.detail "not implemented")
          (label ^ " discloses unavailable observation") c.detail
    | exception exn -> check false (label ^ " (raised)") (Printexc.to_string exn)
  in
  no_crash "CHAOS a hostile disk declaration fails closed without probing"
    (Disk_space
       { path = "\000/../../untrusted";
         bytes_needed = 1_000_000_000_000_000_000;
         margin = max_float });
  no_crash "CHAOS an untrusted writable target fails closed without probing"
    (Writable "../../untrusted-store");
  no_crash "CHAOS an unregistered binary fails closed without PATH lookup"
    (Binary { name = "hermes-nope-zzz"; env_var = Some "UNDECLARED_OVERRIDE" });
  no_crash "CHAOS an executable identity cannot trigger a raw stat"
    (Exact_executable { path = "/proc/self/exe"; expected = sample_identity });
  no_crash "CHAOS a kernel request cannot trigger a procfs or signal probe"
    (Kernel_capability Process_group_signalling);
  no_crash "CHAOS a frozen reference cannot trigger a raw directory scan"
    (Frozen_reference { root = "../../untrusted-reference" })

(* -------------------------------------------------------- STRUCTURE layer *)

let structure_layer () =
  let open Resource_envelope in
  (* R31 migration gate: pure model facts remain useful for boundary/STPA
     proofs, but they are not operational observations and cannot satisfy a
     preflight without an owner-produced receipt.  Until that controlled owner
     exists the operational observer is explicitly unavailable. *)
  (match operational_status with
  | Implemented_unavailable reason ->
      check (reason <> "")
        "STRUCTURE the operational observer discloses Implemented_unavailable" reason);
  let model_only =
    evaluate (Disk_space { path = "/x"; bytes_needed = 1; margin = 0.0 })
      (Space { available_bytes = gib 100 })
  in
  check model_only.met "STRUCTURE pure evaluation still models a met fact" "";
  check (not model_only.receipt_bound)
    "STRUCTURE a caller-supplied fact is not a receipt-bound observation" "";
  check (not (satisfied [ model_only ]))
    "STRUCTURE model-only evidence cannot satisfy operational preflight" "";
  let unavailable = check_one (Binary { name = "sh"; env_var = None }) in
  check (not unavailable.met && not unavailable.receipt_bound)
    "STRUCTURE operational observation refuses until owner injection exists"
    (render_check unavailable);
  (* Every resource constructor, when unmet, maps to exactly one hazard-bearing
     diagnostic. Adding a constructor without classifying it fails here. *)
  List.iter
    (fun resource ->
      let unmet_check = evaluate resource (Unknown "for classification") in
      match to_diagnostics [ unmet_check ] with
      | [ d ] ->
          check (starts_with d.hazard "HZ-RES-")
            "STRUCTURE a resource shortfall names a resource hazard" d.hazard;
          check (Fractal_diagnostic.hazard d.hazard <> None)
            "STRUCTURE the named hazard exists in the analysis" d.hazard
      | other ->
          check false "STRUCTURE one unmet resource yields one diagnostic"
            (describe_resource resource ^ " -> " ^ string_of_int (List.length other)))
    all_resource_shapes;

  (* Every resource hazard in the analysis is fully specified and -- the
     invariant that keeps H-1 impossible from this quarter -- cannot grant false
     parity credit. A resource shortfall proves nothing about the candidate. *)
  let resource_hazards =
    List.filter
      (fun (h : Fractal_diagnostic.hazard) -> starts_with h.id "HZ-RES-")
      Fractal_diagnostic.hazards
  in
  check (resource_hazards <> []) "STRUCTURE resource hazards are registered" "";
  List.iter
    (fun (h : Fractal_diagnostic.hazard) ->
      check (not h.realises_h1)
        "STRUCTURE a resource hazard cannot realise H-1" h.id;
      check
        (h.unsafe_action <> "" && h.failure_mode <> "" && h.effect_if_undetected <> ""
       && h.detection <> "")
        "STRUCTURE a resource hazard is fully specified" h.id)
    resource_hazards;

  (* Pure checks preserve their semantic verdict, while operational folding
     refuses them because they carry no owner receipt. *)
  let met = evaluate (Disk_space { path = "/x"; bytes_needed = 1; margin = 0.0 })
              (Space { available_bytes = gib 100 }) in
  let unmet = evaluate (Temp_space { bytes_needed = 1; margin = 0.0 }) (Unknown "z") in
  check (not (satisfied [ met; met ]))
    "STRUCTURE model-only met checks do not satisfy operational preflight" "";
  check (not (satisfied [ met; unmet ])) "STRUCTURE one shortfall fails the envelope" "";
  check (List.length (unmet_checks [ met; unmet; unmet ]) = 3)
    "STRUCTURE unmet_checks retains shortfalls and unbound model facts" "";

  let exact_unmet =
    evaluate (Exact_executable { path = "/oracle"; expected = sample_identity })
      (Unknown "identity unavailable")
  in
  let kernel_unmet =
    evaluate (Kernel_capability Rlimit_as) (Unknown "rlimit unavailable")
  in
  (match to_diagnostics [ exact_unmet ] with
  | [ d ] ->
      check (d.hazard = "HZ-RES-BIN")
        "STRUCTURE exact executable identity uses the binary hazard" d.hazard;
      check
        (d.origin = Fractal_diagnostic.Environment
        && d.impact = Fractal_diagnostic.Blocks_credit)
        "STRUCTURE exact executable failure is an Environment block" d.hazard
  | _ -> check false "STRUCTURE exact executable emits one diagnostic" "");
  match to_diagnostics [ kernel_unmet ] with
  | [ d ] ->
      check (d.hazard = "HZ-RES-KERNEL")
        "STRUCTURE kernel capability uses the kernel resource hazard" d.hazard;
      check
        ((d.origin = Fractal_diagnostic.Environment
         || d.origin = Fractal_diagnostic.Control)
        && d.origin <> Fractal_diagnostic.Implementation
        && d.impact = Fractal_diagnostic.Blocks_credit)
        "STRUCTURE kernel capability failure blocks without Implementation origin" d.hazard
  | _ -> check false "STRUCTURE kernel capability emits one diagnostic" ""

let () =
  print_endline "resource envelope suite";
  List.iter
    (fun (name, layer) ->
      layer ();
      Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("numeric", numeric_domain_layer);
      ("oracle", numeric_oracle_layer);
      ("supervision", supervision_unit_layer);
      ("feature", feature_layer); ("bdd", bdd_layer);
      ("property", property_layer); ("otel", otel_layer); ("fuzz", fuzz_layer);
      ("chaos", chaos_layer); ("structure", structure_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_resource_envelope" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_resource_envelope ]);
  exit (Suite_telemetry.exit_code self)
