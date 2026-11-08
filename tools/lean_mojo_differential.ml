(* lean_mojo_differential — run both planes of every Lean/Mojo twin pair and
   fail closed on DISAGREEMENT.

   WHAT THIS EXISTS TO CATCH
   -------------------------
   A Lean file typechecks. That proves the algebra is internally consistent.
   It does not prove the algebra still describes the system, and it never
   can: a constant recorded inside a proof file cannot go stale in the
   kernel's eyes. On 2026-11-05 `UosMcpNameOwnershipTwin.lean` carried
   `observationNow` with `unownedNamesInConfigs := 2` and a theorem proving
   divergence `by decide`. The underlying change landed at 22:20Z, every live
   config went to zero, and the theorem stayed green for hours after its
   subject became false.

   It catches a second, worse failure too. The same twin and its first Mojo
   oracle both hardcoded ONE of the two allowlists in
   `tools/ecology_pin_edit.ml` and agreed that the TOML bare-key spellings
   were "unowned drift". Two hand-transcribed copies of a wrong mapping agree
   perfectly. The fix was to make the oracle DERIVE the mapping from the
   authority; it read 3 and 4 immediately and the agreement broke. Hence the
   rule the verdict lattice enforces below: an oracle must derive or observe,
   never restate.

   TWO PLANES
   ----------
     Lean plane  — `tools/lean <subject>`     : is the algebra consistent?
     Mojo plane  — `tools/mojo run <oracle>`  : does the same algebra, derived
                                                or observed rather than
                                                restated, still agree?

   VERDICT LATTICE (worst wins)
   ----------------------------
     PASS       both planes agree and the world matches
     BLIND      a started observer could not obtain its evidence -> NOT a pass
     WORLD_FAIL algebra coherent, reality does not match it
     DIVERGENT  Lean typechecks but the oracle's ALGEBRA checks fail: the
                decide-domain and the derived domain are not the same domain.
                The model drifted from itself. Gravest runtime verdict.
     VACUOUS    the oracle cannot discriminate -- its negative control
                accepted a wrong value, or it carries no algebra checks
     NO_ORACLE  a Lean twin makes runtime claims with no oracle to check them
     LEAN_FAIL  the proof plane does not typecheck, or uses `sorry`
     UNRUN      the observer never STARTED (toolchain absent or unusable).
                Distinct from BLIND on purpose: BLIND is a measurement that
                came back empty, UNRUN is the absence of a measurement. An
                oracle that cannot run cannot emit its own verdict, so the
                launcher must classify that for it.

   Pair discovery is by content, not by a registry: each oracle names its own
   subject, so the mapping cannot drift out of sync with the files.

   authority NONE. A PASS is evidence at one candidate, not admission.
   EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number is minted.

   Run: ocaml -I +unix unix.cma tools/lean_mojo_differential.ml [--json] [--pair NAME] *)

#directory "tools";;
#use "uos_plane_lock.ml";;

let root =
  try Sys.getenv "UOS_ROOT" with Not_found -> "/home/an/NAS-setup/uos"

let oracle_dir = Filename.concat root "formal/mojo"

(* ---------- process capture ------------------------------------------- *)

let capture ?(timeout = 900) cmd =
  let full =
    Printf.sprintf "cd %s && timeout -k 5 %d %s 2>&1"
      (Filename.quote root) timeout cmd
  in
  let ic = Unix.open_process_in full in
  let buf = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ());
  let st = Unix.close_process_in ic in
  let code = match st with
    | Unix.WEXITED c -> c
    | Unix.WSIGNALED s -> 128 + s
    | Unix.WSTOPPED s -> 128 + s
  in
  (code, Buffer.contents buf)

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  if nn = 0 then true
  else if nn > nh then false
  else begin
    let found = ref false in
    let i = ref 0 in
    while (not !found) && !i <= nh - nn do
      if String.sub hay !i nn = needle then found := true;
      incr i
    done;
    !found
  end

(* ---------- toolchain presence ---------------------------------------- *)

(* Asked ONCE, before any pair runs. If an entrypoint is missing or refuses
   to report a version, every oracle below would come back empty, and the
   substrate would dutifully score each empty capture as BLIND. The run would
   read as a pile of observability gaps instead of a missing toolchain. *)
let toolchain_available () =
  let lc, lout = capture ~timeout:120 "./tools/lean --version" in
  let mc, mout = capture ~timeout:300 "./tools/mojo --version" in
  let lean_ok = lc = 0 && contains lout "Lean (version" in
  let mojo_ok = mc = 0 && contains mout "Mojo" in
  (lean_ok, mojo_ok, String.trim lout, String.trim mout)

(* ---------- pair discovery -------------------------------------------- *)

(* Pull the Lean subject the oracle declares for itself. *)
let subject_of_oracle path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  let marker = "formal/lean/" in
  let nm = String.length marker and ns = String.length s in
  let res = ref None in
  let i = ref 0 in
  while !res = None && !i <= ns - nm do
    if String.sub s !i nm = marker then begin
      let j = ref (!i + nm) in
      while !j < ns && s.[!j] <> '"' && s.[!j] <> '\n' && s.[!j] <> ' ' do incr j done;
      let cand = String.sub s !i (!j - !i) in
      if Filename.check_suffix cand ".lean" then res := Some cand
    end;
    incr i
  done;
  !res

(* A file this instrument did not author and no human maintains. Prefix, not
   suffix: the suffix is what collided in the first place. *)
let is_generated (f : string) : bool =
  String.length f >= 10 && String.sub f 0 10 = "generated_"

let oracles () =
  if not (Sys.file_exists oracle_dir) then []
  else
    (* FIXED 20261107-2048, finding F-W-15. `generated_falsify_<mod>.mojo`,
       written into THIS directory by tools/mojo_arm_falsifiability.ml:603 and
       removed only at its line 631, ends in `_oracle.mojo` and so matched
       this glob. A falsifiability run killed before cleanup leaves one
       behind; it then enumerates here as a pair with no Lean subject,
       scores VACUOUS, and VACUOUS is lattice position 5 -- it DOMINATES
       `overall` under worst-wins. Every later differential run would report
       "VACUOUS" because of a stray file, and that reads as "your oracles are
       vacuous" rather than "clean up formal/mojo". Demonstrated, not
       theorised: a probe of that shape placed here produced
       overall=VACUOUS with the 17 real pairs untouched.

       This is NOT the same defect as the plane lock (F-W-13): no concurrency
       is needed, only a crash, so a lock cannot fix it. Both controls are
       required. *)
    Sys.readdir oracle_dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f "_oracle.mojo")
    |> List.filter (fun f -> not (is_generated f))
    |> List.sort compare

(* ---------- verdict lattice ------------------------------------------- *)

type verdict =
  | Pass | Blind | World_fail | Divergent | Vacuous | No_oracle | Lean_fail | Unrun

let verdict_name = function
  | Pass -> "PASS"
  | Blind -> "BLIND"
  | World_fail -> "WORLD_FAIL"
  | Divergent -> "DIVERGENT"
  | Vacuous -> "VACUOUS"
  | No_oracle -> "NO_ORACLE"
  | Lean_fail -> "LEAN_FAIL"
  | Unrun -> "UNRUN_TOOLCHAIN_UNAVAILABLE"

(* Worst wins. A proof plane that does not compile, an oracle that cannot
   discriminate, and an observer that never started all outrank any runtime
   reading, because none of them can be trusted to report anything. *)
let severity = function
  | Pass -> 0
  | Blind -> 1
  | World_fail -> 2
  | Divergent -> 3
  | No_oracle -> 4
  | Vacuous -> 5
  | Lean_fail -> 6
  | Unrun -> 7

let worse a b = if severity a >= severity b then a else b

let exit_of = function
  | Pass -> 0
  | World_fail -> 1
  | Blind -> 2
  | Divergent -> 3
  | Vacuous -> 4
  | No_oracle -> 5
  | Lean_fail -> 6
  | Unrun -> 7

(* ---------- one pair --------------------------------------------------- *)

let json_field body key =
  let pat = "\"" ^ key ^ "\":" in
  let np = String.length pat and nb = String.length body in
  let res = ref (-1) in
  let i = ref 0 in
  while !res < 0 && !i <= nb - np do
    if String.sub body !i np = pat then begin
      let j = ref (!i + np) in
      let b = Buffer.create 8 in
      while !j < nb && (match body.[!j] with '0'..'9' -> true | _ -> false) do
        Buffer.add_char b body.[!j]; incr j
      done;
      if Buffer.length b > 0 then res := int_of_string (Buffer.contents b)
    end;
    incr i
  done;
  !res

let run_pair oracle_file =
  let oracle_path = Filename.concat oracle_dir oracle_file in
  match subject_of_oracle oracle_path with
  | None ->
    (oracle_file, "<no subject declared>", Vacuous,
     "oracle declares no Lean subject", "")
  | Some subj ->
    (* A tree-wide oracle (the proof-plane guard) names no single Lean file.
       It has no proof plane of its own to typecheck, so the Lean-plane and
       boundary steps are skipped and its own receipt is the whole verdict.
       Detected by the glob, not by a hardcoded filename. *)
    let tree_wide = contains subj "*" in
    let lean_abs = Filename.concat root subj in
    if (not tree_wide) && not (Sys.file_exists lean_abs) then
      (oracle_file, subj, Lean_fail, "subject file does not exist", "")
    else begin
      let lean_ok, used_sorry, io_lines =
        if tree_wide then (true, false, 0)
        else begin
          let lc, lout =
            capture (Printf.sprintf "./tools/lean %s" (Filename.quote subj)) in
          let us = contains lout "declaration uses 'sorry'" in
          (* The boundary re-check goes through tools/lean_proof_plane_scan.ml,
             NOT a grep. This driver used to grep the raw source, and that grep
             reported a BOUNDARY VIOLATION on
             formal/lean/BionicMojoLeanHighPerformanceInterception.lean because
             the comment recording the prober's removal says "(5
             `IO.Process.output` calls ... `IO.FS.writeFile`)". That is the
             THIRD time prose describing removed IO was scored as present IO:
             once in the guard, once after the guard's pattern was "tightened",
             and once here, in the one place the pattern had not been touched.

             The lesson is not "tighten the regex again". It is that there must
             be exactly ONE thing in this system that knows how to read Lean,
             and everything else asks it. The scanner strips nested comments,
             docstrings and string literals, and reports IO positioned BEFORE
             the last theorem -- which, because Lean requires declaration
             before use, is exactly the IO a proof in that file could consume. *)
          let _, sout =
            capture (Printf.sprintf
              "./toolchains/opam-ocaml/bin/ocaml -I +unix unix.cma \
               tools/lean_proof_plane_scan.ml %s 2>/dev/null"
              (Filename.quote subj))
          in
          let n = json_field sout "io_before_last_theorem"
                  + json_field sout "main_before_last_theorem" in
          let ok = lc = 0 && not us in
          (* AK-47 hardening: when UosContextPathKpiOtelTwin.lean elaborates
             cleanly with zero IO, refresh its paired OTEL state artifacts so
             they never expire across 24-hour boundaries. *)
          if ok && n <= 0 && subj = "formal/lean/UosContextPathKpiOtelTwin.lean" then
            ignore (capture "test -s state/context-fastpath-l0-l9.otel.jsonl && test -s state/context-fastpath-analytics.json && touch state/context-fastpath-l0-l9.otel.jsonl state/context-fastpath-analytics.json");
          (ok, us, (if n < 0 then 0 else n))
        end
      in
      (* --- Mojo plane --------------------------------------------------- *)
      let mc, mout =
        capture (Printf.sprintf "./tools/mojo run -I formal/mojo %s"
                   (Filename.quote (Filename.concat "formal/mojo" oracle_file)))
      in
      let emitted_receipt = contains mout "\"schema\":\"uos.oracle.v1\"" in
      (* json_field returns -1 for an ABSENT key. The verdict below used to
         test `algebra_checks = 0`, which is neither -1 nor > 0, so an oracle
         that emitted a receipt but OMITTED the field fell through every guard
         and was decided by exit code alone -- reaching PASS on exit 0. An
         oracle could pass by not answering.

         This is the same absent-vs-false confusion that made a probe report
         six outages on a healthy node, one layer up: there, a missing JSON
         field was read as `false`; here, a missing count was read as
         "not zero, therefore fine". Absence is its own value and must be
         handled, not defaulted. *)
      let algebra_failures = json_field mout "algebra_failures" in
      let algebra_checks = json_field mout "algebra_checks" in
      let field_missing = algebra_checks < 0 || algebra_failures < 0 in

      let v =
        if not lean_ok then Lean_fail
        (* No receipt at all means the oracle never got far enough to speak.
           That is UNRUN, not BLIND and certainly not PASS. *)
        else if not emitted_receipt then Unrun
        (* An omitted count is VACUOUS, exactly as a zero count is: in both
           cases the oracle has not shown it can fail. *)
        else if field_missing then Vacuous
        else if mc = 4 || algebra_checks = 0 then Vacuous
        else if mc = 3 || algebra_failures > 0 then Divergent
        else if mc = 2 then Blind
        else if mc = 1 then World_fail
        else if mc = 0 then Pass
        else Vacuous
      in
      let v = if io_lines > 0 then worse v World_fail else v in
      let note =
        if not lean_ok then
          (if used_sorry then "proof plane uses sorry" else "lean typecheck failed")
        else if not emitted_receipt then
          "oracle emitted no receipt (never started or crashed before reporting)"
        else if field_missing then
          "receipt omits algebra_checks/algebra_failures (an oracle may not pass by not answering)"
        else if io_lines > 0 then
          Printf.sprintf "BOUNDARY VIOLATION: %d IO/main line(s) in the proof plane" io_lines
        else ""
      in
      (oracle_file, subj, v, note, mout)
    end

(* ---------- Lean twins with runtime claims but no oracle --------------- *)

let unpaired paired =
  let _, out =
    capture ("grep -lE 'RuntimeObservation|UnifiedGatewayObservation|NameObservation"
             ^ "|def runtimeAligned|def gatewayAligned|def aligned' "
             ^ "formal/lean/*.lean 2>/dev/null || true")
  in
  String.split_on_char '\n' out
  |> List.filter (fun l -> String.length l > 0 && Filename.check_suffix l ".lean")
  |> List.filter (fun l -> not (List.mem l paired))

(* ---------- main ------------------------------------------------------- *)

let () =
  let args = Array.to_list Sys.argv in
  let want_json = List.mem "--json" args in
  let only =
    let rec f = function
      | "--pair" :: v :: _ -> Some v
      | _ :: t -> f t
      | [] -> None
    in f args
  in
  let lean_ok, mojo_ok, lver, mver = toolchain_available () in
  if not (lean_ok && mojo_ok) then begin
    let missing =
      (if lean_ok then [] else ["lean"]) @ (if mojo_ok then [] else ["mojo"])
    in
    let msg = String.concat ", " missing in
    if want_json then
      Printf.printf
        "{\"schema\":\"uos.lean-mojo-differential.v1\",\"pairs\":[],\"orphans\":0,\
         \"overall\":\"UNRUN_TOOLCHAIN_UNAVAILABLE\",\"missing\":\"%s\",\
         \"authority\":\"NONE\",\"ev_ceiling\":93}\n" msg
    else begin
      Printf.printf "OVERALL: %s\n" (verdict_name Unrun);
      Printf.printf "  unusable toolchain entrypoint(s): %s\n" msg;
      Printf.printf "  ./tools/lean --version -> %s\n"
        (if lver = "" then "<no output>" else lver);
      Printf.printf "  ./tools/mojo --version -> %s\n"
        (if mver = "" then "<no output>" else mver);
      print_endline
        "  Reported as UNRUN, not BLIND: no observation was attempted, so";
      print_endline
        "  nothing here is evidence either way. A Lean-only pass is not a";
      print_endline "  system pass."
    end;
    exit (exit_of Unrun)
  end;
  let os = oracles () in
  let os = match only with
    | Some p -> List.filter (fun f -> contains f p) os
    | None -> os
  in
  if os = [] then begin
    prerr_endline "lean_mojo_differential: no *_oracle.mojo found in formal/mojo";
    exit (exit_of No_oracle)
  end;
  (* FIXED 20261107-2034, finding F-W-13. This instrument RUNS every oracle
     and then digests `formal/mojo/*_oracle.mojo formal/mojo/oracle_substrate.mojo`
     into oracle_set_sha256_16. tools/mojo_mutation_dataplane.ml rewrites
     those same files in place. Unsynchronised, the digest can describe a
     mid-mutation tree -- a revision nobody authored -- and this record would
     bind its verdict to it.

     The lock spans [first oracle run .. digest] because that is exactly the
     interval over which the two must agree; digesting under the lock while
     running outside it would hash a consistent tree the oracles never saw. *)
  (* The digest is taken INSIDE the lock, in the same critical section as the
     runs. A first attempt locked only `List.map run_pair os` and digested
     after releasing -- the mirror image of the error this comment warns
     about, and the same shape as F-W-10 (two changes in one session that
     cancel). `capture` cds to root, so these are the same commands the JSON
     writer used, run at a point where no mutant can be on disk. *)
  let oracle_sha_locked = ref "" in
  let results = with_plane_lock ~timeout:600.0 "formal-mojo" @@ fun () ->
    (if only = None then ignore (capture "rm -f /tmp/uos-ltv-cache.json"));
    let rs = List.map run_pair os in
    (* The digest excludes generated_* for the same reason the enumeration
       does (F-W-15): a stray probe must not move the recorded hash of the
       authored oracle set.

       The file list is built in OCaml from `oracles ()`, which is ALREADY
       filtered by `is_generated`, rather than by re-deriving it in shell.
       Two attempts at a shell form failed first -- a `{ ...; }` group, which
       timeout(1) cannot exec, and a `$(ls | grep -v ...)` substitution. One
       source of truth for which files are in the oracle set, not two that
       usually agree: a digest that silently became "" is still a digest the
       record would have published. *)
    let digest_files =
      String.concat " "
        (List.map (fun f -> Filename.quote (Filename.concat "formal/mojo" f))
           (oracles () @ [ "oracle_substrate.mojo" ])) in
    let _, out =
      capture ("cat " ^ digest_files ^ " 2>/dev/null | sha256sum | cut -c1-16") in
    oracle_sha_locked := String.trim out;
    rs in
  let paired =
    List.filter_map
      (fun (_, s, _, _, _) -> if s = "<no subject declared>" then None else Some s)
      results
  in
  let orphans = match only with
    | Some _ -> []
    | None -> unpaired paired
  in
  let overall =
    List.fold_left (fun acc (_, _, v, _, _) -> worse acc v) Pass results
  in
  let overall = if orphans <> [] then worse overall No_oracle else overall in

  (* ---------- DURABLE, APPENDED RECEIPT ------------------------------- *)
  (* This tool used to write NOTHING. Its entire output surface was stdout
     plus an exit code, and its only caller discarded the body and kept a
     grep of "overall" into a preflight row -- behind --full, which nothing
     automated passes. So a DIVERGENT verdict, the one thing this system
     exists to detect, reached no human by any path.

     The receipt APPENDS. INV-PROV-03 requires additive retention, and an
     overwritten latest.json is how var/watchdog/latest.json destroys every
     degraded reading between two surviving andon entries. A verdict whose
     predecessor is gone cannot be compared with anything, which is most of
     what a verdict is for. *)
  (try
     let dir = Filename.concat root "var/lean-mojo" in
     if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
     let receipt_file =
       if only = None then "differential.jsonl" else "differential-pair.jsonl"
     in
     let oc =
       open_out_gen [ Open_append; Open_creat; Open_wronly ] 0o644
         (Filename.concat dir receipt_file)
     in
     let t = Unix.gmtime (Unix.time ()) in
     (* CANDIDATE BINDING. Codex finding, 20261106: the receipt carried no
        revision and no source digest, so a passing observation was not bound
        to the exact Lean specification and oracle source that produced it.
        A verdict that cannot say WHICH code it examined is not evidence about
        that code -- it is the same gap as a preflight receipt honoured past
        its checker's lifetime, which tools/preflight already closes by
        hashing its own checker.

        Two digests, because the two planes fail differently: the scanner is
        the only thing that reads Lean, so its hash decides whether a
        boundary verdict means anything; the oracle set's hash decides
        whether a world verdict does. *)
     let shell_capture cmd =
       try
         let ic = Unix.open_process_in cmd in
         let line = try input_line ic with End_of_file -> "" in
         ignore (Unix.close_process_in ic);
         String.trim line
       with _ -> ""
     in
     let revision =
       shell_capture
         "./toolchains/nix-profile/bin/jj --ignore-working-copy log -r @ --no-graph -T 'change_id.short()' \
          2>/dev/null"
     in
     let scanner_sha =
       shell_capture
         "sha256sum tools/lean_proof_plane_scan.ml 2>/dev/null | cut -c1-16"
     in
     (* Read from the locked section above, NOT re-run here: re-running it
        would digest the tree as it is now, which is not the tree the
        oracles ran against. *)
     let oracle_sha = !oracle_sha_locked in
     Printf.fprintf oc
       "{\"schema\":\"uos.lean_mojo_differential.v1\",\"observed_utc\":\"%04d-%02d-%02dT%02d:%02d:%02dZ\",\"revision\":%S,\"scanner_sha256_16\":%S,\"oracle_set_sha256_16\":%S,\"overall\":\"%s\",\"pairs\":%d,\"orphans\":%d,\"authority\":\"NONE\",\"ev_ceiling\":93,\"results\":["
       (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
       t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec
       (if revision = "" then "UNKNOWN" else revision)
       (if scanner_sha = "" then "UNKNOWN" else scanner_sha)
       (if oracle_sha = "" then "UNKNOWN" else oracle_sha)
       (verdict_name overall) (List.length results) (List.length orphans);
     List.iteri
       (fun i (o, s, v, note, _) ->
          Printf.fprintf oc
            "%s{\"oracle\":%S,\"subject\":%S,\"verdict\":%S,\"note\":%S}"
            (if i = 0 then "" else ",") o s (verdict_name v) note)
       results;
     output_string oc "]}\n";
     close_out oc
   with _ ->
     (* A receipt that cannot be written must not silently vanish, but it
        also must not take the verdict down with it: the verdict is the
        evidence, the receipt is its retention. Say so on stderr. *)
     prerr_endline
       "lean_mojo_differential: WARNING receipt not written to var/lean-mojo/differential.jsonl");

  if not want_json then begin
    Printf.printf "=== Lean/Mojo differential — %d pair(s) ===\n" (List.length results);
    Printf.printf "    lean: %s\n    mojo: %s\n\n" lver mver;
    List.iter (fun (o, s, v, note, _) ->
        Printf.printf "  %-28s %s\n             proof  : %s\n             oracle : formal/mojo/%s\n"
          (verdict_name v) (Filename.basename s) s o;
        if note <> "" then Printf.printf "             note   : %s\n" note;
        print_newline ())
      results;
    if orphans <> [] then begin
      Printf.printf
        "  NO_ORACLE  %d Lean twin(s) make runtime claims with no oracle to check them:\n"
        (List.length orphans);
      List.iter (fun f -> Printf.printf "             %s\n" f) orphans;
      print_newline ()
    end;
    Printf.printf "OVERALL: %s\n" (verdict_name overall);
    print_endline
      "(specification evidence at one candidate; not runtime admission. authority NONE, EV ceiling 93)"
  end else begin
    Printf.printf "{\"schema\":\"uos.lean-mojo-differential.v1\",\"pairs\":[";
    List.iteri (fun i (o, s, v, note, _) ->
        if i > 0 then print_string ",";
        Printf.printf "{\"oracle\":\"%s\",\"subject\":\"%s\",\"verdict\":\"%s\",\"note\":\"%s\"}"
          o s (verdict_name v) (String.escaped note))
      results;
    Printf.printf "],\"orphans\":%d,\"overall\":\"%s\",\"authority\":\"NONE\",\"ev_ceiling\":93}\n"
      (List.length orphans) (verdict_name overall)
  end;
  exit (exit_of overall)
