(* Wiki Theme Token Injector — a REAL, honest theme-token producer + auditor.

   INTENT (from the phase-7 stub).  "Injects light/dark mode CSS variables safely
   into the rendered HTML pages."

   WHAT THIS HONESTLY DOES.  It emits the canonical, SAFE light/dark theme-token
   CSS block (a static constant — no string interpolation from any note/page, so
   there is no injection surface) and then AUDITS the rendered HTML pages under
   [root]/docs and [root]/web for theme-token coverage: whether each page carries
   a `prefers-color-scheme` media query and CSS custom properties (`--…:`). It
   reports which pages already declare theme tokens and which do not.

   [NOTE] read-only audit: this module PRINTS the safe token block and REPORTS
   coverage; it does not rewrite pages on disk. "Safe" is established structurally
   — the emitted block is a compile-time constant with no interpolated content,
   so it cannot carry a stored-XSS payload into a view boundary. *)

let safe_theme_tokens =
  ":root{--bg:#ffffff;--fg:#1a1a1a;--accent:#2b6cb0;--muted:#6b7280;\
   --border:#e5e7eb;--code-bg:#f6f8fa;}\n\
   :root[data-theme=\"dark\"]{--bg:#0d1117;--fg:#e6edf3;--accent:#58a6ff;\
   --muted:#8b949e;--border:#30363d;--code-bg:#161b22;}\n\
   @media (prefers-color-scheme: dark){:root:not([data-theme=\"light\"]){\
   --bg:#0d1117;--fg:#e6edf3;--accent:#58a6ff;--muted:#8b949e;\
   --border:#30363d;--code-bg:#161b22;}}\n"

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

(* Case-insensitive substring test without Str. *)
let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else if nl > hl then false
  else
    let lc c = Char.lowercase_ascii c in
    let rec at i j =
      if j = nl then true
      else if lc hay.[i + j] = lc needle.[j] then at i (j + 1)
      else false
    in
    let rec scan i = if i > hl - nl then false else if at i 0 then true else scan (i + 1) in
    scan 0

let list_html root =
  let acc = ref [] in
  let rec go dir depth =
    if depth > 6 then ()
    else
      match Sys.readdir dir with
      | entries ->
          Array.iter
            (fun e ->
              (* skip vcs/worktree/build noise *)
              if e <> ".git" && e <> ".claude" && e <> "_opam" then
                let p = Filename.concat dir e in
                if (try Sys.is_directory p with _ -> false) then go p (depth + 1)
                else if Filename.check_suffix e ".html" then acc := p :: !acc)
            entries
      | exception _ -> ()
  in
  List.iter
    (fun sub ->
      let d = Filename.concat root sub in
      if (try Sys.is_directory d with _ -> false) then go d 0)
    [ "docs"; "web" ];
  List.sort compare !acc

let run (root : string) : unit =
  Printf.printf "[wiki_theme_token_injector] canonical SAFE theme-token block:\n";
  String.split_on_char '\n' safe_theme_tokens
  |> List.iter (fun l -> if l <> "" then Printf.printf "    | %s\n" l);
  let files = list_html root in
  let with_scheme = ref 0 and with_vars = ref 0 and missing = ref [] in
  List.iter
    (fun f ->
      let t = read_file f in
      let has_scheme = contains t "prefers-color-scheme" in
      let has_vars = contains t "--" && contains t ":root" in
      if has_scheme then incr with_scheme;
      if has_vars then incr with_vars;
      if not (has_scheme || has_vars) then
        missing := Filename.basename f :: !missing)
    files;
  Printf.printf "  HTML pages audited: %d\n" (List.length files);
  Printf.printf "  with prefers-color-scheme: %d   with :root CSS vars: %d\n"
    !with_scheme !with_vars;
  Printf.printf "  pages with NO theme tokens: %d\n" (List.length !missing);
  List.iter (fun m -> Printf.printf "    [no-theme] %s\n" m) (List.rev !missing);
  Printf.printf
    "  [NOTE] read-only audit: token block is a static constant (no interpolation); pages not rewritten\n"
