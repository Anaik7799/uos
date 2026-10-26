(* Bounded native guardian for Telegram /verify gate execution.
   DERIVED from tools/validation/obs_guardian.ml (the Sa-plan observer
   guardian); the fork, setsid, group SIGKILL, WNOHANG reap loop, monotonic
   deadline and control-channel abort are unchanged. Differences:
     V1 Distinct marker uos.telegram.verify.guardian.v1, so neither adapter
        can mistake the other tool's receipt for its own.
     V2 Partial output is PRESERVED. Every path on which a child ran (exit,
        deadline kill, parent abort, output-bound kill, signal) prints the
        bytes captured so far, capped at max_bytes, after the receipt.
        obs_guardian discards them, which loses the evidence of a failing gate.
     V3 The receipt declares output_sha256 and truncated, so a caller can bind
        the exact preserved bytes as gate evidence.
   Original header follows.

   PRIVATE bounded native guardian for the read-only Sa-plan observer.
   PROVENANCE CORRECTION: the patterns here are taken from the accepted
   transport guardian tools/telegram_store_transport_guardian.ml
   (sha256 9ba03f57d2350c75ab95bfaa36553e637f432bd30e32dffd7db6ce738978d6d5),
   acceptance receipt governance/planning/20261011-1502-telegram-store-tooling-independent-verification.json.
   An earlier draft of this header wrongly cited native/ocaml/telegram_store
   test_n11, which is a process-chaos TEST fixture and not the transport
   guardian. The borrowed mechanics are: child made a process-group leader,
   SIGKILL to the GROUP then the pid, a waitpid WNOHANG reap loop, and stdin
   readiness treated as an abort signal.

   Why native rather than Erlang port signalling: the guardian is the PARENT of
   the observer child, so Unix.waitpid gives exact child ownership and a
   confirmed reap with NO pid-reuse race. Erlang can only observe an os_pid and
   must kill while the port is still owned; that is weaker.

   Invariants:
     G1 The child is identified by fork, never by a scanned pid.
     G2 The expected binary is pinned by SHA-256 of its CONTENT, read in bounded
        chunks with a size cap, and the file must be a regular file.
     G3 One absolute deadline covers digest, spawn and output. Expiry triggers
        a separate bounded reap budget (up to 2 seconds). The deadline is
        re-checked immediately BEFORE fork.
     G4 Output is capped while streaming.
     G7 The deadline and the parent control channel stay ACTIVE for the WHOLE
        lifetime, including after the child closes stdout. A blocking waitpid
        there was the falsified defect: an 80 ms budget ran 2025 ms because the
        child closed stdout then slept, and the guardian reported child_exited
        with cleanup confirmed. Every wait is now WNOHANG with the deadline and
        control channel re-checked between polls.
     G8 ECHILD does NOT prove this child exited cleanly. Unless a matching exit
        was already observed for this exact pid, the outcome is cleanup_unknown.
     G5 On deadline or parent EOF (caller death) the child PROCESS GROUP is
        SIGKILLed and then reaped with waitpid. Cleanup is confirmed only after
        waitpid returns for that exact pid. Group kill is what makes this
        actual-no-orphans rather than bounded-unknown: a grandchild inherits the
        group even though the pinned observer creates none.
     G6 The child execs the observer directly, no shell, and the pinned OCaml
        observer itself spawns nothing. *)

let max_binary_bytes = 134217728
let digest_chunk = 65536

type outcome =
  | Ok_exit of int * string
  | Killed_deadline of string
  | Killed_parent_eof of string
  (* G9 the output-bound path KILLS and REAPS the child, so its receipt must
     say cleanup=confirmed. Reporting it as a plain Refused with cleanup=n/a
     understated a confirmed reap and made a reaped cancellation
     indistinguishable from a prelaunch refusal that never had a child. *)
  | Killed_output_bound of string
  | Child_signalled of string
  | Refused of string

(* MONOTONIC, matching the accepted guardian:
   tools/telegram_store_transport_guardian.ml line 6. Unix.gettimeofday is a
   wall clock and can jump; it was used in the falsified draft. *)
let now () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9

let read_digest_bounded path deadline =
  let st = Unix.stat path in
  if st.Unix.st_kind <> Unix.S_REG then Error "exe_not_regular_file"
  else if st.Unix.st_size > max_binary_bytes then Error "exe_too_large"
  else begin
    let fd = Unix.openfile path [ Unix.O_RDONLY ] 0 in
    let ctx = ref (Cryptokit.Hash.sha256 ()) in
    let buf = Bytes.create digest_chunk in
    let rec loop () =
      if now () > deadline then Error "deadline_during_digest"
      else
        let k = Unix.read fd buf 0 digest_chunk in
        if k = 0 then Ok ()
        else ((!ctx)#add_substring buf 0 k; loop ())
    in
    let r = loop () in
    Unix.close fd;
    match r with
    | Error e -> Error e
    | Ok () ->
        Ok (Cryptokit.transform_string (Cryptokit.Hexa.encode ()) ((!ctx)#result))
  end

let run ~exe ~expected ~args ~deadline_ms ~max_bytes =
  let deadline = now () +. (float_of_int deadline_ms /. 1000.0) in
  match (try read_digest_bounded exe deadline with
    | Unix.Unix_error _ | Sys_error _ -> Error "exe_unreadable") with
  | Error e -> Refused e
  | Ok actual when actual <> expected -> Refused "exe_digest_mismatch"
  | Ok _ ->
      (* G3 re-check immediately before creating the child. *)
      if now () > deadline then Refused "deadline_before_spawn"
      else begin
        let r, w = Unix.pipe () in
        match Unix.fork () with
        | -1 -> Unix.close r; Unix.close w; Refused "fork_failed"
        | 0 ->
            (* Child: stdout to the pipe, then exec directly. No shell. *)
            Unix.close r;
            (* Group leader, so the whole group can be signalled. *)
            (try ignore (Unix.setsid ()) with _ -> ());
            Unix.dup2 w Unix.stdout;
            Unix.dup2 w Unix.stderr;
            Unix.close w;
            (try Unix.execv exe (Array.of_list (exe :: args))
             with _ -> exit 127)
        | pid ->
            Unix.close w;
            let buf = Buffer.create 65536 in
            let chunk = Bytes.create 65536 in
            let stdin_fd = Unix.stdin in
            let reap why =
              (* Group first, then the pid itself. *)
              (try Unix.kill (-pid) Sys.sigkill with _ -> ());
              (try Unix.kill pid Sys.sigkill with _ -> ());
              let rec wait_it n =
                if n <= 0 then false
                else
                  try
                    match Unix.waitpid [ Unix.WNOHANG ] pid with
                    | 0, _ -> ignore (Unix.select [] [] [] 0.01); wait_it (n - 1)
                    | p, _ when p = pid -> true
                    | _ -> wait_it (n - 1)
                  with
                  | Unix.Unix_error (Unix.EINTR, _, _) -> wait_it (n - 1)
                  (* G8 ECHILD is not proof THIS child exited as expected. *)
                  | Unix.Unix_error (Unix.ECHILD, _, _) -> false
                  | _ -> false
              in
              let wait_it () = wait_it 200 in
              (* G5 confirmed only when waitpid returns for THIS pid. *)
              let confirmed = wait_it () in
              Unix.close r;
              if confirmed then why else Refused "cleanup_unknown"
            in
            let rec loop () =
              let left = deadline -. now () in
              if left <= 0.0 then reap (Killed_deadline (Buffer.contents buf))
              else
                match Unix.select [ r; stdin_fd ] [] [] left with
                | [], _, _ -> reap (Killed_deadline (Buffer.contents buf))
                | ready, _, _ ->
                    (* Readiness on the control channel is an abort signal,
                       matching the accepted guardian (line 69). The caller is
                       expected to hold control stdin open for the duration. *)
                    if List.mem stdin_fd ready then
                      reap (Killed_parent_eof (Buffer.contents buf))
                    else read_child ready
            and read_child ready =
              if List.mem r ready then begin
                let k = try Unix.read r chunk 0 65536 with _ -> 0 in
                if k = 0 then await_exit ()
                else begin
                  Buffer.add_subbytes buf chunk 0 k;
                  if Buffer.length buf > max_bytes then
                    reap (Killed_output_bound (Buffer.contents buf))
                  else loop ()
                end
              end
              else loop ()
            (* G7 never block here: deadline and control channel stay live. *)
            and await_exit () =
              if now () > deadline then reap (Killed_deadline (Buffer.contents buf))
              else begin
                let polled =
                  try Some (Unix.waitpid [ Unix.WNOHANG ] pid) with
                  | Unix.Unix_error (Unix.EINTR, _, _) -> Some (0, Unix.WEXITED 0)
                  | Unix.Unix_error (Unix.ECHILD, _, _) -> None
                  | _ -> None
                in
                match polled with
                | None ->
                    (* G8 someone else reaped it; we cannot assert a clean exit. *)
                    Unix.close r; Refused "cleanup_unknown"
                | Some (p, st) when p = pid ->
                    Unix.close r;
                    (match st with
                     | Unix.WEXITED c -> Ok_exit (c, Buffer.contents buf)
                     | Unix.WSIGNALED _ -> Child_signalled (Buffer.contents buf)
                     | _ -> Refused "cleanup_unknown")
                | Some _ ->
                    let slice = max 0.0 (min 0.002 (deadline -. now ())) in
                    (match Unix.select [ stdin_fd ] [] [] slice with
                     | ready, _, _ when List.mem stdin_fd ready ->
                         reap (Killed_parent_eof (Buffer.contents buf))
                     | _ -> await_exit ())
              end
            in
            loop ()
      end

(* ------------------------------------------------------------------ CLI *)
let rec parse a (e, s, d, m, rest) =
  match a with
  | [] -> (e, s, d, m, List.rev rest)
  | "--exe" :: v :: t -> parse t (Some v, s, d, m, rest)
  | "--sha256" :: v :: t -> parse t (e, Some v, d, m, rest)
  | "--deadline-ms" :: v :: t -> parse t (e, s, Some v, m, rest)
  | "--max-bytes" :: v :: t -> parse t (e, s, d, Some v, rest)
  | "--" :: t -> (e, s, d, m, List.rev rest @ t)
  | x :: t -> parse t (e, s, d, m, x :: rest)

let () =
  let args = match Array.to_list Sys.argv with _ :: r -> r | [] -> [] in
  let e, s, d, m, child = parse args (None, None, None, None, []) in
  let fail c w = prerr_endline ("refused: " ^ w); exit c in
  let exe = match e with Some x -> x | None -> fail 2 "missing_exe" in
  let sha = match s with Some x -> x | None -> fail 2 "missing_sha256" in
  let dl = match d with Some x -> (try int_of_string x with _ -> fail 2 "bad_deadline") | None -> fail 2 "missing_deadline" in
  let mb = match m with Some x -> (try int_of_string x with _ -> fail 2 "bad_max_bytes") | None -> fail 2 "missing_max_bytes" in
  if String.length exe = 0 || exe.[0] <> '/' then fail 3 "exe_path_must_be_absolute";
  if String.length sha <> 64 then fail 3 "invalid_expected_digest";
  if dl <= 0 || dl > 60000 then fail 3 "invalid_deadline";
  if mb <= 0 || mb > 4194304 then fail 3 "invalid_max_bytes";
  let hex_sha256 s = Cryptokit.transform_string (Cryptokit.Hexa.encode ())
      (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s) in
  (* V2/V3 the payload is capped, hashed and always printed after the receipt. *)
  let report tag cleanup extra out =
    let kept = if String.length out > mb then String.sub out 0 mb else out in
    Printf.printf "{\"guardian\":\"uos.telegram.verify.guardian.v1\",\"result\":\"%s\",\
                   \"cleanup\":\"%s\"%s,\"output_bytes\":%d,\"output_sha256\":\"%s\",\
                   \"truncated\":%b}\n"
      tag cleanup extra (String.length kept) (hex_sha256 kept) (String.length out > mb);
    print_string kept
  in
  match run ~exe ~expected:sha ~args:child ~deadline_ms:dl ~max_bytes:mb with
  | Ok_exit (c, out) ->
      report "child_exited" "confirmed" (Printf.sprintf ",\"child_exit\":%d" c) out;
      exit (if c = 0 then 0 else 3)
  | Killed_deadline out ->
      report "killed_deadline" "confirmed" "" out; exit 4
  | Killed_parent_eof out ->
      report "killed_parent_eof" "confirmed" "" out; exit 5
  | Killed_output_bound out ->
      report "killed_output_bound" "confirmed" "" out; exit 6
  | Child_signalled out ->
      report "child_signalled" "confirmed" "" out; exit 7
  | Refused w ->
      report "refused" (if w = "cleanup_unknown" then "unknown" else "n/a")
        (Printf.sprintf ",\"reason\":\"%s\"" w) "";
      exit 3
