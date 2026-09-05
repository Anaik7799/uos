(* HW.9.1.3 / HW.9.4.1 / HW.9.2.2 / HW.9.2.3 — binding documentation to
   source. See the mli for the laws; this file only has to enforce them.

   PURE: no IO, no clock. Every reader is injected. *)

(* ------------------------------------------------------------ escaping *)

let escape_html s =
  let b = Buffer.create (String.length s + 16) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | '\'' -> Buffer.add_string b "&#39;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

(* ------------------------------------ HW.9.1.3 — API summary tables *)

type api_row = { name : string; signature : string; summary : string; documented : bool }

(* The first sentence of a doc comment. `Wiki_iface` has already
   whitespace-normalised it, so a sentence ends at ". " or at the end. *)
let first_sentence doc =
  let n = String.length doc in
  let rec go i =
    if i + 1 >= n then String.trim doc
    else if doc.[i] = '.' && doc.[i + 1] = ' ' then String.trim (String.sub doc 0 (i + 1))
    else go (i + 1)
  in
  if n = 0 then "" else go 0

(* ONE ROW PER ITEM. The map is total and length-preserving, which is
   what makes "complete over the public interface" a fact about the code
   rather than a hope: there is no filter here to go wrong. *)
let api_rows text =
  List.map
    (fun (it : Wiki_iface.item) ->
      { name = it.Wiki_iface.name;
        signature = it.Wiki_iface.signature;
        summary = first_sentence it.Wiki_iface.doc;
        documented = Wiki_iface.documented it })
    (Wiki_iface.items text)

let api_table_html text =
  match api_rows text with
  | [] ->
      (* NAMED NOTICE, never an empty table: an empty <table> cannot be
         told apart from a renderer that failed. *)
      "<p class=\"api-empty\">no values declared: this interface exposes no \
       <code>val</code>, so there is no API table to render</p>"
  | rows ->
      let b = Buffer.create 512 in
      Buffer.add_string b "<table class=\"api-summary\">\n";
      Buffer.add_string b
        "<thead><tr><th>name</th><th>signature</th><th>summary</th></tr></thead>\n<tbody>\n";
      List.iter
        (fun r ->
          Buffer.add_string b "<tr class=\"";
          Buffer.add_string b (if r.documented then "api-documented" else "api-undocumented");
          Buffer.add_string b "\"><td><code>";
          Buffer.add_string b (escape_html r.name);
          Buffer.add_string b "</code></td><td><code>";
          Buffer.add_string b (escape_html r.signature);
          Buffer.add_string b "</code></td><td>";
          (* an EXPLICIT marker, never a blank cell *)
          Buffer.add_string b
            (if r.documented then escape_html r.summary
             else "<span class=\"api-undocumented-mark\">undocumented</span>");
          Buffer.add_string b "</td></tr>\n")
        rows;
      Buffer.add_string b "</tbody>\n</table>\n";
      Buffer.contents b

(* ---------------------------- HW.9.4.1 — documentation coverage census *)

type status = Measured | No_values of string | Unreadable of string

type entry = {
  path : string;
  status : status;
  documented : int;
  total : int;
  percent : float;
}

type census = {
  entries : entry list;
  declared : int;
  measured : int;
  no_values : int;
  unreadable : int;
  items_documented : int;
  items_total : int;
}

let pct ~num ~den = if den <= 0 then 0.0 else 100.0 *. float_of_int num /. float_of_int den

let entry_of ~read path =
  match read path with
  | None ->
      (* DISCLOSED and counted at 0%. Never dropped: dropping it is the
         one move that makes a coverage number rise for free. *)
      { path;
        status = Unreadable (path ^ ": source could not be read (the injected reader \
                                    returned nothing); counted at 0%");
        documented = 0; total = 0; percent = 0.0 }
  | Some text -> (
      match Wiki_iface.coverage text with
      | None ->
          { path;
            status = No_values (path ^ ": declares no recoverable value; 0/0 is not 100%, \
                                       so it is counted at 0%");
            documented = 0; total = 0; percent = 0.0 }
      | Some (d, t) -> { path; status = Measured; documented = d; total = t; percent = pct ~num:d ~den:t })

let census ~read paths =
  (* duplicates collapse (a path declared twice is one source, not two
     votes) and the order is the sorted order, never the caller's *)
  let declared_paths = List.sort_uniq compare paths in
  let entries = List.map (entry_of ~read) declared_paths in
  let count f = List.length (List.filter f entries) in
  { entries;
    declared = List.length entries;
    measured = count (fun e -> match e.status with Measured -> true | _ -> false);
    no_values = count (fun e -> match e.status with No_values _ -> true | _ -> false);
    unreadable = count (fun e -> match e.status with Unreadable _ -> true | _ -> false);
    items_documented =
      List.fold_left (fun a e -> match e.status with Measured -> a + e.documented | _ -> a) 0 entries;
    items_total =
      List.fold_left (fun a e -> match e.status with Measured -> a + e.total | _ -> a) 0 entries }

(* The mean over the DECLARED set. None on an empty census: no census is
   not 0%, and 0.0 is a number a dashboard would plot. *)
let module_percent c =
  match c.entries with
  | [] -> None
  | es -> Some (List.fold_left (fun a e -> a +. e.percent) 0.0 es /. float_of_int (List.length es))

let undetermined c =
  List.filter_map (fun e -> match e.status with Unreadable r -> Some r | Measured | No_values _ -> None) c.entries
  |> List.sort compare

let item_percent c =
  if undetermined c <> [] then None
  else if c.items_total <= 0 then None
  else Some (pct ~num:c.items_documented ~den:c.items_total)

let summary_line c =
  Printf.sprintf
    "census: %d declared, %d measured, %d without values, %d UNREADABLE (all %d in the denominator)"
    c.declared c.measured c.no_values c.unreadable c.declared

let disclosure c =
  List.map
    (fun e ->
      match e.status with
      | Measured -> Printf.sprintf "%s: %d/%d documented" e.path e.documented e.total
      | No_values r -> r
      | Unreadable r -> r)
    c.entries

let census_html c =
  let b = Buffer.create 512 in
  Buffer.add_string b "<div class=\"doc-census\">\n<p class=\"doc-census-summary\">";
  Buffer.add_string b (escape_html (summary_line c));
  Buffer.add_string b "</p>\n";
  Buffer.add_string b "<p class=\"doc-census-figure\">";
  Buffer.add_string b
    (match module_percent c with
    | None -> "module coverage: UNDETERMINED (nothing declared)"
    | Some p -> escape_html (Printf.sprintf "module coverage: %.1f%%" p));
  Buffer.add_string b " &middot; ";
  Buffer.add_string b
    (match item_percent c with
    | None -> "item coverage: UNDETERMINED (see the unreadable sources below)"
    | Some p -> escape_html (Printf.sprintf "item coverage: %.1f%%" p));
  Buffer.add_string b "</p>\n<ul class=\"doc-census-lines\">\n";
  List.iter
    (fun line ->
      Buffer.add_string b "<li>";
      Buffer.add_string b (escape_html line);
      Buffer.add_string b "</li>\n")
    (disclosure c);
  Buffer.add_string b "</ul>\n</div>\n";
  Buffer.contents b

(* ----------------------------- HW.9.2.2 — `literalinclude` with `:diff:` *)

type edit = Keep of string | Del of string | Add of string

let max_lcs_cells = 1_000_000

let diff_lines ~before ~after =
  let a = Array.of_list before and b = Array.of_list after in
  let n = Array.length a and m = Array.length b in
  if n = 0 && m = 0 then []
  else if n * m > max_lcs_cells then
    (* the bound degrades QUALITY, never correctness: this still
       round-trips exactly *)
    List.map (fun l -> Del l) before @ List.map (fun l -> Add l) after
  else begin
    let lcs = Array.make_matrix (n + 1) (m + 1) 0 in
    for i = n - 1 downto 0 do
      for j = m - 1 downto 0 do
        lcs.(i).(j) <-
          (if a.(i) = b.(j) then lcs.(i + 1).(j + 1) + 1 else max lcs.(i + 1).(j) lcs.(i).(j + 1))
      done
    done;
    let out = ref [] in
    let i = ref 0 and j = ref 0 in
    while !i < n || !j < m do
      if !i < n && !j < m && a.(!i) = b.(!j) then begin
        out := Keep a.(!i) :: !out;
        incr i;
        incr j
      end
      else if !j < m && (!i = n || lcs.(!i).(!j + 1) >= lcs.(!i + 1).(!j)) then begin
        out := Add b.(!j) :: !out;
        incr j
      end
      else begin
        out := Del a.(!i) :: !out;
        incr i
      end
    done;
    List.rev !out
  end

(* The round trip, and the derivability check in the same function: a
   Keep or a Del that does not match the before slice REFUSES. *)
let patch ~before edits =
  let rec go src es acc =
    match (es, src) with
    | [], [] -> Ok (List.rev acc)
    | [], _ :: _ ->
        Error "diff does not derive from this slice: the before slice has lines the script never consumed"
    | Add l :: rest, _ -> go src rest (l :: acc)
    | Keep l :: rest, s :: more ->
        if s = l then go more rest (l :: acc)
        else
          Error
            (Printf.sprintf "diff does not derive from this slice: context %S, slice has %S" l s)
    | Del l :: rest, s :: more ->
        if s = l then go more rest acc
        else
          Error (Printf.sprintf "diff does not derive from this slice: deletes %S, slice has %S" l s)
    | (Keep l | Del l) :: _, [] ->
        Error (Printf.sprintf "diff does not derive from this slice: wants %S, slice ended" l)
  in
  go before edits []

let tokens info =
  String.split_on_char ' ' info
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun s -> s <> "")

let diff_selector info =
  let k = "diff=" in
  let nk = String.length k in
  List.fold_left
    (fun acc tok ->
      let nt = String.length tok in
      if nt > nk && String.sub tok 0 nk = k then Some (String.sub tok nk (nt - nk)) else acc)
    None (tokens info)

type diff_render = {
  edits : edit list;
  before : string list;
  after : string list;
  before_path : string;
  after_path : string;
}

let diff_of_info ~read info =
  if not (Wiki_include.attempted info) then None
  else
    match diff_selector info with
    | None -> None (* a plain literalinclude — HW.9.2.1's directive, untouched *)
    | Some other -> (
        match Wiki_include.parse info with
        | None ->
            Some (Error "literalinclude with diff= but no path: nothing to compare against")
        | Some d when d.Wiki_include.path = "diff=" ^ other ->
            (* `literalinclude diff=b.ml` has no source path of its own:
               the base directive took the SELECTOR as the path. Naming
               it beats slicing a file called "diff=b.ml". *)
            Some (Error "literalinclude with diff= but no path: nothing to compare against")
        | Some d -> (
            (* the SAME directive, the SAME selectors, one path swapped —
               so the two slices are comparable by construction *)
            let base = { d with Wiki_include.path = other } in
            match (Wiki_include.slice ~read base, Wiki_include.slice ~read d) with
            | Error e, _ -> Some (Error ("diff before side: " ^ e))
            | _, Error e -> Some (Error ("diff after side: " ^ e))
            | Ok before, Ok after ->
                let edits = diff_lines ~before ~after in
                let changed =
                  List.exists (function Keep _ -> false | Del _ | Add _ -> true) edits
                in
                if not changed then
                  Some
                    (Error
                       (Printf.sprintf
                          "diff is empty: %s and %s select identical lines, so there is no change to show"
                          other d.Wiki_include.path))
                else
                  Some
                    (Ok
                       { edits; before; after; before_path = other;
                         after_path = d.Wiki_include.path })))

let diff_html edits =
  let b = Buffer.create 512 in
  Buffer.add_string b "<pre class=\"literalinclude-diff\"><code>";
  List.iter
    (fun e ->
      let cls, sign, line =
        match e with
        | Keep l -> ("diff-keep", " ", l)
        | Del l -> ("diff-del", "-", l)
        | Add l -> ("diff-add", "+", l)
      in
      Buffer.add_string b "<span class=\"";
      Buffer.add_string b cls;
      Buffer.add_string b "\">";
      Buffer.add_string b sign;
      Buffer.add_string b (escape_html line);
      Buffer.add_string b "</span>\n")
    edits;
  Buffer.add_string b "</code></pre>\n";
  Buffer.contents b

(* --------------------------- HW.9.2.3 — source cross-links (viewcode) *)

type target = { file : string; line : int }
type xref = { name : string; target : target; href : string; label : string }
type xrefs = { links : xref list; gaps : string list }

let no_source _ = None

let line_count text =
  if text = "" then 0
  else
    let ls = String.split_on_char '\n' text in
    (* a trailing newline TERMINATES the last line, exactly as
       Wiki_include.slice reads it *)
    match List.rev ls with "" :: rest -> List.length rest | _ -> List.length ls

let resolves ~read t =
  match read t.file with
  | None -> false
  | Some text -> t.line >= 1 && t.line <= line_count text

let xref_of ~read ~name t =
  match read t.file with
  | None -> Error (Printf.sprintf "%s: cannot read %s, so no cross-link is emitted" name t.file)
  | Some text ->
      let n = line_count text in
      if t.line < 1 || t.line > n then
        (* NAMED, never clamped: a clamped line resolves and points at the
           wrong code, which is the failure a reader cannot detect *)
        Error
          (Printf.sprintf "%s: line %d is outside %s (%d lines), so no cross-link is emitted" name
             t.line t.file n)
      else
        Ok
          { name;
            target = t;
            href = escape_html (Printf.sprintf "%s#L%d" t.file t.line);
            label = Printf.sprintf "%s:%d" t.file t.line }

let is_ident_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c = '\''

(* TOKEN-BOUNDED: `let apply` must not match `let apply_start`. Without
   the boundary the emitted link resolves and points at the neighbour. *)
let defines line name =
  let t = String.trim line in
  let after_kw =
    let strip p s =
      let np = String.length p in
      if String.length s >= np && String.sub s 0 np = p then Some (String.sub s np (String.length s - np))
      else None
    in
    match strip "let rec " t with
    | Some r -> Some r
    | None -> ( match strip "let " t with Some r -> Some r | None -> None)
  in
  match after_kw with
  | None -> false
  | Some rest ->
      let nn = String.length name in
      String.length rest >= nn
      && String.sub rest 0 nn = name
      && (String.length rest = nn || not (is_ident_char rest.[nn]))

let definition_line text name =
  let rec go n = function
    | [] -> None
    | l :: rest -> if defines l name then Some n else go (n + 1) rest
  in
  go 1 (String.split_on_char '\n' text)

let cross_links ~read ~iface ~impl =
  match read iface with
  | None ->
      { links = [];
        gaps = [ Printf.sprintf "cannot read interface %s: no cross-link can be emitted" iface ] }
  | Some itext ->
      let items = Wiki_iface.items itext in
      let impl_text = match impl with None -> None | Some p -> read p in
      let step (links, gaps) (it : Wiki_iface.item) =
        let name = it.Wiki_iface.name in
        let target_r =
          match (impl, impl_text) with
          | None, _ -> Ok { file = iface; line = it.Wiki_iface.line }
          | Some p, None ->
              Error (Printf.sprintf "%s: cannot read implementation %s, so no cross-link is emitted" name p)
          | Some p, Some mtext -> (
              match definition_line mtext name with
              | None ->
                  Error
                    (Printf.sprintf "%s: no definition of %s in %s, so no cross-link is emitted" name
                       name p)
              | Some l -> Ok { file = p; line = l })
        in
        match target_r with
        | Error g -> (links, g :: gaps)
        | Ok t -> (
            (* every emitted link is an Ok of xref_of — resolution is not
               checked after the fact, it is the only way in *)
            match xref_of ~read ~name t with
            | Ok x -> (x :: links, gaps)
            | Error g -> (links, g :: gaps))
      in
      let links, gaps = List.fold_left step ([], []) items in
      { links = List.rev links; gaps = List.sort compare gaps }

let xref_html x =
  let b = Buffer.create 512 in
  Buffer.add_string b "<div class=\"viewcode\">\n<ul class=\"viewcode-links\">\n";
  List.iter
    (fun l ->
      Buffer.add_string b "<li><a class=\"viewcode-link\" href=\"";
      Buffer.add_string b l.href;
      Buffer.add_string b "\"><code>";
      Buffer.add_string b (escape_html l.name);
      Buffer.add_string b "</code> &rarr; ";
      Buffer.add_string b (escape_html l.label);
      Buffer.add_string b "</a></li>\n")
    x.links;
  Buffer.add_string b "</ul>\n";
  (match x.gaps with
  | [] -> ()
  | gs ->
      Buffer.add_string b "<ul class=\"viewcode-gaps\">\n";
      List.iter
        (fun g ->
          Buffer.add_string b "<li class=\"viewcode-gap\">";
          Buffer.add_string b (escape_html g);
          Buffer.add_string b "</li>\n")
        gs;
      Buffer.add_string b "</ul>\n");
  Buffer.add_string b "</div>\n";
  Buffer.contents b
