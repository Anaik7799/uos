(* ZK Query DSL Fuzzer — a REAL, TOTAL-parser robustness probe.

   Promoted from a phase-7 printf stub. The zkquery DSL (Dataview/Bases-shaped
   saved-query language, `Docs_wiki.zkquery_parse`) is documented TOTAL: every
   string maps to `Ok query` or `Error msg`, and the grammar is non-recursive so
   parsing must terminate and never raise. This module CHECKS that claim against
   the REAL parser by bombarding it with malformed / adversarial token streams.

   METHOD. A deterministic (fixed-seed OCaml `Random.State`) generator draws token
   sequences from an alphabet mixing DSL keywords (from/where/and/sort/limit),
   field names, operators, numbers, and pure junk, plus fragments of valid
   queries mutated by deletion/duplication. Each string is fed to the real
   `Docs_wiki.zkquery_parse`; the only failure is an EXCEPTION escaping (a panic),
   which is a real robustness bug. Ok vs Error are both healthy outcomes.

   [NOTE] Track A (this `run`) is bounded random fuzzing (no coverage-guided
   minimization), so it establishes "no panic on N sampled inputs", not a proof of
   totality. It complements the parser's own laws.

   TRACK B (DIVERGENCE 692) discharges the earlier "no SMT" gap: a REAL Z3-backed
   SATISFIABILITY + REDUNDANCY analyzer for the WHERE fragment, over the LIVE
   parser, admitted by a law battery against an independent evaluator — see below
   (`selfcheck` / `check`, `--selfcheck-query-sat` / `--check-query-sat`). *)

module Docs_wiki = Wiki_render.Docs_wiki

let run (root : string) : unit =
  ignore root;
  let st = Random.State.make [| 0x7A6B_9151; 0x4655_5A5A |] in (* "zk"·"FUZZ" *)
  let alphabet =
    [| "from"; "where"; "and"; "sort"; "limit"; "all"; "asc"; "desc";
       "type:note"; "group:x"; "tag:"; "status"; "words"; "degree"; "slug";
       "="; "!="; ">="; "<="; ">"; "<"; "0"; "-1"; "999999999999"; "3.14";
       ""; " "; "=="; "type:"; "\t"; "limitlimit"; "sortsort";
       "\xff\xfe"; "where=and"; "()"; "'; DROP"; "slug=" |]
  in
  let seeds =
    [ "from all"; "from type:note where status=draft sort slug asc limit 5";
      "where words>10 and degree>=2 sort pagerank desc";
      "from group:features--notion where tag=notion" ]
  in
  let rand_string () =
    let n = 1 + Random.State.int st 9 in
    let buf = Buffer.create 32 in
    for _ = 1 to n do
      Buffer.add_string buf alphabet.(Random.State.int st (Array.length alphabet));
      Buffer.add_char buf ' '
    done;
    Buffer.contents buf
  in
  let mutate s =
    match String.split_on_char ' ' s |> List.filter (fun t -> t <> "") with
    | [] -> s
    | toks ->
        let arr = Array.of_list toks in
        let i = Random.State.int st (Array.length arr) in
        (match Random.State.int st 3 with
         | 0 -> arr.(i) <- ""
         | 1 -> arr.(i) <- arr.(i) ^ arr.(i)
         | _ -> arr.(i) <- alphabet.(Random.State.int st (Array.length alphabet)));
        String.concat " " (Array.to_list arr)
  in
  let iters = 20000 in
  let panics = ref 0 and oks = ref 0 and errs = ref 0 in
  let first_panic = ref None in
  let feed s =
    match Docs_wiki.zkquery_parse s with
    | Ok _ -> incr oks
    | Error _ -> incr errs
    | exception e ->
        incr panics;
        if !first_panic = None then first_panic := Some (s, Printexc.to_string e)
  in
  for k = 0 to iters - 1 do
    if k mod 7 = 0 then
      feed (mutate (List.nth seeds (Random.State.int st (List.length seeds))))
    else feed (rand_string ())
  done;
  List.iter feed
    [ ""; " "; "\n\t\r"; "from"; "where"; "sort"; "limit"; "limit x";
      "from :"; "from type:"; "where =5"; "where words="; "where words=abc";
      "sort nonesuch"; String.make 4096 'a'; "from all where and and and" ];
  Printf.printf
    "[zk_query_dsl_fuzzer] fuzzed Docs_wiki.zkquery_parse: %d inputs — %d Ok, \
     %d Error(rejected), %d PANIC\n"
    (iters + 16) !oks !errs !panics;
  (match !first_panic with
   | None ->
       Printf.printf
         "[zk_query_dsl_fuzzer] no exception escaped the parser (TOTAL held on \
          this sample).\n"
   | Some (s, e) ->
       Printf.printf
         "[zk_query_dsl_fuzzer] TOTALITY VIOLATED: input %S raised %s\n" s e);
  Printf.printf
    "[zk_query_dsl_fuzzer] [LIMITATION] bounded random fuzzing over a fixed \
     seed; establishes no-panic on the sampled inputs, not a totality proof.\n"

(* ── TRACK B (DIVERGENCE 692): REAL SMT satisfiability + redundancy analysis of
   the zkquery WHERE fragment, over the LIVE parser. ───────────────────────────
   A WHERE-clause is a CONJUNCTION of `Docs_wiki.zcond`s (field/op/value). The
   numeric fields (`words`/`degree`/`outlinks`/`backlinks`) carry LIA comparisons
   {=,>,>=,<,<=}; the string fields carry equality {=,!=}. This is a DECIDABLE
   fragment (conjunctive LIA + equality), so Z3 decides:
     - SATISFIABILITY — an UNSAT clause is a DEAD query (matches no possible note),
     - REDUNDANCY     — condition C is redundant iff (rest ∧ ¬C) is UNSAT.
   Strings are abstracted to distinct integer codes (sound for =/≠). The subject is
   the LIVE `Docs_wiki.zkquery_parse` output (NOT a reimplemented grammar — this
   discharges the module's earlier "no SMT" limitation), and every SMT verdict is
   admitted against an INDEPENDENT OCaml predicate-evaluator: a `sat` is validated
   by evaluating its model, an `unsat` is refutation-tested over the bounded
   candidate domain. Backend: smtml native `Solver.Batch(Z3_mappings)` (z3 4.16.0).
   Not gate authority; standalone `--check-query-sat` / `--selfcheck-query-sat`. *)

module S = Smtml.Solver.Batch (Smtml.Z3_mappings)

let is_int_field f = List.mem f Docs_wiki.zk_int_fields

let ivar f = Smtml.Expr.symbol (Smtml.Symbol.make Smtml.Ty.Ty_int f)
let ci n = Smtml.Expr.value (Smtml.Value.Int n)
let rel op a b = Smtml.Expr.relop Smtml.Ty.Ty_int op a b

(* a per-analysis string→code table (distinct literals ↦ distinct ints) *)
let make_codes () =
  let tbl = Hashtbl.create 16 and next = ref 0 in
  fun s ->
    match Hashtbl.find_opt tbl s with
    | Some c -> c
    | None -> let c = !next in incr next; Hashtbl.replace tbl s c; c

(* encode one condition as an Int constraint (Relop has no Gt: v>n ≡ n<v) *)
let encode codes (c : Docs_wiki.zcond) =
  let v = ivar c.zf in
  if is_int_field c.zf then
    let n = ci (int_of_string c.zv) in
    match c.zop with
    | ">" -> rel Smtml.Ty.Relop.Lt n v
    | ">=" -> rel Smtml.Ty.Relop.Le n v
    | "<" -> rel Smtml.Ty.Relop.Lt v n
    | "<=" -> rel Smtml.Ty.Relop.Le v n
    | _ -> rel Smtml.Ty.Relop.Eq v n (* "=" (parser forbids != on int) *)
  else
    let code = ci (codes c.zv) in
    (match c.zop with "!=" -> rel Smtml.Ty.Relop.Ne v code | _ -> rel Smtml.Ty.Relop.Eq v code)

(* the negation of a condition (for the redundancy obligation) *)
let neg_encode codes (c : Docs_wiki.zcond) =
  let v = ivar c.zf in
  if is_int_field c.zf then
    let n = ci (int_of_string c.zv) in
    match c.zop with
    | ">" -> rel Smtml.Ty.Relop.Le v n   (* ¬(v>n)=v<=n *)
    | ">=" -> rel Smtml.Ty.Relop.Lt v n  (* ¬(v>=n)=v<n *)
    | "<" -> rel Smtml.Ty.Relop.Le n v   (* ¬(v<n)=n<=v *)
    | "<=" -> rel Smtml.Ty.Relop.Lt n v  (* ¬(v<=n)=n<v *)
    | _ -> rel Smtml.Ty.Relop.Ne v n     (* ¬(v=n)=v!=n *)
  else
    let code = ci (codes c.zv) in
    (match c.zop with "!=" -> rel Smtml.Ty.Relop.Eq v code | _ -> rel Smtml.Ty.Relop.Ne v code)

type sat = Sat of (string * int) list | Unsat | Unknown

let model_env solver =
  match S.model solver with
  | None -> []
  | Some m ->
      List.filter_map (fun (sym, v) ->
        match v with
        | Smtml.Value.Int n -> Some (Format.asprintf "%a" Smtml.Symbol.pp sym, n)
        | _ -> None)
        (Smtml.Model.get_bindings m)

let decide_sat codes (conds : Docs_wiki.zcond list) : sat =
  let s = S.create () in
  S.add s (List.map (encode codes) conds);
  match S.check s [] with
  | `Sat -> Sat (model_env s)
  | `Unsat -> Unsat
  | `Unknown -> Unknown

(* condition i is REDUNDANT iff (rest ∧ ¬C_i) is UNSAT (the rest already implies C_i) *)
let is_redundant codes (conds : Docs_wiki.zcond list) i =
  let c = List.nth conds i in
  let rest = List.filteri (fun j _ -> j <> i) conds in
  let s = S.create () in
  S.add s (neg_encode codes c :: List.map (encode codes) rest);
  match S.check s [] with `Unsat -> true | _ -> false

let has_redundant codes conds =
  List.exists (is_redundant codes conds) (List.init (List.length conds) Fun.id)

(* ── the INDEPENDENT oracle: a concrete predicate-evaluator (never the solver) ─ *)
let eval_cond codes env (c : Docs_wiki.zcond) =
  let v = try List.assoc c.zf env with Not_found -> 0 in
  if is_int_field c.zf then
    let n = int_of_string c.zv in
    (match c.zop with
     | ">" -> v > n | ">=" -> v >= n | "<" -> v < n | "<=" -> v <= n | _ -> v = n)
  else
    let code = codes c.zv in
    (match c.zop with "!=" -> v <> code | _ -> v = code)

let eval_clause codes env conds = List.for_all (eval_cond codes env) conds

(* per-field candidate values (literals ±1 + a fresh value) for refuting an UNSAT *)
let sample_domain codes conds =
  let fields = List.sort_uniq compare (List.map (fun (c : Docs_wiki.zcond) -> c.zf) conds) in
  List.map (fun f ->
    let vals =
      List.filter_map (fun (c : Docs_wiki.zcond) ->
        if c.zf = f then Some (if is_int_field f then int_of_string c.zv else codes c.zv)
        else None) conds
    in
    let extra = List.concat_map (fun v -> [ v - 1; v; v + 1 ]) vals in
    let fresh = List.fold_left max 0 (0 :: vals) + 100 in
    (f, List.sort_uniq compare (fresh :: extra)))
    fields

let rec cartesian = function
  | [] -> [ [] ]
  | (f, vals) :: rest ->
      let tails = cartesian rest in
      List.concat_map (fun v -> List.map (fun t -> (f, v) :: t) tails) vals

(* true iff SOME bounded assignment satisfies the clause (should be false for UNSAT) *)
let some_assignment_satisfies codes conds =
  List.exists (fun env -> eval_clause codes env conds) (cartesian (sample_domain codes conds))

let where_of qstr =
  match Docs_wiki.zkquery_parse qstr with
  | Ok (q : Docs_wiki.zquery) -> Some q.zwhere
  | Error _ -> None

(* extract every ```zkquery block body from the LIVE wiki content — docs/zk (notes)
   and docs/features (feature pages). docs/journal is EXCLUDED: its zkquery blocks
   are historical narrative/examples (some intentionally malformed or dead) and are
   not shipped live queries. *)
let corpus_queries root =
  let acc = ref [] in
  let rec go dir =
    match Sys.readdir dir with
    | entries ->
        Array.iter (fun e ->
          let p = Filename.concat dir e in
          if (try Sys.is_directory p with _ -> false) then go p
          else if Filename.check_suffix e ".md" then
            let raw = try In_channel.with_open_bin p In_channel.input_all with _ -> "" in
            List.iter (fun q -> acc := (Filename.basename p, q) :: !acc) (Docs_wiki.zkquery_blocks raw))
          entries
    | exception _ -> ()
  in
  List.iter (fun sub ->
    let base = Filename.concat (Filename.concat root "docs") sub in
    if (try Sys.is_directory base with _ -> false) then go base)
    [ "zk"; "features" ];
  List.rev !acc

(* ── the fail-closed check: any live corpus query with an UNSAT (dead) clause ── *)
type verdict = Clean | Dead of (string * string) list

let check root : verdict =
  let dead =
    List.filter_map (fun (note, q) ->
      match where_of q with
      | Some (_ :: _ as w) -> if decide_sat (make_codes ()) w = Unsat then Some (note, q) else None
      | _ -> None)
      (corpus_queries root)
  in
  match dead with [] -> Clean | l -> Dead l

(* ── the law battery ─────────────────────────────────────────────────────────── *)
(* (label, query string, expected SATISFIABLE?) — each parsed by the LIVE parser *)
let sat_fixtures =
  [ ("range contradiction  words>5 & words<3", "from all where words>5 and words<3", false);
    ("eq/gt clash          words=2 & words>5", "from all where words=2 and words>5", false);
    ("distinct str clash   status=draft & status=published", "from all where status=draft and status=published", false);
    ("from/where type clash type:note & type=claim", "from type:note where type=claim", false);
    ("nonneg range         words>=0", "from all where words>=0", true);
    ("neq pair             status!=draft & status!=published", "from all where status!=draft and status!=published", true);
    ("independent fields   words>5 & degree>=2", "from all where words>5 and degree>=2", true);
    ("boundary eq          words=10 & words>=10", "from all where words=10 and words>=10", true);
    ("redundant pair sat   words>5 & words>3", "from all where words>5 and words>3", true);
    ("empty where          from all", "from all", true) ]

let selfcheck (root : string) : bool =
  Printf.printf
    "[selfcheck-query-sat] admitting the zkquery WHERE SMT analysis (native Z3) against an independent OCaml predicate-evaluator:\n";
  match
    List.map (fun (label, q, exp) ->
      let w = match where_of q with Some w -> w | None -> [] in
      (label, q, exp, w, make_codes ())) sat_fixtures
  with
  | exception e ->
      Printf.printf "  [LIMITATION] smtml native Z3 unavailable (%s) — install z3; selfcheck FAILS CLOSED\n" (Printexc.to_string e);
      false
  | prepared ->
    (try
      let results = ref [] in
      let law name passed detail = results := (name, passed, detail) :: !results in
      let n = List.length sat_fixtures in
      (* decide every fixture once *)
      let decided = List.map (fun (label, q, exp, w, codes) -> (label, q, exp, w, codes, decide_sat codes w)) prepared in

      (* L1 SOUNDNESS: SAT/UNSAT verdict ≡ hand-labelled truth (parsed live) *)
      let l1_bad = List.filter (fun (_, _, exp, _, _, v) ->
        match v with Sat _ -> not exp | Unsat -> exp | Unknown -> true) decided in
      law "L1 SOUNDNESS decide=label" (l1_bad = [])
        (Printf.sprintf "%d/%d fixtures match the hand label" (n - List.length l1_bad) n);

      (* L2 WITNESS-VALIDITY: every SAT model satisfies the clause per the oracle *)
      let l2_bad = List.filter_map (fun (label, _, _, w, codes, v) ->
        match v with Sat env -> if eval_clause codes env w then None else Some label | _ -> None) decided in
      let n_sat = List.length (List.filter (fun (_,_,_,_,_,v) -> match v with Sat _ -> true | _ -> false) decided) in
      law "L2 WITNESS-VALIDITY sat-model-checked" (l2_bad = [])
        (Printf.sprintf "%d/%d SAT models validated by eval" (n_sat - List.length l2_bad) n_sat);

      (* L3 UNSAT-REFUTATION: no bounded assignment satisfies an UNSAT clause *)
      let l3_bad = List.filter_map (fun (label, _, _, w, codes, v) ->
        match v with Unsat -> if some_assignment_satisfies codes w then Some label else None | _ -> None) decided in
      let n_unsat = List.length (List.filter (fun (_,_,_,_,_,v) -> v = Unsat) decided) in
      law "L3 UNSAT-REFUTATION no-model-in-domain" (l3_bad = [])
        (Printf.sprintf "%d/%d UNSAT clauses survive bounded refutation" (n_unsat - List.length l3_bad) n_unsat);

      (* L4 REDUNDANCY: the redundant fixture has a redundant condition; the
         independent-fields fixture has none (detected via rest ∧ ¬C UNSAT) *)
      let red_codes = make_codes () and ind_codes = make_codes () in
      let red_w = Option.value ~default:[] (where_of "from all where words>5 and words>3") in
      let ind_w = Option.value ~default:[] (where_of "from all where words>5 and degree>=2") in
      let red_ok = has_redundant red_codes red_w and ind_ok = not (has_redundant ind_codes ind_w) in
      law "L4 REDUNDANCY implied-detected independent-not" (red_ok && ind_ok)
        (Printf.sprintf "words>3⊑words>5 flagged:%b  independent-clean:%b" red_ok ind_ok);

      (* L5 LIVE-PARSER FIDELITY: every fixture parsed via the REAL parser (no
         reimplemented grammar), and field typing = Docs_wiki.zk_int_fields *)
      let parsed_ok = List.for_all (fun (_, q, _, _, _) -> where_of q <> None) prepared in
      let typing_ok =
        List.for_all (fun f -> is_int_field f) Docs_wiki.zk_int_fields
        && List.for_all (fun f -> not (is_int_field f)) Docs_wiki.zk_str_fields in
      law "L5 LIVE-PARSER-FIDELITY real-parse+typing" (parsed_ok && typing_ok)
        (Printf.sprintf "all-fixtures-parse:%b field-typing=Docs_wiki:%b" parsed_ok typing_ok);

      (* L6 TOTALITY: every clause decides SAT/UNSAT, none Unknown (decidable) *)
      let n_unknown = List.length (List.filter (fun (_,_,_,_,_,v) -> v = Unknown) decided) in
      law "L6 TOTALITY no-unknown" (n_unknown = 0)
        (Printf.sprintf "%d/%d decided, %d unknown" (n - n_unknown) n n_unknown);

      (* L7 LIVE-CORPUS: no shipped zkquery block is a dead (UNSAT) query *)
      let cq = corpus_queries root in
      let dead = List.filter_map (fun (_, q) ->
        match where_of q with Some (_::_ as w) -> if decide_sat (make_codes ()) w = Unsat then Some q else None | _ -> None) cq in
      law "L7 LIVE-CORPUS no-dead-query" (dead = [])
        (Printf.sprintf "%d corpus queries, %d dead (UNSAT)" (List.length cq) (List.length dead));

      let laws = List.rev !results in
      List.iter (fun (nm, ok, detail) ->
        Printf.printf "  %s %-40s %s\n" (if ok then "OK " else "RED") nm detail) laws;
      let passed = List.for_all (fun (_, ok, _) -> ok) laws in
      Printf.printf "[selfcheck-query-sat] %d/%d laws passed%s\n"
        (List.length (List.filter (fun (_, ok, _) -> ok) laws)) (List.length laws)
        (if passed then "" else " — FAIL CLOSED");
      passed
    with e ->
      Printf.printf "  [LIMITATION] smtml native Z3 unavailable (%s) — install z3; selfcheck FAILS CLOSED\n" (Printexc.to_string e);
      false)
