(* Fuzz and chaos over every vision component.

   The unit suite asks whether each law holds on inputs a person chose.
   This one asks whether it holds on inputs nobody chose — and, in the
   chaos sections, whether the failure paths survive when the world
   misbehaves at exactly the wrong moment.

   DETERMINISM IS A REQUIREMENT, NOT A CONVENIENCE. The generator is
   seeded from a constant, so a failure found here reproduces exactly.
   A fuzz suite that cannot reproduce its own finding reports noise, and
   this repository's determinacy gate exists because that is worse than
   no suite at all. *)

let passed = ref 0
let failed = ref 0
let seed = 20260811

let check name c =
  if c then incr passed
  else begin incr failed; print_endline ("  [FAIL] " ^ name) end

(* one law, N random cases; reports the FIRST counterexample rather than
   a count, because a count does not tell you what broke *)
let forall name n gen prop =
  let bad = ref None in
  for i = 0 to n - 1 do
    if !bad = None then
      let x = gen i in
      match prop x with
      | true -> ()
      | false -> bad := Some x
      | exception e -> bad := Some (x ^ " (raised " ^ Printexc.to_string e ^ ")")
  done;
  match !bad with
  | None -> incr passed
  | Some x ->
      incr failed;
      print_endline (Printf.sprintf "  [FAIL] %s — counterexample: %S" name x)

let () = Random.init seed

(* strings that break parsers: shell metacharacters, quotes, control
   bytes, unicode, and the empty string *)
let nasty =
  [| ""; " "; "\n"; "\000"; "'"; "\""; "\\"; ";"; "|"; "&"; "$(id)"; "`id`"; "../../etc/passwd";
     "%s%s%n"; "a\rb"; "\xff\xfe"; "日本語"; String.make 300 'x'; "--flag"; "-"; "//"; "?a=b";
     "\t"; "{}"; "[]"; "<script>"; "%00"; "0x00" |]

let rand_string i =
  if i mod 3 = 0 then nasty.(Random.int (Array.length nasty))
  else begin
    let n = Random.int 24 in
    String.init n (fun _ -> Char.chr (32 + Random.int 95))
  end

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k = 0 || go 0

(* ------------------------------------------- fuzz: declarative intent *)

let () =
  print_endline "fuzz: vision_intent";
  (* argv must be TOTAL and must never let a value become syntax *)
  forall "argv is total over hostile source paths" 500 rand_string (fun s ->
      let i =
        { (Vision_intent.looping_test_pattern ~dir:"/tmp/f") with
          Vision_intent.source = Vision_intent.Loop_file { path = s } }
      in
      let v = Vision_intent.argv i in
      List.length v > 0 && List.hd v = "ffmpeg");
  forall "a hostile path is never SPLIT across argv elements" 500 rand_string (fun s ->
      if String.length s = 0 then true
      else
        let i =
          { (Vision_intent.looping_test_pattern ~dir:"/tmp/f") with
            Vision_intent.source = Vision_intent.Loop_file { path = s } }
        in
        List.mem s (Vision_intent.argv i));
  forall "argv is total over hostile output dirs" 400 rand_string (fun s ->
      let i =
        { (Vision_intent.looping_test_pattern ~dir:"/tmp/f") with
          Vision_intent.sink = Vision_intent.Hls { dir = s; segment_seconds = 1; window = 5 } }
      in
      List.length (Vision_intent.argv i) > 0);
  forall "validate never raises, whatever it is given" 400 rand_string (fun s ->
      let i =
        { (Vision_intent.looping_test_pattern ~dir:s) with
          Vision_intent.source = Vision_intent.Loop_file { path = s } }
      in
      match Vision_intent.validate i with _ -> true);
  forall "describe never raises" 300 rand_string (fun s ->
      let i =
        { (Vision_intent.looping_test_pattern ~dir:s) with
          Vision_intent.source = Vision_intent.Loop_file { path = s } }
      in
      String.length (Vision_intent.describe i) >= 0);
  (* the shell-free law must actually REJECT the bytes that break a log *)
  check "a newline path is rejected as shell-unsafe"
    (not
       (Vision_intent.argv_is_shell_free
          { (Vision_intent.looping_test_pattern ~dir:"/tmp/f") with
            Vision_intent.source = Vision_intent.Loop_file { path = "a\nb" } }));
  check "a NUL path is rejected as shell-unsafe"
    (not
       (Vision_intent.argv_is_shell_free
          { (Vision_intent.looping_test_pattern ~dir:"/tmp/f") with
            Vision_intent.source = Vision_intent.Loop_file { path = "a\000b" } }))

(* ----------------------------------------------------- fuzz: algebra *)

let () =
  print_endline "fuzz: algebra and coverage";
  let all = Array.of_list Vision_ontology.stages in
  let rand_stage () = all.(Random.int (Array.length all)) in
  let rand_seg () =
    let a = rand_stage () and b = rand_stage () in
    if Vision_ontology.stage_index a <= Vision_ontology.stage_index b then (a, b) else (b, a)
  in
  let ok = ref true in
  for _ = 1 to 800 do
    let a1, b1 = rand_seg () and a2, b2 = rand_seg () in
    match (Vision_algebra.segment a1 b1, Vision_algebra.segment a2 b2) with
    | Some s1, Some s2 -> (
        match Vision_algebra.compose s1 s2 with
        | None -> ()
        | Some m ->
            (* composition may never SHRINK the span it was given *)
            if Vision_ontology.stage_index m.Vision_algebra.first
               > Vision_ontology.stage_index s1.Vision_algebra.first
            then ok := false;
            if Vision_ontology.stage_index m.Vision_algebra.last
               < Vision_ontology.stage_index s1.Vision_algebra.last
            then ok := false)
    | _ -> ()
  done;
  check "composition never shrinks the span it was given" !ok;

  let ok = ref true in
  for _ = 1 to 500 do
    let a, b = rand_seg () in
    match Vision_algebra.segment a b with
    | None -> ()
    | Some s ->
        (* coverage of one segment is that segment; and never claims the
           whole pipeline unless it really spans it *)
        (match Vision_algebra.coverage [ s ] with
         | Ok c ->
             if Vision_algebra.covers_pipeline c && not (Vision_algebra.covers_pipeline s) then
               ok := false
         | Error _ -> ok := false)
  done;
  check "coverage of one segment never invents span" !ok;

  (* the property that matters most: a set of segments missing a stage
     can NEVER report end-to-end coverage *)
  let ok = ref true in
  for _ = 1 to 300 do
    let missing = rand_stage () in
    let segs =
      List.filter (fun s -> s <> missing) Vision_ontology.stages
      |> List.map Vision_algebra.identity
    in
    match Vision_algebra.coverage segs with
    | Ok c -> if Vision_algebra.covers_pipeline c then ok := false
    | Error _ -> ()
  done;
  check "a missing stage can NEVER yield end-to-end coverage" !ok

(* ------------------------------------------------ fuzz: libav codes *)

let () =
  print_endline "fuzz: libav return codes";
  let ok = ref true and eagain_ok = ref true in
  for _ = 1 to 3000 do
    let n = Random.int 2_000_000 - 1_000_000 in
    let c = Vision_libav_ontology.classify n in
    (* success is exactly the non-negative half *)
    if (n >= 0) <> (c = Vision_libav_ontology.Ok_zero) then ok := false;
    (* and the two sentinels are never failures *)
    if Vision_libav_ontology.is_failure c && (n = -11 || n = -541478725) then eagain_ok := false
  done;
  check "non-negative is success and negative is not, for every int" !ok;
  check "the EAGAIN/EOF sentinels are never classed as failure" !eagain_ok;
  let ok = ref true in
  for _ = 1 to 500 do
    let n = -(Random.int 100000) - 1 in
    if n <> -11 && n <> -541478725 then
      if not (Vision_libav_ontology.is_failure (Vision_libav_ontology.classify n)) then ok := false
  done;
  check "every other negative IS a failure" !ok

(* ------------------------------------------------- fuzz: OBS counters *)

let () =
  print_endline "fuzz: obs loss accounting";
  let ok = ref true and never_neg = ref true in
  for _ = 1 to 2000 do
    let s =
      { Vision_obs.rendered = Random.int 10000;
        render_missed = Random.int 100;
        encoded = Random.int 10000;
        skipped = Random.int 100;
        dropped = Random.int 100 }
    in
    (* intact iff every counter is zero — no other combination *)
    let expect = s.Vision_obs.render_missed = 0 && s.skipped = 0 && s.dropped = 0 in
    if Vision_obs.intact s <> expect then ok := false;
    if List.length (Vision_obs.losses_observed s) > 3 then never_neg := false
  done;
  check "intact holds exactly when all three counters are zero" !ok;
  check "no more than three losses are ever reported" !never_neg

(* ---------------------------------------- chaos: the restart failure paths *)

let () =
  print_endline "chaos: graceful restart under injected failure";
  (* Every operation is made to fail, one at a time and in combination.
     The invariant is the one that matters: THE OLD INSTANCE IS NEVER
     RETIRED UNLESS THE GATE PASSED. *)
  let violations = ref 0 and runs = ref 0 in
  let modes = [ `Drain_raises; `Start_raises; `Start_errors; `Health_raises; `Health_false;
                `Kill_raises; `All_fine ] in
  List.iter
    (fun mode ->
      for _ = 1 to 40 do
        incr runs;
        let retired = ref false and gate_passed = ref false in
        let ops =
          { Vision_restart.drain =
              (fun () -> if mode = `Drain_raises then failwith "drain");
            start =
              (fun () ->
                match mode with
                | `Start_raises -> failwith "start"
                | `Start_errors -> Error "start refused"
                | _ -> Ok (1000 + Random.int 1000));
            health =
              (fun _ ->
                match mode with
                | `Health_raises -> failwith "health"
                | `Health_false -> false
                | _ -> gate_passed := true; true);
            retire = (fun () -> retired := true);
            kill_new = (fun _ -> if mode = `Kill_raises then failwith "kill") }
        in
        match Vision_restart.execute ops with
        | o ->
            (* THE INVARIANT *)
            if !retired && not !gate_passed then incr violations;
            if o.Vision_restart.old_retired <> !retired then incr violations;
            if not (Vision_restart.well_formed o.Vision_restart.trace) then incr violations
        | exception _ ->
            (* an escaping exception is itself a violation: the caller
               would not know whether the old instance still serves *)
            incr violations
      done)
    modes;
  check (Printf.sprintf "the old instance is never retired without a passing gate (%d runs)" !runs)
    (!violations = 0);

  (* chaos on the trigger: unreadable, identical and differing digests *)
  let ok = ref true in
  for i = 1 to 400 do
    let a = if i mod 3 = 0 then None else Some (rand_string i) in
    let b = if i mod 5 = 0 then None else Some (rand_string i) in
    let changed = Vision_restart.image_changed ~running:a ~current:b in
    (* unknown on either side must NEVER trigger a restart *)
    if (a = None || b = None) && changed then ok := false
  done;
  check "an unknown digest NEVER triggers a restart" !ok

(* ---------------------------------- chaos: the control plane under garbage *)

let () =
  print_endline "chaos: zenoh control plane under garbage";
  let restarts = ref 0 in
  let comps =
    [ { Vision_control.name = "ffmpeg";
        status = (fun () -> {|"running":true|});
        restart = (fun () -> incr restarts; Ok "restarted") } ]
  in
  let before = !restarts in
  let ok = ref true in
  for i = 1 to 1500 do
    let key = "hermes/vision/control/" ^ rand_string i in
    let payload = rand_string (i + 7) in
    match Vision_control.dispatch comps key payload with
    | reply ->
        (* every reply is JSON with an explicit ok field — never empty,
           never a bare string *)
        if not (contains reply "\"ok\"") then ok := false
    | exception _ -> ok := false
  done;
  check "dispatch is TOTAL over random keys and payloads" !ok;
  (* THE SAFETY PROPERTY: no amount of garbage may restart anything *)
  check "no random payload ever triggered a restart" (!restarts = before)

let () =
  Printf.printf "\nvision fuzz/chaos: %d passed, %d failed (seed %d)\n" !passed !failed seed;
  let self = Suite_telemetry.observe ~suite:"test_vision_fuzz" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vision ]);
  exit (Suite_telemetry.exit_code self)
