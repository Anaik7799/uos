(* HW.9.2.1 — literalinclude: the denotation IS the file. See the mli for
   the grammar and the stated marker limit. PURE: the reader is injected,
   so every law here is a unit test rather than a filesystem fixture. *)

type t = {
  path : string;
  lines : (int * int) option;
  start_after : string option;
  end_before : string option;
  dedent : bool;
  lang : string option;
  emphasize : int list;
  bad : string list;
}

let tokens info =
  String.split_on_char ' ' info
  |> List.concat_map (String.split_on_char '\t')
  |> List.filter (fun s -> s <> "")

let strip_key key tok =
  let k = key ^ "=" in
  let nk = String.length k and nt = String.length tok in
  if nt > nk && String.sub tok 0 nk = k then Some (String.sub tok nk (nt - nk)) else None

(* A positive int, or None — malformed author input is IGNORED, never raised. *)
let int_opt s = match int_of_string_opt (String.trim s) with Some n when n > 0 -> Some n | _ -> None

let lines_of_value v =
  match String.index_opt v '-' with
  | Some i -> (
      match
        (int_opt (String.sub v 0 i), int_opt (String.sub v (i + 1) (String.length v - i - 1)))
      with
      | Some a, Some b when a <= b -> Some (a, b)
      | _ -> None)
  | None -> ( match int_opt v with Some a -> Some (a, a) | None -> None)

let emphasize_of_value v =
  String.split_on_char ',' v |> List.filter_map int_opt |> List.sort_uniq compare

let emphasize_of_info info =
  List.fold_left
    (fun acc tok ->
      match strip_key "emphasize" tok with Some v -> emphasize_of_value v | None -> acc)
    [] (tokens info)

let attempted info = match tokens info with "literalinclude" :: _ -> true | _ -> false

let parse info =
  match tokens info with
  | "literalinclude" :: path :: rest ->
      let d =
        { path; lines = None; start_after = None; end_before = None; dedent = false;
          lang = None; emphasize = []; bad = [] }
      in
      Some
        (List.fold_left
           (fun d tok ->
             match strip_key "lines" tok with
             | Some v -> (
                 (* a selector that does not parse is RECORDED, never
                    ignored: ignoring it meant "no window", which is the
                    whole file — a typo silently inlining everything *)
                 match lines_of_value v with
                 | Some w -> { d with lines = Some w }
                 | None -> { d with bad = ("lines=" ^ v) :: d.bad })
             | None -> (
                 match strip_key "start-after" tok with
                 | Some v -> { d with start_after = Some v }
                 | None -> (
                     match strip_key "end-before" tok with
                     | Some v -> { d with end_before = Some v }
                     | None -> (
                         match strip_key "lang" tok with
                         | Some v -> { d with lang = Some v }
                         | None -> (
                             match strip_key "emphasize" tok with
                             | Some v -> { d with emphasize = emphasize_of_value v }
                             | None -> if tok = "dedent" then { d with dedent = true } else d)))))
           d rest)
  | _ -> None

(* The language of an include: explicit dominates, else the extension.
   An unknown extension is None — exactly the info-less rendering, never
   a class nobody highlights. *)
let lang_of d =
  match d.lang with
  | Some l -> Some l
  | None -> (
      match String.lowercase_ascii (Filename.extension d.path) with
      | ".ml" | ".mli" -> Some "ocaml"
      | ".md" -> Some "markdown"
      | ".json" -> Some "json"
      | ".sh" -> Some "bash"
      | ".txt" -> Some "text"
      | ".html" -> Some "html"
      | ".css" -> Some "css"
      | ".js" -> Some "javascript"
      | ".py" -> Some "python"
      | _ -> None)

let dedent_lines ls =
  let indent_of l =
    let n = String.length l in
    let rec go i = if i < n && l.[i] = ' ' then go (i + 1) else i in
    go 0
  in
  let common =
    List.fold_left
      (fun acc l -> if String.trim l = "" then acc else min acc (indent_of l))
      max_int ls
  in
  if common = max_int || common = 0 then ls
  else
    List.map
      (fun l -> if String.length l <= common then String.trim l else String.sub l common (String.length l - common))
      ls

let contains hay needle =
  let nh = String.length hay and nn = String.length needle in
  let rec go i = i + nn <= nh && (String.sub hay i nn = needle || go (i + 1)) in
  nn > 0 && go 0

(* Marker application: the FIRST line containing the marker delimits, and
   the marker line itself is excluded. An unmatched marker is an Error —
   the whole point of the feature is that a silent empty block cannot
   happen. *)
let apply_start marker ls =
  let rec go = function
    | [] -> Error (Printf.sprintf "start-after marker never matched: %s" marker)
    | l :: rest -> if contains l marker then Ok rest else go rest
  in
  go ls

let apply_end marker ls =
  let rec go acc = function
    | [] -> Error (Printf.sprintf "end-before marker never matched: %s" marker)
    | l :: rest -> if contains l marker then Ok (List.rev acc) else go (l :: acc) rest
  in
  go [] ls

let ( let* ) r f = match r with Ok v -> f v | Error e -> Error e

let slice ~read d =
  match d.bad with
  | _ :: _ -> Error (Printf.sprintf "unparsable selector(s): %s" (String.concat ", " (List.rev d.bad)))
  | [] -> (
  match read d.path with
  | None -> Error (Printf.sprintf "cannot read %s" d.path)
  | Some content ->
      let all = String.split_on_char '\n' content in
      (* a trailing newline is a terminator, not an empty final line *)
      let all =
        match List.rev all with "" :: rest -> List.rev rest | _ -> all
      in
      let total = List.length all in
      let* windowed =
        match d.lines with
        | None -> Ok all
        | Some (a, b) ->
            if a > total || b > total then
              Error
                (Printf.sprintf "lines %d-%d out of range (%s has %d lines)" a b d.path total)
            else Ok (List.filteri (fun i _ -> i + 1 >= a && i + 1 <= b) all)
      in
      let* after =
        match d.start_after with None -> Ok windowed | Some m -> apply_start m windowed
      in
      let* before = match d.end_before with None -> Ok after | Some m -> apply_end m after in
      (* An EMPTY slice is an Error, not a success. Markers on adjacent
         lines, a marker on the first or last line, or an empty file all
         yield [] — and [] renders as <pre><code></code></pre>, the
         silent blank block this whole feature exists to prevent. The
         unmatched-marker Error was never the only route to it. *)
      if before = [] then
        Error
          (Printf.sprintf "slice is empty: %s selects no lines (markers adjacent, or file empty)"
             d.path)
      else Ok (if d.dedent then dedent_lines before else before))
