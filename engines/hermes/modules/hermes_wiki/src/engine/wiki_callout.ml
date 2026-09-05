(* HW.2.3.1 — callouts. See the mli: closed vocabulary, unknown types
   preserved, arbitrary block content, one emitter for both renderers. *)

type kind =
  | Note | Abstract | Info | Todo | Tip | Success | Question
  | Warning | Failure | Danger | Bug | Example | Quote
  | Unknown of string

type fold = Plain | Expanded | Collapsed
type header = { kind : kind; title : string; fold : fold }

(* The thirteen types and their aliases, exactly as section 8.2 records
   them. Written as data rather than a match so the vocabulary can be
   read at a glance and counted by a test. *)
let vocabulary =
  [ (Note, [ "note" ]);
    (Abstract, [ "abstract"; "summary"; "tldr" ]);
    (Info, [ "info" ]);
    (Todo, [ "todo" ]);
    (Tip, [ "tip"; "hint"; "important" ]);
    (Success, [ "success"; "check"; "done" ]);
    (Question, [ "question"; "help"; "faq" ]);
    (Warning, [ "warning"; "caution"; "attention" ]);
    (Failure, [ "failure"; "fail"; "missing" ]);
    (Danger, [ "danger"; "error" ]);
    (Bug, [ "bug" ]);
    (Example, [ "example" ]);
    (Quote, [ "quote"; "cite" ]) ]

let kind_of_string s =
  let lower = String.lowercase_ascii (String.trim s) in
  match List.find_opt (fun (_, names) -> List.mem lower names) vocabulary with
  | Some (k, _) -> k
  | None -> Unknown (String.trim s)

let kind_name = function
  | Unknown s -> s
  | k -> ( match List.find_opt (fun (k', _) -> k' = k) vocabulary with
           | Some (_, n :: _) -> n
           | _ -> "note")

let parse_header line =
  let t = String.trim line in
  let n = String.length t in
  if n < 4 || t.[0] <> '[' || t.[1] <> '!' then None
  else
    match String.index_opt t ']' with
    | None -> None
    | Some close ->
        let raw = String.sub t 2 (close - 2) in
        if String.trim raw = "" then None
        else
          let rest = String.sub t (close + 1) (n - close - 1) in
          let fold, rest =
            if String.length rest > 0 && rest.[0] = '+' then
              (Expanded, String.sub rest 1 (String.length rest - 1))
            else if String.length rest > 0 && rest.[0] = '-' then
              (Collapsed, String.sub rest 1 (String.length rest - 1))
            else (Plain, rest)
          in
          Some { kind = kind_of_string raw; title = String.trim rest; fold }

let html ~escape ~inline h ~body =
  let name = kind_name h.kind in
  let cls = Printf.sprintf "callout callout-%s" (escape name) in
  (* the title defaults to the type, which is what a reader expects when
     the author wrote none *)
  let title_html =
    if h.title = "" then escape (String.capitalize_ascii name) else inline h.title
  in
  match h.fold with
  | Plain ->
      Printf.sprintf "<div class=\"%s\">\n<p class=\"callout-title\">%s</p>\n%s</div>\n" cls
        title_html body
  | Expanded | Collapsed ->
      let open_attr = if h.fold = Expanded then " open" else "" in
      Printf.sprintf
        "<details class=\"%s\"%s>\n<summary class=\"callout-title\">%s</summary>\n%s</details>\n"
        cls open_attr title_html body
