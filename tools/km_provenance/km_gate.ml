(* SC-PROVENANCE-001 — KM provenance gate.

   Authority: REPORT_ONLY. This tool observes and records; it grants no
   admission and no effect authority. A PASS here means the indexes match the
   observed corpus and every quarantine-derived record carries its marker. It
   does not mean any EV cycle is admitted.

   Usage:
     km_gate --metrics                     observe the corpus, print metrics JSON
     km_gate --gate                        as above, plus a PASS/HOLD verdict
     km_gate --verify-chain                recompute every cycle digest
     km_gate --append CYCLE KIND TITLE BODY EVIDENCE_JSON   append one cycle row
     km_gate --cycles                      list the recorded cycle chain
*)

open Km_corpus

let now_utc () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let print_json j = print_endline (Yojson.Basic.pretty_to_string j)

(* --- observation ------------------------------------------------------- *)

let observe () =
  let all = adrs () in
  let total = List.length all in
  let q = List.filter Km_metrics.quarantined all in
  let reports = List.map (Km_metrics.index_report all) Km_metrics.indexes in
  let entropy = Km_metrics.layer_entropy_bits all in
  let gap = Km_metrics.contiguous all in
  let dups = Km_metrics.duplicates all in
  (all, total, q, reports, entropy, gap, dups)

let metrics_json () =
  let (all, total, q, reports, entropy, gap, dups) = observe () in
  let ev_of a = match a.claimed_ev with Some v -> `Int v | None -> `Null in
  let index_json r = `Assoc [
    "label", `String r.Km_metrics.ix_label;
    "path", `String r.Km_metrics.ix_path;
    "adrs_enumerated", `Int r.Km_metrics.enumerated;
    "adrs_total", `Int r.Km_metrics.total;
    "completeness_ratio", `Float r.Km_metrics.completeness;
    "quarantined_marked", `Int r.Km_metrics.marked;
    "quarantined_total", `Int r.Km_metrics.quarantined_total;
    "marking_ratio", `Float r.Km_metrics.marking ] in
  let json = `Assoc [
    "schema", `String "uos-km-provenance-metrics/v1";
    "contract", `String "SC-PROVENANCE-001";
    "authority", `String "REPORT_ONLY";
    "runtime_admission", `String "NOT_GRANTED";
    "observed_at", `String (now_utc ());
    "admitted_ev_ceiling", `Int Km_metrics.admitted_ev_ceiling;
    "corpus", `Assoc [
      "adr_total", `Int total;
      "adr_first", `Int (match all with a :: _ -> a.number | [] -> 0);
      "adr_last", `Int (List.fold_left (fun _ a -> a.number) 0 all);
      "contiguous", `Bool (gap = None);
      "first_gap_at", (match gap with Some n -> `Int n | None -> `Null);
      "duplicate_numbers", `List (List.map (fun n -> `Int n) dups);
      "layer_entropy_bits", `Float entropy;
      "quarantined_total", `Int (List.length q);
      "quarantined_ids", `List (List.map (fun a -> `Int a.number) q) ];
    "indexes", `List (List.map index_json reports);
    "quarantined_records", `List (List.map (fun a -> `Assoc [
        "adr", `Int a.number; "file", `String a.file;
        "claims_ev", ev_of a; "layer", `String a.layer ]) q);
    "limits", `List (List.map (fun s -> `String s) [
      "Byte presence of a filename in an index does not prove the index text is correct.";
      "A marker proves the index states the record is not admitted; it does not adjudicate the record.";
      "This gate observes documents only; it asserts nothing about runtime behaviour." ]) ] in
  (json, reports, gap, dups, entropy)

(* --- verdict ----------------------------------------------------------- *)

let gate () =
  let (json, reports, gap, dups, entropy) = metrics_json () in
  let findings = ref [] in
  let add rule detail = findings := `Assoc ["rule", `String rule; "detail", `String detail] :: !findings in
  if gap <> None then add "KMP-GAP" "ADR numbering is not contiguous from 1";
  if dups <> [] then add "KMP-DUP" "duplicate ADR numbers present";
  if entropy < 2.5 then
    add "KMP-ENTROPY"
      (Printf.sprintf "fractal layer entropy %.3f bits is below the CHK-09-MATH floor of 2.50" entropy);
  List.iter (fun r ->
    if r.Km_metrics.completeness < 1.0 then
      add "KMP-INCOMPLETE"
        (Printf.sprintf "%s enumerates %d of %d ADRs" r.Km_metrics.ix_label
           r.Km_metrics.enumerated r.Km_metrics.total);
    if r.Km_metrics.marking < 1.0 then
      add "KMP-UNMARKED"
        (Printf.sprintf "%s marks %d of %d quarantine-derived records" r.Km_metrics.ix_label
           r.Km_metrics.marked r.Km_metrics.quarantined_total)) reports;
  let status = if !findings = [] then "PASS" else "HOLD" in
  let merged = match json with
    | `Assoc kv -> `Assoc (("status", `String status) :: ("findings", `List (List.rev !findings)) :: kv)
    | j -> j in
  print_json merged;
  if status = "PASS" then 0 else 1

(* --- chain ------------------------------------------------------------- *)

let with_db f =
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () -> f db)

let verify_chain () =
  with_db (fun db ->
    let (n, bad) = Km_chain.verify db in
    print_json (`Assoc [
      "schema", `String "uos-km-cycle-chain/v1";
      "authority", `String "REPORT_ONLY";
      "observed_at", `String (now_utc ());
      "rows", `Int n;
      "status", `String (if bad = [] then "CHAIN_INTACT" else "CHAIN_BROKEN");
      "defects", `List (List.map (fun s -> `String s) bad)]);
    if bad = [] then 0 else 1)

let append cycle kind title body evidence =
  with_db (fun db ->
    let (seq, digest) = Km_chain.append db ~cycle_id:cycle
        ~plan_id:"km-index-refresh-20260908-0912" ~task_id:"t8" ~kind ~title ~body
        ~observed:(now_utc ()) ~evidence in
    print_json (`Assoc ["appended", `Bool true; "sequence", `Int seq;
                        "cycle_id", `String cycle; "digest", `String digest]);
    0)

let cycles () =
  with_db (fun db ->
    let stmt = Sqlite3.prepare db
      "SELECT sequence,cycle_id,kind,title,observed_utc,substr(digest,1,12) FROM cycle ORDER BY sequence" in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
      let rec loop acc = match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
          let t i = match Sqlite3.column stmt i with Sqlite3.Data.TEXT s -> s
                                                   | Sqlite3.Data.INT n -> Int64.to_string n | _ -> "" in
          loop (`Assoc ["sequence", `String (t 0); "cycle_id", `String (t 1);
                        "kind", `String (t 2); "title", `String (t 3);
                        "observed_utc", `String (t 4); "digest12", `String (t 5)] :: acc)
        | Sqlite3.Rc.DONE -> List.rev acc
        | _ -> raise (Invalid "cycle listing failed") in
      print_json (`Assoc ["cycles", `List (loop [])]); 0))

let () =
  let fail msg =
    print_json (`Assoc ["status", `String "HOLD"; "authority", `String "NONE";
                        "rule", `String "KMP-INVALID"; "detail", `String msg]);
    exit 2 in
  try
    match Array.to_list Sys.argv with
    | [_; "--metrics"] -> let (j, _, _, _, _) = metrics_json () in print_json j; exit 0
    | [_; "--gate"] -> exit (gate ())
    | [_; "--verify-chain"] -> exit (verify_chain ())
    | [_; "--cycles"] -> exit (cycles ())
    | [_; "--append"; c; k; t; b; e] -> exit (append c k t b e)
    | _ ->
      prerr_endline "Usage: km_gate --metrics | --gate | --verify-chain | --cycles | --append CYCLE KIND TITLE BODY EVIDENCE_JSON";
      exit 2
  with
  | Invalid m -> fail m
  | Km_chain.Invalid m -> fail m
  | Sys_error m -> fail m
