(* ZK Gate Isolation Prover — a REAL source-surface isolation audit.

   Promoted from a phase-7 printf stub. The doc-comment CLAIM is a code-path
   invariant: no ZK read/write path may set `harness_runs.status`, so a ZK
   operation can never redden (or falsely green) the canonical build gate. The
   twin `wiki_gate_coupling_prover.ml` mechanizes the RULE-side of this (no gate
   rule consumes a doc fact-kind). This module mechanizes the SOURCE side: it
   scans the ZK/wiki source surface and proves none of it emits a write to
   `harness_runs.status`.

   METHOD. Enumerate the ZK/wiki harness modules (`<root>/harness/{zk_*,wiki_*,
   docs_wiki,notion}.ml`) — the files that make up the ZK read/write surface.
   For each, look for a co-occurrence of `harness_runs` with a SQL mutation verb
   (UPDATE / INSERT INTO harness_runs / status =). Any hit is a coupling offender.
   The write to `harness_runs.status` lives only in the gate writer (`db.ml`), so
   the ZK surface must be clean.

   [LIMITATION] This is a SYNTACTIC scan over source text, not a formal dataflow
   proof — a write reached indirectly (e.g. via a helper in another module the ZK
   code calls) would be invisible here. It establishes "no ZK/wiki module names a
   harness_runs write in its own text", the tractable half of the claim; a true
   proof needs whole-program dataflow (no SMT/dataflow engine is wired). *)

let read_file p =
  let ic = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let substr hay needle =
  let nl = String.length needle and hl = String.length hay in
  if nl = 0 then true
  else
    let rec go i =
      if i + nl > hl then false
      else if String.sub hay i nl = needle then true
      else go (i + 1)
    in
    go 0

let run (root : string) : unit =
  let hdir = Filename.concat root "harness" in
  let is_zk_surface name =
    Filename.check_suffix name ".ml"
    && (let b = Filename.basename name in
        (String.length b >= 3 && String.sub b 0 3 = "zk_")
        || (String.length b >= 5 && String.sub b 0 5 = "wiki_")
        || b = "docs_wiki.ml" || b = "notion.ml")
  in
  let files =
    if Sys.file_exists hdir && Sys.is_directory hdir then
      Array.to_list (Sys.readdir hdir)
      |> List.filter is_zk_surface |> List.sort String.compare
      |> List.map (fun b -> Filename.concat hdir b)
    else []
  in
  let write_markers =
    [ "UPDATE harness_runs"; "INSERT INTO harness_runs";
      "harness_runs SET"; "update_run_status"; "set_status" ]
  in
  let offenders =
    List.filter_map
      (fun p ->
        let src = read_file p in
        if substr src "harness_runs" then
          let hits = List.filter (fun m -> substr src m) write_markers in
          if hits <> [] then Some (Filename.basename p, hits) else None
        else None)
      files
  in
  Printf.printf
    "[zk_gate_isolation_prover] scanned %d ZK/wiki surface modules for a \
     harness_runs.status write\n"
    (List.length files);
  (match offenders with
   | [] ->
       Printf.printf
         "[zk_gate_isolation_prover] ISOLATED: no ZK/wiki module names a \
          harness_runs write in its own text.\n"
   | os ->
       List.iter
         (fun (b, hits) ->
           Printf.printf "[zk_gate_isolation_prover] COUPLED: %s -> %s\n" b
             (String.concat ", " hits))
         os);
  Printf.printf
    "[zk_gate_isolation_prover] [LIMITATION] syntactic source scan, not a \
     whole-program dataflow proof — indirect writes via called helpers are out \
     of scope (no dataflow/SMT engine wired).\n"
