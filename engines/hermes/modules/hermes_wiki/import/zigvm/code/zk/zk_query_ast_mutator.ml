(* ZK Query AST Mutator — a REAL AST-level fuzzer for the zkquery DSL.

   Promoted from a phase-7 printf stub. The zkquery DSL (mirrored from
   Docs_wiki.zkquery_parse, journal 20260729-1056 §7.7) has the shape:

     [from (all|type:T|group:G|tag:T)] [where COND (and COND)*]
     [sort KEY [asc|desc]] [limit N]
     COND := FIELD(=|!=)VALUE  (str) | FIELD(=|>|>=|<|<=)N  (numeric)

   This module carries a SELF-CONTAINED reimplementation of that grammar as an
   OCaml AST + a total serializer + a total parser, then applies structural
   MUTATION operators to the AST (swap operator, corrupt field name, flip
   numeric/string field, drop/duplicate a condition, negate a limit, inject a
   stray token) and re-parses the mutated string. The property under test is the
   TRANSLATION-ROBUSTNESS invariant the parser promises:

     TOTALITY : parsing ANY mutated query string either succeeds with a
                well-formed AST or REJECTS with a named Error — it NEVER raises
                and NEVER hangs (parsing is non-recursive / structurally total).

   Seeded mutations echo their seed on any violation.

   [NOTE] To keep the module self-contained within zigvm_harness_support (deps:
   stdlib/Unix/Sqlite3/Yojson/Rete only — Docs_wiki is not a declared sibling
   here), this reimplements the grammar rather than calling Docs_wiki.zkquery_*.
   The grammar is kept faithful to that source; it is a robustness fuzzer of the
   grammar shape, not a differential check against the live parser. *)

type cond = { f : string; op : string; v : string }
type query = { from_sel : string option; where : cond list; sort : string option; limit : int option }

let str_fields = [ "status"; "type"; "group"; "slug"; "tag" ]
let int_fields = [ "words"; "degree"; "outlinks"; "backlinks" ]
let sort_keys = [ "slug"; "title"; "words"; "degree"; "pagerank" ]

(* ---- total serializer AST -> string ---- *)
let string_of_query q =
  let b = Buffer.create 64 in
  (match q.from_sel with Some s -> Buffer.add_string b ("from " ^ s ^ " ") | None -> ());
  (match q.where with
   | [] -> ()
   | cs ->
       Buffer.add_string b "where ";
       Buffer.add_string b
         (String.concat " and " (List.map (fun c -> c.f ^ c.op ^ c.v) cs));
       Buffer.add_char b ' ');
  (match q.sort with Some s -> Buffer.add_string b ("sort " ^ s ^ " ") | None -> ());
  (match q.limit with Some n -> Buffer.add_string b ("limit " ^ string_of_int n) | None -> ());
  String.trim (Buffer.contents b)

(* ---- total parser string -> (query, error). Never raises. ---- *)
(* split a condition token FIELDopVALUE by the first matching operator *)
let parse_cond t =
  let ops = [ "!="; ">="; "<="; "="; ">"; "<" ] in
  let find_split () =
    List.fold_left
      (fun acc op ->
        match acc with
        | Some _ -> acc
        | None ->
            let ol = String.length op and n = String.length t in
            let rec at i =
              if i + ol > n then None
              else if String.sub t i ol = op && i > 0 && i + ol < n then
                Some (String.sub t 0 i, op, String.sub t (i + ol) (n - i - ol))
              else at (i + 1)
            in
            at 0)
      None ops
  in
  match find_split () with
  | None -> Error ("not a condition: " ^ t)
  | Some (f, op, v) ->
      if List.mem f int_fields then
        if op = "!=" then Error (f ^ " is numeric; != unsupported")
        else if int_of_string_opt v = None then Error (f ^ " needs a number: " ^ v)
        else Ok { f; op; v }
      else if List.mem f str_fields then
        if op = "=" || op = "!=" then Ok { f; op; v }
        else Error (f ^ " supports only = and !=")
      else Error ("unknown field: " ^ f)

let parse (q : string) : (query, string) result =
  let toks =
    String.map (fun c -> if c = '\t' || c = '\n' || c = '\r' then ' ' else c) q
    |> String.split_on_char ' ' |> List.filter (fun t -> t <> "")
  in
  let from_sel = ref None and where = ref [] and sort = ref None and limit = ref None in
  let rec go = function
    | [] -> Ok ()
    | "from" :: sel :: rest ->
        if sel = "all" then (from_sel := Some "all"; go rest)
        else (match String.index_opt sel ':' with
          | Some i ->
              let f = String.sub sel 0 i in
              if List.mem f [ "type"; "group"; "tag" ]
                 && String.length sel > i + 1
              then (from_sel := Some sel; go rest)
              else Error ("bad from-selector: " ^ sel)
          | None -> Error ("bad from-selector: " ^ sel))
    | "from" :: [] -> Error "from needs a selector"
    | "where" :: rest ->
        let rec conds = function
          | [] -> Error "where needs a condition"
          | t :: more -> (
              match parse_cond t with
              | Error e -> Error e
              | Ok c -> where := c :: !where;
                  (match more with
                   | "and" :: yet -> conds yet
                   | _ -> go more))
        in
        conds rest
    | "sort" :: key :: rest ->
        if List.mem key sort_keys then (sort := Some key;
          match rest with
          | ("asc" | "desc") :: r -> go r
          | _ -> go rest)
        else Error ("bad sort key: " ^ key)
    | "sort" :: [] -> Error "sort needs a key"
    | "limit" :: n :: rest ->
        (match int_of_string_opt n with
         | Some k when k >= 0 -> limit := Some k; go rest
         | _ -> Error ("bad limit: " ^ n))
    | "limit" :: [] -> Error "limit needs a number"
    | tok :: _ -> Error ("unexpected token: " ^ tok)
  in
  match go toks with
  | Ok () -> Ok { from_sel = !from_sel; where = List.rev !where; sort = !sort; limit = !limit }
  | Error e -> Error e

(* ---- mutation operators on the AST / string ---- *)
let mutate_query s q =
  let pick l = List.nth l (Random.State.int s (List.length l)) in
  match Random.State.int s 7 with
  | 0 -> (* swap a condition operator *)
      (match q.where with
       | [] -> { q with limit = Some (-1) }
       | c :: tl -> { q with where = { c with op = pick [ "="; "!="; ">"; "<"; ">="; "<=" ] } :: tl })
  | 1 -> (* corrupt a field name *)
      (match q.where with
       | c :: tl -> { q with where = { c with f = c.f ^ "X" } :: tl }
       | [] -> { q with sort = Some "bogus" })
  | 2 -> (* flip numeric/string field *)
      (match q.where with
       | c :: tl -> { q with where = { c with f = pick (int_fields @ str_fields) } :: tl }
       | [] -> { q with from_sel = Some "kind:z" })
  | 3 -> (* duplicate first condition *)
      (match q.where with c :: _ -> { q with where = c :: q.where } | [] -> q)
  | 4 -> { q with limit = Some (- (Random.State.int s 100 + 1)) } (* negative limit *)
  | 5 -> { q with sort = Some (pick (sort_keys @ [ "nope"; "" ])) }
  | _ -> q (* re-serialize as-is, then inject a stray token via string mangling *)

let run (_root : string) : unit =
  Printf.printf "[zk_query_ast_mutator] fuzzing zkquery grammar via AST mutation\n";
  let seeds = [ "from all where status=draft sort slug asc limit 5";
                "from tag:cov-gap where degree>=3 and words<500";
                "from type:episodic where status!=deprecated limit 10";
                "where slug=x and backlinks>0 sort pagerank desc";
                "from group:features" ] in
  let base = Array.of_list seeds in
  let iters = 600 and base_seed = 0x2A57 in
  let raised = ref 0 and total = ref 0 in
  for i = 0 to iters - 1 do
    let s = Random.State.make [| base_seed + i |] in
    let seed_q = base.(Random.State.int s (Array.length base)) in
    (* parse the seed (must succeed); if it does, mutate its AST and reparse *)
    match parse seed_q with
    | Error _ -> () (* seed itself invalid — skip, not a mutation result *)
    | Ok q ->
        let mq = mutate_query s q in
        (* sometimes inject a stray token at the string level too *)
        let str =
          let base_str = string_of_query mq in
          if Random.State.int s 3 = 0 then base_str ^ " @@garbage%%" else base_str
        in
        incr total;
        (try ignore (parse str)
         with e ->
           incr raised;
           Printf.printf "  [TOTALITY] parser RAISED on mutant (seed=%d): %s => %s\n"
             (base_seed + i) str (Printexc.to_string e))
  done;
  Printf.printf "[zk_query_ast_mutator] %d mutated queries reparsed, %d parser exception(s)\n"
    !total !raised;
  if !raised = 0 then
    Printf.printf "[zk_query_ast_mutator] TOTALITY holds — every mutant parsed or rejected cleanly\n"
  else
    Printf.printf "[zk_query_ast_mutator] %d TOTALITY VIOLATION(S) — parser is not total\n" !raised
