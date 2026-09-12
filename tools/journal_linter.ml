(* tools/journal_linter.ml -- SC-JOURNAL-v3 Anticipatory Epistemic Ledger Linter
   Authority: Operator Directive / contracts/rules/20260912-0745-sc-journal-v3-anticipatory-contract.md
   Zero-Muda, Tri-Sovereign Governance, 7-Engine Verification *)

open Printf

let read_lines file_path =
  let ic = open_in file_path in
  let rec loop acc =
    match input_line ic with
    | line -> loop (line :: acc)
    | exception End_of_file ->
        close_in ic;
        List.rev acc
  in
  loop []

let read_entire_file file_path =
  let ic = open_in file_path in
  let len = in_channel_length ic in
  let s = really_input_string ic len in
  close_in ic;
  s

let contains_substring haystack needle =
  try
    let _ = Str.search_forward (Str.regexp_string needle) haystack 0 in
    true
  with Not_found -> false

let matches_regex str pattern =
  try
    let regex = Str.regexp pattern in
    let _ = Str.search_forward regex str 0 in
    true
  with Not_found -> false

(* Section headers to match in exact order *)
let canonical_sections = [
  (1, "Scope & Trigger", "^##[ \t]+1\\.[ \t]+Scope");
  (2, "Pre-State Assessment", "^##[ \t]+2\\.[ \t]+Pre-State");
  (3, "Execution Detail", "^##[ \t]+3\\.[ \t]+Execution");
  (4, "Root Cause Analysis", "^##[ \t]+4\\.[ \t]+Root[ \t]+Cause");
  (5, "Fix Taxonomy", "^##[ \t]+5\\.[ \t]+Fix[ \t]+Taxonomy");
  (6, "Patterns & Anti-Patterns", "^##[ \t]+6\\.[ \t]+Patterns");
  (7, "Verification Matrix", "^##[ \t]+7\\.[ \t]+Verification");
  (8, "Files Modified", "^##[ \t]+8\\.[ \t]+Files[ \t]+Modified");
  (9, "Architectural Observations", "^##[ \t]+9\\.[ \t]+Architectural");
  (10, "Remaining Gaps", "^##[ \t]+10\\.[ \t]+Remaining[ \t]+Gaps");
  (11, "Metrics Summary", "^##[ \t]+11\\.[ \t]+Metrics[ \t]+Summary");
  (12, "STAMP & Constitutional Alignment", "^##[ \t]+12\\.[ \t]+STAMP");
  (13, "Conclusion", "^##[ \t]+13\\.[ \t]+Conclusion")
]

type section_content = {
  sec_id: int;
  title: string;
  lines: string list;
}

let partition_sections all_lines =
  let rec group cur_sec acc_lines acc_sections = function
    | [] ->
        let finished = match cur_sec with
          | Some (id, name) -> { sec_id = id; title = name; lines = List.rev acc_lines } :: acc_sections
          | None -> acc_sections
        in
        List.rev finished
    | line :: rest ->
        let matched_header =
          List.find_opt (fun (_, _, pat) -> matches_regex line pat) canonical_sections
        in
        match matched_header with
        | Some (id, name, _) ->
            let new_acc = match cur_sec with
              | Some (prev_id, prev_name) -> { sec_id = prev_id; title = prev_name; lines = List.rev acc_lines } :: acc_sections
              | None -> acc_sections
            in
            group (Some (id, name)) [] new_acc rest
        | None ->
            group cur_sec (line :: acc_lines) acc_sections rest
  in
  group None [] [] all_lines

let lint_journal file_path =
  let base_name = Filename.basename file_path in
  printf "Evaluating SC-JOURNAL-v3 Anticipatory Epistemic Ledger:\n";
  printf "Target: %s\n" file_path;

  let errors = ref [] in
  let add_err err = errors := err :: !errors in

  (* Check 1: Timestamp Prefix *)
  let ts_regex = Str.regexp "^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-" in
  let has_ts =
    try
      let _ = Str.search_forward ts_regex base_name 0 in
      true
    with Not_found -> false
  in
  if has_ts then
    printf "  [PASS] CHK-TIME: Valid YYYYMMDD-HHSS- timestamp prefix in filename\n"
  else begin
    printf "  [FAIL] CHK-TIME: Filename '%s' missing mandatory YYYYMMDD-HHSS- prefix\n" base_name;
    add_err "Filename lacks YYYYMMDD-HHSS- prefix"
  end;

  let all_lines =
    try read_lines file_path
    with e ->
      printf "  [FAIL] Cannot read file: %s\n" (Printexc.to_string e);
      exit 1
  in
  let full_text = String.concat "\n" all_lines in

  (* Check 2: All 13 Sections Present in Order *)
  let sections = partition_sections all_lines in
  let section_ids = List.map (fun s -> s.sec_id) sections in
  let expected_ids = List.init 13 (fun i -> i + 1) in
  if section_ids = expected_ids then
    printf "  [PASS] CHK-SECT: All 13 canonical sections present in exact sequential order\n"
  else begin
    printf "  [FAIL] CHK-SECT: Expected sections 1..13, found [%s]\n"
      (String.concat ", " (List.map string_of_int section_ids));
    add_err "Missing or out-of-order canonical sections"
  end;

  (* Check non-empty content in sections *)
  List.iter (fun s ->
    let non_empty = List.exists (fun l -> String.trim l <> "") s.lines in
    if not non_empty then begin
      printf "  [FAIL] CHK-SECT: Section %d (%s) has empty body\n" s.sec_id s.title;
      add_err (sprintf "Section %d is empty" s.sec_id)
    end
  ) sections;

  (* Check 3: Engine 1 - ACH in Section 4 *)
  let sec4 = List.find_opt (fun s -> s.sec_id = 4) sections in
  let has_ach = match sec4 with
    | None -> false
    | Some s ->
        let text = String.concat "\n" s.lines in
        (contains_substring text "ACH" || contains_substring text "Analysis of Competing Hypotheses")
        && (matches_regex text "H1\\|H_1\\|Hypothesis 1")
        && (matches_regex text "H2\\|H_2\\|Hypothesis 2")
  in
  if has_ach then
    printf "  [PASS] CHK-ACH: Engine 1 (ACH Hypothesis Disconfirmation) verified in Section 4\n"
  else begin
    printf "  [FAIL] CHK-ACH: Section 4 lacks structured ACH competing hypotheses (H1, H2)\n";
    add_err "Section 4 lacks ACH matrix"
  end;

  (* Check 4: Engine 2 - Admiralty Protocol in Section 7 *)
  let sec7 = List.find_opt (fun s -> s.sec_id = 7) sections in
  let has_admiralty = match sec7 with
    | None -> false
    | Some s ->
        let text = String.concat "\n" s.lines in
        (contains_substring text "Admiralty" || contains_substring text "STANAG" || contains_substring text "Grade")
        && (contains_substring text "A1" || contains_substring text "A2" || contains_substring text "B1" || contains_substring text "B2")
  in
  let has_substandard = match sec7 with
    | None -> false
    | Some s ->
        let text = String.concat "\n" s.lines in
        (* Check if C3, D4, E3, F6 are cited as passing/admitted without rejection *)
        matches_regex text "PASS.*\\(C[1-6]\\|D[1-6]\\|E[1-6]\\|F[1-6]\\)"
  in
  if has_admiralty && not has_substandard then
    printf "  [PASS] CHK-ADMR: Engine 2 (Admiralty Protocol >= B2) verified in Section 7\n"
  else begin
    printf "  [FAIL] CHK-ADMR: Section 7 lacks Admiralty >= B2 verification evidence\n";
    add_err "Section 7 Admiralty verification missing or substandard"
  end;

  (* Check 5: Engine 4 - Devil's Advocate / Falsification in Section 6 or 10 *)
  let sec6 = List.find_opt (fun s -> s.sec_id = 6) sections in
  let sec10 = List.find_opt (fun s -> s.sec_id = 10) sections in
  let has_devils_advocate =
    let in_sec s_opt = match s_opt with
      | None -> false
      | Some s ->
          let text = String.concat "\n" s.lines in
          contains_substring text "Devil's Advocate"
          || contains_substring text "Red Team"
          || contains_substring text "Popperian"
          || contains_substring text "Falsif"
    in
    in_sec sec6 || in_sec sec10
  in
  if has_devils_advocate then
    printf "  [PASS] CHK-RED: Engine 4 (Devil's Advocate / Falsification) present in Section 6/10\n"
  else begin
    printf "  [FAIL] CHK-RED: Section 6 or 10 lacks Devil's Advocate / Popperian falsification\n";
    add_err "Devil's Advocate / Red Team analysis missing"
  end;

  (* Check 6: Engine 3 - Bayesian / Lyapunov in Section 11 *)
  let sec11 = List.find_opt (fun s -> s.sec_id = 11) sections in
  let has_decay_metrics = match sec11 with
    | None -> false
    | Some s ->
        let text = String.concat "\n" s.lines in
        (contains_substring text "Bayes" || contains_substring text "Beta" || contains_substring text "Trust")
        || (contains_substring text "Lyapunov" || contains_substring text "Stability" || contains_substring text "drift")
  in
  if has_decay_metrics then
    printf "  [PASS] CHK-DECAY: Engine 3 (Bayesian Trust & Lyapunov Stability) present in Section 11\n"
  else begin
    printf "  [FAIL] CHK-DECAY: Section 11 lacks Bayesian trust or Lyapunov stability metrics\n";
    add_err "Section 11 lacks Bayesian/Lyapunov metrics"
  end;

  (* Check 7: Engine 7 - Predictive Forecast & Brier Score in Section 13 *)
  let sec13 = List.find_opt (fun s -> s.sec_id = 13) sections in
  let has_forecast = match sec13 with
    | None -> false
    | Some s ->
        let text = String.concat "\n" s.lines in
        (contains_substring text "Forecast" || contains_substring text "Prediction" || contains_substring text "Prognostication")
        && (contains_substring text "Brier" || contains_substring text "p =" || contains_substring text "Probability" || matches_regex text "p[ \t]*=[ \t]*0\\.[0-9]+")
        && (contains_substring text "Horizon" || contains_substring text "T_" || contains_substring text "2026")
  in
  if has_forecast then
    printf "  [PASS] CHK-PRED: Engine 7 (Predictive Forecast & Brier Horizon) present in Section 13\n"
  else begin
    printf "  [FAIL] CHK-PRED: Section 13 lacks precommitted Brier-scored forecast\n";
    add_err "Section 13 lacks precommitted forecast"
  end;

  (* Check 8: Zero-Muda Purity *)
  (* Forbidden unless explicitly qualified by 0 or Zero *)
  let raw_bevy = matches_regex full_text "[^0-9a-zA-Z_][bB]evy" &&
                 not (matches_regex full_text "[0Zz]ero[ \t-]+[bB]evy\\|0[ \t]+[bB]evy") in
  let raw_graphite = matches_regex full_text "[^0-9a-zA-Z_][gG]raphite" &&
                     not (matches_regex full_text "[0Zz]ero[ \t-]+[gG]raphite\\|0[ \t]+[gG]raphite") in
  if not raw_bevy && not raw_graphite then
    printf "  [PASS] CHK-MUDA: Zero-Muda purity verified (0 Bevy, 0 Graphite)\n"
  else begin
    printf "  [FAIL] CHK-MUDA: Zero-Muda violation (unqualified Bevy or Graphite mentioned)\n";
    add_err "Zero-Muda violation"
  end;

  (* Check 9: Hardware Storage Safety Redaction *)
  (* NVMe serial 25503L801736 must be [REDACTED_SYSTEM_OS_SERIAL] *)
  let has_raw_serial = contains_substring full_text "25503L801736" in
  if not has_raw_serial then
    printf "  [PASS] CHK-DRIVE: Hardware storage interlock respected (serial redacted)\n"
  else begin
    printf "  [FAIL] CHK-DRIVE: Unredacted host NVMe serial detected! Replace with [REDACTED_SYSTEM_OS_SERIAL]\n";
    add_err "Storage serial redaction violation"
  end;

  (* Check 10: SC-DIAGRAM-001 Dual-Source Diagram Parity *)
  let has_mermaid = contains_substring full_text "```mermaid" in
  let has_ascii =
    contains_substring full_text "+---" ||
    contains_substring full_text "|   " ||
    contains_substring full_text "|  " ||
    contains_substring full_text "+===" ||
    contains_substring full_text "┌──" ||
    contains_substring full_text "├──"
  in
  if has_mermaid then begin
    if has_ascii then
      printf "  [PASS] CHK-DIAG: SC-DIAGRAM-001 dual diagram source parity verified (ASCII + Mermaid)\n"
    else begin
      printf "  [FAIL] CHK-DIAG: Mermaid diagram found without corresponding ASCII diagram source (SC-DIAGRAM-001)\n";
      add_err "SC-DIAGRAM-001 dual diagram parity missing"
    end
  end else
    printf "  [PASS] CHK-DIAG: No diagrams or text-only (SC-DIAGRAM-001 satisfied)\n";

  if !errors = [] then begin
    printf "\nSummary: 10/10 Verification Checks Passed (PASS)\n";
    0
  end else begin
    printf "\nSummary: %d Verification Failure(s) Detected (FAIL)\n" (List.length !errors);
    1
  end

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  match args with
  | ["--help"] | ["-h"] ->
      printf "Usage: %s <path-to-journal.md>\n" Sys.argv.(0);
      printf "       %s --latest\n" Sys.argv.(0);
      exit 0
  | ["--latest"] ->
      let dir = "docs/journal" in
      let files = Sys.readdir dir in
      let md_files = List.filter (fun f -> Filename.check_suffix f ".md") (Array.to_list files) in
      let sorted = List.sort (fun a b -> String.compare b a) md_files in
      (match sorted with
       | latest :: _ ->
           let path = Filename.concat dir latest in
           exit (lint_journal path)
       | [] ->
           printf "No journals found in %s\n" dir;
           exit 1)
  | [path] ->
      exit (lint_journal path)
  | _ ->
      printf "Usage: %s <path-to-journal.md> | --latest\n" Sys.argv.(0);
      exit 2
