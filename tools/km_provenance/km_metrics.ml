(* SC-PROVENANCE-001 — metrics and verdicts over the observed corpus.

   The quarantine boundary is a single constant. Everything else is derived. *)

open Km_corpus

let admitted_ev_ceiling = 93

(* A record is quarantine-derived when its title asserts ratification of an EV
   cycle above the admitted ceiling. *)
let quarantined a = match a.claimed_ev with Some v -> v > admitted_ev_ceiling | None -> false

type index = { path : string; label : string }

let indexes = [
  { path = "docs/zk/20260905-1801-moc-uos-unified-master.md";      label = "zk-master-moc" };
  { path = "docs/wiki/20260905-1801-uos-zk-km-corpus-index.md";    label = "wiki-corpus-index" };
]

type index_report = {
  ix_label : string;
  ix_path : string;
  enumerated : int;        (* ADR files referenced by name *)
  total : int;
  marked : int;            (* quarantined ADRs whose id is followed by a marking *)
  quarantined_total : int;
  completeness : float;
  marking : float;
}

(* An index "enumerates" an ADR when the ADR's exact filename appears in it. *)
let index_report (all : adr list) ix =
  let body = read ix.path in
  let enumerated = List.length (List.filter (fun a -> find_sub body a.file 0 <> None) all) in
  let q = List.filter quarantined all in
  (* A quarantined record is marked when NOT_ADMITTED appears in the index and
     the record's own filename is present: the index-level statement plus the
     per-row marker are both required, so we check the row text near the file. *)
  let marked =
    List.length (List.filter (fun a ->
      match find_sub body a.file 0 with
      | None -> false
      | Some i ->
        (* look ahead within the same table row / list item *)
        let window_end = min (String.length body) (i + 600) in
        let window = String.sub body i (window_end - i) in
        find_sub window "NOT_ADMITTED" 0 <> None
        || (match find_sub body "NOT_ADMITTED" 0 with Some _ -> false | None -> false)) q) in
  let total = List.length all and qt = List.length q in
  { ix_label = ix.label; ix_path = ix.path; enumerated; total; marked;
    quarantined_total = qt;
    completeness = (if total = 0 then 0.0 else float_of_int enumerated /. float_of_int total);
    marking = (if qt = 0 then 1.0 else float_of_int marked /. float_of_int qt) }

(* Shannon entropy in bits of the fractal-layer distribution: a degenerate
   corpus (everything tagged L0) carries no structural information. This is the
   CHK-09-MATH gate applied to the knowledge corpus. *)
let layer_entropy_bits (all : adr list) =
  let tbl = Hashtbl.create 16 in
  List.iter (fun a ->
    let k = if a.layer = "" then "none" else a.layer in
    Hashtbl.replace tbl k (1 + (try Hashtbl.find tbl k with Not_found -> 0))) all;
  let total = float_of_int (List.length all) in
  if total <= 0.0 then 0.0
  else Hashtbl.fold (fun _ c acc ->
    let p = float_of_int c /. total in
    if p > 0.0 then acc -. (p *. (log p /. log 2.0)) else acc) tbl 0.0

let contiguous (all : adr list) =
  let rec go expect = function
    | [] -> None
    | a :: tl -> if a.number <> expect then Some expect else go (expect + 1) tl
  in go 1 all

let duplicates (all : adr list) =
  let rec go seen = function
    | [] -> []
    | a :: tl -> if List.mem a.number seen then a.number :: go seen tl else go (a.number :: seen) tl
  in go [] all
