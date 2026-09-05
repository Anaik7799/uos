(* Multiway exploration of the diagnosis space. See the .mli. *)

type state = string list

let verdicts = [ "LIVE"; "ABSENT"; "UNKNOWN" ]

(* the full rule-space: every assignment over the six stages *)
let states () =
  let n = List.length Vision_ontology.stages in
  let rec build k =
    if k = 0 then [ [] ]
    else List.concat_map (fun rest -> List.map (fun v -> v :: rest) verdicts) (build (k - 1))
  in
  build n

let facts_of_state st =
  List.map2 (fun s v -> Vision_rules.Verdict (s, v)) Vision_ontology.stages st

(* a few orderings per state: reversed and rotated. Exhaustive
   permutation of six facts is 720 per state and 525k overall, which
   buys nothing over these — the rules fold over stages in ontology
   order, so any reordering exercises the same fold. *)
let orderings fs =
  let rot = match fs with [] -> [] | x :: r -> r @ [ x ] in
  [ fs; List.rev fs; rot; List.rev rot ]

let order_dependent () =
  List.filter
    (fun st ->
      let fs = facts_of_state st in
      let base = Vision_rules.infer fs in
      List.exists (fun o -> Vision_rules.infer o <> base) (orderings fs))
    (states ())

let blamed cs =
  List.filter_map
    (function Vision_rules.Blame { stage; _ } -> Some stage | _ -> None)
    cs

let cascade_violations () =
  List.filter
    (fun st ->
      let fs = facts_of_state st in
      List.exists
        (fun s ->
          let up = Vision_ontology.upstream s in
          up <> s && Vision_rules.verdict_of fs up = Some "ABSENT")
        (blamed (Vision_rules.infer fs)))
    (states ())

let unmeasured_blamed () =
  List.filter
    (fun st ->
      let fs = facts_of_state st in
      List.exists
        (fun s -> Vision_rules.verdict_of fs s = Some "UNKNOWN")
        (blamed (Vision_rules.infer fs)))
    (states ())

let undiagnosed () =
  List.filter (fun st -> Vision_rules.infer (facts_of_state st) = []) (states ())

let summary () =
  let all = List.length (states ()) in
  Printf.sprintf
    "ruliad: %d states explored exhaustively\n  order-dependent:    %d\n  cascade violations: \
     %d\n  unmeasured blamed:  %d\n  undiagnosed:        %d\n"
    all
    (List.length (order_dependent ()))
    (List.length (cascade_violations ()))
    (List.length (unmeasured_blamed ()))
    (List.length (undiagnosed ()))
