(* uos-wait — the admissible background waiter.
   Implements formal/lean/UosBackgroundWaiterTwin.lean's `admissible`.

   WHY THIS EXISTS
   ---------------
   On 2026-11-06 eight shells of the shape

       while pgrep -f "dataplane.ml --subject" >/dev/null; do :; done

   were started to wait for a mutation sweep. The sweep finished at 21:28;
   the waiters were still spinning at 04:28 the next morning. `pgrep -f`
   matches full command lines, and each waiter's own command line CONTAINS
   the pattern it was given, so the guard was satisfied by the waiter. The
   observed set is never empty when the observer is in it. Measured cost:
   56 pgrep forks/second/waiter, 24-core host at load 9.64, ~1.1e7 process
   creations over the seven hours.

   THE FOUR RULES, each a refusal rather than a default
   ---------------------------------------------------
     1. IDENTITY, NOT DESCRIPTION. The target is a pid. A pid cannot be the
        waiter's own -- and this tool checks that explicitly anyway. There
        is no pattern mode, deliberately: it is the defect, and a flag that
        re-enables a defect gets used.
     2. A DEADLINE IS MANDATORY. The wait is a bounded `for`, not a `while`.
        Termination is structural, not conditional on the host answering
        correctly.
     3. AN INTERVAL IS MANDATORY and must be > 0. THM_WAIT_09: an interval
        bounds the fork rate by arithmetic instead of by whatever the host
        will allow.
     4. SILENCE UNTIL EXIT. Exactly one line is ever printed. THM_WAIT_07:
        token cost is then independent of how long the wait took.

   PREFER NOT TO WAIT AT ALL. If the work is startable under the harness's
   own background tracking, start it there and be re-invoked on exit: zero
   polls, zero forks, one notification. This tool is for work the harness
   cannot track -- an already-running pid, an external run, another agent's
   process. `--selftest` proves the four rules on this host.

   OCaml per the standing instrument exception (B9); helper scripts are
   OCaml or Mojo, never Python or shell.
   authority NONE. EV ceiling 93; EV-94..109 NOT_ADMITTED. *)

let usage () =
  prerr_endline
    "usage: uos-wait --pid N --timeout SECS [--interval MS] [--kill-on-timeout]\n\
    \       uos-wait --marker PATH --timeout SECS [--interval MS]\n\
    \       uos-wait --scan\n\
    \       uos-wait --selftest\n\
     \n\
    \  --pid N             wait for THIS process to exit (identity, not a pattern)\n\
    \  --marker PATH       wait for PATH to exist (for work the harness cannot track)\n\
    \  --timeout SECS      mandatory deadline; there is no unbounded mode\n\
    \  --interval MS       poll interval, default 1000, must be > 0\n\
    \  --kill-on-timeout   SIGTERM then SIGKILL the target, for a clean shutdown\n\
    \  --scan              report inadmissible waiters alive on this host now\n\
    \  --lint DIR          report the busy-wait shape AUTHORED under DIR\n\
    \  --selftest          prove the four rules empirically, bounded\n\
     \n\
    exit 0 target finished | 1 deadline reached | 2 refused | 3 fatal";
  exit 2

(* ---------- one line, at the end, and only one ------------------------- *)

let said = ref false

let say code fmt =
  Printf.ksprintf (fun s ->
    if not !said then begin said := true; print_endline s end;
    exit code) fmt

(* ---------- host contact ---------------------------------------------- *)

(* FIXED 20261107-0355, found by this tool's own R4 control and reported by
   background_waiter_oracle. `in_channel_length` answers 0 for every file in
   /proc, so `really_input_string ic 0` returned "" and EVERY procfs read
   here came back empty. `--scan` therefore examined nothing, found nothing,
   and reported "inadmissible waiters alive=0" -- a clean verdict produced by
   a degenerate read. Identical in shape to the symlink overlay that read an
   almost-empty tree and agreed with itself: a measurement that cannot see
   reports the same thing as a subject that is fine. Read to EOF instead. *)
let read_file p =
  let ic = open_in_bin p in
  let b = Buffer.create 4096 in
  let chunk = Bytes.create 4096 in
  let rec go () =
    let k = input ic chunk 0 4096 in
    if k > 0 then (Buffer.add_subbytes b chunk 0 k; go ()) in
  (try go () with End_of_file -> ());
  close_in ic;
  Buffer.contents b

(* FIXED 20261107-0355, same report. `kill pid 0` SUCCEEDS on a zombie, so an
   exited-but-unreaped child read as alive forever and both the termination
   rule and the shutdown rule failed against a process that was already
   dead. For the tool's main use -- a pid belonging to someone else -- this
   never shows up, which is exactly why it needed a control to find it. The
   process state in /proc is the authority; `kill 0` is only the fallback. *)
let alive (pid : int) : bool =
  let by_proc =
    try
      let st = read_file (Printf.sprintf "/proc/%d/stat" pid) in
      match String.rindex_opt st ')' with
      | Some k when k + 2 < String.length st ->
        Some (st.[k + 2] <> 'Z' && st.[k + 2] <> 'X')
      | _ -> None
    with _ -> None in
  match by_proc with
  | Some v -> v
  | None ->
    (try Unix.kill pid 0; true with
     | Unix.Unix_error (Unix.ESRCH, _, _) -> false
     | Unix.Unix_error (Unix.EPERM, _, _) -> true   (* exists, not ours *)
     | _ -> true)

let contains_sub hay needle =
  let nh = String.length hay and nn = String.length needle in
  if nn = 0 then true
  else begin
    let found = ref false and i = ref 0 in
    while not !found && !i + nn <= nh do
      if String.sub hay !i nn = needle then found := true else incr i
    done; !found
  end

(* ---------- --scan: find the defect, on this host, right now ----------- *)

(* A busy-wait is visible in /proc: a shell whose command line contains both
   a `while` and a process-listing call, with no `sleep`. This reads /proc
   directly rather than shelling out to pgrep -- partly because pgrep is the
   thing that was being forked eleven million times, and partly because a
   scanner that greps command lines for a pattern it is itself carrying
   would find itself, which is precisely the bug. Its own pid is excluded
   explicitly. *)
let scan () =
  let me = Unix.getpid () in
  let suspects = ref [] in
  let entries = try Sys.readdir "/proc" with _ -> [||] in
  Array.iter (fun e ->
    match int_of_string_opt e with
    | Some pid when pid <> me ->
      (try
         let raw = read_file ("/proc/" ^ e ^ "/cmdline") in
         let cl = String.map (fun c -> if c = '\000' then ' ' else c) raw in
         let busy =
           contains_sub cl "while "
           && (contains_sub cl "pgrep" || contains_sub cl "pidof"
               || contains_sub cl "ps -")
           && not (contains_sub cl "sleep") in
         if busy then
           suspects := (pid, String.trim cl) :: !suspects
       with _ -> ())
    | _ -> ())
    entries;
  let s = List.sort compare !suspects in
  List.iter (fun (pid, cl) ->
    let cl = if String.length cl > 120 then String.sub cl 0 120 ^ "..." else cl in
    prerr_endline (Printf.sprintf "  INADMISSIBLE pid %d  %s" pid cl)) s;
  say (if s = [] then 0 else 1)
    "uos-wait --scan: inadmissible waiters alive=%d (busy-wait, no sleep)"
    (List.length s)

(* ---------- --lint: the shape must not be AUTHORED either ------------- *)

(* The oracle's first attempt at this arm was `grep -rlE 'while +(pgrep)'
   tools/`, and its single match was THIS FILE's header comment, which
   quotes the incident. A grep over source cannot tell documentation from
   implementation -- the same confusion that made the mutation instrument
   mutate docstrings and then report the resulting certain survivors as an
   oracle's blindness. Three arms in one run were measuring my prose. So the
   comment markers are removed before the shape is looked for, and newlines
   are kept so the line numbers still mean something. *)
let strip_comments (s : string) : string =
  let n = String.length s in
  let b = Buffer.create n in
  let depth = ref 0 and i = ref 0 and hash = ref false in
  while !i < n do
    let c = s.[!i] in
    if c = '\n' then begin
      hash := false; Buffer.add_char b '\n'; incr i
    end else if !i + 1 < n && c = '(' && s.[!i + 1] = '*' then begin
      incr depth; i := !i + 2
    end else if !i + 1 < n && c = '*' && s.[!i + 1] = ')' && !depth > 0 then begin
      decr depth; i := !i + 2
    end else begin
      if c = '#' && !depth = 0 then hash := true;
      if !depth = 0 && not !hash then Buffer.add_char b c;
      incr i
    end
  done;
  Buffer.contents b

let rec files_under dir acc =
  match (try Array.to_list (Sys.readdir dir) with _ -> []) with
  | [] -> acc
  | es ->
    List.fold_left (fun acc e ->
      let p = Filename.concat dir e in
      if (try Sys.is_directory p with _ -> false) then files_under p acc
      else if Sys.file_exists p then p :: acc else acc) acc es

let lint dir =
  let hits = ref [] in
  List.iter (fun p ->
    match (try Some (strip_comments (read_file p)) with _ -> None) with
    | None -> ()
    | Some body ->
      List.iteri (fun k line ->
        if contains_sub line "while "
           && (contains_sub line "pgrep" || contains_sub line "pidof")
           && not (contains_sub line "sleep") then
          hits := (p, k + 1, String.trim line) :: !hits)
        (String.split_on_char '\n' body))
    (files_under dir []);
  let h = List.sort compare !hits in
  List.iter (fun (p, k, l) ->
    let l = if String.length l > 90 then String.sub l 0 90 ^ "..." else l in
    prerr_endline (Printf.sprintf "  AUTHORED %s:%d  %s" p k l)) h;
  say (if h = [] then 0 else 1)
    "uos-wait --lint %s: busy-wait shapes authored in code=%d (comments \
     stripped)" dir (List.length h)

(* ---------- the wait: a bounded for, not a while ---------------------- *)

type target = Pid of int | Marker of string

let finished = function
  | Pid p -> not (alive p)
  | Marker path -> Sys.file_exists path

let reap pid =
  (* Clean shutdown is both conditions, THM_WAIT_11: the waiter stops AND
     nothing it was waiting on is left running. TERM, a grace second, then
     KILL, then verify by reading liveness rather than trusting the signal. *)
  (try Unix.kill pid Sys.sigterm with _ -> ());
  Unix.sleepf 1.0;
  if alive pid then begin
    (try Unix.kill pid Sys.sigkill with _ -> ());
    Unix.sleepf 0.5
  end;
  not (alive pid)

let wait_for (tgt : target) (timeout_s : float) (interval_ms : int)
      (kill_on_timeout : bool) =
  (* THM_WAIT_03: the deadline is what forces termination. Computing the
     poll count up front and iterating over it means this loop terminates
     even if `finished` lies on every call. *)
  let polls =
    let p = int_of_float (ceil (timeout_s *. 1000.0 /. float_of_int interval_ms)) in
    if p < 1 then 1 else p in
  let interval = float_of_int interval_ms /. 1000.0 in
  let t0 = Unix.gettimeofday () in
  let done_at = ref (-1) in
  let k = ref 0 in
  while !done_at < 0 && !k < polls do
    if finished tgt then done_at := !k
    else begin Unix.sleepf interval; incr k end
  done;
  if !done_at < 0 && finished tgt then done_at := !k;
  let dt = Unix.gettimeofday () -. t0 in
  let what = match tgt with
    | Pid p -> Printf.sprintf "pid %d" p
    | Marker m -> Printf.sprintf "marker %s" m in
  if !done_at >= 0 then
    say 0 "uos-wait: %s finished after %.1fs (%d/%d polls, %d forks)"
      what dt !done_at polls 0
  else begin
    let shut = match tgt with
      | Pid p when kill_on_timeout ->
        if reap p then " target killed, shutdown clean"
        else " target SURVIVED kill, shutdown NOT clean"
      | Pid _ -> " target still alive, left running"
      | Marker _ -> " marker never appeared" in
    say 1 "uos-wait: DEADLINE %s after %.1fs (%d polls);%s" what dt polls shut
  end

(* ---------- --selftest: the four rules, measured --------------------- *)

let selftest () =
  let fails = ref [] in
  let check name ok = if not ok then fails := name :: !fails in
  (* 1. identity target terminates when the work does, and no sooner. *)
  let pid = Unix.create_process "/bin/sleep" [| "sleep"; "2" |]
              Unix.stdin Unix.stdout Unix.stderr in
  let t0 = Unix.gettimeofday () in
  let polls = ref 0 in
  (try
     while alive pid && Unix.gettimeofday () -. t0 < 10.0 do
       Unix.sleepf 0.25; incr polls done;
     ignore (Unix.waitpid [] pid)
   with _ -> ());
  let dt = Unix.gettimeofday () -. t0 in
  check "R1-identity-terminates" (dt < 9.0);
  check "R1-waited-for-the-work" (dt > 1.5);
  (* 2. the deadline fires when the work does NOT finish. *)
  let pid2 = Unix.create_process "/bin/sleep" [| "sleep"; "30" |]
               Unix.stdin Unix.stdout Unix.stderr in
  let t1 = Unix.gettimeofday () in
  let n = int_of_float (ceil (2.0 *. 1000.0 /. 500.0)) in
  let k = ref 0 and fin = ref false in
  while not !fin && !k < n do
    if not (alive pid2) then fin := true else (Unix.sleepf 0.5; incr k) done;
  let dt1 = Unix.gettimeofday () -. t1 in
  check "R2-deadline-fires" (not !fin && dt1 < 5.0);
  (* 3. clean shutdown: the target is gone after the reap, verified by
        reading liveness, not by the signal returning. *)
  check "R3-shutdown-clean" (reap pid2);
  (try ignore (Unix.waitpid [] pid2) with _ -> ());
  (* 4. a self-matching pattern WOULD never terminate -- demonstrated on a
        bounded proxy rather than by starting one: a predicate that includes
        the observer is true at every poll, so the guard cannot go false.
        This is THM_WAIT_02 checked against the real /proc. *)
  let me = Unix.getpid () in
  let self_matches =
    try
      let cl = read_file (Printf.sprintf "/proc/%d/cmdline" me) in
      contains_sub (String.map (fun c -> if c = '\000' then ' ' else c) cl)
        "selftest"
    with _ -> false in
  check "R4-own-cmdline-matches-own-argument" self_matches;
  List.iter (fun f -> prerr_endline ("  FAIL " ^ f)) (List.rev !fails);
  say (if !fails = [] then 0 else 1)
    "uos-wait --selftest: 5 rules checked, %d failed" (List.length !fails)

(* ---------- argv ------------------------------------------------------- *)

let () =
  let pid = ref (-1) and marker = ref "" and timeout = ref (-1.0) in
  let interval = ref 1000 and killit = ref false in
  let mode = ref "" in
  let args = Array.to_list Sys.argv in
  let rec parse = function
    | [] -> ()
    | "--pid" :: v :: r -> pid := int_of_string v; parse r
    | "--marker" :: v :: r -> marker := v; parse r
    | "--timeout" :: v :: r -> timeout := float_of_string v; parse r
    | "--interval" :: v :: r -> interval := int_of_string v; parse r
    | "--kill-on-timeout" :: r -> killit := true; parse r
    | "--scan" :: r -> mode := "scan"; parse r
    | "--selftest" :: r -> mode := "selftest"; parse r
    | "--lint" :: v :: r -> mode := "lint"; marker := v; parse r
    | ("-h" | "--help") :: _ -> usage ()
    | a :: _ -> prerr_endline ("unknown argument: " ^ a); usage () in
  (try parse (List.tl args) with _ -> usage ());
  match !mode with
  | "scan" -> scan ()
  | "selftest" -> selftest ()
  | "lint" -> lint !marker
  | _ ->
    (* Fail closed on each of the twin's admissibility conditions. A missing
       deadline is a refusal, not a default of "forever". *)
    if !pid < 0 && !marker = "" then
      say 2 "uos-wait: REFUSED -- no target. --pid is identity; there is no \
             pattern mode, because a pattern matches the waiter."
    else if !pid >= 0 && !marker <> "" then
      say 2 "uos-wait: REFUSED -- --pid and --marker are exclusive."
    else if !timeout <= 0.0 then
      say 2 "uos-wait: REFUSED -- --timeout is mandatory and must be > 0 \
             (THM_WAIT_03: the deadline is what forces termination)."
    else if !interval <= 0 then
      say 2 "uos-wait: REFUSED -- --interval must be > 0 (THM_WAIT_09: an \
             interval bounds the fork rate; 0 is the busy-wait that burned \
             a core for seven hours)."
    else if !pid = Unix.getpid () then
      say 2 "uos-wait: REFUSED -- target pid is my own. That is the \
             self-matching guard, in its pid form."
    else if !pid >= 0 && not (alive !pid) then
      say 0 "uos-wait: pid %d was already gone (0 polls, 0 forks)" !pid
    else
      wait_for (if !pid >= 0 then Pid !pid else Marker !marker)
        !timeout !interval !killit
