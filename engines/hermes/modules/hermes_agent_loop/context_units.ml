(* Context-reference units, reproduced faithfully from the frozen
   agent/context_references.py (read completely before writing; parity is
   measured by the context.* scenarios, never assumed).

   The frozen REFERENCE_PATTERN:

     (?<![\w/])@(?:(?P<simple>diff|staged)\b
                  |(?P<kind>file|folder|git|url):
                   (?P<value>QUOTED(?::\d+(?:-\d+)?)?|\S+))

   with QUOTED = a backtick-, double- or single-quoted run of one or more
   characters excluding the quote and newline. This module is a direct
   scanner for that grammar: the negative lookbehind bars a preceding word
   character or slash, the simple alternative demands a word boundary, the
   quoted alternative is tried before the greedy non-space run, and matches
   are non-overlapping left to right. (The quote characters are spelled out
   in prose here because OCaml lexes string literals inside comments — an
   odd quote count in a comment swallows the code after it, which this
   file's first build demonstrated.) *)

type reference = {
  raw : string;
  kind : string;
  target : string;
  start : int;
  finish : int;
  line_start : int option;
  line_end : int option;
}

let is_word c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'

let is_digit c = c >= '0' && c <= '9'

let trailing_punctuation = [ ','; '.'; ';'; '!'; '?' ]

(* _strip_trailing_punctuation: rstrip ",.;!?" then peel unbalanced closers. *)
let strip_trailing_punctuation value =
  let length = ref (String.length value) in
  while !length > 0 && List.mem value.[!length - 1] trailing_punctuation do
    decr length
  done;
  let stripped = ref (String.sub value 0 !length) in
  let count s c = String.fold_left (fun acc x -> if x = c then acc + 1 else acc) 0 s in
  let continue_ = ref true in
  while !continue_ do
    let s = !stripped in
    let n = String.length s in
    if n = 0 then continue_ := false
    else
      match s.[n - 1] with
      | (')' | ']' | '}') as closer ->
          let opener = match closer with ')' -> '(' | ']' -> '[' | _ -> '{' in
          if count s closer > count s opener then stripped := String.sub s 0 (n - 1)
          else continue_ := false
      | _ -> continue_ := false
  done;
  !stripped

(* _strip_reference_wrappers: peel one matching pair of wrapping quotes
   (backtick, double or single). *)
let strip_reference_wrappers value =
  let n = String.length value in
  if n >= 2 && value.[0] = value.[n - 1] && (value.[0] = '`' || value.[0] = '"' || value.[0] = '\'')
  then String.sub value 1 (n - 2)
  else value

(* _parse_file_reference_value: quoted-with-optional-range first, then the
   last ":digits(-digits)" suffix, then the wrapper peel. The frozen range
   regex is ^(.+?):(\d+)(?:-(\d+))?$ — a lazy path with an anchored tail,
   which resolves to the LAST colon whose suffix is all digits with an
   optional -digits. *)
let parse_file_reference_value value =
  let n = String.length value in
  let all f s = s <> "" && String.for_all f s in
  let quoted =
    if n >= 2 && (value.[0] = '`' || value.[0] = '"' || value.[0] = '\'') then begin
      let quote = value.[0] in
      (* the frozen path group is lazy: the FIRST closing quote ends it *)
      let rec close i = if i >= n then None else if value.[i] = quote then Some i else close (i + 1) in
      match close 1 with
      | Some close_at when close_at > 1 ->
          let path = String.sub value 1 (close_at - 1) in
          let rest = String.sub value (close_at + 1) (n - close_at - 1) in
          if rest = "" then Some (path, None, None)
          else if rest.[0] = ':' then begin
            let range = String.sub rest 1 (String.length rest - 1) in
            match String.index_opt range '-' with
            | Some dash ->
                let s = String.sub range 0 dash in
                let e = String.sub range (dash + 1) (String.length range - dash - 1) in
                if all is_digit s && all is_digit e then
                  Some (path, Some (int_of_string s), Some (int_of_string e))
                else None
            | None ->
                if all is_digit range then
                  Some (path, Some (int_of_string range), Some (int_of_string range))
                else None
          end
          else None
      | _ -> None
    end
    else None
  in
  match quoted with
  | Some result -> result
  | None -> (
      (* find the last ':' whose tail parses as digits(-digits) *)
      let range_split =
        let rec last_colon i best =
          if i >= n then best
          else last_colon (i + 1) (if value.[i] = ':' then Some i else best)
        in
        (* the lazy .+? demands a non-empty path, so a colon at index 0 is
           not a split point; and the regex anchors at $, so only a tail
           that is entirely digits(-digits) counts. Because .+? is lazy the
           EARLIEST valid split wins -- but every valid split has an
           all-digit tail, and a colon inside that tail would break it, so
           the earliest valid split is the last colon with a valid tail. *)
        ignore last_colon;
        let rec find i =
          if i >= n then None
          else if value.[i] = ':' && i > 0 then begin
            let tail = String.sub value (i + 1) (n - i - 1) in
            let ok =
              match String.index_opt tail '-' with
              | Some dash ->
                  all is_digit (String.sub tail 0 dash)
                  && all is_digit (String.sub tail (dash + 1) (String.length tail - dash - 1))
              | None -> all is_digit tail
            in
            if ok then Some (i, tail) else find (i + 1)
          end
          else find (i + 1)
        in
        find 1
      in
      match range_split with
      | Some (colon, tail) ->
          let path = String.sub value 0 colon in
          (match String.index_opt tail '-' with
           | Some dash ->
               let s = int_of_string (String.sub tail 0 dash) in
               let e = int_of_string (String.sub tail (dash + 1) (String.length tail - dash - 1)) in
               (path, Some s, Some e)
           | None ->
               let s = int_of_string tail in
               (path, Some s, Some s))
      | None -> (strip_reference_wrappers value, None, None))

(* _NEEDS_QUOTING = [\s()\[\]{}<>"'`] ; format_reference_value picks the first
   of ` " ' absent from the value. *)
let format_reference_value value =
  let needs_quoting =
    String.exists
      (fun c ->
        is_space c || c = '(' || c = ')' || c = '[' || c = ']' || c = '{' || c = '}'
        || c = '<' || c = '>' || c = '"' || c = '\'' || c = '`')
      value
  in
  if not needs_quoting then value
  else
    let absent quote = not (String.exists (fun c -> c = quote) value) in
    if absent '`' then "`" ^ value ^ "`"
    else if absent '"' then "\"" ^ value ^ "\""
    else if absent '\'' then "'" ^ value ^ "'"
    else value

(* The scanner for REFERENCE_PATTERN. *)
let parse_context_references message =
  let n = String.length message in
  let starts_at prefix i =
    i + String.length prefix <= n && String.sub message i (String.length prefix) = prefix
  in
  (* the quoted value alternative: quote, 1+ non-quote non-newline, quote,
     then an optional :digits(-digits); returns the end offset *)
  let match_quoted i =
    if i < n && (message.[i] = '`' || message.[i] = '"' || message.[i] = '\'') then begin
      let quote = message.[i] in
      let rec close j =
        if j >= n || message.[j] = '\n' then None
        else if message.[j] = quote then Some j
        else close (j + 1)
      in
      match close (i + 1) with
      | Some close_at when close_at > i + 1 ->
          (* optional :digits(-digits), matched greedily as the regex does *)
          let after = close_at + 1 in
          let rec digits j = if j < n && is_digit message.[j] then digits (j + 1) else j in
          if after < n && message.[after] = ':' && after + 1 < n && is_digit message.[after + 1]
          then begin
            let end_start = digits (after + 1) in
            if end_start < n && message.[end_start] = '-' && end_start + 1 < n
               && is_digit message.[end_start + 1]
            then digits (end_start + 1) |> Option.some
            else Some end_start
          end
          else Some after
      | _ -> None
    end
    else None
  in
  let refs = ref [] in
  let i = ref 0 in
  while !i < n do
    let c = message.[!i] in
    if c = '@' && (!i = 0 || (not (is_word message.[!i - 1]) && message.[!i - 1] <> '/'))
    then begin
      let after_at = !i + 1 in
      let simple =
        if starts_at "diff" after_at
           && (after_at + 4 >= n || not (is_word message.[after_at + 4]))
        then Some ("diff", after_at + 4)
        else if starts_at "staged" after_at
                && (after_at + 6 >= n || not (is_word message.[after_at + 6]))
        then Some ("staged", after_at + 6)
        else None
      in
      match simple with
      | Some (kind, finish) ->
          refs :=
            { raw = String.sub message !i (finish - !i); kind; target = ""; start = !i;
              finish; line_start = None; line_end = None }
            :: !refs;
          i := finish
      | None -> (
          let kind =
            List.find_opt
              (fun k -> starts_at (k ^ ":") after_at)
              [ "file"; "folder"; "git"; "url" ]
          in
          match kind with
          | None -> incr i
          | Some kind ->
              let value_start = after_at + String.length kind + 1 in
              let value_end =
                match match_quoted value_start with
                | Some quoted_end -> Some quoted_end
                | None ->
                    let rec eat j =
                      if j < n && not (is_space message.[j]) then eat (j + 1) else j
                    in
                    let e = eat value_start in
                    if e > value_start then Some e else None
              in
              (match value_end with
               | None -> incr i
               | Some finish ->
                   let value =
                     strip_trailing_punctuation
                       (String.sub message value_start (finish - value_start))
                   in
                   let target, line_start, line_end =
                     if kind = "file" then parse_file_reference_value value
                     else (strip_reference_wrappers value, None, None)
                   in
                   refs :=
                     { raw = String.sub message !i (finish - !i); kind; target;
                       start = !i; finish; line_start; line_end }
                     :: !refs;
                   i := finish))
    end
    else incr i
  done;
  List.rev !refs
