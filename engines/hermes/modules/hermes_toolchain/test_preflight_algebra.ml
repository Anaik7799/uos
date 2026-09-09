(* The executable specification of the preflight's denotational semantics.

   Every law below is checked against the SHIPPED Preflight_algebra module, not
   a copy, so a green run is evidence about the code that the gate, the SRE
   receipt and the agent hooks all rest on.

   Each law names the concrete defect it exists for. All three of the defects
   cited were found by deliberately breaking a check, never by reading one. *)

let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false ->
      incr failed;
      print_endline ("FAILED: " ^ name)
  | exception e ->
      incr failed;
      print_endline ("FAILED: " ^ name ^ " (raised " ^ Printexc.to_string e ^ ")")

open Preflight_algebra

let f1 = [ { arm = "useable"; name = "npm"; detail = "missing semver" } ]
let f2 = [ { arm = "tracked"; name = "tools/x.lock"; detail = "present but not tracked" } ]
let f3 = [ { arm = "locality"; name = "jj"; detail = "$HOME toolchain" } ]

let sample = [ Pass; Fail f1; Fail f2; Fail f3 ]

let for_all_pairs f = List.for_all (fun a -> List.for_all (fun b -> f a b) sample) sample

let for_all_triples f =
  List.for_all
    (fun a -> List.for_all (fun b -> List.for_all (fun c -> f a b c) sample) sample)
    sample

let receipt =
  { status = Pass; epoch_s = 1_000_000; checker_sha256 = "aa"; table_sha256 = "bb" }

let () =
  (* --- the verdict meet-semilattice ------------------------------------- *)
  check "L1 meet is associative" (fun () -> for_all_triples Laws.meet_associative);
  check "L2 meet is commutative on the verdict" (fun () -> for_all_pairs Laws.meet_commutative);
  check "L3 meet is idempotent" (fun () -> List.for_all Laws.meet_idempotent sample);
  check "L4 Pass is the identity of meet" (fun () -> List.for_all Laws.meet_identity sample);
  check "L5 Fail absorbs -- this is why fail-closed is provable once, not re-applied per call site"
    (fun () -> List.for_all (fun a -> Laws.fail_absorbs a f1) sample);

  (* --- composition ------------------------------------------------------ *)
  check "L6 a composite passes iff every component passes" (fun () ->
      Laws.meet_all_pass_iff_all_pass sample
      && Laws.meet_all_pass_iff_all_pass [ Pass; Pass ]
      && Laws.meet_all_pass_iff_all_pass []);
  check "L7 every component finding survives into the composite (defect: a gate that named only the first failing arm)"
    (fun () -> Laws.findings_preserved sample);
  check "L8 the empty composite is Pass (vacuous conjunction)" (fun () ->
      is_pass (meet_all []));

  (* --- useability: the npm defect --------------------------------------- *)
  check "L9 exit 0 with NO output is NOT success where output was required \
         (defect: a zero-byte executable is a valid empty shell script, and the \
         first useable arm reported it PASS)" (fun () ->
      Laws.silent_zero_is_not_success ~arm:"useable" ~name:"node");
  check "L10 exit 0 with output is success" (fun () ->
      is_pass
        (interpret_execution ~arm:"useable" ~name:"erl" Output_required
           (Exited_zero_with_output "OTP 29")));
  check "L11 a nonzero exit is a failure that names the code" (fun () ->
      match interpret_execution ~arm:"useable" ~name:"npm" Output_required (Exited_nonzero 7) with
      | Fail [ { detail; _ } ] -> detail = "exit 7"
      | _ -> false);
  check "L12 not-executable is a failure, never a skip" (fun () ->
      not (is_pass (interpret_execution ~arm:"useable" ~name:"z3" Silent_ok Not_executable)));
  check "L13 silence is success only where the probe declared it legitimate" (fun () ->
      is_pass (interpret_execution ~arm:"useable" ~name:"erlc" Silent_ok Exited_zero_silent));

  (* --- locality: the honest /nix/store boundary -------------------------- *)
  let barred = [ "/usr/"; "/opt/"; "/home/an/dev/ver/"; "/home/an/.cargo/" ] in
  check "L14 an entrypoint outside the project root fails" (fun () ->
      not
        (is_pass
           (interpret_locality ~name:"jj" ~root:"/repo" ~entrypoint:"/home/an/.cargo/bin/jj"
              ~resolved:"/home/an/.cargo/bin/jj" ~barred_prefixes:barred)));
  check "L15 an in-project entrypoint resolving into /nix/store PASSES -- that is \
         the honest boundary, not a violation" (fun () ->
      is_pass
        (interpret_locality ~name:"erl" ~root:"/repo"
           ~entrypoint:"/repo/toolchains/nix-profile/bin/erl"
           ~resolved:"/nix/store/abc-erlang-29.0.5/lib/erlang/bin/erl" ~barred_prefixes:barred));
  check "L16 an in-project entrypoint resolving into an evidence tree fails" (fun () ->
      not
        (is_pass
           (interpret_locality ~name:"ocaml" ~root:"/repo"
              ~entrypoint:"/repo/toolchains/opam-ocaml/bin/ocaml"
              ~resolved:"/home/an/dev/ver/zigvm/_opam/bin/ocaml" ~barred_prefixes:barred)));

  (* --- tracking: both directions ---------------------------------------- *)
  check "L17 present-but-untracked fails" (fun () ->
      not (is_pass (interpret_tracking ~tracked:[ "a" ] ~present:[ "a"; "b" ])));
  check "L18 tracked-but-absent fails (a phantom tool is not tooling)" (fun () ->
      not (is_pass (interpret_tracking ~tracked:[ "a"; "b" ] ~present:[ "a" ])));
  check "L19 exact agreement passes" (fun () ->
      is_pass (interpret_tracking ~tracked:[ "a"; "b" ] ~present:[ "b"; "a" ]));

  (* --- receipts ---------------------------------------------------------- *)
  check "L20 a fresh receipt from the same checker and table is valid" (fun () ->
      is_pass
        (receipt_valid ~now_s:(receipt.epoch_s + 10) ~max_age_s:900 ~checker_sha256:"aa"
           ~table_sha256:"bb" receipt));
  check "L21 receipt validity is antitone in age" (fun () ->
      List.for_all
        (fun (a, b) -> Laws.receipt_validity_antitone_in_age receipt 900 a b)
        [ (0, 10); (10, 900); (900, 901); (0, 100000); (500, 500) ]);
  check "L22 a stale receipt is invalid" (fun () ->
      not
        (is_pass
           (receipt_valid ~now_s:(receipt.epoch_s + 901) ~max_age_s:900 ~checker_sha256:"aa"
              ~table_sha256:"bb" receipt)));
  check "L23 either digest changing invalidates the receipt at ANY age" (fun () ->
      Laws.digest_change_invalidates receipt 900
      && Laws.digest_change_invalidates receipt max_int);
  check "L24 a cached FAIL is never valid, however fresh" (fun () ->
      not
        (is_pass
           (receipt_valid ~now_s:receipt.epoch_s ~max_age_s:900 ~checker_sha256:"aa"
              ~table_sha256:"bb"
              { receipt with status = Fail f1 })));
  check "L25 a receipt from the future is invalid (negative age is not fresh)" (fun () ->
      not
        (is_pass
           (receipt_valid ~now_s:(receipt.epoch_s - 1) ~max_age_s:900 ~checker_sha256:"aa"
              ~table_sha256:"bb" receipt)));

  (* --- the composite property the whole gate rests on -------------------- *)
  check "L26 one failing arm anywhere fails the run, for every arm position" (fun () ->
      let arms n =
        List.init 6 (fun i -> if i = n then Fail f1 else Pass)
      in
      List.for_all (fun n -> not (is_pass (meet_all (arms n)))) [ 0; 1; 2; 3; 4; 5 ]);
  check "L27 all arms passing passes" (fun () ->
      is_pass (meet_all (List.init 6 (fun _ -> Pass))))

let () =
  Printf.printf "preflight_algebra: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_preflight_algebra" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.toolchain_core ]);
  exit (Suite_telemetry.exit_code self)
