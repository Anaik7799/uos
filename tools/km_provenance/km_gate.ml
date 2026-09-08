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
     km_gate --classify-layers              propose a fractal layer per record
     km_gate --ooda                         one bounded observe/orient/decide/act pass
     km_gate --series METRIC                the recorded history of one metric
     km_gate --rete                         forward-chain the provenance rule network
     km_gate --rete-selftest                closed-schema and salience laws
     km_gate --publish                      write live JSON artifacts under generated/
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

(* --- layer classification proposal (KMP-ENTROPY) ----------------------- *)

let classify_layers () =
  let all = adrs () in
  let proposals =
    List.filter_map (fun a ->
      let body = read (Filename.concat "docs/zk" a.file) in
      Km_layers.classify ~file:a.file ~current:a.layer ~body) all in
  let current_counts = Km_layers.tally (List.map (fun p -> p.Km_layers.current) proposals) in
  let proposed_counts = Km_layers.tally (List.map (fun p -> p.Km_layers.proposed) proposals) in
  let h_now = Km_layers.entropy_of current_counts in
  let h_prop = Km_layers.entropy_of proposed_counts in
  let changed = List.filter (fun p -> p.Km_layers.current <> p.Km_layers.proposed) proposals in
  (* A small margin means the archetypes barely separated: say so per record. *)
  let low_margin = List.filter (fun p -> p.Km_layers.margin < 0.05) proposals in
  let dist name counts = name, `Assoc (List.map (fun (l, c) -> l, `Int c) counts) in
  print_json (`Assoc [
    "schema", `String "uos-km-layer-proposal/v1";
    "contract", `String "SC-PROVENANCE-001";
    "authority", `String "PROPOSAL_ONLY";
    "applied", `Bool false;
    "observed_at", `String (now_utc ());
    "method", `String "term-frequency vector over a fixed vocabulary, cosine similarity against one archetype per layer, highest wins";
    "vocabulary_terms", `Int Km_layers.dim;
    "records", `Int (List.length proposals);
    "records_where_proposal_differs", `Int (List.length changed);
    "low_margin_records", `Int (List.length low_margin);
    "entropy_bits", `Assoc [
      "current", `Float h_now;
      "if_proposal_applied", `Float h_prop;
      "floor", `Float 2.5 ];
    (let (n, v) = dist "current_distribution" current_counts in n, v);
    (let (n, v) = dist "proposed_distribution" proposed_counts in n, v);
    "proposals", `List (List.map (fun p -> `Assoc [
      "file", `String p.Km_layers.file;
      "current", `String p.Km_layers.current;
      "proposed", `String p.Km_layers.proposed;
      "confidence", `Float p.Km_layers.confidence;
      "margin", `Float p.Km_layers.margin ]) proposals);
    "limits", `List (List.map (fun s -> `String s) [
      "A term-frequency match is weak evidence of architectural layer; it reflects vocabulary, not design intent.";
      "Records with margin below 0.05 were barely separated and should be treated as unclassified.";
      "Nothing is written. Applying a layer is an authorship act belonging to the record author or sovereign review." ]) ]);
  0

(* Emits real document/archetype vector pairs so an independent implementation
   (the Mojo kernel via its NIF) can recompute the same cosine values. Two
   implementations agreeing is the differential oracle; one implementation
   agreeing with itself is not evidence. *)
let layer_vectors n =
  let all = adrs () in
  let take k l = List.filteri (fun i _ -> i < k) l in
  let sample = take n all in
  let pairs = List.map (fun a ->
    let body = read (Filename.concat "docs/zk" a.file) in
    let v = Km_layers.doc_vector body in
    let best = match Km_layers.classify ~file:a.file ~current:a.layer ~body with
      | Some p -> p.Km_layers.proposed | None -> "" in
    let av = Km_layers.archetype_vector best in
    let ocaml_cos = match Km_layers.cosine v av with Some c -> c | None -> -1.0 in
    `Assoc ["file", `String a.file;
            "layer", `String best;
            "doc", `List (List.map (fun x -> `Float x) v);
            "archetype", `List (List.map (fun x -> `Float x) av);
            "ocaml_cosine", `Float ocaml_cos]) sample in
  print_json (`Assoc ["schema", `String "uos-km-layer-vectors/v1";
                      "dim", `Int Km_layers.dim;
                      "pairs", `List pairs]);
  0

(* --- bounded predictive OODA pass -------------------------------------- *)

let plan_id = "km-convergence-20260908-0940"

let ooda () =
  (* OBSERVE *)
  let (_json, reports, gap, dups, entropy) = metrics_json () in
  let all = adrs () in
  let observed = now_utc () in
  let completeness =
    match reports with
    | [] -> 0.0
    | _ ->
      List.fold_left (fun a r -> a +. r.Km_metrics.completeness) 0.0 reports
      /. float_of_int (List.length reports) in
  let marking =
    match reports with
    | [] -> 0.0
    | _ ->
      List.fold_left (fun a r -> a +. r.Km_metrics.marking) 0.0 reports
      /. float_of_int (List.length reports) in

  (* ORIENT: append this observation, then fit the history *)
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    List.iter (fun (m, v) -> Km_ooda.record db ~observed ~metric:m ~value:v ~plan:plan_id)
      [ "layer_entropy_bits", entropy;
        "index_completeness", completeness;
        "quarantine_marking", marking;
        "adr_total", float_of_int (List.length all) ];

    let orient metric threshold =
      let xs = Km_ooda.series db ~metric in
      let n = List.length xs in
      let level = match Km_ooda.ewma 0.5 xs with Some l -> `Float l | None -> `Null in
      let proj = match Km_ooda.project xs ~steps:5 ~threshold with
        | None -> `Null
        | Some p -> `Assoc [
            "slope_per_observation", `Float p.Km_ooda.slope;
            "rms_residual", `Float p.Km_ooda.residual;
            "projected_5_steps", `Float p.Km_ooda.projected;
            "band_low", `Float p.Km_ooda.low;
            "band_high", `Float p.Km_ooda.high;
            "decisive_against_threshold", `Bool p.Km_ooda.decisive ] in
      `Assoc ["metric", `String metric; "observations", `Int n;
              "current", `Float (match xs with [] -> 0.0 | l -> List.nth l (n - 1));
              "ewma_level", level; "threshold", `Float threshold;
              "projection", proj] in

    (* DECIDE: thresholds come from the contract, not from the trend *)
    let orients = [ orient "layer_entropy_bits" 2.5;
                    orient "index_completeness" 1.0;
                    orient "quarantine_marking" 1.0 ] in
    let breaches =
      (if entropy < 2.5 then ["layer_entropy_bits below 2.50"] else [])
      @ (if completeness < 1.0 then ["index_completeness below 1.0"] else [])
      @ (if marking < 1.0 then ["quarantine_marking below 1.0"] else [])
      @ (if gap <> None then ["ADR numbering not contiguous"] else [])
      @ (if dups <> [] then ["duplicate ADR numbers"] else []) in

    (* ACT: report only *)
    print_json (`Assoc [
      "schema", `String "uos-km-ooda/v1";
      "contract", `String "SC-PROVENANCE-001";
      "authority", `String "REPORT_ONLY";
      "effect_authority", `String "NONE";
      "observed_at", `String observed;
      "observe", `Assoc [
        "adr_total", `Int (List.length all);
        "layer_entropy_bits", `Float entropy;
        "index_completeness", `Float completeness;
        "quarantine_marking", `Float marking ];
      "orient", `List orients;
      "decide", `Assoc [
        "verdict", `String (if breaches = [] then "PASS" else "HOLD");
        "breaches", `List (List.map (fun s -> `String s) breaches) ];
      "act", `String "reported; no document written, no admission changed, no work dispatched";
      "limits", `List (List.map (fun s -> `String s) [
        "A projection is a least-squares line, not a probabilistic model; no confidence level is claimed.";
        "The band is one RMS residual either side. A band spanning the threshold decides nothing and is marked not decisive.";
        "History accumulates only when this pass runs, so the series is a record of observations, not of wall-clock time." ]) ]);
    if breaches = [] then 0 else 1)

let show_series metric =
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    let xs = Km_ooda.series db ~metric in
    print_json (`Assoc ["metric", `String metric; "observations", `Int (List.length xs);
                        "values", `List (List.map (fun v -> `Float v) xs)]);
    0)

(* --- Rete-UL provenance verdicts ---------------------------------------- *)

let rete_facts () =
  let all = adrs () in
  let reports = List.map (Km_metrics.index_report all) Km_metrics.indexes in
  let db = Km_chain.open_db () in
  let (rows, defects) =
    Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () -> Km_chain.verify db) in
  let open Km_rete in
  let adr_facts = List.map (fun a ->
    { kind = "adr";
      fields = ["id", N (float_of_int a.number);
                "claims_ev", N (match a.claimed_ev with Some v -> float_of_int v | None -> 0.0);
                "layer", S (if a.layer = "" then "none" else a.layer)] }) all in
  let index_facts = List.map (fun r ->
    { kind = "index";
      fields = ["label", S r.Km_metrics.ix_label;
                "completeness", N r.Km_metrics.completeness;
                "marking", N r.Km_metrics.marking] }) reports in
  let ceiling_fact =
    { kind = "ceiling"; fields = ["policy", N 93.0; "machine", N 92.0] } in
  let chain_fact =
    { kind = "chain"; fields = ["rows", N (float_of_int rows);
                                "intact", B (defects = [])] } in
  adr_facts @ index_facts @ [ceiling_fact; chain_fact]

let rete () =
  let facts = rete_facts () in
  let (wm, traces, cycles) = Km_rete.run facts in
  let vs = Km_rete.violations wm in
  let ans = Km_rete.andons wm in
  let quarantined = List.length (List.filter (fun f -> f.Km_rete.kind = "quarantined") wm) in
  print_json (`Assoc [
    "schema", `String "uos-km-rete/v1";
    "contract", `String "SC-PROVENANCE-001";
    "governing_invariant", `String "ADR-001 closed fact schema, strict typing, duplicate-key rejection";
    "authority", `String "REPORT_ONLY";
    "observed_at", `String (now_utc ());
    "initial_facts", `Int (List.length facts);
    "working_memory_after_fixpoint", `Int (List.length wm);
    "cycles_to_fixpoint", `Int cycles;
    "derived_quarantined", `Int quarantined;
    "firing_trace", `List (List.map (fun t -> `Assoc [
      "cycle", `Int t.Km_rete.cycle;
      "rule", `String t.Km_rete.rule_name;
      "derived_facts", `Int t.Km_rete.derived]) traces);
    "andon", `List (List.map (fun a -> `String a) ans);
    "violations", `List (List.map (fun (r, d) -> `Assoc [
      "rule", `String r; "detail", `String d]) vs);
    "verdict", `String (if ans <> [] then "ANDON" else if vs = [] then "PASS" else "HOLD");
    "limits", `List (List.map (fun s -> `String s) [
      "A rule network decides over the facts it is given; it cannot see state nobody asserted.";
      "Salience orders conflict resolution; it is not a proof of precedence correctness.";
      "REPORT_ONLY: no verdict here grants admission or dispatches any effect." ]) ]);
  if ans <> [] || vs <> [] then 1 else 0

(* Laws for the network itself, independent of the corpus. *)
let rete_selftest () =
  let open Km_rete in
  let checks = ref 0 and fails = ref 0 in
  let check name ok =
    incr checks;
    if ok then Printf.printf "ok   %s\n" name
    else (incr fails; Printf.printf "FAIL %s\n" name) in
  let rejects name f =
    incr checks;
    match f () with
    | exception Invalid _ -> Printf.printf "ok   %s (rejected)\n" name
    | _ -> incr fails; Printf.printf "FAIL %s (accepted)\n" name in

  (* ADR-001: closed schema *)
  rejects "unknown fact kind" (fun () ->
    validate { kind = "sneaky"; fields = ["x", N 1.0] });
  rejects "unknown field" (fun () ->
    validate { kind = "ceiling"; fields = ["policy", N 93.0; "machine", N 92.0; "extra", N 1.0] });
  rejects "duplicate key" (fun () ->
    validate { kind = "ceiling"; fields = ["policy", N 93.0; "policy", N 92.0; "machine", N 92.0] });
  rejects "field type mismatch" (fun () ->
    validate { kind = "ceiling"; fields = ["policy", S "93"; "machine", N 92.0] });
  rejects "missing field" (fun () ->
    validate { kind = "ceiling"; fields = ["policy", N 93.0] });

  (* Forward chaining: R1 derives quarantined, which enables R2. *)
  let base = [
    { kind = "ceiling"; fields = ["policy", N 93.0; "machine", N 93.0] };
    { kind = "adr"; fields = ["id", N 71.0; "claims_ev", N 94.0; "layer", S "#fractal-l5"] };
    { kind = "index"; fields = ["label", S "t"; "completeness", N 1.0; "marking", N 0.5] };
    { kind = "chain"; fields = ["rows", N 20.0; "intact", B true] } ] in
  let (wm, traces, _) = run base in
  check "R1 derives a quarantined fact"
    (List.exists (fun f -> f.kind = "quarantined") wm);
  check "R2 fires only because R1 derived first (chaining)"
    (List.exists (fun (r, _) -> r = "KMP-UNMARKED") (violations wm));
  check "R1 fires before R2 (salience order)"
    (match List.map (fun t -> t.rule_name) traces with
     | a :: b :: _ -> a = "R1-quarantine-above-ceiling" && b = "R2-unmarked-quarantine"
     | _ -> false);

  (* A record at or below the ceiling must NOT be quarantined. *)
  let below = [
    { kind = "ceiling"; fields = ["policy", N 93.0; "machine", N 93.0] };
    { kind = "adr"; fields = ["id", N 70.0; "claims_ev", N 93.0; "layer", S "#fractal-l0"] };
    { kind = "index"; fields = ["label", S "t"; "completeness", N 1.0; "marking", N 1.0] };
    { kind = "chain"; fields = ["rows", N 20.0; "intact", B true] } ] in
  let (wm2, _, _) = run below in
  check "a record exactly at the ceiling is not quarantined"
    (not (List.exists (fun f -> f.kind = "quarantined") wm2));
  check "a clean corpus yields no violations" (violations wm2 = []);

  (* Emergency precedence: a broken chain fires first, above everything. *)
  let broken = [
    { kind = "ceiling"; fields = ["policy", N 93.0; "machine", N 92.0] };
    { kind = "adr"; fields = ["id", N 71.0; "claims_ev", N 94.0; "layer", S "#fractal-l5"] };
    { kind = "index"; fields = ["label", S "t"; "completeness", N 0.5; "marking", N 0.0] };
    { kind = "chain"; fields = ["rows", N 20.0; "intact", B false] } ] in
  let (wm3, traces3, _) = run broken in
  check "andon raised on a broken chain" (andons wm3 <> []);
  check "andon fires FIRST despite lower-salience rules being ready"
    (match traces3 with t :: _ -> t.rule_name = "R0-andon-chain-broken" | [] -> false);

  (* Fixpoint: rerunning adds nothing. *)
  let (wm4, traces4, _) = run wm3 in
  check "rerunning from a saturated memory derives nothing new"
    (List.length wm4 = List.length wm3 && traces4 = []);

  (* Ceiling split is derived, not hard-coded. *)
  check "ceiling discrepancy derived from facts"
    (List.exists (fun (r, _) -> r = "KMP-CEILING-SPLIT") (violations wm3));

  Printf.printf "\n%d checks, %d failures\n" !checks !fails;
  if !fails = 0 then 0 else 1

(* --- publish live artifacts ---------------------------------------------- *)
(* The web engine already serves /files/<path> for any repository path, so
   writing here makes the metrics live over the Tailnet without touching the
   Wisp router, which another session currently owns. *)

let write_file path contents =
  let dir = Filename.dirname path in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc contents)

let capture f =
  (* Re-runs a reporter and captures its JSON rather than duplicating logic. *)
  let tmp = Filename.temp_file "km-gate" ".json" in
  let saved = Unix.dup Unix.stdout in
  let fd = Unix.openfile tmp [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o600 in
  Unix.dup2 fd Unix.stdout;
  let code = (try f () with _ -> 2) in
  flush stdout;
  Unix.dup2 saved Unix.stdout;
  Unix.close fd; Unix.close saved;
  let ic = open_in tmp in
  let n = in_channel_length ic in
  let body = really_input_string ic n in
  close_in ic; Sys.remove tmp;
  (code, body)

let publish () =
  let base = "generated/km-provenance" in
  if not (Sys.file_exists "generated") then Unix.mkdir "generated" 0o755;
  if not (Sys.file_exists base) then Unix.mkdir base 0o755;
  let items = [
    "metrics.json", (fun () -> let (j, _, _, _, _) = metrics_json () in print_json j; 0);
    "gate.json", gate;
    "rete.json", rete;
    "ooda.json", ooda;
    "layers.json", classify_layers;
  ] in
  let written = List.map (fun (name, f) ->
    let (code, body) = capture f in
    write_file (Filename.concat base name) body;
    `Assoc ["artifact", `String (base ^ "/" ^ name);
            "bytes", `Int (String.length body);
            "exit_code", `Int code;
            "live_url", `String ("http://nas-1.tail55d152.ts.net:4100/files/" ^ base ^ "/" ^ name)])
    items in
  print_json (`Assoc [
    "schema", `String "uos-km-publish/v1";
    "contract", `String "SC-PROVENANCE-001";
    "authority", `String "REPORT_ONLY";
    "observed_at", `String (now_utc ());
    "note", `String "written under generated/, served by the existing /files/ route; the Wisp router is not modified";
    "artifacts", `List written]);
  0

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
    | [_; "--classify-layers"] -> exit (classify_layers ())
    | [_; "--layer-vectors"; n] -> exit (layer_vectors (int_of_string n))
    | [_; "--ooda"] -> exit (ooda ())
    | [_; "--rete"] -> exit (rete ())
    | [_; "--rete-selftest"] -> exit (rete_selftest ())
    | [_; "--publish"] -> exit (publish ())
    | [_; "--series"; m] -> exit (show_series m)
    | [_; "--fit"; csv] ->
      let xs = List.map float_of_string (String.split_on_char ',' csv) in
      let (slope, resid) = match Km_ooda.fit xs with
        | Some (sl, _, r) -> (sl, r) | None -> (nan, nan) in
      let lvl = match Km_ooda.ewma 0.5 xs with Some l -> l | None -> nan in
      print_json (`Assoc ["n", `Int (List.length xs); "ewma_0_5", `Float lvl;
                          "slope", `Float slope; "rms_residual", `Float resid]);
      exit 0
    | [_; "--append"; c; k; t; b; e] -> exit (append c k t b e)
    | _ ->
      prerr_endline "Usage: km_gate --metrics | --gate | --verify-chain | --cycles | --classify-layers | --append CYCLE KIND TITLE BODY EVIDENCE_JSON";
      exit 2
  with
  | Invalid m -> fail m
  | Km_layers.Invalid m -> fail m
  | Km_ooda.Invalid m -> fail m
  | Km_rete.Invalid m -> fail m
  | Km_chain.Invalid m -> fail m
  | Sys_error m -> fail m
