(* SC-PROVENANCE-001 — corpus observation.
   Reads the ADR corpus and the KM index documents from the working tree and
   reports what is actually there. No policy, no verdicts: those live in
   km_metrics.ml. Every function is bounded and read-only. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

let max_files = 4096
let max_bytes = 4 * 1024 * 1024

let read path =
  require (Sys.file_exists path) ("missing file: " ^ path);
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let n = in_channel_length ic in
    require (n <= max_bytes) ("oversize file: " ^ path);
    really_input_string ic n)

let sha256 s = Cryptokit.(transform_string (Hexa.encode ()) (hash_string (Hash.sha256 ()) s))

type adr = {
  number : int;            (* 1..999 *)
  file : string;           (* basename under docs/zk *)
  title : string;          (* H1 with the leading stamp and id stripped *)
  layer : string;          (* first #fractal-lN tag, or "" *)
  layers : string list;    (* ALL distinct #fractal-lN tags, ascending *)
  claimed_ev : int option; (* EV cycle asserted in the H1, if any *)
}

(* --- small scanning helpers, all bounded ------------------------------- *)

let is_digit c = c >= '0' && c <= '9'

let find_sub hay needle start =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 || nl > hl then None
  else begin
    let res = ref None and i = ref start in
    while !res = None && !i <= hl - nl do
      if String.sub hay !i nl = needle then res := Some !i else incr i
    done; !res
  end

(* Reads the integer following "adr-" or "EV-" at position i. *)
let int_at s i =
  let n = String.length s in
  let j = ref i and v = ref 0 and seen = ref 0 in
  while !j < n && is_digit s.[!j] && !seen < 4 do
    v := (!v * 10) + (Char.code s.[!j] - 48); incr j; incr seen
  done;
  if !seen = 0 then None else Some !v

let adr_number_of_name name =
  match find_sub name "adr-" 0 with
  | None -> None
  | Some i -> int_at name (i + 4)

(* First markdown H1 line. *)
let first_h1 body =
  let lines = String.split_on_char '\n' body in
  let rec go = function
    | [] -> ""
    | l :: tl ->
      if String.length l > 2 && l.[0] = '#' && l.[1] = ' ' then String.sub l 2 (String.length l - 2)
      else go tl
  in go lines

(* Strips a leading "YYYYMMDD-HHSS — " stamp and a leading "ADR-0NN: " id. *)
let strip_title t =
  let t = String.trim t in
  let t =
    if String.length t > 13 && is_digit t.[0] then
      match find_sub t "— " 0 with
      | Some i when i < 24 -> String.trim (String.sub t (i + 4) (String.length t - i - 4))
      | _ -> t
    else t in
  match find_sub t "ADR-" 0 with
  | Some 0 ->
    (match find_sub t ": " 0 with
     | Some i when i < 12 -> String.trim (String.sub t (i + 2) (String.length t - i - 2))
     | _ -> t)
  | _ -> t

let first_layer body =
  match find_sub body "#fractal-l" 0 with
  | None -> ""
  | Some i -> if i + 11 <= String.length body then String.sub body i 11 else ""

(* ALL distinct #fractal-lN tags in the record, ascending.

   first_layer is a LOSSY PROJECTION of the labelling, and reading the corpus
   through it produced a false alarm that stood for some time. Records here are
   multi-label -- 47 of 80 ADRs carry all ten layers, and only 6 carry as few as
   two -- while the tag block is conventionally written in ascending order. So
   `first_layer` returns "#fractal-l0" for 74 of 80 records, and any statistic
   over it measures the WRITING CONVENTION rather than the corpus.

   Nothing about the corpus was degenerate; the observable was. *)
let all_layers body =
  let rec go i acc =
    match find_sub body "#fractal-l" i with
    | None -> acc
    | Some j ->
      if j + 11 > String.length body then acc
      else
        let tag = String.sub body j 11 in
        let d = tag.[10] in
        let acc = if d >= '0' && d <= '9' && not (List.mem tag acc) then tag :: acc else acc in
        go (j + 10) acc
  in
  List.sort String.compare (go 0 [])

(* Highest EV-NNN mentioned in the H1 line only: a ratification claim lives in
   the title. Body mentions may be forward authorizations, which are not claims. *)
let ev_in_title h1 =
  let rec go i best =
    match find_sub h1 "EV-" i with
    | None -> best
    | Some j ->
      let b = match int_at h1 (j + 3) with
        | Some v when v >= 1 && v <= 999 -> (match best with Some p when p >= v -> best | _ -> Some v)
        | _ -> best in
      go (j + 3) b
  in go 0 None

let zk_dir = "docs/zk"

let adrs () =
  require (Sys.file_exists zk_dir) "docs/zk missing";
  let all = Sys.readdir zk_dir in
  require (Array.length all <= max_files) "docs/zk exceeds file bound";
  Array.sort compare all;
  let acc = ref [] in
  Array.iter (fun name ->
    if Filename.check_suffix name ".md" then
      match adr_number_of_name name with
      | Some n when n >= 1 && n <= 999 ->
        let body = read (Filename.concat zk_dir name) in
        let h1 = first_h1 body in
        acc := { number = n; file = name; title = strip_title h1;
                 layer = first_layer body; layers = all_layers body;
                 claimed_ev = ev_in_title h1 } :: !acc
      | _ -> ()) all;
  let l = List.sort (fun a b -> compare a.number b.number) !acc in
  require (l <> []) "no ADR documents found";
  l

(* Counts how many of `needles` appear at least once in `body`. *)
let coverage body needles =
  List.fold_left (fun acc n -> if find_sub body n 0 <> None then acc + 1 else acc) 0 needles
