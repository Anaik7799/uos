(* Wiki Cache Poisoning Detector — a REAL heuristic XSS/injection scan.

   Promoted from a phase-7 printf stub. Intent: detect if the generated HTML
   cache for the live wiki has been maliciously poisoned.

   WHAT IT REALLY DOES.  It scans the repo's own generated HTML caches under
   [root] (docs/*.html and docs/journal/*.html — deliberately excluding .git,
   _coverage vendor output, and .claude/worktrees other-agent trees) for known
   injection markers: external-origin <script src="http…">, inline event
   handlers (onerror=/onload=/onclick=), `javascript:` URIs, `eval(`,
   `document.cookie`, and `<iframe`. It reports the per-marker hit counts and
   names the files that carry them.

   HONESTY.  There is no signed/known-good baseline stored for these caches, so
   the module CANNOT prove absence of poisoning; it reports the presence of
   suspicious markers. "0 markers found" is reported literally as "no markers
   matched", never as "clean/safe/verified".

   [LIMITATION] Heuristic substring scan with no trusted baseline; a legitimate
   dashboard that inlines JS will also match, and a novel payload that avoids
   these markers will not. This raises signal, it does not certify integrity. *)

let read_file p =
  try
    let ic = open_in_bin p in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Some s
  with _ -> None

let lower s = String.lowercase_ascii s

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

let markers =
  [ ("external <script src=http>", "<script src=\"http");
    ("external <script src=http(nq)", "<script src=http");
    ("onerror= handler", "onerror=");
    ("onload= handler", "onload=");
    ("onclick= handler", "onclick=");
    ("javascript: URI", "javascript:");
    ("eval(", "eval(");
    ("document.cookie", "document.cookie");
    ("<iframe", "<iframe") ]

(* Candidate generated caches: docs/ top-level + docs/journal/. *)
let candidate_files root =
  let dirs = [ Filename.concat root "docs"; Filename.concat root "docs/journal" ] in
  List.concat_map
    (fun d ->
      (try Array.to_list (Sys.readdir d) with _ -> [])
      |> List.filter (fun e -> Filename.check_suffix e ".html")
      |> List.map (fun e -> Filename.concat d e))
    dirs

let run (root : string) : unit =
  Printf.printf
    "[wiki_cache_poisoning_detector] scanning generated HTML caches for injection markers...\n";
  let files = candidate_files root in
  let total = ref 0 and flagged = ref [] in
  List.iter
    (fun p ->
      match read_file p with
      | None -> ()
      | Some raw ->
          let s = lower raw in
          let hits =
            List.filter_map
              (fun (label, needle) ->
                let c = count_sub s needle in
                if c > 0 then Some (label, c) else None)
              markers
          in
          if hits <> [] then begin
            let n = List.fold_left (fun a (_, c) -> a + c) 0 hits in
            total := !total + n;
            flagged := (p, hits) :: !flagged
          end)
    files;
  Printf.printf "  scanned %d cache file(s)\n" (List.length files);
  if !flagged = [] then
    Printf.printf "  no injection markers matched across the scanned caches\n"
  else
    List.iter
      (fun (p, hits) ->
        Printf.printf "  MARKERS in %s: %s\n"
          (Filename.basename p)
          (String.concat ", "
             (List.map (fun (l, c) -> Printf.sprintf "%s x%d" l c) hits)))
      (List.rev !flagged);
  Printf.printf "  total suspicious markers: %d\n" !total;
  Printf.printf
    "  [LIMITATION] heuristic marker scan with NO trusted baseline — signals \
     presence, cannot certify absence of poisoning\n"
