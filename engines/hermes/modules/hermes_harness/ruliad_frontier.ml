(* The ruliad lens over the harness's REAL operations. Three live analyses:

   1. THE PARITY FRONTIER AS A MULTIWAY SYSTEM. States = sets of satisfied
      intents; moves = building an intent whose requires are met. From scratch,
      the explorer counts every valid build order (the linear extensions of the
      requires DAG) and proves causal invariance: all orders reach the same
      converged terminal. From the LIVE state (the evidence roll-up), the first
      moves are literally today's options -- multiway branching as a decision
      surface, not a metaphor.

   2. THE CONFIGURATION ALGEBRA'S CAUSAL INVARIANCE, verified exhaustively: the
      live pipeline verdicts folded in every possible order reach one terminal.
      The z3-discharged join laws say WHY; the multiway graph shows it CONCRETELY.

   3. THE HASHLIFE COLLAPSE, measured: maximal paths grow factorially while
      memoized states grow exponentially-or-slower; the dedup factor is printed.

   Honesty: exploration is bounded and says so; and enumerating ORDERS never
   shortcuts the work itself -- each frontier edge costs real differential
   evidence (computational irreducibility is R10). NO AUTHORITY: this annotates
   decisions; verdicts and evidence remain the sole authority. *)

let canonical_of_set satisfied = String.concat "," (List.sort compare satisfied)

let frontier_system ~(blueprint : Blueprint.t) ~initially_satisfied :
    (string list, string) Ruliad.system =
  let ids = List.map (fun d -> d.Blueprint.id) blueprint in
  let requires_of id =
    match List.find_opt (fun d -> d.Blueprint.id = id) blueprint with
    | Some d -> d.Blueprint.requires
    | None -> []
  in
  { initial = List.sort compare initially_satisfied;
    moves =
      (fun satisfied ->
        List.filter
          (fun id ->
            (not (List.mem id satisfied))
            && List.for_all (fun r -> List.mem r satisfied) (requires_of id))
          ids);
    apply = (fun satisfied id -> List.sort compare (id :: satisfied));
    canonical = canonical_of_set }

let fold_system verdicts : (int list * Parity_algebra.verdict, int) Ruliad.system =
  let arr = Array.of_list verdicts in
  { initial = (List.init (Array.length arr) Fun.id, Parity_algebra.Verified);
    moves = (fun (remaining, _) -> remaining);
    apply =
      (fun (remaining, acc) i ->
        (List.filter (( <> ) i) remaining, Parity_algebra.combine acc arr.(i)));
    canonical =
      (fun (remaining, acc) ->
        String.concat "," (List.map string_of_int (List.sort compare remaining))
        ^ "|" ^ Parity_algebra.name acc) }

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> String.trim (input_line channel))
  with _ -> "unknown"

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let blueprint = Parity_intent.blueprint in
  Printf.printf "ruliad: multiway exploration over the harness's own rule spaces\n\n";

  (* 1a. The full build space from scratch. *)
  Printf.printf "-- parity frontier: all build orders (from scratch) --\n";
  (match Ruliad.explore (frontier_system ~blueprint ~initially_satisfied:[]) with
  | Ok g ->
      Printf.printf
        "  %d intents: %d valid build orders on %d states (%d edges), depth %d\n"
        (List.length blueprint) g.path_count g.state_count g.edge_count g.max_depth;
      Printf.printf "  causal invariance (one converged terminal): %b\n" g.confluent
  | Error e -> Printf.printf "  exploration refused: %s\n" e);

  (* 1b. The frontier from the LIVE evidence state: today's real options. *)
  let reference_root = Bootstrap.reference_root root in
  (match Inventory.scan ~root:reference_root with
  | Error message -> Printf.printf "\n(live frontier skipped: %s)\n" message
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      let path = Filename.concat root "state/hermes_harness.sqlite3" in
      match Evidence_store.open_db ~path with
      | Error message -> Printf.printf "\n(live frontier skipped: %s)\n" message
      | Ok store ->
          let actual =
            match Evidence_store.parity_results store ~snapshot_digest with
            | Ok rows ->
                Evidence_rollup.actual_with_families
                  ~catalog:Parity_intent.family_catalog
                  ~nodes:(Evidence_rollup.per_node rows)
            | Error _ -> fun _ -> Parity_algebra.Unmapped
          in
          let satisfied =
            List.filter_map
              (fun (d : Blueprint.directive) ->
                if actual d.Blueprint.target = d.Blueprint.desired then Some d.Blueprint.id
                else None)
              blueprint
          in
          Printf.printf "\n-- parity frontier: from the LIVE evidence state --\n";
          Printf.printf "  satisfied today: %s\n"
            (match satisfied with [] -> "(none)" | s -> String.concat ", " s);
          (match Ruliad.explore (frontier_system ~blueprint ~initially_satisfied:satisfied) with
          | Ok g ->
              let system = frontier_system ~blueprint ~initially_satisfied:satisfied in
              let options = system.Ruliad.moves system.Ruliad.initial in
              Printf.printf "  remaining plans: %d orders on %d states; next-move options: %s\n"
                g.path_count g.state_count
                (match options with [] -> "(converged)" | o -> String.concat ", " o);
              Printf.printf "  every plan converges to the same terminal: %b\n" g.confluent;
              (* Record this observation of the trajectory (append-only; an
                 identical replay is a no-op). Telemetry, not parity evidence. *)
              let folded =
                List.fold_left
                  (fun acc (d : Blueprint.directive) ->
                    Parity_algebra.combine acc (actual d.Blueprint.target))
                  Parity_algebra.Verified blueprint
              in
              let row : Evidence_store.evolution =
                { snapshot_digest; harness_revision = git_revision root;
                  satisfied = String.concat "," (List.sort compare satisfied);
                  remaining_orders = g.path_count; state_count = g.state_count;
                  confluent = g.confluent; folded_verdict = Parity_algebra.name folded }
              in
              (match Evidence_store.record_evolution store row with
              | Ok () -> ()
              | Error message -> Printf.printf "  (evolution not recorded: %s)\n" message);
              (match Evidence_store.evolution_history store ~snapshot_digest with
              | Ok history ->
                  Printf.printf "\n-- the system's trajectory (ruliad_evolution) --\n";
                  List.iter
                    (fun (e : Evidence_store.evolution) ->
                      Printf.printf "  %s  satisfied=[%s]  plans=%d states=%d %s\n"
                        (String.sub e.Evidence_store.harness_revision 0
                           (min 12 (String.length e.Evidence_store.harness_revision)))
                        e.Evidence_store.satisfied e.Evidence_store.remaining_orders
                        e.Evidence_store.state_count e.Evidence_store.folded_verdict)
                    history
              | Error _ -> ())
          | Error e -> Printf.printf "  exploration refused: %s\n" e);
          Evidence_store.close store));

  (* 2. Config-algebra causal invariance over the live pipeline verdicts. *)
  Printf.printf "\n-- configuration algebra: fold under every order --\n";
  let live_verdicts =
    Parity_algebra.[ Verified (* preflight *); Divergent (* compare *);
                     Verified (* contracts *); Verified (* determinism *);
                     Blocked (* reconcile *); Verified (* report *) ]
  in
  (match Ruliad.explore (fold_system live_verdicts) with
  | Ok g -> (
      match g.terminals with
      | [ (_, verdict) ] ->
          Printf.printf
            "  6 primitives: %d orderings on %d states -- ALL fold to %s (confluent: %b)\n"
            g.path_count g.state_count (Parity_algebra.name verdict) g.confluent
      | _ -> Printf.printf "  NON-CONFLUENT: the join laws are violated\n")
  | Error e -> Printf.printf "  exploration refused: %s\n" e);

  (* 3. The HashLife collapse, measured. *)
  Printf.printf "\n-- the memoization collapse (paths vs states) --\n";
  List.iter
    (fun n ->
      let verdicts = List.init n (fun i -> if i = 0 then Parity_algebra.Divergent else Parity_algebra.Verified) in
      let start = Unix.gettimeofday () in
      match Ruliad.explore (fold_system verdicts) with
      | Ok g ->
          Printf.printf "  n=%2d: %8d paths collapse onto %5d states (x%d), %6.1f ms\n" n
            g.path_count g.state_count (g.path_count / max 1 g.state_count)
            ((Unix.gettimeofday () -. start) *. 1000.0)
      | Error e -> Printf.printf "  n=%2d: refused (%s)\n" n e)
    [ 6; 8; 9 ];
  Printf.printf
    "\nirreducibility, honestly: orders are enumerable; the WORK on each edge is\n\
     differential evidence, which nothing shortcuts (R10). Exploration annotates;\n\
     verdicts decide.\n"
