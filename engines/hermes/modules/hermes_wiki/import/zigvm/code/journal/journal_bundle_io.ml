open Bos

module Bundle = Journal_bundle_core.Journal_bundle
module Task = Domainslib.Task
module Transaction = Journal_bundle_transaction

type disposition = Written | Unchanged

type publication = {
  path : string;
  disposition : disposition;
}

let ( let* ) result next = Result.bind result next

let ensure_parent path =
  let* _created = OS.Dir.create (Fpath.parent (Fpath.v path)) in
  Ok ()

let temporary_path path content =
  path ^ "." ^ Bundle.fingerprint content ^ ".tmp"

let write_atomic path content =
  let temporary = temporary_path path content in
  let* () = ensure_parent path in
  let* () = OS.File.write (Fpath.v temporary) content in
  OS.Path.move ~force:true (Fpath.v temporary) (Fpath.v path)

let materialize_image (image : Bundle.image_artifact) =
  if Sys.file_exists image.path then Ok ()
  else
    match image.source with
    | None -> Error (`Msg ("missing durable image and source: " ^ image.path))
    | Some source when not (Sys.file_exists source) ->
        Error (`Msg ("missing image materialization source: " ^ source))
    | Some source ->
        let* content = OS.File.read (Fpath.v source) in
        write_atomic image.path content

let map_ordered ~pool_size transform values =
  let pool_size = max 1 pool_size in
  if pool_size = 1 || List.length values < 2 then List.map transform values
  else
    let pool = Task.setup_pool ~num_domains:(pool_size - 1) () in
    Fun.protect
      ~finally:(fun () -> Task.teardown_pool pool)
      (fun () ->
        Task.run pool (fun () ->
          values
          |> List.map (fun value -> Task.async pool (fun () -> transform value))
          |> List.map (Task.await pool)))

let acquire_files ~pool_size paths =
  let pool_size = max 1 pool_size in
  let read path =
    match OS.File.read (Fpath.v path) with
    | Ok content -> Ok (path, content)
    | Error (`Msg message) ->
        Error (`Msg (Printf.sprintf "read %s: %s" path message))
  in
  let results = map_ordered ~pool_size read paths in
  List.fold_left
    (fun accumulated result ->
      match accumulated, result with
      | Ok values, Ok value -> Ok (value :: values)
      | Error message, _ | _, Error message -> Error message)
    (Ok []) results
  |> Result.map List.rev

let observe_target ~content path =
  let existing =
    if Sys.file_exists path then
      OS.File.read (Fpath.v path) |> Result.map Option.some
    else Ok None
  in
  let* existing = existing in
  match existing with
  | Some current when String.equal current content ->
      Ok ({ path; disposition = Unchanged }, None)
  | _ -> Ok ({ path; disposition = Written }, Some path)

let publish ~content ~outputs =
  let* observed =
    List.fold_left
      (fun accumulated path ->
        let* values = accumulated in
        let* value = observe_target ~content path in
        Ok (value :: values))
      (Ok []) outputs
    |> Result.map List.rev
  in
  let publications = List.map fst observed in
  let changed = List.filter_map snd observed in
  match changed with
  | [] -> Ok publications
  | first :: _ ->
      let lock_path = first ^ ".fanout.lock" in
      let journal_path = first ^ ".fanout.transaction.json" in
      let content_id =
        Journal_bundle_core.Journal_bundle_digest.Content_id.of_string content
        |> Journal_bundle_core.Journal_bundle_digest.Content_id.to_string
      in
      let* () =
        Transaction.with_lock ~path:lock_path (fun () ->
          let* () = Transaction.recover ~journal_path in
          let* transaction =
            Transaction.prepare ~journal_path ~content_id ~content ~targets:changed
          in
          Transaction.commit transaction)
      in
      Ok publications

let sha256_file path =
  Journal_bundle_core.Journal_bundle_digest.sha256_file path

let disposition_name = function Written -> "written" | Unchanged -> "unchanged"
