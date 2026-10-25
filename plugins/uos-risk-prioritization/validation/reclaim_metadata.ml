(* SC-RISK-PRIORITY-001 / OPT-E: Bounded read-only metadata observation for expired task reconciliation.
   Evaluates NO ranking, NO first-eligible, and NO tie/sensitivity rules.
   Confined to metadata validation and Live_plan exact-set snapshot observation.
   Reuses Checker.reclaim_set_projection preconditions verbatim.
   Grants authority=NONE, runtime_admission=NOT_GRANTED, selection=NOT_EVALUATED. *)

open Priority
open Record

type binding = {
  task_id: string;
  worker: string;
  previous_attempt: int;
  previous_lease_until_ns: int64;
  expected_new_attempt: int;
}

let valid_charset s =
  let len = String.length s in
  len >= 1 && len <= 200 &&
  String.for_all (fun c ->
    (c >= 'A' && c <= 'Z') ||
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c = '-' || c = '_' || c = '/' || c = '.'
  ) s

(* Strict single schema parser:
   Payload must be a JSON object containing exactly {"plan_id", "bindings"}.
   Each binding must contain exactly {"task_id", "worker", "previous_attempt", "previous_lease_until_ns", "expected_new_attempt"}.
   No alias keys and no file-path fallback allowed. *)
let parse_bindings ?now_ns raw =
  let trimmed = String.trim raw in
  require (String.length trimmed > 0) "reclaim bindings payload cannot be empty";
  let v =
    try Bounded.json_text trimmed
    with Invalid msg -> raise (Invalid msg)
    | e -> raise (Invalid ("malformed JSON in bindings: " ^ Printexc.to_string e))
  in
  unique v;
  let fields =
    match v with
    | `Assoc fs -> fs
    | _ -> raise (Invalid "reclaim payload must be a JSON object with plan_id and bindings")
  in
  let keys = List.map fst fields |> List.sort String.compare in
  require (keys = ["bindings"; "plan_id"])
    "reclaim payload must contain exactly {plan_id, bindings} with no unknown or alias fields";
  let plan_id =
    match List.assoc "plan_id" fields with
    | `String s -> s
    | _ -> raise (Invalid "plan_id must be a string")
  in
  require (valid_charset plan_id) "invalid plan_id characters; must match [A-Za-z0-9-_/.]";
  let items =
    match List.assoc "bindings" fields with
    | `List is -> is
    | _ -> raise (Invalid "bindings must be a JSON array")
  in
  require (items <> []) "reclaim bindings list cannot be empty";
  require (List.length items <= 1000) "reclaim bindings list exceeds bound (1..1000)";
  let bindings = List.map (fun item ->
    unique item;
    let item_fields =
      match item with
      | `Assoc fs -> fs
      | _ -> raise (Invalid "reclaim binding must be a JSON object")
    in
    let item_keys = List.map fst item_fields |> List.sort String.compare in
    require (item_keys = ["expected_new_attempt"; "previous_attempt"; "previous_lease_until_ns"; "task_id"; "worker"])
      "reclaim binding must contain exactly {task_id, worker, previous_attempt, previous_lease_until_ns, expected_new_attempt} with no alias or unknown fields";
    let task_id =
      match List.assoc "task_id" item_fields with
      | `String s -> s
      | _ -> raise (Invalid "task_id must be a string")
    in
    require (valid_charset task_id) "invalid task_id characters; must match [A-Za-z0-9-_/.]";
    let worker =
      match List.assoc "worker" item_fields with
      | `String s -> s
      | _ -> raise (Invalid "worker must be a string")
    in
    require (valid_charset worker) "invalid worker characters; must match [A-Za-z0-9-_/.]";
    let previous_attempt =
      match List.assoc "previous_attempt" item_fields with
      | `Int n -> n
      | _ -> raise (Invalid "previous_attempt must be an integer")
    in
    require (previous_attempt >= 1 && previous_attempt < 1000000)
      "invalid previous_attempt; must be between 1 and 999999";
    let lease_val = List.assoc "previous_lease_until_ns" item_fields in
    let lease_str =
      match lease_val with
      | `String s -> s
      | `Int _ | `Float _ -> raise (Invalid "previous_lease_until_ns must be a decimal string, not a number")
      | _ -> raise (Invalid "previous_lease_until_ns must be a decimal string")
    in
    require (String.length lease_str > 0 && String.length lease_str <= 20) "invalid previous_lease_until_ns length";
    require (String.for_all (fun c -> c >= '0' && c <= '9') lease_str)
      "previous_lease_until_ns must be decimal digits";
    let previous_lease_until_ns =
      try
        let l = Int64.of_string lease_str in
        require (l > 0L) "previous_lease_until_ns must be positive";
        l
      with _ -> raise (Invalid "previous_lease_until_ns overflow or non-decimal")
    in
    Option.iter (fun ns ->
      require (previous_lease_until_ns <= ns)
        "previous_lease_until_ns is in the future; task is not expired") now_ns;
    let expected_new_attempt =
      match List.assoc "expected_new_attempt" item_fields with
      | `Int n ->
          require (n = previous_attempt + 1) "expected_new_attempt must equal previous_attempt + 1";
          n
      | _ -> raise (Invalid "expected_new_attempt must be an integer")
    in
    { task_id; worker; previous_attempt; previous_lease_until_ns; expected_new_attempt }
  ) items in
  let ids = List.map (fun b -> b.task_id) bindings in
  require (List.length ids = List.length (List.sort_uniq String.compare ids))
    "reclaim bindings contain duplicate task IDs";
  (plan_id, bindings)

(* Internal observation logic.
   NOTE on test-only parameters:
   ?root, ?dbpath, ?now_ns, ?after_read, ?clock_delay_s are strictly test-only hooks
   for in-process adversarial testing (adversarial.ml) and are completely inaccessible
   from the command-line interface. The CLI verb risk-priority-check --reclaim-metadata-observe
   only exposes portfolio path and raw bindings JSON string. *)
let observe_internal ?root ?dbpath ?now_ns ?after_read ?clock_delay_s ~portfolio_path ~raw_bindings () =
  let timer = Mtime_clock.counter () in
  let wall_start = Unix.gettimeofday () in
  let root = match root with Some r -> r | None -> Unix.realpath "." in
  let dbpath = match dbpath with Some p -> p | None -> Filename.concat root "var/sa-plan/uos.sqlite3" in

  (* 1. Sample beginning host clock *)
  let clock_start = Host_clock.observe () in
  let now_str = Record.now_utc () in
  let actual_now_ns = match now_ns with
    | Some ns -> ns
    | None -> Int64.add (Int64.of_float (ceil (Unix.gettimeofday () *. 1e9))) 1024L
  in

  (* 2. Parse and validate bindings structure using single strict schema *)
  let plan_id, bindings = parse_bindings ~now_ns:actual_now_ns raw_bindings in

  (* 3. Read and validate portfolio records before *)
  let raw_portfolio_before = Bounded.read portfolio_path in
  let portfolio_digest_before = Bounded.sha256 raw_portfolio_before in
  let portfolio_json = Bounded.json_text raw_portfolio_before in
  unique portfolio_json;
  let portfolio_items =
    match portfolio_json with
    | `List rs -> rs
    | _ -> raise (Invalid "portfolio must be a JSON array")
  in
  require (portfolio_items <> []) "portfolio cannot be empty";
  require (List.length portfolio_items <= 1000) "portfolio exceeds 1000 records bound";
  let s = Record.schema () in
  let checked_records = List.map (Record.check_record s) portfolio_items in
  let portfolio_task_ids = List.map (Record.text "task_id") checked_records in
  require (List.length portfolio_task_ids = List.length (List.sort_uniq String.compare portfolio_task_ids))
    "portfolio contains duplicate task IDs";
  let portfolio_plan_id = Record.text "plan_id" (List.hd checked_records) in
  List.iter (fun r ->
    require (Record.text "plan_id" r = portfolio_plan_id) "portfolio contains multiple plan_ids"
  ) checked_records;
  require (plan_id = portfolio_plan_id) "bindings plan_id does not match portfolio plan_id";

  (* 4. Read Live_plan snapshot before and enforce exact-set equality via Checker.reclaim_set_projection *)
  let safe_live_read path plan =
    require (try (Unix.lstat path).Unix.st_kind = Unix.S_REG with _ -> false)
      "Sa-plan database must exist as a regular file";
    try Live_plan.read ~path ~plan
    with
    | Sqlite3.Error msg -> raise (Invalid ("Sa-plan query unavailable/schema incompatible: " ^ msg))
    | Unix.Unix_error (Unix.ENOENT, _, _) -> raise (Invalid "Sa-plan database must exist as a regular file")
  in
  let live_before = safe_live_read dbpath plan_id in
  let digest_before = Live_plan.digest live_before in

  (* 5. REUSE EXACT Checker.reclaim_set_projection preconditions verbatim.
        Enforces:
        - exact-set equality (binding_ids = expired_executing_ids)
        - exact same-worker attempt and expired lease
        - completed = None and not result_present (reclaim_matches)
        - portfolio declares task_state=executing and actor=worker
        Raises Invalid on any deviation. *)
  let tuple_bindings = List.map (fun b ->
    (b.task_id, b.worker, b.previous_attempt, b.previous_lease_until_ns)
  ) bindings in
  let projected_portfolio = Checker.reclaim_set_projection ~now_ns:actual_now_ns tuple_bindings checked_records live_before in
  ignore projected_portfolio;

  (* Optional hook to simulate mutation between before and after reads for NC-16 *)
  Option.iter (fun f -> f ()) after_read;

  (* Optional hook to test clock delay / timeout falsifier for META-03 *)
  Option.iter (fun delay -> Unix.sleepf delay) clock_delay_s;

  (* 6. Read Live_plan snapshot after and enforce digest stability *)
  let live_after = safe_live_read dbpath plan_id in
  let digest_after = Live_plan.digest live_after in
  require (digest_before = digest_after)
    "plan mutated during observation window; digest mismatch";

  (* 7. Read portfolio file after and verify raw bytes and digest stability *)
  let raw_portfolio_after = Bounded.read portfolio_path in
  let portfolio_digest_after = Bounded.sha256 raw_portfolio_after in
  require (raw_portfolio_before = raw_portfolio_after && portfolio_digest_before = portfolio_digest_after)
    "portfolio file mutated during observation window; raw bytes mismatch";

  (* 8. Sample ending host clock *)
  let clock_end = Host_clock.observe () in
  let ended_str = Record.now_utc () in

  (* 9. Construct receipt JSON with explicit authority=NONE, runtime_admission=NOT_GRANTED, selection=NOT_EVALUATED *)
  let receipt = `Assoc [
    "status", `String "METADATA_OBSERVATION_PASS";
    "authority", `String "NONE";
    "runtime_admission", `String "NOT_GRANTED";
    "selection", `String "NOT_EVALUATED";
    "selection_reason", `String "Reclaim metadata observation only; does not evaluate dispatch selection or work priority.";
    "plan_id", `String plan_id;
    "observed_at", `String now_str;
    "completed_at", `String ended_str;
    "elapsed_monotonic_seconds", `Float 0.0; (* updated after render *)
    "clock_start", Host_clock.to_json clock_start;
    "clock_end", Host_clock.to_json clock_end;
    "snapshot_sha256", `String digest_before;
    "sa_plan_database", `Assoc [
      "path", `String dbpath;
      "mode", `String "READONLY";
      "query_only", `Bool true;
      "writes", `String "NONE";
      "wal_housekeeping_note", `String "SQLite reader housekeeping may touch -shm read marks per wal.html"
    ];
    "bindings_count", `Int (List.length bindings);
    "bindings", `List (List.map (fun b -> `Assoc [
      "task_id", `String b.task_id;
      "worker", `String b.worker;
      "previous_attempt", `Int b.previous_attempt;
      "previous_lease_until_ns", `String (Int64.to_string b.previous_lease_until_ns);
      "expected_new_attempt", `Int b.expected_new_attempt;
    ]) bindings);
    "limits", `List (List.map (fun s -> `String s) [
      "Reclaim metadata observation only; does not grant execution authority or work admission.";
      "Selection, rank, and work priority were NOT evaluated.";
      "Observation is not atomic with a later Sa-plan task claim; recheck authority and fencing then.";
      "Snapshot is confined to one complete plan; no global optimum is asserted."
    ])
  ] in

  (* 10. Render receipt and bound whole-operation duration including clock reads and serialization *)
  let out_initial = Yojson.Basic.pretty_to_string receipt in
  require (String.length out_initial <= 262144) "output exceeds 262144 bytes bound";
  let elapsed = Mtime.Span.to_float_ns (Mtime_clock.count timer) /. 1e9 in
  Host_clock.consistent ~wall_start ~elapsed ~wall_end:(Unix.gettimeofday ());
  require (elapsed <= 5.0) "observation exceeded 5000ms deadline";
  let final_receipt = match receipt with
    | `Assoc kvs ->
        `Assoc (List.map (fun (k, v) -> if k = "elapsed_monotonic_seconds" then (k, `Float elapsed) else (k, v)) kvs)
    | other -> other
  in
  let final_out = Yojson.Basic.pretty_to_string final_receipt in
  (final_receipt, final_out)

let observe ?root ?dbpath ?now_ns ?after_read ?clock_delay_s ~portfolio_path ~raw_bindings () =
  let receipt, _ = observe_internal ?root ?dbpath ?now_ns ?after_read ?clock_delay_s ~portfolio_path ~raw_bindings () in
  receipt

let run ?root ?dbpath ~portfolio_path ~raw_bindings () =
  let with_timeout seconds f =
    let old_handler = Sys.signal Sys.sigalrm (Sys.Signal_handle (fun _ ->
      raise (Invalid "observation exceeded 5000ms deadline"))) in
    ignore (Unix.alarm seconds);
    Fun.protect
      ~finally:(fun () ->
        ignore (Unix.alarm 0);
        Sys.set_signal Sys.sigalrm old_handler)
      f
  in
  with_timeout 5 (fun () ->
    let _, out = observe_internal ?root ?dbpath ~portfolio_path ~raw_bindings () in
    print_endline out
  )
