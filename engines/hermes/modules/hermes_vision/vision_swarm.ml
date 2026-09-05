(* Pure preparation of vision stage requests. See the .mli: this module
   executed until the engine call was removed, and it holds no scheduler,
   process, effect or verdict now. *)

type stage_request = {
  stage : Vision_ontology.stage;
  request_id : string;
  dependencies : string list;
}

type preparation_error =
  | Stage_declarations_not_canonical of Vision_ontology.stage list

type availability =
  | Prepared of stage_request list
  | Unavailable_observed of string

let request_id_of s =
  "VISION-" ^ String.uppercase_ascii (Vision_ontology.stage_name s)

let prepare ~stages =
  (* Structural equality against the ontology's own list, which rejects
     reordering, omission, extension and duplication in one test rather
     than four partial ones. The offered declaration is carried back so a
     caller can see what it actually sent. *)
  if stages <> Vision_ontology.stages then
    Error (Stage_declarations_not_canonical stages)
  else
    let rec derive previous acc = function
      | [] -> List.rev acc
      | stage :: rest ->
          let dependencies =
            match previous with None -> [] | Some p -> [ request_id_of p ]
          in
          derive (Some stage)
            ({ stage; request_id = request_id_of stage; dependencies } :: acc)
            rest
    in
    Ok (derive None [] stages)

(* Not a stub awaiting a body: the honest current answer. The canonical
   bridge does not exist, so no preparation can become a dispatch, and
   saying so in the type is the point. *)
let execution_availability _ =
  Unavailable_observed "Run_swarm_bridge is not implemented"
