(* The parity ledger: per-scenario priors from the receipt trajectory, and the
   surprisal of the newest observation under each scenario's OWN history.

   This is the consumer Info_math's header promised: beta_pred/surprisal
   landed "for the principled prior the ledger design wants", and this is
   that design. A verdict flip on a scenario that has never flipped in 29
   runs is a headline (~5.9 bits); the same flip on a scenario that flips
   every other run is background (~1 bit). Without the ledger every diff
   looks equally surprising and the reader re-derives normal from scratch
   each cycle.

   Emission discipline (the predictive/context-payload rules):
     - deltas against the ledger, never absolute state: steady scenarios are
       ONE number, only movers carry detail;
     - rank by surprisal, then truncate by budget, in that order — and
       disclose the truncation;
     - stable prefix, volatile tail: the block renders after the standing
       report sections so cached prefixes survive across runs;
     - a scenario with no prior transitions is NEW, reported as such, with
       no surprisal claim — no history means no prior, and inventing one
       would be a fabricated gauge. *)

type entry = {
  scenario_id : string;
  observations : int;      (* total verdicts recorded, newest included *)
  flips : int;             (* verdict changes among PRIOR consecutive pairs *)
  last_passed : bool;
  moved : bool;            (* newest verdict differs from the one before *)
  surprisal_bits : float;  (* -log2 P(newest transition | prior history) *)
}

type t = { movers : entry list; steady : int; fresh : string list }

(* Fold one scenario's chronological verdicts into an entry. [history] must be
   oldest-first and non-empty; fewer than two observations has no transition
   to score. *)
let entry_of_history scenario_id history =
  match history with
  | [] | [ _ ] -> None
  | first :: rest ->
      let observations = List.length history in
      (* Transitions among the PRIOR observations (all but the newest), then
         the newest transition scored against that prior. *)
      let rec split_last acc = function
        | [] -> (List.rev acc, None)
        | [ last ] -> (List.rev acc, Some last)
        | x :: tail -> split_last (x :: acc) tail
      in
      let prior_rest, newest = split_last [] rest in
      (match newest with
       | None -> None
       | Some newest ->
           let prior = first :: prior_rest in
           let flips, previous =
             List.fold_left
               (fun (flips, previous) verdict ->
                 ((if verdict <> previous then flips + 1 else flips), verdict))
               (0, first) prior_rest
           in
           let prior_transitions = List.length prior - 1 in
           let p_change =
             Info_math.beta_pred ~k:(float_of_int flips)
               ~n:(float_of_int prior_transitions) ~a:0.5 ~b:0.5
           in
           let moved = newest <> previous in
           let surprisal_bits =
             Info_math.surprisal (if moved then p_change else 1.0 -. p_change)
           in
           Some
             { scenario_id; observations; flips; last_passed = newest; moved;
               surprisal_bits })

(* Group the store's chronological (contract, scenario, passed) rows by
   scenario, preserving per-scenario order, then score each. Grouping is by
   first-appearance order so the result is deterministic in the input alone. *)
let assess rows =
  let order = ref [] in
  let table = Hashtbl.create 64 in
  List.iter
    (fun (_contract, scenario_id, passed) ->
      (match Hashtbl.find_opt table scenario_id with
       | None ->
           order := scenario_id :: !order;
           Hashtbl.add table scenario_id [ passed ]
       | Some history -> Hashtbl.replace table scenario_id (passed :: history)))
    rows;
  let scenario_ids = List.rev !order in
  let entries, fresh =
    List.fold_left
      (fun (entries, fresh) scenario_id ->
        let history = List.rev (Hashtbl.find table scenario_id) in
        match entry_of_history scenario_id history with
        | Some entry -> (entry :: entries, fresh)
        | None -> (entries, scenario_id :: fresh))
      ([], []) scenario_ids
  in
  let entries = List.rev entries and fresh = List.rev fresh in
  let movers =
    List.filter (fun entry -> entry.moved) entries
    |> List.sort (fun a b ->
           match compare b.surprisal_bits a.surprisal_bits with
           | 0 -> compare a.scenario_id b.scenario_id
           | order -> order)
  in
  { movers; steady = List.length entries - List.length movers; fresh }

(* Bounded, deterministic render. The budget bounds the MOVER lines — the
   ranked ones — and the remainder is disclosed, never silently dropped. *)
let render ?(budget = 10) { movers; steady; fresh } =
  let buffer = Buffer.create 512 in
  Printf.bprintf buffer "ledger: %d moved · %d steady · %d new\n"
    (List.length movers) steady (List.length fresh);
  List.iteri
    (fun index entry ->
      if index < budget then
        Printf.bprintf buffer "  %5.2fb  %-28s %s  (%d flips in %d runs)\n"
          entry.surprisal_bits entry.scenario_id
          (if entry.last_passed then "-> pass" else "-> FAIL")
          entry.flips (entry.observations - 1))
    movers;
  let hidden = List.length movers - budget in
  if hidden > 0 then Printf.bprintf buffer "  … %d more mover(s)\n" hidden;
  (match fresh with
   | [] -> ()
   | fresh ->
       let named = List.filteri (fun index _ -> index < budget) fresh in
       Printf.bprintf buffer "  new: %s%s\n" (String.concat ", " named)
         (let hidden = List.length fresh - budget in
          if hidden > 0 then Printf.sprintf " … %d more" hidden else ""));
  Buffer.contents buffer
