(* Classifier for the model-to-source differential oracle.

   Reads the Lean and Gleam canonical outputs and reports, per case, whether
   they are IDENTICAL, differ only in list ORDER (set-equal), or are genuinely
   DIVERGENT. OCaml per the repository helper-language rule.

   Usage: compare LEAN_OUT GLEAM_OUT [--quiet] [--allow FILE]

   --quiet   suppress per-case ORDER_ONLY lines (for large generated corpora)
   --allow   a file of case keys ("seed | rules | steps") whose divergence is
             known, documented and accepted. An allowed divergence is reported
             as ALLOWED and does not fail the run; an unlisted one does. This
             keeps a known modelling boundary visible instead of hiding it in a
             threshold. *)

let read_lines path =
  let ic = open_in_bin path in
  let rec go acc =
    match input_line ic with
    | l -> go (if String.trim l = "" then acc else l :: acc)
    | exception End_of_file -> close_in ic; List.rev acc
  in go []

let split_on c s = String.split_on_char c s

(* Extract the comma lists inside bracket groups, in order. *)
let brackets s =
  let out = ref [] and buf = Buffer.create 64 and inside = ref false in
  String.iter (fun ch ->
    if ch = '[' then (inside := true; Buffer.clear buf)
    else if ch = ']' && !inside then (inside := false; out := Buffer.contents buf :: !out)
    else if !inside then Buffer.add_char buf ch) s;
  List.rev !out

let norm group = List.sort compare (if group = "" then [] else split_on ',' group)

(* Strip an edge's ":offset" suffix, keeping "@rule". Lets the classifier
   separate the documented grapheme-vs-scalar OFFSET class from a genuine
   content divergence: if two outputs agree on which rule rewrote what, and
   differ only in the positional index, that is the known modelling boundary and
   not a new finding. The rule index is deliberately retained — a disagreement
   about WHICH rule fired is content, not coordinates. *)
let strip_offset e =
  if String.contains e '@' then
    match String.rindex_opt e ':' with
    | Some i -> String.sub e 0 i
    | None -> e
  else e

let norm_no_offset group = List.sort compare (List.map strip_offset (norm group))

let tail_after_last_bracket s =
  match String.rindex_opt s ']' with
  | Some i -> String.sub s i (String.length s - i)
  | None -> s

let classify a b =
  if a = b then `Identical
  else
    let ba = brackets a and bb = brackets b in
    let same_shape =
      List.length ba = List.length bb && List.length ba > 0
      && tail_after_last_bracket a = tail_after_last_bracket b
    in
    if same_shape && List.for_all2 (fun x y -> norm x = norm y) ba bb then `OrderOnly
    else if same_shape
            && List.for_all2 (fun x y -> norm_no_offset x = norm_no_offset y) ba bb
    then `OffsetOnly
    else `Divergent

let () =
  let argv = Array.to_list Sys.argv in
  let quiet = List.mem "--quiet" argv in
  let allow_path =
    let rec find = function
      | "--allow" :: p :: _ -> Some p
      | _ :: rest -> find rest
      | [] -> None
    in find argv
  in
  let allowed =
    match allow_path with
    | None -> []
    | Some p ->
        read_lines p
        |> List.map String.trim
        |> List.filter (fun l -> l <> "" && l.[0] <> '#')
  in
  let lean = read_lines Sys.argv.(1) and gleam = read_lines Sys.argv.(2) in
  if List.length lean <> List.length gleam then begin
    Printf.printf "FATAL: line count mismatch %d vs %d\n"
      (List.length lean) (List.length gleam); exit 2
  end;
  let ident = ref 0 and order = ref 0 and diverge = ref 0 and allowed_n = ref 0
  and offset_n = ref 0 in
  List.iter2 (fun l g ->
    let lf = split_on '\t' l and gf = split_on '\t' g in
    let key = String.concat " | " (match lf with a :: b :: c :: _ -> [a;b;c] | _ -> [l]) in
    let lv = (match lf with _ :: _ :: _ :: v :: _ -> v | _ -> "") in
    let gv = (match gf with _ :: _ :: _ :: v :: _ -> v | _ -> "") in
    match classify lv gv with
    | `Identical -> incr ident
    | `OrderOnly ->
        incr order;
        if not quiet then Printf.printf "ORDER_ONLY   %s\n" key
    | `OffsetOnly ->
        incr offset_n;
        if not quiet then Printf.printf "OFFSET_ONLY  %s\n" key
    | `Divergent ->
        if List.mem key allowed then begin
          incr allowed_n;
          Printf.printf "ALLOWED      %s  (known, documented divergence)\n" key
        end else begin
          incr diverge;
          Printf.printf "DIVERGENT    %s\n      lean : %s\n      gleam: %s\n" key lv gv
        end)
    lean gleam;
  Printf.printf
    "\n%d cases: %d identical, %d order-only, %d offset-only (known class), \
%d allowed, %d DIVERGENT\n"
    (List.length lean) !ident !order !offset_n !allowed_n !diverge;
  if !diverge > 0 then exit 1
