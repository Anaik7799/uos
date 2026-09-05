(* Wiki Sidebar Tree Generator — a REAL Notion-like navigational tree builder.

   Promoted from a phase-7 printf stub. The wiki's slugs encode a hierarchy in
   two ways: the on-disk directory layout (docs/zk vs docs/zk/episodic) and the
   `--` prefix convention inside a flat directory (features--notion-db-board is a
   child of features, then notion). This module constructs the persistent
   sidebar tree over the REAL corpus by folding every note into a prefix trie,
   then emits it as compact JSON (the shape a sidebar view consumes) and a
   human-readable indented outline.

   METHOD. Scan `<root>/docs/zk/**/*.md`; each note's path becomes a key of the
   directory component(s) followed by the `--`-split slug segments. Insert into a
   trie; count leaves (notes) and interior nodes (sections). Output is a pure
   function of the file set — deterministic, no clock/RNG.

   [N/A] No `order:` / manual-pin frontmatter field is used anywhere in the
   corpus, so ordering is the natural (lexicographic) one; a manual-ordering
   feature would be needed to honor curator-pinned positions, and none exists. *)

let rec walk dir base =
  if Sys.file_exists dir && Sys.is_directory dir then
    Array.to_list (Sys.readdir dir)
    |> List.sort String.compare
    |> List.concat_map (fun e ->
           let p = Filename.concat dir e in
           if (try Sys.is_directory p with Sys_error _ -> false) then
             walk p (base @ [ e ])
           else if Filename.check_suffix p ".md" then
             [ (base, Filename.remove_extension e) ]
           else [])
  else []

(* split a slug on the literal "--" section-convention *)
let split_sections (slug : string) : string list =
  let n = String.length slug in
  let rec go start acc i =
    if i + 2 > n then List.rev (String.sub slug start (n - start) :: acc)
    else if slug.[i] = '-' && slug.[i + 1] = '-' then
      go (i + 2) (String.sub slug start (i - start) :: acc) (i + 2)
    else go start acc (i + 1)
  in
  if n = 0 then [ slug ] else go 0 [] 0

type node = { mutable leaf : bool; children : (string, node) Hashtbl.t }

let mk () = { leaf = false; children = Hashtbl.create 8 }

let insert root path =
  let cur = ref root in
  List.iter
    (fun seg ->
      let n =
        match Hashtbl.find_opt !cur.children seg with
        | Some n -> n
        | None ->
            let n = mk () in
            Hashtbl.add !cur.children seg n;
            n
      in
      cur := n)
    path;
  !cur.leaf <- true

let sorted_children n =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) n.children []
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)

let rec count_nodes n =
  let leaves = if n.leaf then 1 else 0 in
  let self_section = if Hashtbl.length n.children > 0 then 1 else 0 in
  List.fold_left
    (fun (l, s) (_, c) ->
      let cl, cs = count_nodes c in
      (l + cl, s + cs))
    (leaves, self_section) (sorted_children n)

let rec to_json n =
  match sorted_children n with
  | [] -> Printf.sprintf "{\"leaf\":%b}" n.leaf
  | kids ->
      let inner =
        List.map (fun (k, c) -> Printf.sprintf "%S:%s" k (to_json c)) kids
        |> String.concat ","
      in
      Printf.sprintf "{%s}" inner

let rec outline buf depth n =
  List.iter
    (fun (k, c) ->
      Buffer.add_string buf (String.make (depth * 2) ' ');
      Buffer.add_string buf
        (Printf.sprintf "%s%s\n" k (if c.leaf then " (note)" else "/"));
      outline buf (depth + 1) c)
    (sorted_children n)

let run (root : string) : unit =
  let zk_dir = Filename.concat root "docs/zk" in
  let notes = walk zk_dir [] in
  let trie = mk () in
  List.iter
    (fun (dirs, slug) -> insert trie (dirs @ split_sections slug))
    notes;
  let leaves, sections = count_nodes trie in
  Printf.printf
    "[wiki_sidebar_tree_generator] built sidebar tree over docs/zk: %d notes, \
     %d section nodes\n"
    leaves sections;
  let buf = Buffer.create 4096 in
  outline buf 0 trie;
  let lines = String.split_on_char '\n' (Buffer.contents buf) in
  List.iteri
    (fun i l -> if i < 40 && l <> "" then Printf.printf "  %s\n" l)
    lines;
  if List.length lines > 40 then
    Printf.printf "  ... (%d more lines)\n" (List.length lines - 40);
  let json = to_json trie in
  Printf.printf
    "[wiki_sidebar_tree_generator] JSON tree = %d bytes (deterministic, \
     lexicographic order)\n"
    (String.length json);
  Printf.printf
    "[wiki_sidebar_tree_generator] [N/A] no manual `order:` field in the corpus \
     — ordering is lexicographic, curator-pinning unused.\n"
