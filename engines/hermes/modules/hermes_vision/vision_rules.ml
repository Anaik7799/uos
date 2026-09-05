(* Forward-chaining diagnosis. See the .mli for the two laws. *)

type fact = Verdict of Vision_ontology.stage * string

type conclusion =
  | Blame of { stage : Vision_ontology.stage; because : string }
  | Cascade of { stage : Vision_ontology.stage; from_ : Vision_ontology.stage }
  | Unmeasured of Vision_ontology.stage
  | Healthy

let fact_of (o : Vision_controller.observation) =
  Verdict (o.Vision_controller.stage, Vision_controller.verdict_name o.Vision_controller.verdict)

let facts_of obs = List.map fact_of obs

let verdict_of facts s =
  List.fold_left
    (fun acc (Verdict (st, v)) -> if st = s then Some v else acc)
    None facts

(* Fired per stage, in ontology order so the result is independent of
   the order facts arrived in. *)
let fire facts s =
  let up = Vision_ontology.upstream s in
  match verdict_of facts s with
  | None -> []
  | Some "UNKNOWN" ->
      (* proves nothing in either direction: cannot be blamed, and
         cannot clear the stage below it *)
      [ Unmeasured s ]
  | Some "LIVE" -> []
  | Some "ABSENT" -> (
      if up = s then
        (* the head of the chain has no upstream to inherit from *)
        [ Blame { stage = s; because = Vision_ontology.law s } ]
      else
        match verdict_of facts up with
        (* THE CASCADE LAW. The upstream failed too, so this stage is a
           victim and blaming it sends someone to the wrong place. *)
        | Some "ABSENT" -> [ Cascade { stage = s; from_ = up } ]
        (* upstream was never measured, so we cannot tell whether this is
           a local fault or a cascade — and saying so beats guessing *)
        | Some "UNKNOWN" | None -> [ Unmeasured s ]
        | Some _ -> [ Blame { stage = s; because = Vision_ontology.law s } ])
  | Some _ -> []

let infer facts =
  match List.concat_map (fire facts) Vision_ontology.stages with
  | [] when facts <> [] -> [ Healthy ]
  | cs -> cs

(* The first blamed stage in ontology order: with the cascade law
   applied there is normally exactly one, and when there is more than
   one the earliest is the one to investigate. *)
let root_cause cs =
  List.fold_left
    (fun acc c ->
      match (acc, c) with
      | None, Blame { stage; _ } -> Some stage
      | Some a, Blame { stage; _ }
        when Vision_ontology.stage_index stage < Vision_ontology.stage_index a ->
          Some stage
      | _ -> acc)
    None cs

let render cs =
  let b = Buffer.create 512 in
  List.iter
    (fun c ->
      Buffer.add_string b
        (match c with
         | Healthy -> "  healthy: every measured stage is live\n"
         | Blame { stage; because } ->
             Printf.sprintf "  BLAME    %-8s %s\n" (Vision_ontology.stage_name stage) because
         | Cascade { stage; from_ } ->
             Printf.sprintf "  cascade  %-8s (a victim of %s, not the fault)\n"
               (Vision_ontology.stage_name stage) (Vision_ontology.stage_name from_)
         | Unmeasured s ->
             Printf.sprintf "  unknown  %-8s (not measured; neither blamed nor cleared)\n"
               (Vision_ontology.stage_name s)))
    cs;
  Buffer.contents b
