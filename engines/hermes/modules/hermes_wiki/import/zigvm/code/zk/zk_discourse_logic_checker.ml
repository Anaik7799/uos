(* ZK Discourse Logic Checker — a REAL argumentation-well-formedness audit.

   Promoted from a phase-7 printf stub. The wiki supports TYPED semantic edges
   `[[Target|@relation]]` (Docs_wiki: `zettel_typed`), the substrate for a Dung
   argumentation graph. The grounded-semantics well-formedness rule this module
   checks: an ATTACK edge (@opposes / @refutes / @contradicts / @rebuts) must be
   BACKED — the asserting note must also carry at least one EVIDENCE edge
   (@evidences / @cites / @supports / @grounds). An unbacked attack is a bare
   assertion, inadmissible as grounded evidence.

   METHOD. Scan `<root>/docs/zk/**/*.md`; extract every `[[Target|@rel]]` typed
   edge per note with a total, non-recursive string parser (mirrors the renderer's
   grammar). Partition each note's relations into attack vs evidence; flag any
   note that asserts an attack with zero evidence edges.

   [N/A] The corpus currently uses NO @opposes-family discourse edges (typed edges
   are near-absent). The check is real and the well-formedness property holds
   VACUOUSLY — reported honestly as an unused feature, not a fabricated pass. It
   is NOT a full Dung grounded-extension solver (no fixpoint over the attack
   relation); that is a named, unimplemented extension. *)

let read_file p =
  let ic = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let rec walk_md dir =
  if Sys.file_exists dir && Sys.is_directory dir then
    Array.to_list (Sys.readdir dir)
    |> List.sort String.compare
    |> List.concat_map (fun e ->
           let p = Filename.concat dir e in
           if (try Sys.is_directory p with Sys_error _ -> false) then walk_md p
           else if Filename.check_suffix p ".md" then [ p ]
           else [])
  else []

(* extract the @relation of every [[Target|@rel]] wikilink in a note (total) *)
let typed_relations (raw : string) : string list =
  let n = String.length raw in
  let acc = ref [] in
  let i = ref 0 in
  while !i + 1 < n do
    if raw.[!i] = '[' && raw.[!i + 1] = '[' then (
      (* find closing ]] *)
      let j = ref (!i + 2) in
      let closed = ref (-1) in
      while !j + 1 < n && !closed < 0 do
        if raw.[!j] = ']' && raw.[!j + 1] = ']' then closed := !j
        else incr j
      done;
      if !closed >= 0 then (
        let inner = String.sub raw (!i + 2) (!closed - (!i + 2)) in
        (match String.index_opt inner '|' with
         | Some bar ->
             let disp =
               String.trim (String.sub inner (bar + 1) (String.length inner - bar - 1))
             in
             if String.length disp > 0 && disp.[0] = '@' then
               acc := String.sub disp 1 (String.length disp - 1) :: !acc
         | None -> ());
        i := !closed + 2)
      else i := n)
    else incr i
  done;
  List.rev !acc

let run (root : string) : unit =
  let zk_dir = Filename.concat root "docs/zk" in
  let files = walk_md zk_dir in
  let attack = [ "opposes"; "refutes"; "contradicts"; "rebuts" ] in
  let evidence = [ "evidences"; "cites"; "supports"; "grounds" ] in
  let total_typed = ref 0 and total_attack = ref 0 in
  let violations = ref [] in
  List.iter
    (fun p ->
      let slug = Filename.remove_extension (Filename.basename p) in
      let rels = typed_relations (read_file p) in
      total_typed := !total_typed + List.length rels;
      let has_attack = List.exists (fun r -> List.mem r attack) rels in
      let has_evidence = List.exists (fun r -> List.mem r evidence) rels in
      let attacks = List.filter (fun r -> List.mem r attack) rels in
      total_attack := !total_attack + List.length attacks;
      if has_attack && not has_evidence then
        violations := (slug, attacks) :: !violations)
    files;
  Printf.printf
    "[zk_discourse_logic_checker] scanned %d notes: %d typed edges, %d attack \
     edges (@opposes-family), %d unbacked-attack violations\n"
    (List.length files) !total_typed !total_attack (List.length !violations);
  (match !violations with
   | [] when !total_attack = 0 ->
       Printf.printf
         "[zk_discourse_logic_checker] [N/A] no @opposes-family discourse edges \
          in the corpus — well-formedness holds vacuously (feature unused).\n"
   | [] ->
       Printf.printf
         "[zk_discourse_logic_checker] WELL-FORMED: every attack edge is backed \
          by an evidence edge in its asserting note.\n"
   | vs ->
       List.iter
         (fun (slug, atks) ->
           Printf.printf
             "[zk_discourse_logic_checker] UNBACKED ATTACK: %s asserts @%s with \
              no evidence edge\n"
             slug
             (String.concat "/@" (List.sort_uniq String.compare atks)))
         (List.rev vs));
  Printf.printf
    "[zk_discourse_logic_checker] [LIMITATION] checks per-note attack/evidence \
     backing, not a full Dung grounded-extension fixpoint (unimplemented).\n"
