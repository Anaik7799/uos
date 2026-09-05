(* Re-baseline the corpus. This ACCEPTS a corpus-wide rendering change and
   is therefore NEVER run by the battery (zigvm §11): running it without a
   stated reason is exactly how silent drift enters.

   R19: it rewrites a TRACKED gate artifact, so it validates before it
   writes, writes atomically, and exits non-zero when it refuses. Before
   2026-08-09 it did none of those: an empty corpus — which a failed
   `git ls-files` produced silently — truncated the baseline to zero
   bytes and printed "re-baselined 0 documents" with exit 0. The gate
   that protects every render could be destroyed by running the tool
   from the wrong directory. *)

(* A corpus this small is not a corpus; it is a symptom. The pinned root
   has carried 239+ documents all year, so the floor is generous and
   still catches every realistic failure (empty, a handful, a wrong
   root). Deliberately shrinking the corpus below it means passing the
   floor explicitly, which is a decision someone has to write down. *)
let default_floor = 50

let read_whole path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let usage () =
  prerr_endline
    "usage: gen_render_baseline [ROOT [OUT]] [--floor N]\n\
    \  ROOT   repository root (default .)\n\
    \  OUT    baseline path (default ROOT/modules/hermes_wiki/baseline/render-baseline.txt)\n\
    \  --floor N  refuse to write fewer than N documents (default 50)\n\
    \  --accept-removals  acknowledge that pages which no longer render were\n\
    \                     deliberately deleted (blocks without it)";
  exit 2

let () =
  (* R19: an unknown flag is REFUSED, never taken as a positional. `--help`
     used to be read as a repository root. *)
  let positional = ref [] and floor = ref default_floor in
  let accept_removals = ref false in
  let args = Array.to_list Sys.argv in
  let rec parse = function
    | [] -> ()
    | "--accept-removals" :: rest -> accept_removals := true; parse rest
    | "--floor" :: n :: rest -> (
        match int_of_string_opt n with
        | Some v when v >= 0 -> floor := v; parse rest
        | _ -> usage ())
    | a :: _ when String.length a > 0 && a.[0] = '-' -> usage ()
    | a :: rest -> positional := a :: !positional; parse rest
  in
  (match args with _ :: rest -> parse rest | [] -> ());
  let positional = List.rev !positional in
  if List.length positional > 2 then usage ();
  let root = match positional with r :: _ -> r | [] -> "." in
  let out =
    match positional with
    | _ :: o :: _ -> o
    | _ -> Filename.concat root "modules/hermes_wiki/baseline/render-baseline.txt"
  in
  let files =
    try Hermes_wiki.read_tracked (Filename.concat root "modules/hermes_wiki/pages") with
    | Hermes_wiki.Corpus_unreadable reason ->
        Printf.eprintf
          "[L0/product environment] REFUSED: %s\n\
          \  cause: the corpus could not be determined, so the baseline it would\n\
          \         produce would be a fiction\n\
          \  fix:   run from the repository root inside the git work tree\n"
          reason;
        exit 1
  in
  let model = Hermes_wiki.build ~read_source:Hermes_wiki.read_source_file files in
  let documents =
    List.map
      (fun (p : Hermes_wiki.page) -> (p.Hermes_wiki.path, p.Hermes_wiki.raw, p.Hermes_wiki.html))
      model.Hermes_wiki.pages
  in
  let entries = Wiki_baseline.build documents in
  let n = List.length entries in
  (* VALIDATE BEFORE WRITING — nothing touches the artifact until here. *)
  if n < !floor then begin
    Printf.eprintf
      "[L0/product environment] REFUSED: %d documents is below the floor of %d\n\
      \  cause: a corpus this small means a wrong root, a failed oracle, or a\n\
      \         deletion — writing the baseline now would destroy the gate\n\
      \  fix:   check the root, or pass --floor %d deliberately if the corpus\n\
      \         really did shrink\n"
      n !floor n;
    exit 1
  end;
  (* THE ACCEPTANCE RATCHET (R30). A floor on document COUNT cannot see a
     change that guts a hundred pages while keeping the count, so every pin
     delta is classified before the artifact is touched. A REMOVAL blocks:
     a page that stopped rendering is indistinguishable from one deliberately
     deleted, and a regression looks exactly like intent. Acknowledging it is
     a claim the operator makes on the command line, never an inference this
     tool draws. *)
  (match (try Some (read_whole out) with _ -> None) with
   | None ->
       print_string "triage: no prior baseline — first pin, nothing to classify\n"
   | Some previous -> (
       match Baseline_triage.parse previous with
       | Error message ->
           Printf.eprintf "[LX/control-plane control] REFUSED: %s\n" message;
           exit 2
       | Ok before -> (
           match Baseline_triage.parse (String.concat "\n" (Wiki_baseline.to_lines entries)) with
           | Error message ->
               Printf.eprintf "[LX/control-plane control] REFUSED: %s\n" message;
               exit 2
           | Ok after ->
               let deltas = Baseline_triage.classify ~before ~after in
               print_string (Baseline_triage.render deltas);
               (match Baseline_triage.verdict ~accept_removals:!accept_removals deltas with
                | Baseline_triage.Block ->
                    prerr_endline
                      "[LX/control-plane control] REFUSED: pages present in the pinned\n\
                      \  baseline no longer render. A page that stopped rendering looks\n\
                      \  identical to one deliberately deleted, so this needs a human\n\
                      \  claim: re-run with --accept-removals if the deletion is intended.";
                    exit 2
                | Baseline_triage.Review | Baseline_triage.Auto -> ()))));
  (* ATOMIC: open_out truncates in place, so an interrupt would leave the
     gate half-written. rename(2) is atomic within a filesystem. *)
  let tmp = out ^ ".tmp" in
  (match
     try
       let channel = open_out_bin tmp in
       Fun.protect
         ~finally:(fun () -> close_out_noerr channel)
         (fun () ->
           List.iter
             (fun line -> output_string channel (line ^ "\n"))
             (Wiki_baseline.to_lines entries));
       Some ()
     with _ -> None
   with
  | Some () -> Sys.rename tmp out
  | None ->
      Printf.eprintf "[L0/product environment] REFUSED: could not write %s\n" tmp;
      (try Sys.remove tmp with _ -> ());
      exit 1);
  Printf.printf "re-baselined %d documents -> %s\n" n out
