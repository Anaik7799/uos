(* Frozen-source and documentation artifacts for every L2 capability slice.

   An artifact records what the reference contains and where, digest-pinned to
   the frozen snapshot. Attaching one to a node is a discovery fact, never
   parity credit. *)

type link = { node_id : string; artifact_id : string; role : string }

let source_role = "reference-source"
let documentation_role = "reference-documentation"

let artifact_id ~kind anchor =
  match kind with
  | "documentation" -> "doc/" ^ anchor
  | _ -> "source/" ^ anchor

(* Directories are digested over their whole subtree so a single content digest
   pins the anchor no matter whether it names a file or a package. *)
let anchor_digest ~reference_root anchor =
  let path = Filename.concat reference_root anchor in
  if not (Sys.file_exists path) then Error ("missing frozen anchor: " ^ anchor)
  else if Sys.is_directory path then
    match Inventory.scan ~root:path with
    | Error _ as error -> error
    | Ok entries -> Ok (Inventory.snapshot_digest entries)
  else Inventory.sha256_file path

let build ~snapshot_digest ~reference_root ~git_revision =
  let digests = Hashtbl.create 256 in
  let artifacts = Hashtbl.create 256 in
  let links = ref [] in
  let add_anchor ~node_id ~kind ~role anchor =
    let id = artifact_id ~kind anchor in
    let digest_result =
      match Hashtbl.find_opt digests anchor with
      | Some digest -> Ok digest
      | None ->
          (match anchor_digest ~reference_root anchor with
          | Error _ as error -> error
          | Ok digest -> Hashtbl.replace digests anchor digest; Ok digest)
    in
    match digest_result with
    | Error _ as error -> error
    | Ok content_digest ->
        if not (Hashtbl.mem artifacts id) then
          Hashtbl.replace artifacts id
            { Evidence_store.snapshot_digest; id; kind; path = anchor; title = anchor;
              content_digest; git_revision };
        links := { node_id; artifact_id = id; role } :: !links;
        Ok ()
  in
  let result =
    List.fold_left
      (fun result (capability : Capability_catalog.capability) ->
        match result with
        | Error _ -> result
        | Ok () ->
            let node_id = Capability_catalog.node_id capability in
            let sources =
              List.fold_left
                (fun result anchor ->
                  match result with
                  | Error _ -> result
                  | Ok () -> add_anchor ~node_id ~kind:"source" ~role:source_role anchor)
                (Ok ()) capability.source_anchors
            in
            (match sources with
            | Error _ as error -> error
            | Ok () ->
                List.fold_left
                  (fun result anchor ->
                    match result with
                    | Error _ -> result
                    | Ok () ->
                        add_anchor ~node_id ~kind:"documentation" ~role:documentation_role anchor)
                  (Ok ()) capability.doc_anchors))
      (Ok ()) Capability_catalog.all
  in
  match result with
  | Error _ as error -> error
  | Ok () ->
      let artifacts =
        Hashtbl.fold (fun _ artifact accumulator -> artifact :: accumulator) artifacts []
        |> List.sort (fun (left : Evidence_store.artifact) right -> String.compare left.id right.id)
      in
      let links =
        List.sort
          (fun left right ->
            match String.compare left.node_id right.node_id with
            | 0 -> String.compare left.artifact_id right.artifact_id
            | order -> order)
          !links
      in
      Ok (artifacts, links)
