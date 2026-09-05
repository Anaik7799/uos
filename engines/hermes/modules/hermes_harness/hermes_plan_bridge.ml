let usage () =
  prerr_endline
    "usage: hermes_plan_bridge --path PATH --snapshot DIGEST --feature ID... \
     [--capability KEY[=DEP,DEP]...]";
  exit 64

(* "family.slice=dep1,dep2" -> ("family.slice", ["dep1"; "dep2"]) *)
let parse_capability value =
  match String.index_opt value '=' with
  | None -> (value, [])
  | Some index ->
      let key = String.sub value 0 index in
      let encoded = String.sub value (index + 1) (String.length value - index - 1) in
      let dependencies =
        String.split_on_char ',' encoded |> List.filter (fun item -> String.trim item <> "")
      in
      (key, dependencies)

let parse arguments =
  let rec loop path snapshot features capabilities = function
    | [] ->
        (match path, snapshot, List.rev features with
        | Some path, Some snapshot, (_ :: _ as features) ->
            (path, snapshot, features, List.rev capabilities)
        | _ -> usage ())
    | "--path" :: value :: rest -> loop (Some value) snapshot features capabilities rest
    | "--snapshot" :: value :: rest -> loop path (Some value) features capabilities rest
    | "--feature" :: value :: rest -> loop path snapshot (value :: features) capabilities rest
    | "--capability" :: value :: rest ->
        loop path snapshot features (parse_capability value :: capabilities) rest
    | _ -> usage ()
  in
  loop None None [] [] arguments

let () =
  let path, snapshot_digest, features, capabilities = parse (List.tl (Array.to_list Sys.argv)) in
  match Hermes_plan.materialize ~path ~snapshot_digest ~features ~capabilities with
  | Error message -> prerr_endline message; exit 1
  | Ok plan ->
      Printf.printf "plan_id: %s\ntask_count: %d\ncapability_task_count: %d\n" plan.plan_id
        (List.length plan.task_ids)
        (List.length plan.capability_task_ids)
