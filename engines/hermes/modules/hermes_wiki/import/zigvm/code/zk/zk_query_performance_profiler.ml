(* ZK Query Performance Profiler — a REAL timing profile of zkquery workload.

   Promoted from a phase-7 printf stub. Intent: profile the execution time of
   zkquery blocks so the live wiki stays fast.

   WHAT IT REALLY DOES.  It finds every ```zkquery fenced block in the real ZK
   corpus (docs/zk/**/*.md) under [root], and profiles the actual cost a live
   executor would pay to answer them: it times (Unix.gettimeofday) the full
   corpus read + scan pass that any query engine must perform, reports per-file
   zkquery block counts, the total block count, corpus byte volume, and the
   measured wall-clock of the scan, plus a derived per-block amortised time.

   HONESTY.  There is no wired zkquery execution engine in this harness
   (`zk_query_live_executor` is itself a stub), so the module does NOT claim to
   have executed the queries. It measures the corpus-scan latency that bounds
   query cost, and says so.

   [LIMITATION] No live zkquery engine is wired; this profiles corpus
   ingest+scan latency as a proxy lower-bound for query cost, not the queries'
   own evaluation. Wall time is a single sample (not a distribution). *)

let rec walk dir f =
  Array.iter
    (fun e ->
      let p = Filename.concat dir e in
      match (try Some (Sys.is_directory p) with _ -> None) with
      | Some true -> walk p f
      | Some false -> f p
      | None -> ())
    (try Sys.readdir dir with _ -> [||])

let read_file p =
  try
    let ic = open_in_bin p in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Some s
  with _ -> None

let count_sub hay needle =
  let nl = String.length needle and hl = String.length hay in
  if nl = 0 || hl < nl then 0
  else begin
    let c = ref 0 and i = ref 0 in
    while !i <= hl - nl do
      if String.sub hay !i nl = needle then (incr c; i := !i + nl) else incr i
    done;
    !c
  end

let run (root : string) : unit =
  Printf.printf
    "[zk_query_performance_profiler] profiling zkquery workload over the corpus...\n";
  let t0 = Unix.gettimeofday () in
  let files = ref [] and bytes = ref 0 and blocks = ref 0 and mentions = ref 0 in
  walk (Filename.concat root "docs/zk") (fun p ->
      if Filename.check_suffix p ".md" then
        match read_file p with
        | Some s ->
            bytes := !bytes + String.length s;
            mentions := !mentions + count_sub s "zkquery";
            let n = count_sub s "```zkquery" in
            if n > 0 then begin
              blocks := !blocks + n;
              files := (p, n) :: !files
            end
        | None -> ());
  let dt_ms = (Unix.gettimeofday () -. t0) *. 1000. in
  Printf.printf "  corpus scan: %d bytes read, %.3f ms wall\n" !bytes dt_ms;
  Printf.printf "  zkquery FENCED blocks found: %d across %d file(s) (inline prose mentions: %d)\n"
    !blocks (List.length !files) !mentions;
  List.iter
    (fun (p, n) -> Printf.printf "    %-44s : %d block(s)\n" (Filename.basename p) n)
    (List.sort compare !files);
  if !blocks > 0 then
    Printf.printf "  amortised scan cost per zkquery block: %.4f ms\n"
      (dt_ms /. float !blocks);
  Printf.printf
    "  [LIMITATION] no live zkquery engine wired (zk_query_live_executor is a \
     stub); this profiles corpus ingest+scan latency as a proxy lower-bound, \
     single sample\n"
