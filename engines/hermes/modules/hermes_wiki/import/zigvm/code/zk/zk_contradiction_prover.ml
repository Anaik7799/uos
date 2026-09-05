(* ZK Contradiction Prover — a REAL Dung grounded-semantics fixpoint over the
   knowledge base's argumentation (attack) graph.

   Promoted from a phase-7 printf stub. Intent: analyse Dung grounded semantics
   to surface logical contradictions in the ZK graph.

   ALGORITHM (real, not fiction).  An abstract argumentation framework is
   (Args, Attacks) with Attacks subset of Args x Args. The grounded extension is
   the least fixpoint of the characteristic function
       F(S) = { a | a is acceptable wrt S }
   where a is acceptable wrt S iff every b that attacks a is itself attacked by
   some c in S. This module computes that fixpoint iteratively from the empty
   set. Contradiction signals it derives from the framework:
     - self-attacks  (a -> a): a is never acceptable — a paraconsistent node;
     - 2-cycles      (a -> b, b -> a) with neither defended: both fall OUTSIDE
       the grounded extension (the classic "undecided/contradiction" pair).

   THE ATTACK GRAPH.  ZK discourse/attack edges are extracted from the real
   corpus by scanning docs/zk/**/*.md for typed discourse links of the form
   [[target|@rel]] whose relation is an attack relation
   (refute/refutes/attack/attacks/contradicts/rebuts/counters), and from
   onto_edge rows whose `rel` is an attack relation.

   HONESTY.  If NO attack edges exist, the module says so and reports the
   grounded fixpoint's trivial result (every argument in, zero contradictions),
   labelled [N/A] feature unused — it does NOT claim to have "proven consistency".

   [N/A] The discourse/attack-edge feature is currently unused in the corpus;
   the count is reported. The grounded-semantics fixpoint below is real and will
   produce non-trivial extensions the moment attack edges are authored. *)

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

let attack_rels =
  [ "refute"; "refutes"; "attack"; "attacks"; "contradict"; "contradicts";
    "rebut"; "rebuts"; "counter"; "counters" ]

(* Extract [[target|@rel]] discourse edges with an attack relation. Returns
   (src_slug, dst_slug) pairs. src is the file's slug. *)
let extract_md_attacks path text =
  let src = Filename.remove_extension (Filename.basename path) in
  let hl = String.length text in
  let edges = ref [] and i = ref 0 in
  while !i < hl - 1 do
    if text.[!i] = '[' && text.[!i + 1] = '[' then begin
      (* read until closing ]] *)
      let j = ref (!i + 2) in
      let b = Buffer.create 32 in
      while !j < hl - 1 && not (text.[!j] = ']' && text.[!j + 1] = ']') do
        Buffer.add_char b text.[!j];
        incr j
      done;
      let inner = Buffer.contents b in
      (match String.split_on_char '|' inner with
       | [ target; rel ] ->
           let rel =
             let r = String.trim rel in
             if String.length r > 0 && r.[0] = '@' then
               String.sub r 1 (String.length r - 1)
             else r
           in
           if List.mem (String.lowercase_ascii rel) attack_rels then
             edges := (src, String.trim target) :: !edges
       | _ -> ());
      i := !j + 2
    end
    else incr i
  done;
  !edges

module SS = Set.Make (String)
module PS = Set.Make (struct type t = string * string let compare = compare end)

(* Grounded extension: least fixpoint of the characteristic function. *)
let grounded (args : SS.t) (attacks : PS.t) : SS.t =
  let attackers_of a =
    PS.fold (fun (x, y) acc -> if y = a then x :: acc else acc) attacks []
  in
  let acceptable s a =
    (* every attacker b of a is attacked by some c in s *)
    List.for_all
      (fun b -> List.exists (fun c -> PS.mem (c, b) attacks) (SS.elements s))
      (attackers_of a)
  in
  let step s = SS.filter (fun a -> acceptable s a) args in
  let rec fix s =
    let s' = step s in
    if SS.equal s s' then s else fix s'
  in
  fix SS.empty

let run (root : string) : unit =
  Printf.printf
    "[zk_contradiction_prover] grounded-semantics fixpoint over the ZK attack graph...\n";
  (* corpus attack edges *)
  let edges = ref [] and md_files = ref 0 in
  walk (Filename.concat root "docs/zk") (fun p ->
      if Filename.check_suffix p ".md" then
        match read_file p with
        | Some t -> incr md_files; edges := extract_md_attacks p t @ !edges
        | None -> ());
  (* onto_edge attack rows *)
  let db_path = Filename.concat root "harness/state/zigvm_harness.sqlite3" in
  if Sys.file_exists db_path then begin
    (match (try `Db (Sqlite3.db_open ~mode:`READONLY db_path) with e -> `Err e) with
     | `Err _ -> ()
     | `Db db ->
         Fun.protect
           ~finally:(fun () -> ignore (Sqlite3.db_close db))
           (fun () ->
             let cb (row : Sqlite3.row) _ =
               match (row.(0), row.(1), row.(2)) with
               | Some src, Some rel, Some dst ->
                   if List.mem (String.lowercase_ascii rel) attack_rels then
                     edges := (src, dst) :: !edges
               | _ -> ()
             in
             ignore (Sqlite3.exec db ~cb "SELECT src, rel, dst FROM onto_edge;")))
  end;
  let attacks = PS.of_list !edges in
  let args =
    PS.fold (fun (a, b) acc -> SS.add a (SS.add b acc)) attacks SS.empty
  in
  let self_attacks = PS.filter (fun (a, b) -> a = b) attacks in
  let two_cycles =
    PS.filter (fun (a, b) -> a <> b && PS.mem (b, a) attacks) attacks
  in
  let ext = grounded args attacks in
  (* contradictions = args excluded from grounded that sit in a self-attack or
     mutual-attack — the paraconsistent / undecided nodes *)
  let contradictions =
    SS.filter
      (fun a ->
        (not (SS.mem a ext))
        && (PS.mem (a, a) attacks
            || PS.exists (fun (x, y) -> (x = a && PS.mem (y, x) attacks)) attacks))
      args
  in
  Printf.printf
    "  scanned %d ZK notes + onto_edge; attack edges=%d, arguments=%d\n"
    !md_files (PS.cardinal attacks) (SS.cardinal args);
  if PS.is_empty attacks then
    Printf.printf
      "  [N/A] discourse/attack-edge feature unused — 0 attack edges found; \
       grounded extension trivially = all %d arguments, 0 contradictions\n"
      (SS.cardinal args)
  else begin
    Printf.printf
      "  grounded extension size=%d ; self-attacks=%d ; 2-cycles=%d ; \
       contradiction nodes=%d\n"
      (SS.cardinal ext) (PS.cardinal self_attacks)
      (PS.cardinal two_cycles / 2) (SS.cardinal contradictions);
    let sample = List.filteri (fun i _ -> i < 8) (SS.elements contradictions) in
    if sample <> [] then
      Printf.printf "  contradiction nodes (sample): %s\n" (String.concat ", " sample)
  end;
  Printf.printf
    "  [NOTE] grounded-semantics fixpoint is real; verdict scales with authored \
     attack edges (none required to exist today)\n"
