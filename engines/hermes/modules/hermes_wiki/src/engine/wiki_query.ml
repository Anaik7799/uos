(* zkquery. See wiki_query.mli for the grammar and the laws.

   Mirrored from zigvm's docs_wiki.ml §2253-2485 (R14). Two deliberate
   differences:

     - `group by` is ADDED (HW.5.1.5). It is Missing in both Notion and
       Obsidian, and it is the natural shape of a grammar that already has
       from/where/sort/limit.
     - `pagerank` is NOT yet a sort key. zigvm has it; our HW.4.2.1 is not
       built, and offering a sort key backed by nothing would be exactly
       the silent-empty-result failure the totality law forbids. It joins
       `sort_keys` when the kernel lands.

   The parser is a descending chain of clause parsers with no recursion, so
   termination is structural rather than argued. *)

type cond = { field : string; op : string; value : string }

type query = {
  conds : cond list;
  group_by : string option;
  sort : string * bool;
  limit : int option;
}

let string_fields = [ "status"; "type"; "group"; "slug"; "tag" ]
let int_fields = [ "words"; "degree"; "outlinks"; "backlinks" ]
let sort_keys = [ "slug"; "title"; "words"; "degree"; "outlinks"; "backlinks" ]
let group_keys = [ "status"; "type"; "group" ]

(* ---------------------------------------------------------------- parse *)

(* Split a token at the FIRST occurrence of [sep]. Longer operators are
   tried first by the caller, so `>=` is never read as `>`. *)
let split_at token sep =
  let n = String.length token and m = String.length sep in
  let rec go i =
    if i + m > n then None
    else if String.sub token i m = sep then
      Some (String.sub token 0 i, String.sub token (i + m) (n - i - m))
    else go (i + 1)
  in
  go 0

let parse_cond token =
  let rec find = function
    | [] -> Error (Printf.sprintf "zkquery: not a condition: %s" token)
    | op :: rest -> (
        match split_at token op with
        | Some (f, v) when f <> "" && v <> "" ->
            if List.mem f int_fields then
              if op = "!=" then
                Error (Printf.sprintf "zkquery: %s is numeric; use =,>,>=,<,<=" f)
              else if int_of_string_opt v = None then
                Error (Printf.sprintf "zkquery: %s needs a number, got %s" f v)
              else Ok { field = f; op; value = v }
            else if List.mem f string_fields then
              if List.mem op [ "="; "!=" ] then Ok { field = f; op; value = v }
              else Error (Printf.sprintf "zkquery: %s supports only = and !=" f)
            else Error (Printf.sprintf "zkquery: unknown field %s" f)
        | _ -> find rest)
  in
  (* longest operators first: `>=` must not be read as `>` *)
  find [ "!="; ">="; "<="; "="; ">"; "<" ]

let parse q =
  let tokens =
    String.map (fun c -> if c = '\t' || c = '\n' || c = '\r' then ' ' else c) q
    |> String.split_on_char ' '
    |> List.filter (fun t -> t <> "")
  in
  let rec p_from tokens acc =
    match tokens with
    | [ "from" ] -> Error "zkquery: from needs a selector (all|type:T|group:G|tag:T)"
    | "from" :: "all" :: rest -> p_where rest acc
    | "from" :: sel :: rest -> (
        match String.index_opt sel ':' with
        | Some i ->
            let f = String.sub sel 0 i in
            let v = String.sub sel (i + 1) (String.length sel - i - 1) in
            if List.mem f [ "type"; "group"; "tag" ] && v <> "" && f <> "" then
              p_where rest ({ field = f; op = "="; value = v } :: acc)
            else Error (Printf.sprintf "zkquery: bad from-selector %s" sel)
        | None -> Error (Printf.sprintf "zkquery: bad from-selector %s" sel))
    | _ -> p_where tokens acc
  and p_where tokens acc =
    match tokens with
    | "where" :: rest ->
        let rec conds tokens acc =
          match tokens with
          | [] -> Error "zkquery: where needs a condition"
          | t :: rest -> (
              match parse_cond t with
              | Error e -> Error e
              | Ok c -> (
                  match rest with
                  | "and" :: more -> conds more (c :: acc)
                  | _ -> p_group rest (c :: acc)))
        in
        conds rest acc
    | _ -> p_group tokens acc
  and p_group tokens acc =
    match tokens with
    | "group" :: "by" :: key :: rest ->
        if List.mem key group_keys then p_sort rest acc (Some key)
        else Error (Printf.sprintf "zkquery: unknown group key %s" key)
    | "group" :: "by" :: [] -> Error "zkquery: group by needs a key"
    | "group" :: _ -> Error "zkquery: expected `group by <key>`"
    | _ -> p_sort tokens acc None
  and p_sort tokens acc grouped =
    match tokens with
    | "sort" :: key :: rest ->
        if not (List.mem key sort_keys) then
          Error (Printf.sprintf "zkquery: unknown sort key %s" key)
        else (
          match rest with
          | "desc" :: more -> p_limit more acc grouped (key, true)
          | "asc" :: more -> p_limit more acc grouped (key, false)
          | _ -> p_limit rest acc grouped (key, false))
    | [ "sort" ] -> Error "zkquery: sort needs a key"
    | _ -> p_limit tokens acc grouped ("slug", false)
  and p_limit tokens acc grouped sort =
    match tokens with
    | [] -> Ok { conds = List.rev acc; group_by = grouped; sort; limit = None }
    | [ "limit"; n ] -> (
        match int_of_string_opt n with
        | Some k when k >= 0 ->
            Ok { conds = List.rev acc; group_by = grouped; sort; limit = Some k }
        | _ -> Error (Printf.sprintf "zkquery: bad limit %s" n))
    | [ "limit" ] -> Error "zkquery: limit needs a number"
    | t :: _ -> Error (Printf.sprintf "zkquery: unexpected token %s" t)
  in
  p_from tokens []

(* ----------------------------------------------------------------- eval *)

let word_count (p : Hermes_wiki.page) =
  String.split_on_char ' '
    (String.map
       (fun c -> if c = '\n' || c = '\t' || c = '\r' then ' ' else c)
       p.Hermes_wiki.raw)
  |> List.filter (fun w -> String.trim w <> "")
  |> List.length

let degree (p : Hermes_wiki.page) =
  List.length p.Hermes_wiki.outlinks + List.length p.Hermes_wiki.backlinks

let int_field (p : Hermes_wiki.page) = function
  | "words" -> word_count p
  | "degree" -> degree p
  | "outlinks" -> List.length p.Hermes_wiki.outlinks
  | "backlinks" -> List.length p.Hermes_wiki.backlinks
  | _ -> 0

let string_field (p : Hermes_wiki.page) = function
  | "status" -> p.Hermes_wiki.meta.Hermes_wiki.status
  | "type" -> p.Hermes_wiki.meta.Hermes_wiki.ntype
  | "group" -> p.Hermes_wiki.group
  | "slug" -> p.Hermes_wiki.slug
  | _ -> ""

let satisfies p c =
  if List.mem c.field int_fields then
    match int_of_string_opt c.value with
    | None -> false
    | Some v -> (
        let x = int_field p c.field in
        match c.op with
        | "=" -> x = v
        | ">" -> x > v
        | ">=" -> x >= v
        | "<" -> x < v
        | "<=" -> x <= v
        | _ -> false)
  else
    let equal =
      if c.field = "tag" then List.mem c.value p.Hermes_wiki.tags
      else String.equal (string_field p c.field) c.value
    in
    match c.op with "=" -> equal | "!=" -> not equal | _ -> false

let eval pages q =
  let rows = List.filter (fun p -> List.for_all (satisfies p) q.conds) pages in
  let key, desc = q.sort in
  let compare_rows (a : Hermes_wiki.page) (b : Hermes_wiki.page) =
    let c =
      match key with
      | "slug" -> compare a.Hermes_wiki.slug b.Hermes_wiki.slug
      | "title" -> compare a.Hermes_wiki.title b.Hermes_wiki.title
      | "words" -> compare (word_count a) (word_count b)
      | "degree" -> compare (degree a) (degree b)
      | "outlinks" ->
          compare (List.length a.Hermes_wiki.outlinks) (List.length b.Hermes_wiki.outlinks)
      | "backlinks" ->
          compare (List.length a.Hermes_wiki.backlinks) (List.length b.Hermes_wiki.backlinks)
      | _ -> 0
    in
    let c = if desc then -c else c in
    (* the slug tiebreak is what makes the order TOTAL, and therefore the
       result pinnable by the render baseline *)
    if c <> 0 then c else compare a.Hermes_wiki.slug b.Hermes_wiki.slug
  in
  let rows = List.stable_sort compare_rows rows in
  match q.limit with Some k -> List.filteri (fun i _ -> i < k) rows | None -> rows

let group pages q =
  let rows = eval pages q in
  match q.group_by with
  | None -> [ ("", rows) ]
  | Some key ->
      let keys =
        List.sort_uniq compare (List.map (fun p -> string_field p key) rows)
      in
      List.map (fun k -> (k, List.filter (fun p -> string_field p key = k) rows)) keys

(* --------------------------------------------------------------- fences *)

let fences raw =
  let lines = String.split_on_char '\n' raw in
  let rec go lines acc current =
    match (lines, current) with
    | [], _ -> List.rev acc
    | line :: rest, None ->
        if String.trim line = "```zkquery" then go rest acc (Some []) else go rest acc None
    | line :: rest, Some body ->
        if String.length (String.trim line) >= 3 && String.sub (String.trim line) 0 3 = "```"
        then go rest (String.concat "\n" (List.rev body) :: acc) None
        else go rest acc (Some (line :: body))
  in
  go lines [] None
