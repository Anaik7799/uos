(* HW.9.1.2 — interface-comment extraction. See the mli: static parse,
   never evaluation, total over author text. *)

type item = { name : string; signature : string; doc : string; line : int }

(* One left-to-right scan classifying every byte as code, comment or
   string. Comments NEST, and an opener inside a string literal is not a
   comment — getting that wrong is how a scanner erases the rest of a
   file and then reports a clean, empty answer. *)
type region = Code | Comment of int | Str

let scan text =
  let n = String.length text in
  let out = Buffer.create n in
  let comments = ref [] in
  let cur = Buffer.create 64 in
  let state = ref Code in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    let two = if !i + 1 < n then String.sub text !i 2 else "" in
    (match !state with
    | Code ->
        if two = "(*" then (state := Comment 1; Buffer.clear cur; i := !i + 2)
        else if c = '"' then (state := Str; Buffer.add_char out c; incr i)
        else (Buffer.add_char out c; incr i)
    | Comment d ->
        if two = "(*" then (state := Comment (d + 1); Buffer.add_string cur two; i := !i + 2)
        else if two = "*)" then begin
          if d = 1 then begin
            comments := Buffer.contents cur :: !comments;
            state := Code;
            (* a comment occupies no code space, but its NEWLINES must
               survive or every line number after it is wrong *)
            String.iter (fun ch -> if ch = '\n' then Buffer.add_char out '\n') (Buffer.contents cur)
          end
          else (state := Comment (d - 1); Buffer.add_string cur two);
          i := !i + 2
        end
        else (Buffer.add_char cur c; incr i)
    | Str ->
        (* a backslash escape cannot end the literal *)
        if c = '\\' && !i + 1 < n then (Buffer.add_string out two; i := !i + 2)
        else begin
          if c = '"' then state := Code;
          Buffer.add_char out c;
          incr i
        end);
    (* an UNTERMINATED comment ends at EOF rather than raising, and what
       it swallowed is not code — the honest reading of a broken file *)
    ()
  done;
  (Buffer.contents out, List.rev !comments)

let normalise s =
  s |> String.split_on_char '\n'
  |> List.concat_map (String.split_on_char '\t')
  |> List.concat_map (String.split_on_char '\r')
  |> List.map String.trim
  |> List.filter (fun t -> t <> "")
  |> String.concat " "

let starts_with p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

(* Comments in source order, each with the line it ENDS on, so a `val`
   can find the comment nearest above it. Recovered by re-scanning with
   positions rather than threading them through `scan`. *)
let comment_positions text =
  let n = String.length text in
  let out = ref [] in
  let state = ref Code in
  let cur = Buffer.create 64 in
  let line = ref 1 in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    let two = if !i + 1 < n then String.sub text !i 2 else "" in
    if c = '\n' then incr line;
    (match !state with
    | Code ->
        if two = "(*" then (state := Comment 1; Buffer.clear cur; i := !i + 2)
        else if c = '"' then (state := Str; incr i)
        else incr i
    | Comment d ->
        if two = "(*" then (state := Comment (d + 1); Buffer.add_string cur two; i := !i + 2)
        else if two = "*)" then begin
          if d = 1 then (out := (Buffer.contents cur, !line) :: !out; state := Code)
          else (state := Comment (d - 1); Buffer.add_string cur two);
          i := !i + 2
        end
        else (Buffer.add_char cur c; incr i)
    | Str ->
        if c = '\\' && !i + 1 < n then i := !i + 2
        else begin
          if c = '"' then state := Code;
          incr i
        end)
  done;
  List.rev !out

let items text =
  let code, _ = scan text in
  let comments = comment_positions text in
  let lines = String.split_on_char '\n' code in
  (* a `val` declaration runs to the next line that starts a new
     top-level construct; joining is what makes a multi-line signature
     one item *)
  let rec collect acc n prev_val = function
    | [] -> List.rev acc
    | line :: rest ->
        let t = String.trim line in
        if starts_with "val " t then begin
          let body = ref [ t ] in
          let seen = ref rest in
          let stop = ref false in
          let k = ref (n + 1) in
          while not !stop do
            match !seen with
            | [] -> stop := true
            | l :: more ->
                let lt = String.trim l in
                if
                  lt = "" || starts_with "val " lt || starts_with "type " lt
                  || starts_with "module " lt || starts_with "exception " lt
                  || starts_with "end" lt || starts_with "include " lt
                then stop := true
                else begin
                  body := lt :: !body;
                  seen := more;
                  incr k
                end
          done;
          let whole = normalise (String.concat " " (List.rev !body)) in
          let after_val = String.sub whole 4 (String.length whole - 4) in
          let name, signature =
            match String.index_opt after_val ':' with
            | Some ci ->
                (String.trim (String.sub after_val 0 ci),
                 String.trim (String.sub after_val (ci + 1) (String.length after_val - ci - 1)))
            | None -> (String.trim after_val, "")
          in
          (* A comment attaches to the NEXT val only. Taking the nearest
             comment above without this guard made ONE comment document
             every val below it — so a file with one header comment
             reported 100% coverage, which is precisely the lie
             HW.9.4.1's census must not inherit. The comment must lie
             BELOW the previous val to be this val's. *)
          let doc =
            List.fold_left
              (fun best (body, endline) ->
                if endline <= n && endline > prev_val then Some body else best)
              None comments
          in
          let doc = match doc with Some d -> normalise d | None -> "" in
          collect ({ name; signature; doc; line = n } :: acc) (n + 1) n rest
        end
        else collect acc (n + 1) prev_val rest
  in
  collect [] 1 0 lines

let documented it = it.doc <> ""
let undocumented text = items text |> List.filter (fun i -> not (documented i)) |> List.map (fun i -> i.name)

let coverage text =
  match items text with
  | [] -> None (* 0/0 is not 100% *)
  | its -> Some (List.length (List.filter documented its), List.length its)
