(** Seven-level, fail-closed parity proof tree. *)

type level = L0 | L1 | L2 | L3 | L4 | L5 | L6
type node = { id : string; level : level; parent : string option; label : string; source_anchor : string }
type evidence = { node_id : string; snapshot_digest : string; check : string; passed : bool }
type status = Unmapped | Verified

let level_of_int = function 0 -> L0 | 1 -> L1 | 2 -> L2 | 3 -> L3 | 4 -> L4 | 5 -> L5 | 6 -> L6 | _ -> invalid_arg "level"
let int_of_level = function L0 -> 0 | L1 -> 1 | L2 -> 2 | L3 -> 3 | L4 -> 4 | L5 -> 5 | L6 -> 6

let validate nodes =
  let ids = List.map (fun node -> node.id) nodes in
  if List.length ids <> List.length (List.sort_uniq String.compare ids) then Error "duplicate parity node id"
  else
    match List.find_opt (fun node -> node.id = "" || node.label = "" || node.source_anchor = "") nodes with
    | Some _ -> Error "blank parity node metadata"
    | None ->
        let find id = List.find_opt (fun node -> node.id = id) nodes in
        if List.exists (fun node -> match node.parent with
          | None -> node.level <> L0
          | Some parent -> match find parent with Some parent_node -> int_of_level node.level <> int_of_level parent_node.level + 1 | None -> true) nodes
        then Error "invalid parity hierarchy" else Ok ()

let rec status ~snapshot_digest nodes evidence id =
  match List.find_opt (fun node -> node.id = id) nodes with
  | None -> Unmapped
  | Some node ->
      let children = List.filter (fun child -> child.parent = Some id) nodes in
      if children <> [] then
        if List.for_all (fun child -> status ~snapshot_digest nodes evidence child.id = Verified) children then Verified else Unmapped
      else if node.level <> L6 then Unmapped
      else if List.exists (fun proof -> proof.node_id = id && proof.snapshot_digest = snapshot_digest && proof.passed) evidence then Verified
      else Unmapped
