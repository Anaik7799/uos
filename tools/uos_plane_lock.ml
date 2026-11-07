(* uos_plane_lock — one advisory lock over a shared code plane.
   Authored 20261107-2029 (host clock read immediately before this write).

   WHY THIS EXISTS (finding F-W-13, 20261107-0348 record)
   ------------------------------------------------------
   `tools/mojo_mutation_dataplane.ml` mutates files under `formal/mojo` in
   place and restores them. `tools/lean_mojo_differential.ml` computes

       cat formal/mojo/*_oracle.mojo formal/mojo/oracle_substrate.mojo
         | sha256sum

   as its `oracle_set_sha256_16`. Those two overlap exactly: between the
   mutation plane's `write_file path text` and its `restore ()`, the bytes on
   disk are a mutant. A differential run whose digest lands in that window
   hashes a tree that never existed and binds its verdict to a revision
   nobody authored. The mutation plane's IN_FLIGHT journal protects against
   ITS OWN crash; it says nothing to a concurrent reader.

   MECHANISM, AND WHY IT IS NOT HAND-ROLLED
   ----------------------------------------
   `Unix.lockf F_TLOCK` on a file descriptor, after the pattern already in
   `tools/ecology_file_transaction.ml` (which uses F_TLOCK + O_EXCL +
   `same_id` identity re-verification for its per-journal lock). Reusing that
   mechanism rather than a pid file with a TTL is a deliberate choice:

     a POSIX record lock is held by the KERNEL and released when the holding
     process dies, however it dies.

   So there is no stale lock, no TTL to tune, no liveness probe, and no
   "is the recorded pid still alive" question -- which is the question a pid
   file would have forced me to answer with the same /proc reasoning that
   already produced two defects today (`kill(pid,0)` on a zombie, and
   `in_channel_length` returning 0 for procfs).

   THE TRAP THIS FILE'S SELFTEST EXISTS TO CATCH
   ---------------------------------------------
   POSIX record locks are per-PROCESS, not per-descriptor. A second `lockf`
   on the same file from the SAME process SUCCEEDS. An in-process selftest
   would therefore observe "exclusion" that does not exist, and report a
   working lock while two peers trample each other. Every exclusion control
   below forks. A selftest that cannot fail is not evidence (INV-FALSIFY).

   BOUNDARY, stated rather than implied:
     - Advisory. It excludes only processes that CALL it. A peer agent's tool
       that never acquires is not excluded by anything here. Both instruments
       are wired in this change; a third writer would need wiring too.
     - It serialises access to the plane. It does not make a mid-mutation
       tree correct, and it grants no admission. EV ceiling 93. *)

(* The lock dir is resolved from UOS_ROOT, the convention already used by
   tools/lib/uos-toolchain.sh, NOT from the caller's cwd. Two instruments that
   resolve different paths would each take a lock neither of them shares, and
   every exclusion control would still pass -- the lock would exclude nothing
   while reporting success. Path agreement is therefore verified empirically
   by `--where`, not assumed. *)
(* Byte-identical to tools/lean_mojo_differential.ml:57-58 on purpose. A
   silent fallback to Sys.getcwd () was tried first and rejected: an
   instrument run without UOS_ROOT from a subdirectory would resolve a
   DIFFERENT lock file, take it successfully, and exclude nobody -- while
   every control in --selftest still passed. The two instruments must share
   one expression, not two that usually agree. *)
let uos_root =
  try Sys.getenv "UOS_ROOT" with Not_found -> "/home/an/NAS-setup/uos"

let lock_dir = Filename.concat uos_root "var/locks"

let path_for (name : string) : string =
  Filename.concat lock_dir (name ^ ".lock")

(* ---------- acquire -----------------------------------------------------
   Bounded. The retry is a `for`, not a `while`: this file is the fix for an
   unbounded self-matching `while` loop, and an unbounded retry here would be
   the same defect wearing the fix's name. It obeys the three admissibility
   rules proved in formal/lean/UosBackgroundWaiterTwin.lean -- mandatory
   deadline, nonzero interval, zero output per poll. *)

(* THE BUDGET INVARIANT, finding F-W-20, 20261107-2147.

   The acquire budget MUST be at least as long as the longest LEGITIMATE hold
   of the same plane, or the lock starves instead of serialising.

   Observed: the default was 120.0 while `lean_mojo_differential.ml` holds the
   plane for its whole 18-pair run (~2 min) and a manual `--hold` can run
   longer. `mojo_mutation_dataplane.ml` was wired without an explicit timeout,
   so it inherited 120.0, and a re-sweep aborted with "could not acquire ...
   within 120s. Nothing was mutated." It failed CLOSED, which is correct and
   safe -- but a lock whose writers abort whenever a reader is working has not
   serialised anything, it has just moved the failure.

   The default is therefore 600.0, matching the three call sites that already
   passed it explicitly. The failure mode of a caller that forgets is now
   "waits longer", not "aborts the run". A caller that genuinely wants to fail
   fast passes a short timeout deliberately. *)
let acquire ?(timeout = 600.0) ?(interval = 0.05) (name : string)
  : Unix.file_descr option =
  if not (Sys.file_exists lock_dir) then
    (try Unix.mkdir lock_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let p = path_for name in
  let fd = Unix.openfile p [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC ] 0o644 in
  (* FOUND 20261107-2048 by the local Qwen2.5-Coder-7B tier (Caste05,
     remote_tokens_billed=0) reviewing this function: the retry count was
     `timeout /. interval` with no guard on `interval`. At interval = 0.0 that
     is `int_of_float infinity` -- undefined, and in practice either 0 polls
     (acquire never retries) or a hot spin. A zero interval is exactly what
     formal/lean/UosBackgroundWaiterTwin.lean's `admissible` forbids
     (intervalMs = 0 => inadmissible), so this file was violating the rule its
     own sibling twin proves. Clamped at both ends: the interval cannot be
     zero, and the iteration count cannot exceed the wall-clock budget.

     Three of Qwen's four findings did not survive checking (the loop sets
     `got` only on success; the failure path does return None). This one did.
     Recorded as an advisory tier whose output was verified, not trusted. *)
  let interval = if interval <= 0.0 then 0.05 else interval in
  let tries = max 1 (min 100_000 (int_of_float (timeout /. interval))) in
  let got = ref false in
  (try
     for _ = 1 to tries do
       if not !got then begin
         (try Unix.lockf fd Unix.F_TLOCK 0; got := true
          with Unix.Unix_error ((Unix.EAGAIN | Unix.EACCES), _, _) ->
            ignore (Unix.select [] [] [] interval));
         if !got then raise Exit
       end
     done
   with Exit -> ());
  if !got then begin
    (* Record WHO, for a human reading a wedged plane. The bytes are a
       courtesy; the lock itself is the kernel's, not these bytes'. *)
    (try
       ignore (Unix.lseek fd 0 Unix.SEEK_SET);
       Unix.ftruncate fd 0;
       let msg = Printf.sprintf "pid=%d since=%.0f\n" (Unix.getpid ()) (Unix.time ()) in
       ignore (Unix.write_substring fd msg 0 (String.length msg))
     with _ -> ());
    Some fd
  end else (Unix.close fd; None)

let release (fd : Unix.file_descr) : unit =
  (try Unix.lockf fd Unix.F_ULOCK 0 with Unix.Unix_error _ -> ());
  (try Unix.close fd with Unix.Unix_error _ -> ())

(* Fail CLOSED. A caller that could not take the lock does not proceed
   unlocked: proceeding unlocked is the defect this file is about. *)
let with_plane_lock ?(timeout = 600.0) (name : string) (f : unit -> 'a) : 'a =
  match acquire ~timeout name with
  | None ->
    failwith (Printf.sprintf
      "uos_plane_lock: could not acquire %s within %.0fs. Another writer or \
       reader holds the plane. Nothing was mutated." (path_for name) timeout)
  | Some fd ->
    let r = (try f () with e -> release fd; raise e) in
    release fd; r

(* ---------- --check: is it held, right now? --------------------------- *)

let held (name : string) : bool =
  let p = path_for name in
  if not (Sys.file_exists p) then false
  else
    let fd = Unix.openfile p [ Unix.O_RDWR; Unix.O_CLOEXEC ] 0o644 in
    let r =
      try Unix.lockf fd Unix.F_TLOCK 0; Unix.lockf fd Unix.F_ULOCK 0; false
      with Unix.Unix_error ((Unix.EAGAIN | Unix.EACCES), _, _) -> true
         | Unix.Unix_error _ -> false in
    Unix.close fd; r
