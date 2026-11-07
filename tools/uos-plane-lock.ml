(* uos-plane-lock — CLI and selftest for the shared code-plane lock.
   Authored alongside tools/uos_plane_lock.ml (see that file's header for the
   finding, the mechanism, and the per-PROCESS trap the controls below exist
   to catch).

   Modes:
     --check NAME        exit 0 free, 3 held; one line either way
     --hold NAME SECS    take it and sit on it (for cross-process testing)
     --selftest          five controls, each able to fail *)

#directory "tools";;
#use "uos_plane_lock.ml";;

let fails = ref 0
let n = ref 0

let ck name ok =
  incr n;
  if ok then Printf.printf "  PASS  %s\n" name
  else (incr fails; Printf.printf "  FAIL  %s\n" name)

(* Run `f` in a forked child; return its exit status. The child is the whole
   point: a same-process second lockf SUCCEEDS, so an in-process control
   would observe exclusion that does not exist. *)
let in_child (f : unit -> bool) : bool =
  match Unix.fork () with
  | 0 -> (try if f () then Unix._exit 0 else Unix._exit 1
          with _ -> Unix._exit 2)
  | pid ->
    let _, st = Unix.waitpid [] pid in
    st = Unix.WEXITED 0

let selftest () =
  let nm = "selftest-plane" in
  (try Sys.remove (path_for nm) with _ -> ());
  Printf.printf "uos-plane-lock --selftest\n";

  (* C1 -- it can be taken at all. Fails if acquire is broken. *)
  let fd1 = acquire ~timeout:2.0 nm in
  ck "C1 free-lock-is-acquirable" (fd1 <> None);

  (* C2 -- EXCLUSION, from another process, while held.
     This is the control that can actually fail: if lockf were a no-op, or if
     the two sides opened different paths, the child would succeed here. *)
  ck "C2 held-lock-refuses-another-process"
     (not (in_child (fun () -> acquire ~timeout:0.3 nm <> None)));

  (* C3 -- the converse of C2, so C2 is not passing by refusing always.
     Without this, a `held` that returned true unconditionally would score
     C2 as PASS. *)
  (match fd1 with Some fd -> release fd | None -> ());
  ck "C3 released-lock-is-acquirable-by-another-process"
     (in_child (fun () -> acquire ~timeout:2.0 nm <> None));

  (* C4 -- the checker must not see a free lock as held (false positive). *)
  ck "C4 check-reports-free-when-free" (not (held nm));

  (* C5 -- a holder's DEATH must release it, with no stale-lock wedge and no
     TTL. Child takes the lock and _exits while holding it; the parent must
     then be able to take it. If this fails, every crashed sweep wedges the
     plane forever. *)
  let r, w = Unix.pipe () in
  (match Unix.fork () with
   | 0 ->
     (* FOUND 20261107-2029 by the pid-file mutant: an uncaught exception
        here resumed the OCaml TOPLEVEL in the child, which re-ran every
        remaining phrase -- selftest included -- and printed a second
        verdict line. A duplicated verdict can be read as a pass. The child
        must never return to the toplevel, on any path. *)
     (try
        Unix.close r;
        let ok = (try acquire ~timeout:2.0 nm <> None with _ -> false) in
        ignore (Unix.write_substring w (if ok then "y" else "n") 0 1);
        Unix.close w
      with _ -> ());
     Unix._exit 0                     (* dies holding it *)
   | pid ->
     Unix.close w;
     let b = Bytes.create 1 in
     let got = (try Unix.read r b 0 1 = 1 && Bytes.get b 0 = 'y'
                with _ -> false) in
     Unix.close r;
     ignore (Unix.waitpid [] pid);
     let after = acquire ~timeout:2.0 nm in
     ck "C5 dead-holder-releases-without-ttl" (got && after <> None);
     (match after with Some fd -> release fd | None -> ()));

  (try Sys.remove (path_for nm) with _ -> ());
  Printf.printf "uos-plane-lock: checks %d failures %d -- %s\n"
    !n !fails (if !fails = 0 then "PASS" else "FAIL");
  exit (if !fails = 0 then 0 else 1)

let () =
  match Array.to_list Sys.argv with
  | _ :: "--selftest" :: _ -> selftest ()
  | _ :: "--where" :: rest ->
    let nm = match rest with nm :: _ -> nm | [] -> "formal-mojo" in
    print_endline (path_for nm); exit 0
  | _ :: "--check" :: nm :: _ ->
    if held nm then (Printf.printf "plane %s: HELD\n" nm; exit 3)
    else (Printf.printf "plane %s: free\n" nm; exit 0)
  | _ :: "--hold" :: nm :: secs :: _ ->
    (match acquire ~timeout:5.0 nm with
     | None -> prerr_endline "uos-plane-lock: could not acquire"; exit 3
     | Some fd ->
       Printf.printf "plane %s: held by pid %d\n%!" nm (Unix.getpid ());
       ignore (Unix.select [] [] [] (float_of_string secs));
       release fd; exit 0)
  | _ ->
    prerr_endline
      "usage: uos-plane-lock [--check NAME | --hold NAME SECS | --where NAME \
                             | --selftest]";
    exit 2
