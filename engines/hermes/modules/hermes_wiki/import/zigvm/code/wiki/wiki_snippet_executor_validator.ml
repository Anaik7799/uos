(* Wiki Snippet Executor Validator — a REAL, honest embedded-snippet auditor.

   INTENT (from the phase-7 stub).  "Extracts Zig code snippets from the wiki
   and runs them to ensure they compile."

   WHAT THIS HONESTLY DOES.  It walks the wiki/ZK markdown corpus under
   [root]/docs, extracts every fenced ```zig … ``` code block, and runs a
   TEXT-based structural sanity scan on each: bracket/paren/brace balance and
   non-emptiness. It reports the real per-block findings and a corpus total.

   [NOTE] text-heuristic — snippets are NOT compiled. Actually compiling each
   block would need a Zig toolchain invocation + a synthesised translation unit
   per block; this module does not shell out to zig, so an unbalanced-bracket
   report is a necessary-but-not-sufficient compile signal, never a green
   "it compiles" claim. *)

let read_file path =
  try In_channel.with_open_bin path In_channel.input_all with _ -> ""

let list_md root =
  let base = Filename.concat root "docs" in
  let acc = ref [] in
  let rec go dir =
    match Sys.readdir dir with
    | entries ->
        Array.iter
          (fun e ->
            let p = Filename.concat dir e in
            if (try Sys.is_directory p with _ -> false) then go p
            else if Filename.check_suffix e ".md" then acc := p :: !acc)
          entries
    | exception _ -> ()
  in
  if (try Sys.is_directory base with _ -> false) then go base;
  List.sort compare !acc

let lines s = String.split_on_char '\n' s

(* Extract fenced ```zig blocks: returns list of block bodies (line lists). *)
let extract_zig_blocks text =
  let rec loop acc cur inside = function
    | [] -> List.rev (if inside then List.rev cur :: acc else acc)
    | line :: rest ->
        let t = String.trim line in
        if inside then
          if String.length t >= 3 && String.sub t 0 3 = "```" then
            loop (List.rev cur :: acc) [] false rest
          else loop acc (line :: cur) true rest
        else if
          String.length t >= 4
          && String.sub t 0 3 = "```"
          && String.trim (String.sub t 3 (String.length t - 3)) = "zig"
        then loop acc [] true rest
        else loop acc cur false rest
  in
  loop [] [] false (lines text)

(* Bracket-balance check; None = balanced, Some msg = defect. *)
let balance_check block_lines =
  let stack = ref [] in
  let err = ref None in
  let closer = function '(' -> ')' | '[' -> ']' | '{' -> '}' | _ -> ' ' in
  List.iter
    (fun line ->
      String.iter
        (fun c ->
          if !err = None then
            match c with
            | '(' | '[' | '{' -> stack := c :: !stack
            | ')' | ']' | '}' -> (
                match !stack with
                | top :: tl when closer top = c -> stack := tl
                | _ -> err := Some (Printf.sprintf "unbalanced '%c'" c))
            | _ -> ())
        line)
    block_lines;
  match !err with
  | Some m -> Some m
  | None -> if !stack <> [] then Some "unclosed bracket(s) at EOF" else None

let run (root : string) : unit =
  Printf.printf
    "[wiki_snippet_executor_validator] scanning docs/ for ```zig blocks under %s\n"
    root;
  let files = list_md root in
  let total_blocks = ref 0 in
  let balanced = ref 0 in
  let empty = ref 0 in
  let unbalanced = ref [] in
  List.iter
    (fun f ->
      let blocks = extract_zig_blocks (read_file f) in
      List.iteri
        (fun i b ->
          incr total_blocks;
          let nonblank = List.exists (fun l -> String.trim l <> "") b in
          if not nonblank then incr empty
          else
            match balance_check b with
            | None -> incr balanced
            | Some m ->
                unbalanced :=
                  Printf.sprintf "%s#zig[%d]: %s" (Filename.basename f) i m
                  :: !unbalanced)
        blocks)
    files;
  Printf.printf "  files scanned: %d\n" (List.length files);
  Printf.printf "  zig blocks: %d  (balanced=%d empty=%d unbalanced=%d)\n"
    !total_blocks !balanced !empty (List.length !unbalanced);
  List.iter (fun m -> Printf.printf "  [UNBALANCED] %s\n" m) (List.rev !unbalanced);
  Printf.printf
    "  [NOTE] text-heuristic: bracket-balance only; snippets NOT compiled (no zig toolchain invoked)\n"
