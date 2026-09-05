(* THE ADDRESSING FAMILY — see the mli for the five laws. Implementation
   notes only here.

   R14 (reuse or mirror, never reinvent):
     - the reference grammar is NOT re-parsed: [parse] calls
       [Wiki_ref.parse] and peels a domain qualifier off the target it
       returns, so there is exactly one payload grammar in the engine;
     - key normalization is [Hermes_wiki.slugify] / [strip_fragment], the
       engine's own, so the inventory cannot normalize differently from
       the resolver that must agree with it;
     - the heading slugger is [Hermes_wiki.make_slugger]'s algorithm
       quirk-for-quirk (stateful, first-wins, `-1`/`-2` on collision,
       empty -> "section", level clamped at 4 BEFORE the text is cut),
       because agreement with the engine is the law and a "cleaner"
       reimplementation would break it;
     - the expansion machinery is [Wiki_transclude.expand]'s algebra:
       the PATH rather than a visited set (a name used twice is not a
       cycle), a REPORTED depth bound, a visible marker for every
       failure, and every diagnostic list sorted at the end. *)

(* ------------------------------------------------------ HW.3.9.1 domains *)

type domain = Wiki | Zk | Journal | Spec

let domains = [ Wiki; Zk; Journal; Spec ]

let domain_name = function
  | Wiki -> "wiki"
  | Zk -> "zk"
  | Journal -> "journal"
  | Spec -> "spec"

(* CLOSED and lowercase, exactly as Wiki_ref's role set: this is what
   keeps `[[re: subject]]` a plain target containing a colon. *)
let domain_of_name = function
  | "wiki" -> Some Wiki
  | "zk" -> Some Zk
  | "journal" -> Some Journal
  | "spec" -> Some Spec
  | _ -> None

(* The parent directory name, read exactly as the engine's [group_of]
   reads it. `specs/` is the corpus's own spelling of the spec stratum.
   Anything else is an ORDINARY PAGE (R16), hence [Wiki] — never a
   refusal: a document always has a domain. *)
let domain_of_path path =
  match Filename.basename (Filename.dirname path) with
  | "specs" -> Spec
  | parent -> ( match domain_of_name parent with Some d -> d | None -> Wiki)

type address = {
  domain : domain option;
  reference : Wiki_ref.t;
}

(* A qualifier is a KNOWN domain name, a colon, and a nonempty remainder.
   Anything else is target text. *)
let split_domain target =
  match String.index_opt target ':' with
  | None -> None
  | Some i -> (
      let name = String.sub target 0 i in
      let rest = String.trim (String.sub target (i + 1) (String.length target - i - 1)) in
      match domain_of_name name with Some d when rest <> "" -> Some (d, rest) | _ -> None)

let parse payload =
  let r0 = Wiki_ref.parse payload in
  match split_domain r0.Wiki_ref.target with
  | None -> { domain = None; reference = r0 }
  | Some (d, rest) ->
      (* `[[zk:doc:x]]`: the role was not consumed by Wiki_ref (the
         qualifier was in the way), so re-run the ONE grammar on the
         remainder. `[[doc:zk:x]]`: the role is already known, only the
         target shortens. Either order, one address. display/rel come
         from the first parse — they live on the far side of the `|` and
         the remainder never contains them. *)
      let reference =
        if r0.Wiki_ref.kind = Wiki_ref.Any then
          let r1 = Wiki_ref.parse rest in
          { r0 with
            Wiki_ref.kind = r1.Wiki_ref.kind;
            target = r1.Wiki_ref.target;
            suppress = r0.Wiki_ref.suppress || r1.Wiki_ref.suppress }
        else { r0 with Wiki_ref.target = rest }
      in
      { domain = Some d; reference }

let to_wiki a =
  let q = match a.domain with Some d -> domain_name d ^ ":" | None -> "" in
  Wiki_ref.to_wiki { a.reference with Wiki_ref.target = q ^ a.reference.Wiki_ref.target }

(* ---------------------------------------------------- HW.3.8.1 inventory *)

type entry = {
  edomain : domain;
  ekind : Wiki_ref.kind;
  ekey : string;
  eslug : string;
  eanchor : string option;
}

let entries_of_model m =
  let pages = m.Hermes_wiki.pages in
  (* build's THREE tiers, in build's order: living identity keys, then
     archived identity keys, then aliases over every page. First
     registration wins, so this table IS the resolver's answer. *)
  let living, archived =
    List.partition (fun p -> p.Hermes_wiki.meta.Hermes_wiki.maturity <> "archived") pages
  in
  let register keys_of table ps =
    List.fold_left
      (fun table p ->
        List.fold_left
          (fun table k -> if k = "" || List.mem_assoc k table then table else (k, p) :: table)
          table (keys_of p))
      table ps
  in
  let table = register Hermes_wiki.resolver_keys [] living in
  let table = register Hermes_wiki.resolver_keys table archived in
  let table = register Hermes_wiki.alias_keys table pages in
  let docs =
    List.map
      (fun (k, p) ->
        { edomain = domain_of_path p.Hermes_wiki.path;
          ekind = Wiki_ref.Doc;
          ekey = k;
          eslug = p.Hermes_wiki.slug;
          eanchor = None })
      table
  in
  (* The glossary space, in CORPUS order — build's [resolve_term] is
     List.assoc over that order, so first-wins here means the same page
     the engine answers with. (Hermes_wiki.glossary_terms is the same set
     SORTED, which would pick a different winner for a term two glossary
     pages both define; agreement, not tidiness, decides.) *)
  let term_space =
    List.concat_map
      (fun p ->
        if List.mem "glossary" p.Hermes_wiki.meta.Hermes_wiki.topics then
          p.Hermes_wiki.headings
          |> List.filter (fun (l, _, _) -> l >= 2)
          |> List.map (fun (_, text, anchor) -> (Hermes_wiki.slugify text, (p, anchor)))
        else [])
      pages
  in
  let terms =
    List.fold_left
      (fun acc (k, v) -> if k = "" || List.mem_assoc k acc then acc else (k, v) :: acc)
      [] term_space
    |> List.map (fun (k, (p, anchor)) ->
           { edomain = domain_of_path p.Hermes_wiki.path;
             ekind = Wiki_ref.Term;
             ekey = k;
             eslug = p.Hermes_wiki.slug;
             eanchor = Some anchor })
  in
  List.sort_uniq compare (docs @ terms)

(* ROOT-RELATIVE: a site path, never a filesystem path and never a URL
   with a host. A consumer joins it to the base it already knows. *)
let location e =
  "/" ^ e.eslug ^ ".html" ^ match e.eanchor with Some a -> "#" ^ a | None -> ""

let inventory_version = "hermes-inventory v1"

let inventory es =
  let line e =
    String.concat "\t" [ domain_name e.edomain; Wiki_ref.kind_name e.ekind; e.ekey; location e ]
  in
  (* SORTED bytes: the digest is then a function of the entry SET, not of
     the order it was assembled in. *)
  let body = List.sort compare (List.map line es) in
  String.concat "" (List.map (fun l -> l ^ "\n") (inventory_version :: body))

let inventory_digest es = Digest.to_hex (Digest.string (inventory es))

let resolve entries a =
  let key = Hermes_wiki.slugify (Hermes_wiki.strip_fragment a.reference.Wiki_ref.target) in
  if key = "" then []
  else
    List.filter
      (fun e ->
        e.ekey = key
        (* THE domain law: a qualified address never leaves its domain. *)
        && (match a.domain with None -> true | Some d -> e.edomain = d)
        (* inherited: kind(resolve_k(x)) = k for k <> Any *)
        && match a.reference.Wiki_ref.kind with Wiki_ref.Any -> true | k -> e.ekind = k)
      entries
    |> List.sort_uniq compare

(* ------------------------------------------------- shared line machinery *)

type outcome = {
  text : string;
  used : string list;
  conflicts : string list;
  missing : string list;
  cycles : string list;
  truncated : string list;
  anomalies : string list;
}

let default_depth = 3

let lines_of text = String.split_on_char '\n' text

let is_fence line =
  let t = String.trim line in
  String.length t >= 3 && String.sub t 0 3 = "```"

(* (line, code?) where code? means "the line is a fence marker or lies
   inside a fence": everything the scanners must pass through untouched. *)
let walk_lines body =
  let _, acc =
    List.fold_left
      (fun (in_fence, acc) line ->
        if is_fence line then (not in_fence, (line, true) :: acc)
        else (in_fence, (line, in_fence) :: acc))
      (false, []) (lines_of body)
  in
  List.rev acc

(* CODE IS NOT PROSE, inline as well as fenced (mask_inline_spans,
   mirrored): true where the character lies in an inline `span`,
   backticks included. Per-line pairing — the same documented bound the
   reference scanner carries. *)
let code_mask line =
  let n = String.length line in
  let m = Array.make (max n 1) false in
  let inside = ref false in
  for i = 0 to n - 1 do
    if line.[i] = '`' then (
      inside := not !inside;
      m.(i) <- true)
    else m.(i) <- !inside
  done;
  m

let find_sub_unmasked mask hay needle start =
  let nh = String.length hay and nn = String.length needle in
  let rec go i =
    if i + nn > nh then None
    else if (not mask.(i)) && String.sub hay i nn = needle then Some i
    else go (i + 1)
  in
  if nn = 0 then None else go (max 0 start)

type directive = Absent | Payload of string | Malformed | Misplaced

(* The corpus's comment-directive family (`<!-- index: ... -->`), read as
   a LINE directive. A directive written inside backticks is an EXAMPLE
   of the grammar and is [Absent] — never an anomaly, or every document
   that documents this feature would report one. *)
let directive_of_line tag line =
  let mask = code_mask line in
  match find_sub_unmasked mask line "<!--" 0 with
  | None -> Absent
  | Some i -> (
      match find_sub_unmasked mask line "-->" (i + 4) with
      | None -> Absent (* an unterminated comment is prose, not a directive *)
      | Some j ->
          let inner = String.trim (String.sub line (i + 4) (j - i - 4)) in
          if not (String.starts_with ~prefix:tag inner) then Absent
          else
            let payload =
              String.trim
                (String.sub inner (String.length tag) (String.length inner - String.length tag))
            in
            let before = String.trim (String.sub line 0 i) in
            let after = String.trim (String.sub line (j + 3) (String.length line - j - 3)) in
            if before <> "" || after <> "" then Misplaced
            else if payload = "" then Malformed
            else Payload payload)

let sortu l = List.sort_uniq compare l

(* ---------------------------------------------- HW.3.10.1 substitutions *)

let valid_name s =
  s <> ""
  && not
       (String.exists
          (fun c -> c = ' ' || c = '\t' || c = '{' || c = '}' || c = '|' || c = '`')
          s)

type sline = Body | Def of string * string | Def_bad of string

let classify_subst line =
  match directive_of_line "subst:" line with
  | Absent -> Body
  | Misplaced -> Def_bad "a definition owns its line"
  | Malformed -> Def_bad "empty definition"
  | Payload p -> (
      match String.index_opt p '=' with
      | None -> Def_bad "no `=` between the name and its replacement"
      | Some i ->
          let name = String.trim (String.sub p 0 i) in
          let value = String.trim (String.sub p (i + 1) (String.length p - i - 1)) in
          (* an EMPTY replacement is a deliberate erasure, and legal *)
          if valid_name name then Def (name, value) else Def_bad "invalid substitution name")

let definitions body =
  let defs = ref [] in
  List.iter
    (fun (line, code) ->
      if not code then
        match classify_subst line with
        | Def (n, v) -> if not (List.mem_assoc n !defs) then defs := (n, v) :: !defs
        | Body | Def_bad _ -> ())
    (walk_lines body);
  List.rev !defs

let substitute ?(depth = default_depth) body =
  let ls = walk_lines body in
  let used = ref []
  and conflicts = ref []
  and missing = ref []
  and cycles = ref []
  and truncated = ref []
  and anomalies = ref [] in
  (* pass 1: the definitions govern the WHOLE document, so they are
     collected before any use is expanded. First wins, and a second
     definition is REPORTED rather than silently preferred. *)
  let defs = ref [] in
  List.iter
    (fun (line, code) ->
      if not code then
        match classify_subst line with
        | Def (n, v) ->
            if List.mem_assoc n !defs then
              conflicts :=
                Printf.sprintf
                  "substitution defined twice: %s (first definition wins, REPORTED not resolved)" n
                :: !conflicts
            else defs := (n, v) :: !defs
        | Body | Def_bad _ -> ())
    ls;
  let defs = List.rev !defs in
  let rec expand_text path level s =
    let n = String.length s in
    let buf = Buffer.create n in
    let in_code = ref false in
    let i = ref 0 in
    while !i < n do
      if s.[!i] = '`' then (
        in_code := not !in_code;
        Buffer.add_char buf s.[!i];
        incr i)
      else if !in_code then (
        Buffer.add_char buf s.[!i];
        incr i)
      else if !i + 2 <= n && String.sub s !i 2 = "{{" then (
        let rec close k =
          if k + 1 < n then if s.[k] = '}' && s.[k + 1] = '}' then Some k else close (k + 1)
          else None
        in
        match close (!i + 2) with
        | None ->
            (* an unterminated `{{` is ordinary prose *)
            Buffer.add_char buf s.[!i];
            incr i
        | Some k ->
            let literal = String.sub s !i (k + 2 - !i) in
            let name = String.trim (String.sub s (!i + 2) (k - !i - 2)) in
            (if valid_name name then Buffer.add_string buf (expand_name path level name)
             else (
               (* MALFORMED is not UNDEFINED: the author's bytes survive *)
               anomalies :=
                 Printf.sprintf "malformed substitution use, preserved verbatim: %s" literal
                 :: !anomalies;
               Buffer.add_string buf literal));
            i := k + 2)
      else (
        Buffer.add_char buf s.[!i];
        incr i)
    done;
    Buffer.contents buf
  and expand_name path level name =
    if List.mem name path then (
      cycles :=
        Printf.sprintf "substitution cycle broken: %s -> %s (already on the path)"
          (String.concat " -> " (List.rev path))
          name
        :: !cycles;
      Printf.sprintf "**[substitution cycle: %s]**" name)
    else
      match List.assoc_opt name defs with
      | None ->
          (* LOUD, and never the marker the author wrote: a reader must
             not have to guess whether it expanded to itself *)
          missing := Printf.sprintf "substitution undefined: {{%s}}" name :: !missing;
          Printf.sprintf "**[undefined substitution: %s]**" name
      | Some value ->
          if level >= depth then (
            truncated :=
              Printf.sprintf "substitution depth %d reached at %s (bound REPORTED, not silent)"
                depth name
              :: !truncated;
            Printf.sprintf "**[substitution depth %d reached: %s]**" depth name)
          else (
            used := name :: !used;
            expand_text (name :: path) (level + 1) value)
  in
  let out =
    List.filter_map
      (fun (line, code) ->
        if code then Some line
        else
          match classify_subst line with
          (* a definition produces no output — it is a definition *)
          | Def _ -> None
          | Def_bad reason ->
              anomalies :=
                Printf.sprintf "malformed substitution definition (%s), preserved verbatim: %s"
                  reason (String.trim line)
                :: !anomalies;
              Some line
          | Body -> Some (expand_text [] 0 line))
      ls
  in
  { text = String.concat "\n" out;
    used = sortu !used;
    conflicts = sortu !conflicts;
    missing = sortu !missing;
    cycles = sortu !cycles;
    truncated = sortu !truncated;
    anomalies = sortu !anomalies }

(* ------------------------------------------- HW.3.10.2 whole-document include *)

let splice ?(depth = default_depth) ~read ~self body =
  let used = ref []
  and missing = ref []
  and cycles = ref []
  and truncated = ref []
  and anomalies = ref [] in
  let rec expand path level text =
    walk_lines text
    |> List.map (fun (line, code) ->
           if code then line
           else
             match directive_of_line "include:" line with
             | Absent -> line
             | Misplaced ->
                 anomalies :=
                   Printf.sprintf
                     "misplaced include directive (it owns its line), preserved verbatim: %s"
                     (String.trim line)
                   :: !anomalies;
                 line
             | Malformed ->
                 anomalies :=
                   Printf.sprintf "malformed include directive (no path), preserved verbatim: %s"
                     (String.trim line)
                   :: !anomalies;
                 line
             | Payload p -> splice_one path level p)
    |> String.concat "\n"
  and splice_one path level p =
    (* the PATH, not a visited set: two siblings including one preamble
       is legitimate and splices twice; only a path member is a cycle *)
    if List.mem p path then (
      cycles :=
        Printf.sprintf "include cycle broken: %s -> %s (already on the path)"
          (String.concat " -> " (List.rev path))
          p
        :: !cycles;
      Printf.sprintf "**[include cycle: %s]**" p)
    else if level >= depth then (
      truncated :=
        Printf.sprintf "include depth %d reached at %s (bound REPORTED, not silent)" depth p
        :: !truncated;
      Printf.sprintf "**[include depth %d reached: %s]**" depth p)
    else
      match read p with
      | None ->
          missing := Printf.sprintf "include unresolved: %s in %s" p self :: !missing;
          Printf.sprintf "**[include unresolved: %s]**" p
      (* THE INCLUDE DENOTES THE FILE: the file's bytes, un-annotated *)
      | Some b ->
          used := p :: !used;
          expand (p :: path) (level + 1) b
  in
  let text = expand [ self ] 0 body in
  { text;
    used = sortu !used;
    conflicts = [];
    missing = sortu !missing;
    cycles = sortu !cycles;
    truncated = sortu !truncated;
    anomalies = sortu !anomalies }

(* ------------------------------------------------- HW.3.2.3 custom ids *)

type heading = {
  hlevel : int;
  htext : string;
  hanchor : string;
  hcustom : bool;
}

(* Hermes_wiki.make_slugger, quirk for quirk — the agreement law depends
   on it: stateful per document (so anchors stay LOCAL to a page), first
   occurrence keeps the base, later ones take `-1`, `-2`, … *)
let derive seen text =
  let base =
    let s = Hermes_wiki.slugify text in
    if s = "" then "section" else s
  in
  match Hashtbl.find_opt seen base with
  | None ->
      Hashtbl.replace seen base 0;
      base
  | Some n ->
      let rec next k =
        let candidate = Printf.sprintf "%s-%d" base k in
        if Hashtbl.mem seen candidate then next (k + 1)
        else (
          Hashtbl.replace seen base k;
          Hashtbl.replace seen candidate 0;
          candidate)
      in
      next (n + 1)

let rindex_sub hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = if i < 0 then None else if String.sub hay i nn = needle then Some i else go (i - 1) in
  if nn = 0 || nn > nh then None else go (nh - nn)

let valid_id s =
  s <> ""
  && not
       (String.exists
          (fun c -> c = ' ' || c = '\t' || c = '{' || c = '}' || c = '#' || c = '`')
          s)

let scan_headings body =
  let seen : (string, int) Hashtbl.t = Hashtbl.create 32 in
  let collisions = ref [] and anomalies = ref [] in
  let heads =
    List.filter_map
      (fun (line, code) ->
        if code then None
        else
          let t = String.trim line in
          if String.starts_with ~prefix:"#" t && String.contains t ' ' then (
            let level = ref 0 in
            while !level < String.length t && t.[!level] = '#' do
              incr level
            done;
            (* the engine clamps BEFORE it cuts the text; mirrored so a
               five-hash heading reads identically in both *)
            let level = min !level 4 in
            let text = String.trim (String.sub t level (String.length t - level)) in
            let declared =
              if String.length text >= 3 && text.[String.length text - 1] = '}' then
                match rindex_sub text "{#" with
                | Some i ->
                    let id = String.sub text (i + 2) (String.length text - i - 3) in
                    Some (i, String.trim (String.sub text 0 i), id)
                | None -> None
              else None
            in
            let htext, hanchor, hcustom =
              match declared with
              | Some (i, before, id) when valid_id id ->
                  (* a SECOND marker earlier in the heading is a fault of
                     its own: named, and the last one still governs *)
                  if rindex_sub (String.sub text 0 i) "{#" <> None then
                    anomalies :=
                      Printf.sprintf
                        "misplaced id marker (an id marker is the last token of its heading), \
                         preserved verbatim: %s"
                        text
                      :: !anomalies;
                  if Hashtbl.mem seen id then
                    collisions :=
                      Printf.sprintf
                        "custom id claimed twice: %s (both headings keep it, REPORTED not \
                         resolved): %s"
                        id text
                      :: !collisions
                  else Hashtbl.replace seen id 0;
                  (* THE OVERRIDE: the declared id, whatever the text says *)
                  (before, id, true)
              | Some (_, _, _) ->
                  anomalies :=
                    Printf.sprintf "malformed id marker, preserved verbatim: %s" text :: !anomalies;
                  (text, derive seen text, false)
              | None ->
                  if rindex_sub text "{#" <> None then
                    anomalies :=
                      Printf.sprintf
                        "misplaced id marker (an id marker is the last token of its heading), \
                         preserved verbatim: %s"
                        text
                      :: !anomalies;
                  (text, derive seen text, false)
            in
            Some { hlevel = level; htext; hanchor; hcustom })
          else None)
      (walk_lines body)
  in
  (heads, sortu !collisions, sortu !anomalies)

let headings_of body =
  let heads, _, _ = scan_headings body in
  heads

let anchors_of body = List.map (fun h -> h.hanchor) (headings_of body)

let id_collisions body =
  let _, c, _ = scan_headings body in
  c

let id_anomalies body =
  let _, _, a = scan_headings body in
  a
