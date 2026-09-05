(* Automatic convergence: Kleene fixpoint iteration of a monotone step over the
   finite powerset lattice of intents. The satisfied set only grows within a run
   (recording evidence satisfies, never un-satisfies), so iteration reaches the
   least fixpoint reachable from the current candidate. A step that shrinks the
   set is a convergence anomaly, surfaced not hidden. Bounded by max_iterations. *)

type outcome =
  | Converged of { iterations : int; satisfied : string list }
  | Settled of { iterations : int; satisfied : string list; drift : string list }
  | Anomaly of { iteration : int; lost : string list }

let normalize xs = List.sort_uniq compare xs
let subset a b = List.for_all (fun x -> List.mem x b) a
let same a b = subset a b && subset b a

let converge ~max_iterations ~all_intents ~step initial =
  let all = normalize all_intents in
  let rec loop iteration current =
    if subset all current then Converged { iterations = iteration; satisfied = normalize current }
    else if iteration >= max_iterations then
      Settled
        { iterations = iteration; satisfied = normalize current;
          drift = List.filter (fun x -> not (List.mem x current)) all }
    else
      let next = normalize (step current) in
      (* monotonicity guard: a previously-satisfied intent must not be lost *)
      let lost = List.filter (fun x -> not (List.mem x next)) current in
      if lost <> [] then Anomaly { iteration = iteration + 1; lost }
      else if same next current then
        (* fixpoint below full satisfaction: the residual is the real work *)
        Settled
          { iterations = iteration; satisfied = current;
            drift = List.filter (fun x -> not (List.mem x current)) all }
      else loop (iteration + 1) next
  in
  loop 0 (normalize initial)

let trajectory ~max_iterations ~step initial =
  let rec loop iteration current acc =
    if iteration >= max_iterations then List.rev (current :: acc)
    else
      let next = normalize (step current) in
      if same next current then List.rev (current :: acc)
      else loop (iteration + 1) next (current :: acc)
  in
  loop 0 (normalize initial) []

let describe = function
  | Converged { iterations; satisfied } ->
      Printf.sprintf "converged in %d iterations: all %d intents satisfied" iterations
        (List.length satisfied)
  | Settled { iterations; satisfied; drift } ->
      Printf.sprintf "settled in %d iterations: %d satisfied, %d residual [%s]" iterations
        (List.length satisfied) (List.length drift) (String.concat ", " drift)
  | Anomaly { iteration; lost } ->
      Printf.sprintf "CONVERGENCE ANOMALY at iteration %d: lost [%s] (a step un-satisfied an intent)"
        iteration (String.concat ", " lost)
