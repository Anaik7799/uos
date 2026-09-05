(* The datastore. See wiki_datastore.mli for the seven rows and the laws
   they carry; this file only has to hold them.

   PURE throughout: no filesystem, no Unix, no clock, no randomness. The
   only computation over author text is the CLOSED kernel set of
   HW.8.3.3, and there is deliberately no function in this file that
   takes author text and evaluates it. *)

(* ============================================================== shared *)

let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

let starts_at s i needle =
  let n = String.length s and m = String.length needle in
  i + m <= n && String.sub s i m = needle

let sorted_uniq_str l = List.sort_uniq String.compare l

(* The tagged generalisation of [Wiki_query.fences]. Same walk, same
   opening test (exact match on the trimmed line), same closing test (any
   trimmed line beginning with ```), so [fences ~tag:"zkquery"] and
   [Wiki_query.fences] agree by construction — and the test pins it. *)
let fences ~tag raw =
  let opener = "```" ^ tag in
  let lines = String.split_on_char '\n' raw in
  let rec go lines acc current =
    match (lines, current) with
    | [], _ -> List.rev acc
    | line :: rest, None ->
        if String.trim line = opener then go rest acc (Some []) else go rest acc None
    | line :: rest, Some body ->
        if is_fence line then go rest (String.concat "\n" (List.rev body) :: acc) None
        else go rest acc (Some (line :: body))
  in
  go lines [] None

(* Walk PROSE lines: a fence delimiter belongs to nobody, and the body of
   a fence is an example. Mirrored from Wiki_lifecycle.fold_prose_lines
   (R14), which took it from Wiki_transclude. *)
let fold_prose_lines f init body =
  String.split_on_char '\n' body
  |> List.fold_left
       (fun (in_fence, acc) line ->
         if is_fence line then (not in_fence, acc)
         else if in_fence then (in_fence, acc)
         else (in_fence, f acc line))
       (false, init)
  |> snd

let whitespace_tokens s =
  String.map (fun c -> if c = '\t' || c = '\n' || c = '\r' then ' ' else c) s
  |> String.split_on_char ' '
  |> List.filter (fun t -> t <> "")

(* ================================================ HW.5.1.1 from selector *)

let corpus_dependent_fields = [ "backlinks"; "degree" ]

let monotone (q : Wiki_query.query) =
  q.Wiki_query.limit = None
  && List.for_all
       (fun (c : Wiki_query.cond) ->
         not (List.mem c.Wiki_query.field corpus_dependent_fields))
       q.Wiki_query.conds

let monotone_defect ~base ~added q =
  let smaller = Hermes_wiki.build base in
  let larger = Hermes_wiki.build (base @ added) in
  let rows_of (m : Hermes_wiki.model) =
    List.map (fun (p : Hermes_wiki.page) -> p.Hermes_wiki.slug)
      (Wiki_query.eval m.Hermes_wiki.pages q)
  in
  let before = rows_of smaller and after = rows_of larger in
  match List.find_opt (fun s -> not (List.mem s after)) before with
  | None -> None
  | Some lost ->
      Some
        (Printf.sprintf
           "zkquery: NOT monotone in the corpus: %s was in the result and left it when %d file(s) were added"
           lost (List.length added))

let selectors pages =
  let of_page (p : Hermes_wiki.page) =
    let t = p.Hermes_wiki.meta.Hermes_wiki.ntype and g = p.Hermes_wiki.group in
    (if t = "" then [] else [ "type:" ^ t ])
    @ (if g = "" then [] else [ "group:" ^ g ])
    @ List.map (fun tg -> "tag:" ^ tg) p.Hermes_wiki.tags
  in
  sorted_uniq_str ("all" :: List.concat_map of_page pages)

(* ======================================================= HW.5.4.2 Bases *)

type base = {
  base_name : string;
  columns : string list;
  source : string;
  query : Wiki_query.query;
}

type base_error =
  | Base_unknown_key of string
  | Base_missing of string
  | Base_unknown_column of string
  | Base_query of string

let show_base_error = function
  | Base_unknown_key k -> "base: unknown key " ^ k
  | Base_missing k -> "base: missing required key " ^ k
  | Base_unknown_column c -> "base: unknown column " ^ c
  | Base_query e -> "base: " ^ e

let column_names =
  [ "backlinks"; "degree"; "group"; "outlinks"; "slug"; "status"; "title"; "type" ]

let cell (p : Hermes_wiki.page) col =
  match col with
  | "slug" -> Some p.Hermes_wiki.slug
  | "title" -> Some p.Hermes_wiki.title
  | "status" -> Some p.Hermes_wiki.meta.Hermes_wiki.status
  | "type" -> Some p.Hermes_wiki.meta.Hermes_wiki.ntype
  | "group" -> Some p.Hermes_wiki.group
  | "outlinks" -> Some (string_of_int (List.length p.Hermes_wiki.outlinks))
  | "backlinks" -> Some (string_of_int (List.length p.Hermes_wiki.backlinks))
  | "degree" ->
      Some
        (string_of_int
           (List.length p.Hermes_wiki.outlinks + List.length p.Hermes_wiki.backlinks))
  | _ -> None

let split_columns value =
  String.split_on_char ',' value |> List.map String.trim |> List.filter (fun c -> c <> "")

let parse_base src =
  let lines =
    String.split_on_char '\n' src |> List.filter (fun l -> String.trim l <> "")
  in
  let errs = ref [] and name = ref None and query = ref None and cols = ref None in
  let err e = errs := e :: !errs in
  List.iter
    (fun line ->
      match String.index_opt line ':' with
      | None -> err (Base_unknown_key (String.trim line))
      | Some i -> (
          let k = String.lowercase_ascii (String.trim (String.sub line 0 i)) in
          let v = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
          match k with
          | "name" -> name := Some v
          | "query" -> query := Some v
          | "columns" -> cols := Some (split_columns v)
          | _ -> err (Base_unknown_key k)))
    lines;
  (match !name with Some v when v <> "" -> () | _ -> err (Base_missing "name"));
  (match !query with Some v when v <> "" -> () | _ -> err (Base_missing "query"));
  let columns = match !cols with None -> [ "slug"; "title" ] | Some c -> c in
  List.iter (fun c -> if not (List.mem c column_names) then err (Base_unknown_column c)) columns;
  let parsed =
    match !query with
    | Some v when v <> "" -> (
        match Wiki_query.parse v with
        | Ok q -> Some q
        | Error e ->
            err (Base_query e);
            None)
    | _ -> None
  in
  match (!errs, parsed) with
  | [], Some q ->
      Ok { base_name = Option.value ~default:"" !name; columns; source = Option.get !query; query = q }
  | es, _ -> Error (List.sort_uniq compare (if es = [] then [ Base_missing "query" ] else es))

(* Definitionally the engine. There is no other path. *)
let base_rows pages b = Wiki_query.eval pages b.query

let base_table pages b =
  b.columns
  :: List.map
       (fun p -> List.map (fun c -> Option.value ~default:"" (cell p c)) b.columns)
       (base_rows pages b)

(* ========================================= HW.5.4.3 Dataview / Datacore *)

type dataview_error =
  | Dv_empty
  | Dv_head of string
  | Dv_from of string
  | Dv_where of string
  | Dv_sort of string
  | Dv_limit of string
  | Dv_column of string
  | Dv_query of string

let show_dataview_error = function
  | Dv_empty -> "dataview: empty block"
  | Dv_head h -> "dataview: expected TABLE or LIST, got " ^ h
  | Dv_from f -> "dataview: FROM takes #tag, \"group\" or all, got " ^ f
  | Dv_where w -> "dataview: WHERE takes FIELD OP VALUE, got " ^ w
  | Dv_sort s -> "dataview: SORT takes a key with optional ASC/DESC, got " ^ s
  | Dv_limit l -> "dataview: LIMIT takes a number, got " ^ l
  | Dv_column c -> "dataview: unknown column " ^ c
  | Dv_query e -> "dataview: " ^ e

let dataview_sources body = fences ~tag:"dataview" body
let dataview_js body = fences ~tag:"dataviewjs" body

let first_line s = match String.index_opt s '\n' with None -> s | Some i -> String.sub s 0 i

let dataview_defects body =
  dataview_js body
  |> List.map (fun block ->
         "dataview: JavaScript block REFUSED, never evaluated: "
         ^ String.trim (first_line block))
  |> List.sort String.compare

let dv_boundaries = [ "FROM"; "WHERE"; "SORT"; "LIMIT" ]
let dv_ops = [ "="; "!="; ">="; "<="; ">"; "<" ]

(* The clause sections of a dataview block. The head section carries the
   key "", so the column list needs no special case. *)
let dv_sections toks =
  let rec go kw cur acc = function
    | [] -> List.rev ((kw, List.rev cur) :: acc)
    | t :: rest when List.mem t dv_boundaries -> go t [] ((kw, List.rev cur) :: acc) rest
    | t :: rest -> go kw (t :: cur) acc rest
  in
  go "" [] [] toks

let dv_section sections kw =
  match List.filter (fun (k, _) -> k = kw) sections with
  | [] -> Ok None
  | [ (_, args) ] -> Ok (Some args)
  | _ :: _ -> Error (Printf.sprintf "duplicate %s" kw)

let dv_columns args =
  String.concat "," args |> String.split_on_char ',' |> List.map String.trim
  |> List.filter (fun c -> c <> "")

let dv_unquote s =
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then Some (String.sub s 1 (n - 2)) else None

let dv_from args =
  match args with
  | [ one ] -> (
      if one = "all" then Ok "from all"
      else if String.length one > 1 && one.[0] = '#' then
        Ok ("from tag:" ^ String.sub one 1 (String.length one - 1))
      else
        match dv_unquote one with
        | Some g when g <> "" -> Ok ("from group:" ^ g)
        | Some _ | None -> Error (Dv_from one))
  | args -> Error (Dv_from (String.concat " " args))

let dv_where args =
  let rec groups cur acc = function
    | [] -> List.rev (List.rev cur :: acc)
    | "AND" :: rest -> groups [] (List.rev cur :: acc) rest
    | t :: rest -> groups (t :: cur) acc rest
  in
  let one g =
    match g with
    | [ f; op; v ] when List.mem op dv_ops && f <> "" && v <> "" -> Ok (f ^ op ^ v)
    | g -> Error (Dv_where (String.concat " " g))
  in
  let rec fold acc = function
    | [] -> Ok (List.rev acc)
    | g :: rest -> ( match one g with Error e -> Error e | Ok c -> fold (c :: acc) rest)
  in
  match fold [] (groups [] [] args) with
  | Error e -> Error e
  | Ok cs -> Ok ("where " ^ String.concat " and " cs)

let dv_sort args =
  match args with
  | [ k ] -> Ok ("sort " ^ k)
  | [ k; "ASC" ] -> Ok ("sort " ^ k ^ " asc")
  | [ k; "DESC" ] -> Ok ("sort " ^ k ^ " desc")
  | args -> Error (Dv_sort (String.concat " " args))

let dv_limit args =
  match args with
  | [ n ] when int_of_string_opt n <> None -> Ok ("limit " ^ n)
  | args -> Error (Dv_limit (String.concat " " args))

(* Surface -> zkquery TEXT. Not an evaluator: the result is a string that
   [Wiki_query.parse] must still agree to. *)
let dv_compile src =
  match whitespace_tokens src with
  | [] -> Error Dv_empty
  | head :: rest ->
      if head <> "TABLE" && head <> "LIST" then Error (Dv_head head)
      else
        let sections = dv_sections rest in
        (* One clause: absent -> nothing emitted; present once -> compiled
           by its own parser; present twice -> a NAMED duplicate. *)
        let clause kw mk compile =
          match dv_section sections kw with
          | Error dup -> Error (mk dup)
          | Ok None -> Ok []
          | Ok (Some args) -> ( match compile args with Error e -> Error e | Ok s -> Ok [ s ])
        in
        let ( let* ) r f = match r with Error e -> Error e | Ok v -> f v in
        let* f = clause "FROM" (fun d -> Dv_from d) dv_from in
        let* w = clause "WHERE" (fun d -> Dv_where d) dv_where in
        let* s = clause "SORT" (fun d -> Dv_sort d) dv_sort in
        let* l = clause "LIMIT" (fun d -> Dv_limit d) dv_limit in
        let cols =
          match List.assoc_opt "" sections with
          | Some args when head = "TABLE" -> dv_columns args
          | Some _ | None -> [ "slug" ]
        in
        Ok (cols, String.concat " " (f @ w @ s @ l))

let to_zkquery src = match dv_compile src with Error e -> Error e | Ok (_, zq) -> Ok zq

let dataview_rows pages src =
  match to_zkquery src with
  | Error e -> Error e
  | Ok zq -> (
      match Wiki_query.parse zq with
      | Error e -> Error (Dv_query e)
      | Ok q -> Ok (Wiki_query.eval pages q))

let base_of_dataview ~name src =
  match dv_compile src with
  | Error e -> Error e
  | Ok (cols, zq) -> (
      match List.find_opt (fun c -> not (List.mem c column_names)) cols with
      | Some bad -> Error (Dv_column bad)
      | None -> (
          match Wiki_query.parse zq with
          | Error e -> Error (Dv_query e)
          | Ok q ->
              Ok
                { base_name = name;
                  columns = (if cols = [] then [ "slug" ] else cols);
                  source = zq;
                  query = q }))

(* ==================================== HW.8.2.6 version lifecycle directives *)

type version = int list
type change = Added | Changed | Deprecated | Removed

let change_name = function
  | Added -> "versionadded"
  | Changed -> "versionchanged"
  | Deprecated -> "deprecated"
  | Removed -> "versionremoved"

let change_of_name n =
  match String.lowercase_ascii (String.trim n) with
  | "versionadded" -> Some Added
  | "versionchanged" -> Some Changed
  | "deprecated" -> Some Deprecated
  | "versionremoved" -> Some Removed
  | _ -> None

let all_digits s =
  s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s

let version_of_string raw =
  let s = String.trim raw in
  if s = "" then Error (Printf.sprintf "version: empty version %S" raw)
  else
    let parts = String.split_on_char '.' s in
    if List.for_all all_digits parts then
      match List.map int_of_string_opt parts with
      | comps when List.for_all (fun c -> c <> None) comps ->
          Ok (List.map Option.get comps)
      | _ -> Error (Printf.sprintf "version: component out of range in %S" raw)
    else Error (Printf.sprintf "version: not a dotted numeric version: %S" raw)

let compare_version a b =
  let rec go a b =
    match (a, b) with
    | [], [] -> 0
    | [], y :: ys -> if y <> 0 then compare 0 y else go [] ys
    | x :: xs, [] -> if x <> 0 then compare x 0 else go xs []
    | x :: xs, y :: ys -> if x <> y then compare x y else go xs ys
  in
  go a b

let show_version v =
  let rec strip = function
    | [] -> []
    | l -> ( match List.rev l with 0 :: rest -> strip (List.rev rest) | _ -> l)
  in
  match strip v with [] -> "0" | l -> String.concat "." (List.map string_of_int l)

type release = { change : change; version : version; version_text : string; note : string }

let change_rank = function Added -> 0 | Changed -> 1 | Deprecated -> 2 | Removed -> 3

let compare_release a b =
  let c = compare_version a.version b.version in
  if c <> 0 then c
  else
    let c = compare (change_rank a.change) (change_rank b.change) in
    if c <> 0 then c else String.compare a.note b.note

(* Column zero, `.. name:: argument` — the Wiki_directive shape (R14
   mirror of the SHAPE; that library is not a dependency here). *)
let directive_of_line line =
  if not (starts_at line 0 ".. ") then None
  else
    let n = String.length line in
    let rec find i = if i + 1 >= n then None else if starts_at line i "::" then Some i else find (i + 1) in
    match find 3 with
    | None -> None
    | Some i ->
        let name = String.trim (String.sub line 3 (i - 3)) in
        let arg = String.trim (String.sub line (i + 2) (n - i - 2)) in
        Some (name, arg)

let releases body =
  let step (rs, ds) line =
    match directive_of_line line with
    | None -> (rs, ds)
    | Some (name, arg) -> (
        match change_of_name name with
        | None -> (rs, ds)
        | Some ch -> (
            match whitespace_tokens arg with
            | [] ->
                ( rs,
                  Printf.sprintf "version lifecycle: %s has no version" (change_name ch) :: ds )
            | vtext :: note -> (
                match version_of_string vtext with
                | Error e -> (rs, Printf.sprintf "version lifecycle: %s: %s" (change_name ch) e :: ds)
                | Ok v ->
                    ( { change = ch; version = v; version_text = vtext; note = String.concat " " note }
                      :: rs,
                      ds ))))
  in
  let rs, ds = fold_prose_lines step ([], []) body in
  (List.sort compare_release (List.rev rs), sorted_uniq_str ds)

let version_history body =
  let rs, _ = releases body in
  List.map
    (fun r ->
      Printf.sprintf "%s %s%s" (change_name r.change) (show_version r.version)
        (if r.note = "" then "" else ": " ^ r.note))
    rs

(* ============== HW.8.3.2 database templates / HW.8.3.3 Templater *)

type kernel = Upper | Lower | Trim | Slug | First_line | Length

let kernel_name = function
  | Upper -> "upper"
  | Lower -> "lower"
  | Trim -> "trim"
  | Slug -> "slug"
  | First_line -> "first_line"
  | Length -> "length"

(* THE CLOSED SET. Nothing outside this match is a kernel, and there is
   no fall-through: an unrecognised name is [None] here and becomes
   [Unknown_kernel] at every call site. *)
let kernel_of_name = function
  | "upper" -> Some Upper
  | "lower" -> Some Lower
  | "trim" -> Some Trim
  | "slug" -> Some Slug
  | "first_line" -> Some First_line
  | "length" -> Some Length
  | _ -> None

let kernels = sorted_uniq_str (List.map kernel_name [ Upper; Lower; Trim; Slug; First_line; Length ])

let apply_kernel k s =
  match k with
  | Upper -> String.uppercase_ascii s
  | Lower -> String.lowercase_ascii s
  | Trim -> String.trim s
  | Slug -> Hermes_wiki.slugify s
  | First_line -> first_line s
  | Length -> string_of_int (String.length s)

type slot = Direct of string | Computed of kernel * string

type template_error =
  | Unknown_kernel of string
  | Empty_argument of string
  | Off_schema of string
  | Unknown_row of string

let show_template_error = function
  | Unknown_kernel k -> "template: unknown kernel " ^ k ^ " (the kernel set is closed; nothing is evaluated)"
  | Empty_argument s -> "template: computed slot names no column: " ^ s
  | Off_schema c -> "database template: cell off the schema: " ^ c
  | Unknown_row r -> "database template: unknown row " ^ r

let classify_slot name =
  match String.index_opt name ':' with
  | None -> Ok (Direct name)
  | Some i -> (
      let k = String.trim (String.sub name 0 i) in
      let col = String.trim (String.sub name (i + 1) (String.length name - i - 1)) in
      match kernel_of_name k with
      | None -> Error (Unknown_kernel k)
      | Some kern -> if col = "" then Error (Empty_argument name) else Ok (Computed (kern, col)))

let fills ~row ~placeholders =
  let classified = List.map (fun p -> (p, classify_slot p)) placeholders in
  let errs =
    List.filter_map (fun (_, r) -> match r with Error e -> Some e | Ok _ -> None) classified
  in
  if errs <> [] then Error (List.sort_uniq compare errs)
  else
    let computed =
      List.filter_map
        (fun (p, r) ->
          match r with
          | Ok (Computed (k, col)) -> (
              match List.assoc_opt col row with
              | Some v -> Some (p, apply_kernel k v)
              | None -> None)
          | Ok (Direct _) -> None
          | Error _ -> None)
        classified
    in
    let rec dedup seen = function
      | [] -> []
      | (k, v) :: rest ->
          if List.mem k seen then dedup seen rest else (k, v) :: dedup (k :: seen) rest
    in
    Ok (List.sort (fun (a, _) (b, _) -> String.compare a b) (dedup [] (row @ computed)))

type database = {
  db_name : string;
  db_columns : string list;
  db_rows : (string * (string * string) list) list;
}

let database_of_base pages b =
  { db_name = b.base_name;
    db_columns = b.columns;
    db_rows =
      List.map
        (fun (p : Hermes_wiki.page) ->
          ( p.Hermes_wiki.slug,
            List.map (fun c -> (c, Option.value ~default:"" (cell p c))) b.columns ))
        (base_rows pages b) }

let database_fills db ~row ~placeholders =
  match List.assoc_opt row db.db_rows with
  | None -> Error [ Unknown_row row ]
  | Some cells ->
      let off =
        List.filter_map
          (fun (c, _) -> if List.mem c db.db_columns then None else Some (Off_schema c))
          cells
      in
      if off <> [] then Error (List.sort_uniq compare off)
      else fills ~row:cells ~placeholders

(* ========================================== HW.8.3.7 comments & discussions *)

type anchor = { target_slug : string; target_anchor : string option }
type comment = { comment_slug : string; on : anchor }

type comment_defect =
  | Empty_target of string
  | Duplicate_marker of string
  | Missing_page of string * string
  | Missing_anchor of string * string * string

let show_comment_defect = function
  | Empty_target s -> "comment: " ^ s ^ " declares @comments-on with no target"
  | Duplicate_marker s -> "comment: " ^ s ^ " declares more than one @comments-on; the subject is ambiguous"
  | Missing_page (s, t) -> "comment: " ^ s ^ " is ORPHANED: no page " ^ t
  | Missing_anchor (s, t, a) ->
      "comment: " ^ s ^ " is ORPHANED: page " ^ t ^ " exists but emits no anchor " ^ a

let comment_prefix = "@comments-on:"

let comment_markers body =
  let step acc line =
    if starts_at line 0 comment_prefix then
      String.trim
        (String.sub line (String.length comment_prefix)
           (String.length line - String.length comment_prefix))
      :: acc
    else acc
  in
  List.rev (fold_prose_lines step [] body)

let parse_comment_target payload =
  let s = String.trim payload in
  if s = "" then None
  else
    match String.index_opt s '#' with
    | None -> Some { target_slug = s; target_anchor = None }
    | Some i ->
        let t = String.trim (String.sub s 0 i) in
        let a = String.trim (String.sub s (i + 1) (String.length s - i - 1)) in
        if t = "" then None
        else Some { target_slug = t; target_anchor = (if a = "" then None else Some a) }

let comments model =
  let step (cs, ds) (p : Hermes_wiki.page) =
    let me = p.Hermes_wiki.slug in
    match comment_markers p.Hermes_wiki.raw with
    | [] -> (cs, ds)
    | [ m ] -> (
        match parse_comment_target m with
        | None -> (cs, Empty_target me :: ds)
        | Some a -> (
            match Hermes_wiki.page model a.target_slug with
            | None -> (cs, Missing_page (me, a.target_slug) :: ds)
            | Some _ -> (
                match a.target_anchor with
                | None -> ({ comment_slug = me; on = a } :: cs, ds)
                | Some an ->
                    if List.mem an (Hermes_wiki.anchors model a.target_slug) then
                      ({ comment_slug = me; on = a } :: cs, ds)
                    else (cs, Missing_anchor (me, a.target_slug, an) :: ds))))
    | _ :: _ :: _ -> (cs, Duplicate_marker me :: ds)
  in
  let cs, ds = List.fold_left step ([], []) model.Hermes_wiki.pages in
  (List.sort compare cs, List.sort compare ds)

let thread model slug =
  let cs, _ = comments model in
  List.filter (fun c -> c.on.target_slug = slug) cs

let discussion_report model =
  let cs, _ = comments model in
  List.map
    (fun c ->
      Printf.sprintf "%s%s <- %s" c.on.target_slug
        (match c.on.target_anchor with None -> "" | Some a -> "#" ^ a)
        c.comment_slug)
    cs
  |> List.sort String.compare
