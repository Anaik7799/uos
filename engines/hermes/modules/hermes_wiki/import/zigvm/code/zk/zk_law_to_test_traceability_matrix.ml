(* ZK Law -> Test Traceability Matrix — a REAL cross-reference builder.

   Promoted from a phase-7 printf stub. Intent (from the stub): link the ZK
   algebraic laws to the Zig property tests that discharge them.

   WHAT IT REALLY DOES.  It reads two real corpora under [root]:
     - src/*.zig — the implementation, which tags laws with `LAW <token>`
       markers and exercises them in `test "<name>"` blocks;
     - docs/zk/**/*.md — the knowledge base, where laws are referenced in prose.
   It extracts the set of law tokens from the Zig sources, the count of test
   blocks, and the set of law tokens actually mentioned somewhere in the ZK
   corpus, then reports the traceability matrix: how many declared laws are
   traced into the knowledge base and how many are untraced.

   No verdict is manufactured: it reports the real counts and a sample of
   untraced laws. It never claims a law is "proven" — that is the Zig suite's
   job, not this matrix's.

   [LIMITATION] Law<->note linkage is by TEXTUAL token match (the `LAW X`
   marker vs note prose), not by executing the suite; a law whose token is
   spelled differently in a note reads as untraced. *)

let read_file p =
  try
    let ic = open_in_bin p in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Some s
  with _ -> None

let rec walk dir f =
  Array.iter
    (fun e ->
      let p = Filename.concat dir e in
      match (try Some (Sys.is_directory p) with _ -> None) with
      | Some true -> walk p f
      | Some false -> f p
      | None -> ())
    (try Sys.readdir dir with _ -> [||])

let is_law_char c =
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
  || c = '-' || c = '.' || c = '_'

(* All start indices of [needle] in [hay]. *)
let indices_of hay needle =
  let nl = String.length needle and hl = String.length hay in
  if nl = 0 || hl < nl then []
  else begin
    let res = ref [] and i = ref 0 in
    while !i <= hl - nl do
      if String.sub hay !i nl = needle then (res := !i :: !res; i := !i + nl)
      else incr i
    done;
    List.rev !res
  end

let contains hay needle = indices_of hay needle <> []

(* Extract the token following each occurrence of [marker] (e.g. "LAW "). *)
let tokens_after hay marker =
  let ml = String.length marker and hl = String.length hay in
  List.filter_map
    (fun start ->
      let j = ref (start + ml) in
      let b = Buffer.create 16 in
      while !j < hl && is_law_char hay.[!j] do
        Buffer.add_char b hay.[!j];
        incr j
      done;
      let t = Buffer.contents b in
      if String.length t >= 2 then Some t else None)
    (indices_of hay marker)

module SS = Set.Make (String)

let run (root : string) : unit =
  Printf.printf
    "[zk_law_to_test_traceability_matrix] tracing LAW markers (src) -> ZK corpus...\n";
  let src_dir = Filename.concat root "src" in
  let laws = ref SS.empty and tests = ref 0 and src_files = ref 0 in
  Array.iter
    (fun e ->
      if Filename.check_suffix e ".zig" then
        match read_file (Filename.concat src_dir e) with
        | None -> ()
        | Some s ->
            incr src_files;
            List.iter (fun t -> laws := SS.add t !laws) (tokens_after s "LAW ");
            tests := !tests + List.length (indices_of s "test \""))
    (try Sys.readdir src_dir with _ -> [||]);
  let corpus = Buffer.create (1 lsl 20) and zk_files = ref 0 in
  walk (Filename.concat root "docs/zk") (fun p ->
      if Filename.check_suffix p ".md" then
        match read_file p with
        | Some s -> incr zk_files; Buffer.add_string corpus s; Buffer.add_char corpus '\n'
        | None -> ());
  let corpus = Buffer.contents corpus in
  let traced, untraced =
    SS.fold
      (fun law (tr, un) ->
        if contains corpus law then (law :: tr, un) else (tr, law :: un))
      !laws ([], [])
  in
  let n_laws = SS.cardinal !laws in
  let n_traced = List.length traced in
  Printf.printf
    "  scanned %d src/*.zig (%d LAW tokens, %d test blocks) + %d ZK notes\n"
    !src_files n_laws !tests !zk_files;
  Printf.printf
    "  MATRIX: %d/%d law tokens traced into the ZK corpus (%.0f%%), %d untraced\n"
    n_traced n_laws
    (if n_laws = 0 then 0. else 100. *. float n_traced /. float n_laws)
    (List.length untraced);
  let sample lbl l =
    let s = List.filteri (fun i _ -> i < 8) (List.sort compare l) in
    if s <> [] then Printf.printf "  %s: %s\n" lbl (String.concat ", " s)
  in
  sample "sample traced" traced;
  sample "sample untraced" untraced;
  Printf.printf
    "  [LIMITATION] textual token match (LAW marker vs note prose); not a suite \
     run and not a proof of discharge\n"
