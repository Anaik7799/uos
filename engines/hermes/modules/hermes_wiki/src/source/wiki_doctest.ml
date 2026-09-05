(* HW.9.3.2–.6 — the doctest extension family. See wiki_doctest.mli for
   the laws; this file only has to satisfy them.

   Structure mirrors the parent builder (`Hermes_wiki.doctest_groups` /
   `doctest_drift`) and `Wiki_include`: parse the fence info into a
   declared header, split the body by DECLARED markers, and inject every
   effectful thing (`~eval`, `~env`) so the whole module is a pure
   function of its arguments. *)

type kind = Testsetup | Testcode | Testoutput | Testcleanup | Transcript

type normalisation = { trim_whitespace : bool; normalise_whitespace : bool }

type header = {
  kind : kind;
  group : string;
  skipif : string option;
  norm : normalisation;
  bad : string list;
}

type block = { page : string; ordinal : int; head : header; body : string list }

let no_normalisation = { trim_whitespace = false; normalise_whitespace = false }
let default_group = "default"
let transcript_marker = ">>>"

(* ---------------------------------------------------------- grammar *)

let tokens info =
  String.split_on_char ' ' info
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun t -> t <> "")

let kind_of_token = function
  | "testsetup" -> Some Testsetup
  | "testcode" -> Some Testcode
  | "testoutput" -> Some Testoutput
  | "testcleanup" -> Some Testcleanup
  | "doctest" -> Some Transcript
  | _ -> None

(* An option token looks like `:name:`. Used to stop `:group: :skipif: x`
   from swallowing an option as if it were a value: a missing argument
   must be a NAMED gap, not a silent rebinding of the next declaration. *)
let is_option_token s = String.length s > 1 && s.[0] = ':'

let header_of_info info =
  match tokens info with
  | [] -> None
  | first :: rest -> (
      match kind_of_token first with
      | None -> None
      | Some k ->
          let rec go h = function
            | [] -> h
            | ":trim-whitespace:" :: t ->
                go { h with norm = { h.norm with trim_whitespace = true } } t
            | ":normalise-whitespace:" :: t ->
                go { h with norm = { h.norm with normalise_whitespace = true } } t
            | ":group:" :: v :: t when not (is_option_token v) -> go { h with group = v } t
            | ":skipif:" :: v :: t when not (is_option_token v) -> go { h with skipif = Some v } t
            | tok :: t -> go { h with bad = h.bad @ [ "unparsed option: " ^ tok ] } t
          in
          Some
            (go
               { kind = k; group = default_group; skipif = None; norm = no_normalisation; bad = [] }
               rest))

let blocks_of_markdown ~page body =
  Wiki_ast.fences (Wiki_ast.parse body)
  (* MIRRORS doctest_drift: a literalinclude fence's body belongs to a
     file, never to this runner. *)
  |> List.filter (fun (info, _) -> not (Wiki_include.attempted info))
  |> List.filter_map (fun (info, b) ->
         match header_of_info info with Some h -> Some (h, b) | None -> None)
  |> List.mapi (fun i (h, b) -> { page; ordinal = i; head = h; body = b })

let blocks_of_model (m : Hermes_wiki.model) =
  List.concat_map
    (fun (p : Hermes_wiki.page) ->
      (* MIRRORS doctest_drift: an allow_example_links page QUOTES the
         grammar rather than using it. *)
      if p.meta.allow_example_links then [] else blocks_of_markdown ~page:p.slug p.raw)
    m.pages

let groups bs = List.sort_uniq compare (List.map (fun b -> b.head.group) bs)

(* ------------------------------------------------ transcript split *)

let has_prefix p l = String.length l >= String.length p && String.sub l 0 (String.length p) = p

(* `>>>` opens, `...` continues. Both markers are 3 characters, so a
   marked line is either exactly the marker or the marker plus a space. *)
let is_marker l = l = ">>>" || has_prefix ">>> " l || l = "..." || has_prefix "... " l
let strip_marker l = if String.length l <= 4 then "" else String.sub l 4 (String.length l - 4)

(* The PARENT builder's marker (HW.9.3.1). A fence carrying it is checked
   there, so this module yields no case for it. *)
let is_parent_marker l = l = ">" || has_prefix "> " l

let trim_blanks ls =
  let rec drop = function "" :: t -> drop t | l -> l in
  List.rev (drop (List.rev (drop ls)))

(* Line-for-line the parent's `doctest_groups`, with this module's
   markers. Order-preserving on purpose: a partition is order-blind, and
   an order-blind split files a blank separator line under "expected". *)
let transcript_cases body =
  let rec go acc cur_in cur_out = function
    | [] ->
        List.rev
          (if cur_in = [] then acc else (List.rev cur_in, trim_blanks (List.rev cur_out)) :: acc)
    | l :: rest when is_marker l ->
        if cur_out <> [] && cur_in <> [] then
          go ((List.rev cur_in, trim_blanks (List.rev cur_out)) :: acc) [ strip_marker l ] [] rest
        else go acc (strip_marker l :: cur_in) cur_out rest
    | l :: rest -> go acc cur_in (l :: cur_out) rest
  in
  go [] [] [] body

let has_transcript body = List.exists is_marker body
let has_parent body = List.exists is_parent_marker body

let unchecked bs =
  List.filter_map
    (fun b ->
      match b.head.kind with
      | Transcript when (not (has_transcript b.body)) && not (has_parent b.body) ->
          Some (Printf.sprintf "doctest fence checked by nothing: %s #%d" b.page b.ordinal)
      | Transcript | Testsetup | Testcode | Testoutput | Testcleanup -> None)
    bs
  |> List.sort_uniq compare

(* ------------------------------------------------------- comparison *)

let collapse_ws l =
  let b = Buffer.create (String.length l) in
  let ws c = c = ' ' || c = '\t' in
  String.iteri
    (fun i c ->
      if ws c then (if i = 0 || not (ws l.[i - 1]) then Buffer.add_char b ' ')
      else Buffer.add_char b c)
    l;
  Buffer.contents b

(* Every weakening of equality is read off a DECLARED flag. There is no
   other branch in this function, which is what makes HW.9.3.2 checkable
   rather than aspirational. *)
let canon n s =
  let ls = String.split_on_char '\n' s in
  let ls = if n.normalise_whitespace then List.map collapse_ws ls else ls in
  let ls = if n.trim_whitespace then List.map String.trim ls else ls in
  let ls = if n.trim_whitespace then trim_blanks ls else ls in
  String.concat "\n" ls

let compare_output n ~expected ~observed = String.equal (canon n expected) (canon n observed)

(* ------------------------------------------------------------- run *)

type eval_result = Output of string | Raised of string
type status = Passed | Failed of string | Skipped of string | Refused of string

type result = {
  id : string;
  grp : string;
  status : status;
  expected : string;
  observed : string;
}

type 'w group_run = { name : string; results : result list; world : 'w }

type 'w report = {
  runs : 'w group_run list;
  passed : int;
  failed : int;
  skipped : int;
  refused : int;
  disclosures : string list;
}

let mk_id b sfx = Printf.sprintf "%s#%s#%d%s" b.page b.head.group b.ordinal sfx
let plain id grp status = { id; grp; status; expected = ""; observed = "" }

(* A prepared case: everything DECLARED about it, resolved before a line
   of it runs. [p_refuse] set means the declaration itself is broken. *)
type prepared = {
  p_id : string;
  p_grp : string;
  p_input : string list;
  p_expected : string list;
  p_norm : normalisation;
  p_skipif : string option;
  p_refuse : string option;
}

let base b sfx =
  {
    p_id = mk_id b sfx;
    p_grp = b.head.group;
    p_input = [];
    p_expected = [];
    p_norm = b.head.norm;
    p_skipif = b.head.skipif;
    p_refuse = None;
  }

let refuse b sfx reason = { (base b sfx) with p_refuse = Some reason }

(* HW.9.3.2 — pairing: a testcode is answered by the block IMMEDIATELY
   following it in the same group, and only if that block is a
   testoutput. Anything else refuses: an unchecked example is not a
   passing one (R3), and an expectation with nothing to expect is not a
   test at all. *)
let pair code out =
  if code.head.bad <> [] || out.head.bad <> [] then
    refuse code "" (String.concat "; " (code.head.bad @ out.head.bad))
  else
    let skipif =
      match (code.head.skipif, out.head.skipif) with
      | None, s -> Ok s
      | s, None -> Ok s
      | Some a, Some b when a = b -> Ok (Some a)
      | Some a, Some b ->
          Error (Printf.sprintf "conflicting :skipif: on the pair: %s vs %s" a b)
    in
    match skipif with
    | Error r -> refuse code "" r
    | Ok s ->
        {
          (base code "") with
          p_input = code.body;
          p_expected = out.body;
          (* declared on EITHER half; a flag written down anywhere in the
             pair is an author's explicit act, and there is no syntax for
             un-declaring one. *)
          p_norm =
            {
              trim_whitespace = code.head.norm.trim_whitespace || out.head.norm.trim_whitespace;
              normalise_whitespace =
                code.head.norm.normalise_whitespace || out.head.norm.normalise_whitespace;
            };
          p_skipif = s;
        }

let prepare bs =
  let rec go acc = function
    | [] -> List.rev acc
    | b :: rest -> (
        (* An unparsed option refuses the block it sits on — but a broken
           testcode still CONSUMES its testoutput, so one broken
           declaration produces one refusal rather than two. *)
        let bad_reason = String.concat "; " b.head.bad in
        let or_bad r = if b.head.bad <> [] then bad_reason else r in
        match b.head.kind with
        | Testsetup | Testcleanup -> go acc rest
        | Testoutput ->
            go
              (refuse b ""
                 (or_bad "testoutput has no testcode: an expectation with nothing to expect")
              :: acc)
              rest
        | Testcode -> (
            match rest with
            | o :: rest' when o.head.kind = Testoutput -> go (pair b o :: acc) rest'
            | [] | _ :: _ ->
                go
                  (refuse b ""
                     (or_bad
                        "testcode has no testoutput: an unchecked example is not a passing one")
                  :: acc)
                  rest)
        | Transcript when b.head.bad <> [] -> go (refuse b "" bad_reason :: acc) rest
        | Transcript ->
            let cs = transcript_cases b.body in
            if cs <> [] then
              go
                (List.rev_append
                   (List.mapi
                      (fun i (inp, exp) ->
                        {
                          (base b (Printf.sprintf ".%d" i)) with
                          p_input = inp;
                          p_expected = exp;
                        })
                      cs)
                   acc)
                rest
            else if has_parent b.body then go acc rest
            else
              go
                (refuse b ""
                   "doctest fence declares neither >>> nor > : checked by nothing"
                :: acc)
                rest)
  in
  go [] bs

type skip_decision = Run_it | Skip_it of string | Unknown_cond of string

(* HW.9.3.6 — the condition is DECLARED data answered by an INJECTED
   environment. Three answers, three outcomes; [None] is fail-closed. *)
let decide_skip ~env = function
  | None -> Run_it
  | Some cond -> (
      match env cond with
      | Some true -> Skip_it (Printf.sprintf "skipif %s: DECLARED and true in this environment" cond)
      | Some false -> Run_it
      | None ->
          Unknown_cond
            (Printf.sprintf "skipif %s: the environment cannot answer this condition" cond)
      | exception e ->
          Unknown_cond (Printf.sprintf "skipif %s: environment raised %s" cond
                          (Printexc.to_string e)))

type interp = Ok_out of string | Blew of string | Broke of string

let safe_eval ~eval w src =
  match eval w src with
  | w', Output s -> (w', Ok_out s)
  | w', Raised m -> (w', Blew m)
  (* An OCaml exception escaping the injected interpreter says the
     INTERPRETER is broken. That proves nothing about the example, so it
     can never be a Failed — and the world is left exactly as it was. *)
  | exception e -> (w, Broke (Printexc.to_string e))

(* A successful fixture is not a test and produces no result; anything
   else is named. Returns whether every fixture actually ran clean. *)
let run_fixtures ~eval ~env ~phase w bs =
  List.fold_left
    (fun (w, rs, ok) b ->
      let id = mk_id b (":" ^ phase) in
      let g = b.head.group in
      if b.head.bad <> [] then
        (w, rs @ [ plain id g (Refused (String.concat "; " b.head.bad)) ], false)
      else
        match decide_skip ~env b.head.skipif with
        | Skip_it r -> (w, rs @ [ plain id g (Skipped r) ], false)
        | Unknown_cond r -> (w, rs @ [ plain id g (Refused r) ], false)
        | Run_it -> (
            match safe_eval ~eval w (String.concat "\n" b.body) with
            | w', Ok_out _ -> (w', rs, ok)
            | w', Blew m -> (w', rs @ [ plain id g (Failed (phase ^ " failed: " ^ m)) ], false)
            | w', Broke m ->
                (w', rs @ [ plain id g (Refused ("interpreter raised out of band: " ^ m)) ], false)))
    (w, [], true) bs

let run_cases ~eval ~env ~setup_ok w cases =
  List.fold_left
    (fun (w, rs) c ->
      match c.p_refuse with
      | Some r -> (w, rs @ [ plain c.p_id c.p_grp (Refused r) ])
      | None ->
          if not setup_ok then
            (* FAIL-CLOSED: a case run without its declared fixture
               produces a plausible answer, which is the worst kind. *)
            ( w,
              rs
              @ [ plain c.p_id c.p_grp
                    (Refused "group fixture did not run: the case cannot be trusted") ] )
          else (
            match decide_skip ~env c.p_skipif with
            | Skip_it r -> (w, rs @ [ plain c.p_id c.p_grp (Skipped r) ])
            | Unknown_cond r -> (w, rs @ [ plain c.p_id c.p_grp (Refused r) ])
            | Run_it -> (
                let expected = String.concat "\n" c.p_expected in
                match safe_eval ~eval w (String.concat "\n" c.p_input) with
                | w', Ok_out observed ->
                    let ok = compare_output c.p_norm ~expected ~observed in
                    let status =
                      if ok then Passed
                      else Failed (Printf.sprintf "expected %S, observed %S" expected observed)
                    in
                    (w', rs @ [ { id = c.p_id; grp = c.p_grp; status; expected; observed } ])
                | w', Blew m ->
                    ( w',
                      rs
                      @ [ { id = c.p_id; grp = c.p_grp;
                            status = Failed ("interpreter reported: " ^ m);
                            expected; observed = "" } ] )
                | w', Broke m ->
                    ( w',
                      rs
                      @ [ { id = c.p_id; grp = c.p_grp;
                            status = Refused ("interpreter raised out of band: " ^ m);
                            expected; observed = "" } ] ))))
    (w, []) cases

let run_group ~eval ~world ~env ~group bs =
  let mine = List.filter (fun b -> b.head.group = group) bs in
  let setups = List.filter (fun b -> b.head.kind = Testsetup) mine in
  let cleanups = List.filter (fun b -> b.head.kind = Testcleanup) mine in
  let cases =
    prepare
      (List.filter
         (fun b ->
           match b.head.kind with
           | Testcode | Testoutput | Transcript -> true
           | Testsetup | Testcleanup -> false)
         mine)
  in
  let w1, setup_results, setup_ok = run_fixtures ~eval ~env ~phase:"setup" world setups in
  let w2, case_results = run_cases ~eval ~env ~setup_ok w1 cases in
  (* HW.9.3.4 — CLEANUP IS UNGUARDED. It runs after a pass, after a
     failure, after a refused setup and after nothing at all. *)
  let w3, cleanup_results, _ = run_fixtures ~eval ~env ~phase:"cleanup" w2 cleanups in
  { name = group; results = setup_results @ case_results @ cleanup_results; world = w3 }

let disclose r =
  match r.status with
  | Skipped m -> Some (Printf.sprintf "SKIPPED %s: %s" r.id m)
  | Refused m -> Some (Printf.sprintf "REFUSED %s: %s" r.id m)
  | Passed | Failed _ -> None

let run ~eval ~world ~env bs =
  (* HW.9.3.5 — a MAP, not a fold: every group is handed the SAME initial
     world, so no group can be made to pass by a neighbour's leftovers. *)
  let runs = List.map (fun g -> run_group ~eval ~world ~env ~group:g bs) (groups bs) in
  let all = List.concat_map (fun r -> r.results) runs in
  let count f = List.length (List.filter f all) in
  {
    runs;
    passed = count (fun r -> match r.status with Passed -> true | Failed _ | Skipped _ | Refused _ -> false);
    failed = count (fun r -> match r.status with Failed _ -> true | Passed | Skipped _ | Refused _ -> false);
    skipped = count (fun r -> match r.status with Skipped _ -> true | Passed | Failed _ | Refused _ -> false);
    refused = count (fun r -> match r.status with Refused _ -> true | Passed | Failed _ | Skipped _ -> false);
    disclosures = List.filter_map disclose all;
  }
