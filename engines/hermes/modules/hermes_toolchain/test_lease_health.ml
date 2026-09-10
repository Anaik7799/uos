(* Laws for task-authority health.

   Each law names the defect it exists for, and the defects are measured, not
   imagined: nineteen `executing` tasks with leases expired since 2026-09-07,
   and a task claimed by a worker named "--help". *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; print_endline ("FAILED: " ^ name)
  | exception e ->
    incr failed;
    print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Lease_health

let now = 1_000_000_000_000_000_000
let sec n = n * 1_000_000_000

let row ?(state = "executing") ?(worker = "claude-a1") ?(lease = now + sec 60) () =
  { plan = "uos/p"; task = "T1"; state; worker; lease_until_ns = lease }

let () =
  (* --- what the module refuses to conclude ------------------------------- *)
  check "L1 the only quiescence value the module can produce is Unknown -- \
         expiry is a point-in-time observable, liveness is a property"
    (fun () ->
       match scan ~now_ns:now [ row ~lease:(now - sec 10) () ] with
       | [ Lease_expired f ] -> f.quiescence = Unknown
       | _ -> false);
  check "L2 there is no verdict that asserts abandonment, at any age" (fun () ->
      List.for_all
        (fun age ->
           match scan ~now_ns:now [ row ~lease:(now - sec age) () ] with
           | [ Lease_expired f ] -> f.quiescence = Unknown
           | _ -> false)
        [ 1; 60; 86_400; 8_640_000 ]);
  check "L3 remediation is not automatic and the module says so" (fun () ->
      authority = "REPORT_ONLY" && remediation_is_not_automatic);

  (* --- expiry ------------------------------------------------------------ *)
  check "L4 a live lease is not a finding" (fun () ->
      scan ~now_ns:now [ row () ] = []);
  check "L5 an expired lease on an executing task is a finding" (fun () ->
      List.exists is_expiry (scan ~now_ns:now [ row ~lease:(now - sec 1) () ]));
  check "L6 the boundary is strict: lease_until == now is not yet expired"
    (fun () -> scan ~now_ns:now [ row ~lease:now () ] = []);
  check "L7 age is reported in seconds, so a reader can judge without arithmetic"
    (fun () ->
       match scan ~now_ns:now [ row ~lease:(now - sec 3600) () ] with
       | [ Lease_expired f ] -> f.expired_seconds = 3600
       | _ -> false);
  check "L8 a zero lease is not treated as expired -- absent is not stale"
    (fun () -> scan ~now_ns:now [ row ~lease:0 () ] = []);

  (* --- only executing rows are judged ------------------------------------ *)
  check "L9 available, completed and blocked rows hold no lease and are never \
         findings (defect: noise that trains readers to ignore real findings)"
    (fun () ->
       List.for_all
         (fun s -> scan ~now_ns:now [ row ~state:s ~lease:(now - sec 999) () ] = [])
         [ "available"; "completed"; "blocked"; "" ]);

  (* --- the worker-identity poka-yoke ------------------------------------- *)
  check "L10 '--help' is refused as a worker identity -- the measured defect"
    (fun () -> Result.is_error (worker_is_identity "--help"));
  check "L11 every leading-dash form is refused, not just the one observed"
    (fun () ->
       List.for_all
         (fun w -> Result.is_error (worker_is_identity w))
         [ "--help"; "-h"; "--format"; "-"; "--" ]);
  check "L12 empty and whitespace-only workers are refused" (fun () ->
      List.for_all
        (fun w -> Result.is_error (worker_is_identity w))
        [ ""; " "; "   " ]);
  check "L13 real worker names in this repository are admitted -- a check that \
         rejects the healthy case is an outage, not a check"
    (fun () ->
       List.for_all
         (fun w -> Result.is_ok (worker_is_identity w))
         [ "worker-claude-a65088e0"; "codex-01a083d2-admission";
           "worker-agy-eb7a"; "claude"; "codex-root-n01";
           "claude-opus5-r2-remediation" ]);
  check "L14 shell metacharacters and whitespace are refused inside a name"
    (fun () ->
       List.for_all
         (fun w -> Result.is_error (worker_is_identity w))
         [ "a b"; "a;b"; "a|b"; "a$b"; "a\nb"; "a'b" ]);
  check "L15 an over-long name is refused" (fun () ->
      Result.is_error (worker_is_identity (String.make 129 'a'))
      && Result.is_ok (worker_is_identity (String.make 128 'a')));
  check "L16 an identity finding is raised on an executing row regardless of \
         lease health" (fun () ->
      List.exists is_identity
        (scan ~now_ns:now [ row ~worker:"--help" ~lease:(now + sec 600) () ]));

  (* --- composition ------------------------------------------------------- *)
  check "L17 one row can carry both findings at once" (fun () ->
      let fs = scan ~now_ns:now [ row ~worker:"--help" ~lease:(now - sec 5) () ] in
      List.exists is_expiry fs && List.exists is_identity fs);
  check "L18 every bad row is reported, not only the first (defect: a report \
         that named one row and hid eighteen)" (fun () ->
      List.length
        (scan ~now_ns:now
           (List.init 19 (fun i ->
                { plan = "uos/p"; task = "T" ^ string_of_int i;
                  state = "executing"; worker = "w"; lease_until_ns = now - sec 1 })))
      = 19);
  check "L19 an empty table is healthy, not an error" (fun () ->
      scan ~now_ns:now [] = []);
  check "L20 every finding describes itself well enough to act on: it names the \
         task, the worker, and for an expiry the age and the unknown quiescence"
    (fun () ->
       let d =
         describe
           (List.hd (scan ~now_ns:now [ row ~lease:(now - sec 42) () ]))
       in
       let has s =
         let n = String.length s and h = String.length d in
         let rec go i = i + n <= h && (String.sub d i n = s || go (i + 1)) in
         go 0
       in
       has "uos/p" && has "T1" && has "claude-a1" && has "42"
       && has "UNKNOWN")

let () =
  Printf.printf "lease_health: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_lease_health" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
