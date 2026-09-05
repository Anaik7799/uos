(* ZK Query Live Executor — a REAL query engine that renders embedded fences.

   Promoted from a phase-7 printf stub. In the wiki export, a ```zkquery fence is
   replaced by a rendered markdown table of the notes it selects. This module:
     1. builds a REAL note index from docs/zk/**/*.md — slug, title (first ATX
        heading), status (frontmatter), and tag set (#tag tokens);
     2. implements a small total query DSL over that index:
          tag:X   status:X   link:X   title:X    (AND of space-separated clauses)
     3. finds every ```zkquery fence in the corpus, evaluates its query, and emits
        the actual rendered markdown table (real bytes) that would replace it.

   If the corpus embeds no fences, it demonstrates the engine on real standing
   queries over the real index and prints the rendered tables it produces — never
   a fake "rendered ok".

   [N/A] the live corpus embeds ZERO ```zkquery fences today; the engine is
   exercised on real demonstration queries against the real index. *)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let zk_files root =
  let dir = Filename.concat root "docs/zk" in
  let rec walk d acc =
    let entries = try Sys.readdir d with _ -> [||] in
    Array.fold_left (fun acc name ->
      let p = Filename.concat d name in
      if (try Sys.is_directory p with _ -> false) then walk p acc
      else if Filename.check_suffix name ".md" then p :: acc
      else acc) acc entries
  in List.sort compare (walk dir [])

let find_from s sub i =
  let ls = String.length s and lsub = String.length sub in
  let rec go i =
    if i + lsub > ls then None
    else if String.sub s i lsub = sub then Some i
    else go (i + 1)
  in if lsub = 0 then None else go i

type note = {
  slug : string;
  title : string;
  status : string;
  tags : string list;
  links : string list;
}

let frontmatter_status lines =
  let rec skip_open = function
    | l :: tl when String.trim l = "" -> skip_open tl
    | l :: tl when String.trim l = "---" -> Some tl
    | _ -> None in
  match skip_open lines with
  | None -> "(none)"
  | Some rest ->
    let rec find = function
      | l :: _ when String.trim l = "---" -> "(none)"
      | l :: tl ->
        let t = String.trim l in
        if String.length t >= 7 && String.sub t 0 7 = "status:" then
          String.trim (String.sub t 7 (String.length t - 7))
        else find tl
      | [] -> "(none)"
    in find rest

let first_title lines =
  let rec go = function
    | l :: tl ->
      let t = String.trim l in
      if String.length t >= 2 && t.[0] = '#' then begin
        let k = ref 0 in while !k < String.length t && t.[!k] = '#' do incr k done;
        String.trim (String.sub t !k (String.length t - !k))
      end else go tl
    | [] -> "(untitled)"
  in go lines

let tags_of body =
  let out = ref [] and ls = String.length body in
  let is_tc c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' || c = '_' in
  let i = ref 0 in
  while !i < ls do
    if body.[!i] = '#'
       && (!i = 0 || body.[!i-1] = ' ' || body.[!i-1] = '`' || body.[!i-1] = '\n')
       && !i + 1 < ls && is_tc body.[!i+1] then begin
      let j = ref (!i + 1) in
      while !j < ls && is_tc body.[!j] do incr j done;
      out := String.sub body (!i + 1) (!j - !i - 1) :: !out; i := !j
    end else incr i
  done;
  List.sort_uniq compare !out

let links_of body =
  let rec go i acc =
    match find_from body "[[" i with
    | None -> List.rev acc
    | Some a ->
      (match find_from body "]]" (a + 2) with
       | None -> List.rev acc
       | Some b ->
         let inner = String.sub body (a + 2) (b - (a + 2)) in
         let t = match String.index_opt inner '|' with
           | Some p -> String.sub inner 0 p | None -> inner in
         go (b + 2) (String.trim t :: acc))
  in List.sort_uniq compare (go 0 [])

let index root =
  List.map (fun path ->
    let body = try read_file path with _ -> "" in
    let lines = String.split_on_char '\n' body in
    { slug = Filename.remove_extension (Filename.basename path);
      title = first_title lines;
      status = frontmatter_status lines;
      tags = tags_of body;
      links = links_of body })
    (zk_files root)

let lower s = String.lowercase_ascii s

(* clause "k:v"; AND over space-separated clauses *)
let matches note clause =
  match String.index_opt clause ':' with
  | None -> lower note.title |> fun t ->
            find_from t (lower clause) 0 <> None
  | Some p ->
    let k = String.sub clause 0 p and v = lower (String.sub clause (p + 1) (String.length clause - p - 1)) in
    (match k with
     | "tag" -> List.exists (fun t -> lower t = v) note.tags
     | "status" -> lower note.status = v
     | "link" -> List.exists (fun l -> lower l = v) note.links
     | "title" -> find_from (lower note.title) v 0 <> None
     | _ -> false)

let query idx q =
  let clauses = List.filter (fun s -> s <> "")
      (String.split_on_char ' ' (String.trim q)) in
  List.filter (fun n -> List.for_all (matches n) clauses) idx

let render_table q rows =
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "  query `%s` -> %d rows\n" q (List.length rows));
  Buffer.add_string b "  | slug | status | title |\n  |---|---|---|\n";
  List.iteri (fun i n ->
    if i < 8 then
      Buffer.add_string b (Printf.sprintf "  | %s | %s | %s |\n" n.slug n.status n.title))
    rows;
  if List.length rows > 8 then Buffer.add_string b "  | ... | | |\n";
  Buffer.contents b

let fences body =
  let rec go i acc =
    match find_from body "```zkquery" i with
    | None -> List.rev acc
    | Some a ->
      (match find_from body "```" (a + 10) with
       | None -> List.rev acc
       | Some b ->
         let inner = String.trim (String.sub body (a + 10) (b - (a + 10))) in
         go (b + 3) (inner :: acc))
  in go 0 []

let run (root : string) : unit =
  let idx = index root in
  Printf.printf "[zk_query_live_executor] indexed %d notes\n" (List.length idx);
  let embedded = List.concat_map (fun path ->
    fences (try read_file path with _ -> "")) (zk_files root) in
  Printf.printf "  embedded ```zkquery fences found: %d\n" (List.length embedded);
  let to_run =
    if embedded <> [] then embedded
    else ["status:published"; "tag:zettelkasten"; "tag:formal"] in
  List.iter (fun q ->
    let rows = query idx q in
    print_string (render_table q rows)) to_run;
  if embedded = [] then
    Printf.printf "  [N/A] no embedded fences in the live corpus; engine run on real demo queries\n"
