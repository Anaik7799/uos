(* route_algebra.ml — the algebra of paths, URLs and routes.

   WHY THIS EXISTS. Every route in this system is currently a string in two
   unrelated places: a pattern in the Dream router (`Dream.get "/api/v1/
   projects/:id"`) and a concatenation in the client (`"/api/v1/projects/" ^
   id`). Nothing connects them. Rename a route and the compiler is silent; the
   failure surfaces as a 404 at runtime, in the browser, possibly only on the
   one path a human happens to click. Captured parameters arrive as `string`
   even when the handler immediately parses them as an integer, so the type
   that would have caught a bad link is thrown away at the door.

   The fix is the one idea worth taking from Eliom, and it needs none of
   Eliom: MAKE THE ROUTE A VALUE. A route is a typed constructor carrying its
   parameters at their real types. The URL is DERIVED from that value by a
   total function, the router pattern is derived from the SAME value, and
   there is no other way to produce either. A link that does not correspond to
   a route is then not a 404 — it is a type error.

   ONTOLOGY (the vocabulary, fixed here and used everywhere downstream):

     Segment   an atomic path component; either a Literal or a Capture
     Path      a finite sequence of segments
     Method    the HTTP verb, part of a route's identity — not a decoration
     Capture   a typed hole in a path; its type is the parameter's real type
     Query     typed optional parameters, closed variants where the value is
               drawn from a fixed set (so `?format=grapml` cannot be written)
     Route     a typed value denoting exactly one endpoint
     Target    a concrete request: method + decoded segments + query
     Pattern   the router's view of a route, with captures named

   SEMANTIC DOMAIN. A route denotes a target:

     ⟦·⟧ : Route → Target       Target = Method × Segment* × Query

   and the parser is the intended inverse:

     parse : Target → Route option

   ENCODINGS. `of_target` has two:

     ORACLE — a linear scan over the pattern table. Each row is one line: a
       method, a pattern, and a builder from the captured segments. Obviously
       correct because there is nothing in a row to get wrong; O(routes ×
       segments).
     FINAL — direct OCaml pattern matching on the method and segment list.
       Fast, and exactly the encoding where a subtle mistake hides: a
       misordered branch silently shadows a later route.

   The ORACLE≡FINAL law is what makes the fast encoding safe to use, and it is
   not decoration — a shadowing bug is invisible to every other law here.

   SCOPE LIMIT. This module is the algebra and its two encodings. Wiring the
   Dream router and the Bonsai client to it are separate steps; the COVERAGE
   law below is what detects that they have drifted, and it reports the drift
   rather than pretending it is absent. *)

(* ---------- capture types --------------------------------------------------
   A capture is a typed hole, and the type is enforced at CONSTRUCTION. `Id`
   is abstract: the only way to obtain one is `of_string`, which is partial,
   so a caller must confront the invalid case at compile time. This is what
   makes `to_path` total — it cannot be handed something that would produce a
   malformed URL, because that value cannot be built. *)

module Id : sig
  type t

  val of_string : string -> t option
  val to_string : t -> string
  val equal : t -> t -> bool
end = struct
  type t = string

  (* Rejected: empty (collapses a segment), '/' (forges a segment boundary),
     control characters (header-splitting shapes), and the two traversal
     segments "." and ".." (a route that reaches a file handler would
     otherwise let an identifier climb the tree). Everything else is admitted
     and carried through percent-encoding, so a legitimate identifier
     containing a space or a '%' round-trips instead of being refused. *)
  let of_string s =
    if s = "" || s = "." || s = ".." then None
    else if String.exists (fun c -> c = '/' || Char.code c < 0x20 || Char.code c = 0x7f) s
    then None
    else Some s

  let to_string s = s
  let equal a b = String.equal a b
end

type meth = GET | POST | PUT | PATCH | DELETE | HEAD

let meth_to_string = function
  | GET -> "GET"
  | POST -> "POST"
  | PUT -> "PUT"
  | PATCH -> "PATCH"
  | DELETE -> "DELETE"
  | HEAD -> "HEAD"

let meth_of_string = function
  | "GET" -> Some GET
  | "POST" -> Some POST
  | "PUT" -> Some PUT
  | "PATCH" -> Some PATCH
  | "DELETE" -> Some DELETE
  | "HEAD" -> Some HEAD
  | _ -> None

(* A closed variant for a query parameter whose values come from a fixed set.
   `?format=grapml` is now a compile error rather than a 400 discovered by a
   user. The `All` list is the totality witness the laws quantify over. *)
type export_format = Json | Graphml | Dot

let export_format_to_string = function Json -> "json" | Graphml -> "graphml" | Dot -> "dot"

let export_format_of_string = function
  | "json" -> Some Json
  | "graphml" -> Some Graphml
  | "dot" -> Some Dot
  | _ -> None

let export_formats = [ Json; Graphml; Dot ]

(* ---------- the route ------------------------------------------------------
   The method is part of the constructor's identity, not a separate argument:
   `Project_delete` and `Project` differ only by verb, and making that a
   constructor distinction is what lets `meth` be a total derived function and
   lets INJECTIVITY be stated over the constructor set. *)

type t =
  | Root
  | Health
  | Overview
  | Features
  | Projects_index
  | Project_create
  | Project of Id.t
  | Project_update of Id.t
  | Project_delete of Id.t
  | Project_duplicate of Id.t
  | Project_views of Id.t
  | Project_view_create of Id.t
  | Project_view_delete of Id.t * Id.t
  | Project_notes of Id.t
  | Project_note_create of Id.t
  | Project_share of Id.t
  | Project_share_set of Id.t
  | Graphs_index
  | Graph of Id.t
  | Graph_analytics of Id.t
  | Graph_export of Id.t * export_format
  | Job of int
  | Preview_text
  | Preview_export
  | Preview_acquire
  | Preview_intelligence
  | Command of Id.t
  | Bonsai_page
  | Bundle_asset
  | Bundle_asset_head
  | Events

(* ---------- percent-encoding ----------------------------------------------
   Captures are encoded on the way out and decoded on the way in. Getting this
   wrong in one direction only is the classic asymmetry defect, which is why
   the round-trip law is quantified over adversarial identifiers rather than
   over the ones we expect. *)

let unreserved c =
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
  || c = '-' || c = '.' || c = '_' || c = '~'

let encode_segment (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      if unreserved c then Buffer.add_char b c
      else Buffer.add_string b (Printf.sprintf "%%%02X" (Char.code c)))
    s;
  Buffer.contents b

let hex_val c =
  if c >= '0' && c <= '9' then Some (Char.code c - 48)
  else if c >= 'a' && c <= 'f' then Some (Char.code c - 87)
  else if c >= 'A' && c <= 'F' then Some (Char.code c - 55)
  else None

(* TOTAL: a malformed escape is carried through literally rather than raising.
   A decoder on a request path reads bytes from a peer we do not control. *)
let decode_segment (s : string) : string =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    (if s.[!i] = '%' && !i + 2 < n then
       match (hex_val s.[!i + 1], hex_val s.[!i + 2]) with
       | Some h, Some l ->
           Buffer.add_char b (Char.chr ((h * 16) + l));
           i := !i + 2
       | _ -> Buffer.add_char b s.[!i]
     else Buffer.add_char b s.[!i]);
    incr i
  done;
  Buffer.contents b

(* ---------- the denotation -------------------------------------------------
   ⟦·⟧ : Route → Target. Segments are DECODED here; encoding is a property of
   the rendered path, not of the target, so the two concerns cannot be
   confused. *)

type target = { meth : meth; segments : string list; query : (string * string) list }

let denote (r : t) : target =
  let id = Id.to_string in
  let g meth segments = { meth; segments; query = [] } in
  match r with
  | Root -> g GET []
  | Health -> g GET [ "health" ]
  | Overview -> g GET [ "api"; "v1"; "overview" ]
  | Features -> g GET [ "api"; "v1"; "features" ]
  | Projects_index -> g GET [ "api"; "v1"; "projects" ]
  | Project_create -> g POST [ "api"; "v1"; "projects" ]
  | Project i -> g GET [ "api"; "v1"; "projects"; id i ]
  | Project_update i -> g PATCH [ "api"; "v1"; "projects"; id i ]
  | Project_delete i -> g DELETE [ "api"; "v1"; "projects"; id i ]
  | Project_duplicate i -> g POST [ "api"; "v1"; "projects"; id i; "duplicate" ]
  | Project_views i -> g GET [ "api"; "v1"; "projects"; id i; "views" ]
  | Project_view_create i -> g POST [ "api"; "v1"; "projects"; id i; "views" ]
  | Project_view_delete (i, v) -> g DELETE [ "api"; "v1"; "projects"; id i; "views"; id v ]
  | Project_notes i -> g GET [ "api"; "v1"; "projects"; id i; "notes" ]
  | Project_note_create i -> g POST [ "api"; "v1"; "projects"; id i; "notes" ]
  | Project_share i -> g GET [ "api"; "v1"; "projects"; id i; "share" ]
  | Project_share_set i -> g PUT [ "api"; "v1"; "projects"; id i; "share" ]
  | Graphs_index -> g GET [ "api"; "v1"; "graphs" ]
  | Graph i -> g GET [ "api"; "v1"; "graphs"; id i ]
  | Graph_analytics i -> g GET [ "api"; "v1"; "graphs"; id i; "analytics" ]
  | Graph_export (i, f) ->
      { meth = GET;
        segments = [ "api"; "v1"; "graphs"; id i; "export" ];
        query = [ ("format", export_format_to_string f) ] }
  | Job n -> g GET [ "api"; "v1"; "jobs"; string_of_int n ]
  | Preview_text -> g POST [ "api"; "v1"; "preview"; "text" ]
  | Preview_export -> g POST [ "api"; "v1"; "preview"; "export" ]
  | Preview_acquire -> g POST [ "api"; "v1"; "preview"; "acquire" ]
  | Preview_intelligence -> g POST [ "api"; "v1"; "preview"; "intelligence" ]
  | Command c -> g POST [ "api"; "v1"; "commands"; id c ]
  | Bonsai_page -> g GET [ "bonsai" ]
  | Bundle_asset -> g GET [ "assets"; "zigvm-bonsai.js" ]
  | Bundle_asset_head -> { meth = HEAD; segments = [ "assets"; "zigvm-bonsai.js" ]; query = [] }
  | Events -> g GET [ "events" ]

let meth_of (r : t) : meth = (denote r).meth

(* ---------- rendering ------------------------------------------------------
   The ONLY way to obtain a URL. Total by construction: every segment comes
   from the denotation and is encoded here, so a rendered path is canonical —
   leading slash, no empty segment, no trailing slash except at the root. *)

let to_path (r : t) : string =
  let d = denote r in
  let path =
    match d.segments with
    | [] -> "/"
    | ss -> "/" ^ String.concat "/" (List.map encode_segment ss)
  in
  match d.query with
  | [] -> path
  | q ->
      path ^ "?"
      ^ String.concat "&"
          (List.map (fun (k, v) -> encode_segment k ^ "=" ^ encode_segment v) q)

(* ---------- the pattern table ----------------------------------------------
   The router's view, derived from the same value. `pattern` is what Dream is
   handed, so the server cannot be listening on a path the client cannot name.
   Each row also carries its BUILDER, which is what makes the oracle a
   one-line-per-route table with nothing to get wrong. *)

let pattern (r : t) : string =
  let d = denote r in
  let hole name = ":" ^ name in
  let segs =
    match r with
    | Project _ | Project_update _ | Project_delete _ -> [ "api"; "v1"; "projects"; hole "id" ]
    | Project_duplicate _ -> [ "api"; "v1"; "projects"; hole "id"; "duplicate" ]
    | Project_views _ | Project_view_create _ -> [ "api"; "v1"; "projects"; hole "id"; "views" ]
    | Project_view_delete _ ->
        [ "api"; "v1"; "projects"; hole "id"; "views"; hole "view_id" ]
    | Project_notes _ | Project_note_create _ -> [ "api"; "v1"; "projects"; hole "id"; "notes" ]
    | Project_share _ | Project_share_set _ -> [ "api"; "v1"; "projects"; hole "id"; "share" ]
    | Graph _ -> [ "api"; "v1"; "graphs"; hole "id" ]
    | Graph_analytics _ -> [ "api"; "v1"; "graphs"; hole "id"; "analytics" ]
    | Graph_export _ -> [ "api"; "v1"; "graphs"; hole "id"; "export" ]
    | Job _ -> [ "api"; "v1"; "jobs"; hole "id" ]
    | Command _ -> [ "api"; "v1"; "commands"; hole "command" ]
    | _ -> d.segments
  in
  match segs with [] -> "/" | ss -> "/" ^ String.concat "/" ss

(* Witness values. Every constructor appears exactly once, which is what turns
   "we tested some routes" into "we quantified over the route type". A new
   constructor that is not added here is caught by the TOTALITY-OF-WITNESSES
   law, which counts constructors via an exhaustive match. *)
let witness_id = match Id.of_string "w" with Some i -> i | None -> assert false
let witness_id2 = match Id.of_string "w2" with Some i -> i | None -> assert false

let all : t list =
  [ Root; Health; Overview; Features; Projects_index; Project_create;
    Project witness_id; Project_update witness_id; Project_delete witness_id;
    Project_duplicate witness_id; Project_views witness_id; Project_view_create witness_id;
    Project_view_delete (witness_id, witness_id2); Project_notes witness_id;
    Project_note_create witness_id; Project_share witness_id; Project_share_set witness_id;
    Graphs_index; Graph witness_id; Graph_analytics witness_id;
    Graph_export (witness_id, Json); Job 7; Preview_text; Preview_export; Preview_acquire;
    Preview_intelligence; Command witness_id; Bonsai_page; Bundle_asset; Bundle_asset_head;
    Events ]

(* An exhaustive match whose only job is to be exhaustive: adding a
   constructor without adding a witness above makes the arity law fail, and
   forgetting this function entirely makes the compiler fail. *)
let constructor_index (r : t) : int =
  match r with
  | Root -> 0 | Health -> 1 | Overview -> 2 | Features -> 3 | Projects_index -> 4
  | Project_create -> 5 | Project _ -> 6 | Project_update _ -> 7 | Project_delete _ -> 8
  | Project_duplicate _ -> 9 | Project_views _ -> 10 | Project_view_create _ -> 11
  | Project_view_delete _ -> 12 | Project_notes _ -> 13 | Project_note_create _ -> 14
  | Project_share _ -> 15 | Project_share_set _ -> 16 | Graphs_index -> 17 | Graph _ -> 18
  | Graph_analytics _ -> 19 | Graph_export _ -> 20 | Job _ -> 21 | Preview_text -> 22
  | Preview_export -> 23 | Preview_acquire -> 24 | Preview_intelligence -> 25
  | Command _ -> 26 | Bonsai_page -> 27 | Bundle_asset -> 28 | Bundle_asset_head -> 29
  | Events -> 30

let constructor_count = 31

(* ---------- ORACLE ---------------------------------------------------------
   A linear scan over the pattern table. One row per route: a method, the
   pattern segments, and a builder from the captured segments in order. There
   is nothing in a row to get wrong, which is the whole point of an oracle. *)

let table : (meth * string list * (string list -> t option)) list =
  let one f = function [ a ] -> f a | _ -> None in
  let two f = function [ a; b ] -> f a b | _ -> None in
  let none r = function [] -> Some r | _ -> None in
  let id1 k = one (fun a -> match Id.of_string a with Some i -> Some (k i) | None -> None) in
  let id2 k =
    two (fun a b ->
        match (Id.of_string a, Id.of_string b) with
        | Some x, Some y -> Some (k x y)
        | _ -> None)
  in
  [ (GET, [], none Root);
    (GET, [ "health" ], none Health);
    (GET, [ "api"; "v1"; "overview" ], none Overview);
    (GET, [ "api"; "v1"; "features" ], none Features);
    (GET, [ "api"; "v1"; "projects" ], none Projects_index);
    (POST, [ "api"; "v1"; "projects" ], none Project_create);
    (POST, [ "api"; "v1"; "projects"; ":id"; "duplicate" ], id1 (fun i -> Project_duplicate i));
    (GET, [ "api"; "v1"; "projects"; ":id" ], id1 (fun i -> Project i));
    (PATCH, [ "api"; "v1"; "projects"; ":id" ], id1 (fun i -> Project_update i));
    (DELETE, [ "api"; "v1"; "projects"; ":id" ], id1 (fun i -> Project_delete i));
    (GET, [ "api"; "v1"; "projects"; ":id"; "views" ], id1 (fun i -> Project_views i));
    (POST, [ "api"; "v1"; "projects"; ":id"; "views" ], id1 (fun i -> Project_view_create i));
    ( DELETE,
      [ "api"; "v1"; "projects"; ":id"; "views"; ":view_id" ],
      id2 (fun i v -> Project_view_delete (i, v)) );
    (GET, [ "api"; "v1"; "projects"; ":id"; "notes" ], id1 (fun i -> Project_notes i));
    (POST, [ "api"; "v1"; "projects"; ":id"; "notes" ], id1 (fun i -> Project_note_create i));
    (GET, [ "api"; "v1"; "projects"; ":id"; "share" ], id1 (fun i -> Project_share i));
    (PUT, [ "api"; "v1"; "projects"; ":id"; "share" ], id1 (fun i -> Project_share_set i));
    (GET, [ "api"; "v1"; "graphs" ], none Graphs_index);
    (GET, [ "api"; "v1"; "graphs"; ":id" ], id1 (fun i -> Graph i));
    (GET, [ "api"; "v1"; "graphs"; ":id"; "analytics" ], id1 (fun i -> Graph_analytics i));
    (GET, [ "api"; "v1"; "graphs"; ":id"; "export" ], id1 (fun i -> Graph_export (i, Json)));
    ( GET,
      [ "api"; "v1"; "jobs"; ":id" ],
      one (fun a -> match int_of_string_opt a with Some n -> Some (Job n) | None -> None) );
    (POST, [ "api"; "v1"; "preview"; "text" ], none Preview_text);
    (POST, [ "api"; "v1"; "preview"; "export" ], none Preview_export);
    (POST, [ "api"; "v1"; "preview"; "acquire" ], none Preview_acquire);
    (POST, [ "api"; "v1"; "preview"; "intelligence" ], none Preview_intelligence);
    (POST, [ "api"; "v1"; "commands"; ":command" ], id1 (fun c -> Command c));
    (GET, [ "bonsai" ], none Bonsai_page);
    (GET, [ "assets"; "zigvm-bonsai.js" ], none Bundle_asset);
    (HEAD, [ "assets"; "zigvm-bonsai.js" ], none Bundle_asset_head);
    (GET, [ "events" ], none Events) ]

let is_hole s = String.length s > 0 && s.[0] = ':'

(* Match a concrete segment list against one pattern, returning the captures.
   The `Graph_export` query default is applied by the caller, because query
   handling is not part of path matching. *)
let match_pattern (pat : string list) (segs : string list) : string list option =
  let rec go pat segs acc =
    match (pat, segs) with
    | [], [] -> Some (List.rev acc)
    | p :: pt, s :: st ->
        if is_hole p then go pt st (s :: acc)
        else if String.equal p s then go pt st acc
        else None
    | _ -> None
  in
  go pat segs []

let of_target_oracle (d : target) : t option =
  let rec scan = function
    | [] -> None
    | (m, pat, build) :: rest ->
        if m = d.meth then
          match match_pattern pat d.segments with
          | Some caps -> ( match build caps with Some r -> Some r | None -> scan rest)
          | None -> scan rest
        else scan rest
  in
  match scan table with
  | Some (Graph_export (i, _)) ->
      (* the query is typed: an unrecognised format is a rejection, not a
         silent fallback, because a silent fallback is how `?format=grapml`
         quietly returns JSON and nobody notices *)
      let f = List.assoc_opt "format" d.query in
      (match f with
       | None -> Some (Graph_export (i, Json))
       | Some s -> (
           match export_format_of_string s with
           | Some fmt -> Some (Graph_export (i, fmt))
           | None -> None))
  | other -> other

(* ---------- FINAL ----------------------------------------------------------
   Direct pattern matching on method and segment list. This is the encoding
   that ships, and the encoding where a misordered branch silently shadows a
   later route — which no law other than ORACLE≡FINAL would detect. *)

let of_target (d : target) : t option =
  let id s = Id.of_string s in
  let ( let* ) o f = match o with Some x -> f x | None -> None in
  match (d.meth, d.segments) with
  | GET, [] -> Some Root
  | GET, [ "health" ] -> Some Health
  | GET, [ "bonsai" ] -> Some Bonsai_page
  | GET, [ "events" ] -> Some Events
  | GET, [ "assets"; "zigvm-bonsai.js" ] -> Some Bundle_asset
  | HEAD, [ "assets"; "zigvm-bonsai.js" ] -> Some Bundle_asset_head
  | GET, [ "api"; "v1"; "overview" ] -> Some Overview
  | GET, [ "api"; "v1"; "features" ] -> Some Features
  | GET, [ "api"; "v1"; "projects" ] -> Some Projects_index
  | POST, [ "api"; "v1"; "projects" ] -> Some Project_create
  | POST, [ "api"; "v1"; "projects"; i; "duplicate" ] ->
      let* i = id i in
      Some (Project_duplicate i)
  | GET, [ "api"; "v1"; "projects"; i ] ->
      let* i = id i in
      Some (Project i)
  | PATCH, [ "api"; "v1"; "projects"; i ] ->
      let* i = id i in
      Some (Project_update i)
  | DELETE, [ "api"; "v1"; "projects"; i ] ->
      let* i = id i in
      Some (Project_delete i)
  | GET, [ "api"; "v1"; "projects"; i; "views" ] ->
      let* i = id i in
      Some (Project_views i)
  | POST, [ "api"; "v1"; "projects"; i; "views" ] ->
      let* i = id i in
      Some (Project_view_create i)
  | DELETE, [ "api"; "v1"; "projects"; i; "views"; v ] ->
      let* i = id i in
      let* v = id v in
      Some (Project_view_delete (i, v))
  | GET, [ "api"; "v1"; "projects"; i; "notes" ] ->
      let* i = id i in
      Some (Project_notes i)
  | POST, [ "api"; "v1"; "projects"; i; "notes" ] ->
      let* i = id i in
      Some (Project_note_create i)
  | GET, [ "api"; "v1"; "projects"; i; "share" ] ->
      let* i = id i in
      Some (Project_share i)
  | PUT, [ "api"; "v1"; "projects"; i; "share" ] ->
      let* i = id i in
      Some (Project_share_set i)
  | GET, [ "api"; "v1"; "graphs" ] -> Some Graphs_index
  | GET, [ "api"; "v1"; "graphs"; i; "analytics" ] ->
      let* i = id i in
      Some (Graph_analytics i)
  | GET, [ "api"; "v1"; "graphs"; i; "export" ] -> (
      let* i = id i in
      match List.assoc_opt "format" d.query with
      | None -> Some (Graph_export (i, Json))
      | Some s -> (
          match export_format_of_string s with
          | Some f -> Some (Graph_export (i, f))
          | None -> None))
  | GET, [ "api"; "v1"; "graphs"; i ] ->
      let* i = id i in
      Some (Graph i)
  | GET, [ "api"; "v1"; "jobs"; i ] ->
      let* n = int_of_string_opt i in
      Some (Job n)
  | POST, [ "api"; "v1"; "preview"; "text" ] -> Some Preview_text
  | POST, [ "api"; "v1"; "preview"; "export" ] -> Some Preview_export
  | POST, [ "api"; "v1"; "preview"; "acquire" ] -> Some Preview_acquire
  | POST, [ "api"; "v1"; "preview"; "intelligence" ] -> Some Preview_intelligence
  | POST, [ "api"; "v1"; "commands"; c ] ->
      let* c = id c in
      Some (Command c)
  | _ -> None

(* ---------- parsing a raw request -----------------------------------------
   TOTAL over any byte string. Splitting, decoding and query parsing all
   happen here so that `of_target` sees a clean target and the messy part has
   exactly one home. *)

let split_query (s : string) : string * (string * string) list =
  match String.index_opt s '?' with
  | None -> (s, [])
  | Some i ->
      let path = String.sub s 0 i in
      let qs = String.sub s (i + 1) (String.length s - i - 1) in
      let pairs =
        String.split_on_char '&' qs
        |> List.filter (fun p -> p <> "")
        |> List.map (fun p ->
               match String.index_opt p '=' with
               | None -> (decode_segment p, "")
               | Some j ->
                   ( decode_segment (String.sub p 0 j),
                     decode_segment (String.sub p (j + 1) (String.length p - j - 1)) ))
      in
      (path, pairs)

let target_of_request ~(meth : meth) ~(path : string) : target =
  let path, query = split_query path in
  let segments =
    String.split_on_char '/' path
    |> List.filter (fun s -> s <> "")
    |> List.map decode_segment
  in
  { meth; segments; query }

(* TOTAL: any method string, any path, never raises. *)
let parse ~(meth : string) ~(path : string) : t option =
  match meth_of_string meth with
  | None -> None
  | Some m -> of_target (target_of_request ~meth:m ~path)

(* ---------- classified parsing ---------------------------------------------
   `parse` collapses two different failures into `None`, and running the wired
   server showed why that is not good enough: `?format=grapml` came back as
   404, because a rejected query is indistinguishable from an unknown path.
   The path EXISTS; the query is wrong; those deserve different answers.

   `path_matches` derives the distinction from the ORACLE table rather than
   restating it — a row builds successfully from the captured segments alone,
   so a build that succeeds while the full parse fails means the PATH was fine
   and the query was not. No logic is duplicated, which is the only reason
   this is safe to add. *)

type parse_outcome =
  | Matched of t
  | Bad_input
      (** the path names a route SHAPE, but a capture or a query value was
          rejected. A malformed integer id and a malformed `?format=` are the
          same situation and must get the same answer: 400, not 404. *)
  | No_route  (** nothing serves this method and path *)

(* SHAPE only — deliberately ignoring whether the builder succeeds. A path
   whose captures fail to convert still NAMES a route shape, and answering 404
   there would say "no such address" about an address that plainly exists.
   Running the generated router surfaced this: /api/v1/jobs/notanint returned
   404 while a malformed ?format= returned 400, for no principled reason. *)
let path_matches (d : target) : bool =
  List.exists
    (fun (m, pat, _build) -> m = d.meth && match_pattern pat d.segments <> None)
    table

let classify_target (d : target) : parse_outcome =
  match of_target d with
  | Some r -> Matched r
  | None -> if path_matches d then Bad_input else No_route

let classify ~(meth : string) ~(path : string) : parse_outcome =
  match meth_of_string meth with
  | None -> No_route
  | Some m -> classify_target (target_of_request ~meth:m ~path)

(* ---------- the dispatch table ---------------------------------------------
   The router, as DATA. Everything a server needs to install its routes is
   derived from `all`, so a route cannot be served-but-unnamed or
   named-but-unserved: those states stop being possible rather than being
   checked for.

   FORMAL SPEC of the generated router. Writing `install : (t -> handler) ->
   route list`, the contract is:

     COMPLETE      every constructor of `t` appears exactly once
     UNAMBIGUOUS   no concrete target matches two entries, so the order in
                   which entries are installed cannot change any outcome
     FAITHFUL      the entry that matches a target is the one whose route
                   `classify` returns for that target
     TOTAL         a target matching no entry is a rejection, never an
                   exception

   COMPLETE and UNAMBIGUOUS are laws below. FAITHFUL is a law below.
   EXHAUSTIVENESS of the handler function is not a law at all — it is a type
   error, because `t -> handler` must match every constructor. That is the
   whole reason to generate rather than to check. *)

let dispatch_table : (meth * string) list = List.map (fun r -> (meth_of r, pattern r)) all

(* Does a concrete target match a pattern? Segment-wise, holes matching any
   single segment — the same rule `match_pattern` uses, expressed over the
   pattern STRING because that is what a server is handed. *)
let pattern_matches ((m, pat) : meth * string) (d : target) : bool =
  m = d.meth
  &&
  let ps = String.split_on_char '/' pat |> List.filter (fun s -> s <> "") in
  List.length ps = List.length d.segments
  && List.for_all2 (fun p s -> is_hole p || String.equal p s) ps d.segments

(* Which entries would a server route this target to? The UNAMBIGUOUS law
   requires this to have at most one element, for every target. *)
let matching_entries (d : target) : (meth * string) list =
  List.filter (fun e -> pattern_matches e d) dispatch_table

(* ---------- observation ----------------------------------------------------
   A name for humans and dashboards. Report-only: nothing here decides
   anything. *)
let describe (r : t) : string =
  Printf.sprintf "%s %s" (meth_to_string (meth_of r)) (to_path r)
