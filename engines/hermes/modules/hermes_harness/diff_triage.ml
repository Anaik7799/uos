(* The nine-class diff triage — the acceptance table the skill has specified
   since it was written, enforced at LINE-DIFF level.

   ADAPTED from the operator-supplied expect_atlas Triage + Scrub modules
   (2026-08-12 paste; both arrived complete). Two enforcement points now
   exist, one per scale, which is the fractal shape: `Baseline_triage`
   classifies PIN deltas before a corpus re-pin; this classifies a single
   site's expected-vs-actual LINE diff before an accept. Same philosophy,
   different carrier — neither replaces the other.

   The class order is load-bearing and tested: `volatile` is checked BEFORE
   `whitespace`, because a timestamp diff that also collapses under
   whitespace is a scrubber gap, not a cosmetic change — misclassifying it
   as auto-acceptable would launder exactly the noise the scrubbers exist to
   name. `unstable`, `emptied`, `error` and `volatile` BLOCK: nobody may
   accept them, because each is a defect in the capture rather than a change
   in behaviour. *)

(* ------------------------------------------------------------- scrubbers *)

let is_digit c = c >= '0' && c <= '9'
let is_hex c = is_digit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
let is_alnum c = is_digit c || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

let ndigits s i k =
  let n = String.length s in
  let rec go j = j - i = k || (j < n && is_digit s.[j] && go (j + 1)) in
  i + k <= n && go i

let nhex s i k =
  let n = String.length s in
  let rec go j = j - i = k || (j < n && is_hex s.[j] && go (j + 1)) in
  i + k <= n && go i

let chr s i c = i < String.length s && s.[i] = c

let m_timestamp s i =
  if
    ndigits s i 4 && chr s (i + 4) '-' && ndigits s (i + 5) 2 && chr s (i + 7) '-'
    && ndigits s (i + 8) 2
  then begin
    let n = String.length s in
    let j = ref (i + 10) in
    (if !j < n
        && (s.[!j] = 'T' || s.[!j] = ' ')
        && ndigits s (!j + 1) 2 && chr s (!j + 3) ':' && ndigits s (!j + 4) 2
        && chr s (!j + 6) ':' && ndigits s (!j + 7) 2
     then begin
       j := !j + 9;
       if chr s !j '.' then begin
         incr j;
         while !j < n && is_digit s.[!j] do incr j done
       end;
       if chr s !j 'Z' then incr j
       else if !j < n && (s.[!j] = '+' || s.[!j] = '-') && ndigits s (!j + 1) 2 then begin
         j := !j + 3;
         if chr s !j ':' && ndigits s (!j + 1) 2 then j := !j + 3
         else if ndigits s !j 2 then j := !j + 2
       end
     end);
    Some (!j - i, "<TS>")
  end
  else None

let m_uuid s i =
  if
    nhex s i 8 && chr s (i + 8) '-' && nhex s (i + 9) 4 && chr s (i + 13) '-'
    && nhex s (i + 14) 4 && chr s (i + 18) '-' && nhex s (i + 19) 4
    && chr s (i + 23) '-' && nhex s (i + 24) 12
  then Some (36, "<UUID>")
  else None

let m_hexaddr s i =
  if chr s i '0' && chr s (i + 1) 'x' && nhex s (i + 2) 4 then begin
    let n = String.length s in
    let j = ref (i + 2) in
    while !j < n && is_hex s.[!j] do incr j done;
    Some (!j - i, "<ADDR>")
  end
  else None

let m_tmpdir s i =
  let pre = "/tmp/" in
  let lp = String.length pre in
  if i + lp <= String.length s && String.sub s i lp = pre then begin
    let n = String.length s in
    let j = ref (i + lp) in
    while
      !j < n
      && (is_alnum s.[!j] || s.[!j] = '.' || s.[!j] = '_' || s.[!j] = '/' || s.[!j] = '-')
    do
      incr j
    done;
    Some (!j - i, "<TMP>")
  end
  else None

let m_pid s i =
  let pre = "pid=" in
  let lp = String.length pre in
  if i + lp <= String.length s && String.sub s i lp = pre && ndigits s (i + lp) 1 then begin
    let n = String.length s in
    let j = ref (i + lp) in
    while !j < n && is_digit s.[!j] do incr j done;
    Some (!j - i, "pid=<PID>")
  end
  else None

let m_duration s i =
  let n = String.length s in
  if i >= n || not (is_digit s.[i]) then None
  else begin
    let j = ref i in
    while !j < n && is_digit s.[!j] do incr j done;
    let frac =
      if chr s !j '.' && ndigits s (!j + 1) 1 then begin
        incr j;
        while !j < n && is_digit s.[!j] do incr j done;
        true
      end
      else false
    in
    let fin len =
      let stop = !j + len in
      if stop < n && is_alnum s.[stop] then None else Some (stop - i, "<DUR>")
    in
    if !j + 1 < n && s.[!j] = 'm' && s.[!j + 1] = 's' then fin 2
    else if !j + 1 < n && s.[!j] = 'u' && s.[!j + 1] = 's' then fin 2
    else if frac && chr s !j 's' then fin 1
    else None
  end

let matchers =
  [ ("timestamp", m_timestamp); ("uuid", m_uuid); ("hexaddr", m_hexaddr);
    ("tmpdir", m_tmpdir); ("pid", m_pid); ("duration", m_duration) ]

(* Fire only at token boundaries so identifiers are never chewed. *)
let boundary s i = i = 0 || not (is_alnum s.[i - 1])

let scrub_line s =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    let hit =
      if boundary s !i then
        List.find_map
          (fun (_, m) -> match m s !i with Some (len, rep) -> Some (len, rep) | None -> None)
          matchers
      else None
    in
    match hit with
    | Some (len, rep) ->
        Buffer.add_string b rep;
        i := !i + len
    | None ->
        Buffer.add_char b s.[!i];
        incr i
  done;
  Buffer.contents b

let scrub_lines = List.map scrub_line

(* ------------------------------------------------------------ diff helpers *)

let collapse_ws s =
  let b = Buffer.create (String.length s) in
  let in_sp = ref true in
  String.iter
    (fun c ->
      if c = ' ' || c = '\t' then begin
        if not !in_sp then Buffer.add_char b ' ';
        in_sp := true
      end
      else begin
        Buffer.add_char b c;
        in_sp := false
      end)
    s;
  let out = Buffer.contents b in
  let l = String.length out in
  if l > 0 && out.[l - 1] = ' ' then String.sub out 0 (l - 1) else out

let is_subseq a b =
  let rec go a b =
    match (a, b) with
    | [], _ -> true
    | _, [] -> false
    | x :: xs, y :: ys -> if x = y then go xs ys else go a ys
  in
  go a b

(* ------------------------------------------------------------ the classes *)

let classes =
  [ "unstable"; "emptied"; "error"; "volatile"; "removal"; "semantic"; "reorder";
    "additive"; "whitespace" ]

type verdict = Auto | Review | Block

let verdict_name = function Auto -> "auto" | Review -> "review" | Block -> "block"
let exit_code = function Auto -> 0 | Review -> 1 | Block -> 2

let verdict_of = function
  | "whitespace" -> Auto
  | "reorder" | "additive" | "removal" | "semantic" -> Review
  | _ -> Block (* unstable, emptied, error, volatile *)

let classify ~status ~expected ~actual =
  if status = "unstable" then "unstable"
  else if status = "error" then "error"
  else if actual = [] && expected <> [] then "emptied"
  else if scrub_lines expected = scrub_lines actual then "volatile"
  else if List.map collapse_ws expected = List.map collapse_ws actual then "whitespace"
  else if List.sort compare expected = List.sort compare actual then "reorder"
  else if is_subseq expected actual then "additive"
  else if is_subseq actual expected then "removal"
  else "semantic"

(* Justification downgrades REVIEW to auto — never a blocking class, which is
   the property that keeps the gate a gate: no written reason makes an
   unstable capture acceptable. The floor on reason length is crude but
   real: "updated" is not a causal story. *)
let triage ?(require_justification = false) ~justify ~site ~status ~expected ~actual () =
  let kind = classify ~status ~expected ~actual in
  let base = verdict_of kind in
  let reason = List.assoc_opt site justify in
  match (base, reason) with
  | Review, Some r when String.length (String.trim r) >= 20 ->
      (kind, Auto, "justified: " ^ r)
  (* An inadequate reason counts as NO reason when justification is required.
     The upstream paste let a too-short string fall through to plain Review —
     so the word "short" evaded the requirement entirely. A word is not a
     causal story, and a gate a single token slips past is decoration. Found
     by this suite s own negative control before the port ever shipped. *)
  | Review, _ when require_justification ->
      (kind, Block, "review-class change with no adequate justification on file")
  | v, _ -> (kind, v, "")
