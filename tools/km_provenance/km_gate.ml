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
     km_gate --ev-admission REVISION        compute [[admit]] per EV from evidence
     km_gate --ev-selftest                  the seven admission laws
     km_gate --ev-record EV REV RUNTIME FORMAL   append one evidence row
     km_gate --merge-selftest               the merge-readiness laws
     km_gate --metrics-selftest             the fractal-layer entropy laws
     km_gate --merge-hold BRANCH REASON CONDITION   record a hold as data
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

(* --- EV admission, computed from evidence ------------------------------- *)

(* Presence is resolved against the CURRENT WORKING TREE only. It deliberately
   does NOT fall back to a canonical absolute root the way tools/uos/uos_ffi.erl
   file_exists/1 does: that fallback is why every existing gate measures the
   canonical checkout instead of the workspace it runs in, and why deleting an
   artifact in a sibling workspace does not fail its gate. *)
let workspace_present path =
  (not (Filename.is_relative path)) = false && Sys.file_exists path

let read_evidence db =
  let stmt = Sqlite3.prepare db
    "SELECT ev,revision,runtime_ref,formal_ref FROM ev_evidence ORDER BY ev" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    let opt i = match Sqlite3.column stmt i with
      | Sqlite3.Data.TEXT t when String.trim t <> "" -> Some t
      | _ -> None in
    let num i = match Sqlite3.column stmt i with
      | Sqlite3.Data.INT n -> Int64.to_int n | _ -> 0 in
    let txt i = match Sqlite3.column stmt i with
      | Sqlite3.Data.TEXT t -> t | _ -> "" in
    let rec loop acc = match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW ->
        loop ({ Km_ev.ev = num 0; revision = txt 1;
                runtime_ref = opt 2; formal_ref = opt 3 } :: acc)
      | Sqlite3.Rc.DONE -> List.rev acc
      | _ -> raise (Invalid "ev_evidence scan failed") in
    loop [])

let ev_record ev revision runtime_ref formal_ref =
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    let stmt = Sqlite3.prepare db
      "INSERT INTO ev_evidence (ev,revision,runtime_ref,formal_ref,recorded_utc,recorded_by) \
       VALUES (?,?,?,?,?,?)" in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
      ignore (Sqlite3.bind_int stmt 1 ev);
      List.iteri (fun i v -> ignore (Sqlite3.bind_text stmt (i + 2) v))
        [revision; runtime_ref; formal_ref; now_utc (); "fable-km-refresh-20260908-0912"];
      require (Sqlite3.step stmt = Sqlite3.Rc.DONE) "ev_evidence insert refused");
    print_json (`Assoc ["recorded", `Bool true; "ev", `Int ev;
                        "revision", `String revision]);
    0)

let ev_admission revision =
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    let evidence = read_evidence db in
    (* Every EV that is CLAIMED anywhere, whether or not evidence exists for it.
       Claims come from the ADR corpus; evidence comes from the database. The
       point of the exercise is that these two sets differ. *)
    let claimed =
      List.filter_map (fun a -> a.claimed_ev) (adrs ())
      |> List.sort_uniq compare in
    let claimed = if claimed = [] then [] else
      let hi = List.fold_left max 0 claimed in
      List.init hi (fun i -> i + 1) in
    let results =
      List.map (fun n ->
        match List.find_opt (fun e -> e.Km_ev.ev = n) evidence with
        | None -> (n, Km_ev.Not_admitted "no evidence row in ev_evidence")
        | Some e -> (n, Km_ev.admit ~present:workspace_present ~at_revision:revision e))
        claimed in
    let results = Km_ev.apply_no_gap results in
    let admitted = Km_ev.admitted_count results in
    let ceiling = Km_ev.ceiling results in
    print_json (`Assoc [
      "schema", `String "uos-ev-admission/v1";
      "contract", `String "SC-PROVENANCE-001";
      "authority", `String "REPORT_ONLY";
      "observed_at", `String (now_utc ());
      "candidate_revision", `String revision;
      "denotation", `String "admit(n,r) = Admitted iff exists e. runtime(e,n,r) and formal(e,n,r) and bound_to(e,r); NotAdmitted otherwise";
      "ev_claimed", `Int (List.length results);
      (* Two counts, deliberately. The total includes rows outside the claimed
         range, such as the ev=999 row inserted on 2026-09-08 to prove the
         append-only triggers refuse UPDATE and DELETE. That row cannot be
         removed, which is the trigger working as designed, so it is disclosed
         rather than filtered away silently. *)
      "evidence_rows_total", `Int (List.length evidence);
      "evidence_rows_in_claimed_range",
        `Int (List.length (List.filter (fun e ->
                let n = e.Km_ev.ev in
                List.exists (fun (m, _) -> m = n) results) evidence));
      "ev_admitted", `Int admitted;
      "derived_ceiling", `Int ceiling;
      "verdicts", `List (List.map (fun (n, v) -> `Assoc [
        "ev", `Int n;
        "verdict", `String (Km_ev.verdict_to_string v);
        "reason", `String (Km_ev.reason v)]) results);
      "limits", `List (List.map (fun s -> `String s) [
        "Presence is resolved against the current working tree only; there is no fallback to a canonical root.";
        "An evidence row asserts that two artifacts exist at a revision; it does not re-execute them.";
        "REPORT_ONLY: this computes a verdict, it does not grant admission." ]) ]);
    if admitted = List.length results then 0 else 1)

(* The seven laws, each executed. *)
let ev_selftest () =
  let open Km_ev in
  let checks = ref 0 and fails = ref 0 in
  let check name ok =
    incr checks;
    if ok then Printf.printf "ok   %s\n" name
    else (incr fails; Printf.printf "FAIL %s\n" name) in
  let all _ = true and none _ = false in
  let ev n ?rt ?fm rev = { ev = n; revision = rev; runtime_ref = rt; formal_ref = fm } in
  let r = "rev-A" in

  check "L1 fail-closed: no evidence at all is NotAdmitted"
    (admit ~present:all ~at_revision:r (ev 1 r) <> Admitted);
  check "L2 two-key: runtime alone is NotAdmitted"
    (admit ~present:all ~at_revision:r (ev 1 ~rt:"t.receipt" r) <> Admitted);
  check "L2 two-key: formal alone is NotAdmitted"
    (admit ~present:all ~at_revision:r (ev 1 ~fm:"s.lean" r) <> Admitted);
  check "L2 two-key: both keys present is Admitted"
    (admit ~present:all ~at_revision:r (ev 1 ~rt:"t.receipt" ~fm:"s.lean" r) = Admitted);
  check "L3 revision-bound: evidence at rev-A says nothing at rev-B"
    (admit ~present:all ~at_revision:"rev-B" (ev 1 ~rt:"t" ~fm:"s" r) <> Admitted);
  check "L3 revision-bound: empty candidate revision is NotAdmitted"
    (admit ~present:all ~at_revision:"" (ev 1 ~rt:"t" ~fm:"s" r) <> Admitted);
  check "L7 falsifiable: same evidence, absent artifacts, flips to NotAdmitted"
    (admit ~present:all ~at_revision:r (ev 1 ~rt:"t" ~fm:"s" r) = Admitted
     && admit ~present:none ~at_revision:r (ev 1 ~rt:"t" ~fm:"s" r) <> Admitted);
  check "L6 idempotent: identical inputs give identical verdicts"
    (admit ~present:all ~at_revision:r (ev 1 ~rt:"t" ~fm:"s" r)
     = admit ~present:all ~at_revision:r (ev 1 ~rt:"t" ~fm:"s" r));

  let full n = (n, admit ~present:all ~at_revision:r (ev n ~rt:"t" ~fm:"s" r)) in
  let bare n = (n, admit ~present:all ~at_revision:r (ev n r)) in
  let gapped = apply_no_gap [full 1; bare 2; full 3] in
  check "L4 no-gap: EV-3 with full evidence is refused when EV-2 is not admitted"
    (List.assoc 3 gapped <> Admitted);
  check "L4 no-gap: EV-1 is unaffected by the gap rule"
    (List.assoc 1 gapped = Admitted);
  check "L5 non-inflation: adding a claim with no evidence never raises the count"
    (admitted_count (apply_no_gap [full 1]) = 1
     && admitted_count (apply_no_gap [full 1; bare 2]) = 1);
  check "ceiling is derived: contiguous admitted prefix only"
    (ceiling (apply_no_gap [full 1; full 2; bare 3; full 4]) = 2);

  Printf.printf "\n%d checks, %d failures\n" !checks !fails;
  if !fails = 0 then 0 else 1

(* --- merge readiness laws ---------------------------------------------- *)

(* The entropy metric's own law suite (KMP-ENTROPY).

   This exists because the metric was wrong for a long time in a way that looked
   like a corpus defect: it folded over the FIRST #fractal-lN tag only, and the
   tag block is written ascending, so it reported the writing convention. A whole
   cosine classifier (Km_layers) was then built to "fix" a corpus that was never
   broken.

   E5 is the important law: correcting a metric is only legitimate if the metric
   still fails what it is supposed to fail. *)
let metrics_selftest () =
  let checks = ref 0 and fails = ref 0 in
  let check name ok =
    incr checks;
    if ok then Printf.printf "ok   %s\n" name
    else (incr fails; Printf.printf "FAIL %s\n" name) in
  let mk n layers =
    { Km_corpus.number = n; file = Printf.sprintf "adr-%03d.md" n;
      title = "t"; layer = (match layers with l :: _ -> l | [] -> "");
      layers; claimed_ev = None } in
  let l i = Printf.sprintf "#fractal-l%d" i in
  let all_ten = List.init 10 l in
  let close a b = Float.abs (a -. b) < 1e-9 in

  check "E1 an empty corpus is 0 bits, not an error"
    (close (Km_metrics.layer_entropy_bits []) 0.0);
  check "E2 a corpus where every record carries ONLY l0 is 0 bits"
    (close (Km_metrics.layer_entropy_bits (List.init 20 (fun i -> mk i [ l 0 ]))) 0.0);
  check "E3 a corpus uniform over all ten layers reaches log2(10)"
    (close (Km_metrics.layer_entropy_bits (List.init 10 (fun i -> mk i [ l i ])))
       (log 10.0 /. log 2.0));
  check "E4 multi-label records contribute EVERY tag, not just the first \
         (the defect: 47 of 80 ADRs carry all ten layers and were counted as l0)"
    (close (Km_metrics.layer_entropy_bits [ mk 1 all_ten ]) (log 10.0 /. log 2.0));
  check "E5 the corrected metric STILL FAILS a genuinely degenerate corpus \
         -- fixing a measurement is not moving a goalpost"
    (Km_metrics.layer_entropy_bits (List.init 50 (fun i -> mk i [ l 0 ])) < 2.5);
  check "E6 a corpus concentrated on two layers is still below the 2.50 floor"
    (Km_metrics.layer_entropy_bits
       (List.init 40 (fun i -> mk i [ l 0; l 4 ])) < 2.5);
  check "E7 an untagged record falls back to \"none\" rather than vanishing"
    (close (Km_metrics.layer_entropy_bits [ mk 1 [] ]) 0.0);
  check "E8 tag ORDER cannot change the entropy (the old metric depended on it)"
    (close
       (Km_metrics.layer_entropy_bits [ mk 1 [ l 0; l 4; l 7 ] ])
       (Km_metrics.layer_entropy_bits [ mk 1 [ l 7; l 4; l 0 ] ]));

  Printf.printf "metrics_selftest: %d checks, %d failed\n" !checks !fails;
  if !fails = 0 then 0 else 1

let merge_selftest () =
  let open Km_merge in
  let checks = ref 0 and fails = ref 0 in
  let check name ok =
    incr checks;
    if ok then Printf.printf "ok   %s\n" name
    else (incr fails; Printf.printf "FAIL %s\n" name) in

  let a ?(readiness=Ready) ?(blockers=[]) ?(rev="rev-A") ~valid_until branch =
    { branch; revision = rev; observed_at = 0.0; valid_until; readiness; blockers } in
  let ok_assess = [a ~valid_until:100.0 "b"] in
  let m ?(assessments=ok_assess) ?(holds=[]) ?(builds=true) ?(now=50.0)
        ?(rev="rev-A") ?(use_rev=false) () =
    mergeable ~assessments ~holds ~builds ~now ~current_revision:rev
              ~use_revision_freshness:use_rev "b" in

  check "M1 fail-closed: no assessment covering the branch is NotMergeable"
    (m ~assessments:[] () <> Mergeable);
  check "M0 baseline: fresh, ready, unblocked, building, unheld is Mergeable"
    (m () = Mergeable);
  check "M2 freshness: an expired assessment is NotMergeable"
    (m ~now:200.0 () <> Mergeable);
  check "M2 reason names expiry, not something else"
    (match m ~now:200.0 () with Not_mergeable r -> r = "assessment expired" | _ -> false);
  check "M3 blockers: a non-empty blocker list is NotMergeable"
    (m ~assessments:[a ~blockers:["x"] ~valid_until:100.0 "b"] () <> Mergeable);
  check "M3 readiness other than ready is NotMergeable"
    (m ~assessments:[a ~readiness:Blocked ~valid_until:100.0 "b"] () <> Mergeable);
  check "M4 build: a branch that does not build is NotMergeable"
    (m ~builds:false () <> Mergeable);
  check "M5 hold: an uncleared hold blocks even when everything else passes"
    (m ~holds:[{ h_branch="b"; h_reason="native gates"; h_clearing_condition="gates green";
                 h_cleared=false }] () <> Mergeable);
  check "M5 a cleared hold does not block"
    (m ~holds:[{ h_branch="b"; h_reason="native gates"; h_clearing_condition="gates green";
                 h_cleared=true }] () = Mergeable);
  check "M5 a hold on another branch does not block this one"
    (m ~holds:[{ h_branch="other"; h_reason="x"; h_clearing_condition="y";
                 h_cleared=false }] () = Mergeable);
  check "M5 an undischargeable hold is reported as such in the reason"
    (match m ~holds:[{ h_branch="b"; h_reason="held"; h_clearing_condition="";
                       h_cleared=false }] () with
     | Not_mergeable r ->
       (try ignore (Str.search_forward (Str.regexp_string "cannot be discharged") r 0); true
        with Not_found -> false)
     | _ -> false);
  check "M5 a hold with no clearing condition is not well-formed"
    (not (hold_well_formed { h_branch="b"; h_reason="r"; h_clearing_condition=" ";
                             h_cleared=false }));

  (* M6/M7: the freshness axis. Same assessment, same instant, different axis. *)
  check "M6 revision freshness: unchanged revision stays valid past the wall clock"
    (m ~now:99999.0 ~use_rev:true ~rev:"rev-A" () = Mergeable);
  check "M6 revision freshness: a changed revision invalidates it"
    (m ~now:50.0 ~use_rev:true ~rev:"rev-B" () <> Mergeable);
  check "M7 falsifiable: the SAME inputs flip verdict when only the clock moves"
    (m ~now:50.0 () = Mergeable && m ~now:200.0 () <> Mergeable);
  check "first failing conjunct is reported: expiry precedes the hold"
    (match m ~now:200.0
              ~holds:[{ h_branch="b"; h_reason="h"; h_clearing_condition="c";
                        h_cleared=false }] () with
     | Not_mergeable r -> r = "assessment expired" | _ -> false);

  Printf.printf "\n%d checks, %d failures\n" !checks !fails;
  if !fails = 0 then 0 else 1

let merge_hold branch reason condition =
  let db = Km_chain.open_db () in
  Fun.protect ~finally:(fun () -> Km_chain.close db) (fun () ->
    let stmt = Sqlite3.prepare db
      "INSERT INTO merge_hold (branch,reason,clearing_condition,recorded_utc,recorded_by) \
       VALUES (?,?,?,?,?)" in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
      List.iteri (fun i v -> ignore (Sqlite3.bind_text stmt (i + 1) v))
        [branch; reason; condition; now_utc (); "fable-km-refresh-20260908-0912"];
      require (Sqlite3.step stmt = Sqlite3.Rc.DONE) "merge_hold insert refused");
    print_json (`Assoc ["recorded", `Bool true; "branch", `String branch]);
    0)

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
    | [_; "--ev-admission"; rev] -> exit (ev_admission rev)
    | [_; "--ev-selftest"] -> exit (ev_selftest ())
    | [_; "--merge-selftest"] -> exit (merge_selftest ())
    | [_; "--metrics-selftest"] -> exit (metrics_selftest ())
    | [_; "--merge-hold"; b; r; c] -> exit (merge_hold b r c)
    | [_; "--ev-record"; n; rev; rt; fm] -> exit (ev_record (int_of_string n) rev rt fm)
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
  | Km_ev.Invalid m -> fail m
  | Km_merge.Invalid m -> fail m
  | Km_chain.Invalid m -> fail m
  | Sys_error m -> fail m
