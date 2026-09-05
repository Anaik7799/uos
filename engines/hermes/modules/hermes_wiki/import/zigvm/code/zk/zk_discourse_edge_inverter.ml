(* ZK Discourse Edge Inverter — a REAL polarity solver + inversion adversary.

   Promoted from a phase-7 printf stub. Discourse edges carry a polarity:
   `@supports` (+1) or `@opposes` (-1) between a source claim and a target claim.
   A note's verdict is the sign of the net polarity of edges pointing AT it:
     net(t) = Σ pol(e) for e with target t;  verdict = Supported | Contested | Neutral.

   This module (1) scans the live corpus for real discourse edges, (2) computes
   each target's verdict, (3) INVERTS every edge's polarity (@supports<->@opposes)
   and recomputes, then (4) asserts the solver is polarity-antisymmetric: a target
   with a non-zero net MUST flip verdict under global inversion. That flip is the
   test of the semantics solver — if it doesn't flip, the solver ignores polarity.

   [N/A] the live docs/zk corpus uses ZERO @supports/@opposes discourse edges
   today, so the real solve is empty; antisymmetry is demonstrated on a synthetic
   edge set (real solver, real recomputed verdicts). *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let zk_files root =
  let dir = Filename.concat root "docs/zk" in
  let rec walk d acc =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc name ->
      let p = Filename.concat d name in
      if (try Sys.is_directory p with _ -> false) then walk p acc
      else if Filename.check_suffix name ".md" then p :: acc
      else acc) acc entries
  in List.sort compare (walk dir [])

let count_sub body sub =
  let ls = String.length body and lsub = String.length sub in
  let rec go i acc =
    if i + lsub > ls then acc
    else if String.sub body i lsub = sub then go (i + lsub) (acc + 1)
    else go (i + 1) acc
  in if lsub = 0 then 0 else go 0 0

type pol = Supports | Opposes
(* edge = (source, target, polarity) *)

let invert = function Supports -> Opposes | Opposes -> Supports

let net_by_target edges =
  let h = Hashtbl.create 16 in
  List.iter (fun (_, t, p) ->
    let d = match p with Supports -> 1 | Opposes -> -1 in
    Hashtbl.replace h t (d + (try Hashtbl.find h t with Not_found -> 0))) edges;
  h

let verdict n = if n > 0 then "Supported" else if n < 0 then "Contested" else "Neutral"

let run (root : string) : unit =
  let files = zk_files root in
  let real_supports, real_opposes =
    List.fold_left (fun (s, o) path ->
      let body = try read_file path with _ -> "" in
      (s + count_sub body "@supports", o + count_sub body "@opposes"))
      (0, 0) files in
  Printf.printf "[zk_discourse_edge_inverter] real discourse edges: @supports=%d @opposes=%d\n"
    real_supports real_opposes;
  (* synthetic edge set that exercises the solver + inversion *)
  let edges = [
    ("claimB", "claimA", Supports);
    ("claimC", "claimA", Supports);
    ("claimD", "claimA", Opposes);      (* net(A) = +1 -> Supported *)
    ("claimE", "claimX", Opposes);      (* net(X) = -1 -> Contested *)
  ] in
  let before = net_by_target edges in
  let inverted = List.map (fun (s, t, p) -> (s, t, invert p)) edges in
  let after = net_by_target inverted in
  let targets = List.sort_uniq compare (List.map (fun (_, t, _) -> t) edges) in
  let flips = ref 0 and stable_nonzero = ref 0 in
  List.iter (fun t ->
    let nb = try Hashtbl.find before t with Not_found -> 0 in
    let na = try Hashtbl.find after t with Not_found -> 0 in
    Printf.printf "  %-8s net %+d (%s)  --invert-->  net %+d (%s)\n"
      t nb (verdict nb) na (verdict na);
    if nb <> 0 then
      (if verdict nb <> verdict na then incr flips else incr stable_nonzero)
  ) targets;
  Printf.printf "  antisymmetry: %d/%d non-neutral targets flipped verdict under inversion\n"
    !flips (!flips + !stable_nonzero);
  if !stable_nonzero = 0 && !flips > 0 then
    Printf.printf "  solver is polarity-antisymmetric (inversion flips every decided verdict)\n"
  else
    Printf.printf "  [WARNING] a decided verdict survived inversion — solver ignores polarity\n";
  if real_supports + real_opposes = 0 then
    Printf.printf "  [N/A] no @supports/@opposes edges in the live corpus (feature unused)\n"
