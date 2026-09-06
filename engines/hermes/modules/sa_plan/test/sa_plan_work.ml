open Bos

type kind = Plans | Tasks | Jobs | Oban | Temporal
type disposition = Written | Unchanged

type materialization = {
  directory : string;
  artifact : string;
  manifest : string;
  disposition : disposition;
}

let ( let* ) value next = Result.bind value next

let kind_name = function
  | Plans -> "plans"
  | Tasks -> "tasks"
  | Jobs -> "jobs"
  | Oban -> "oban"
  | Temporal -> "temporal"

let kind_of_string = function
  | "plans" | "plan" -> Ok Plans
  | "tasks" | "task" -> Ok Tasks
  | "jobs" | "job" -> Ok Jobs
  | "oban" -> Ok Oban
  | "temporal" | "workflows" | "workflow" -> Ok Temporal
  | value -> Error (`Msg ("unknown work kind: " ^ value))

let path_for ~root ~kind ~name =
  if String.equal root "" then Error (`Msg "work root must be non-empty")
  else
    let relative = Sa_plan.Name.to_relpath name in
    if not (Filename.is_relative relative) then
      Error (`Msg "hierarchical name unexpectedly produced an absolute path")
    else
      let base = Filename.concat root (kind_name kind) in
      let path = Filename.concat base relative in
      let prefix = base ^ Filename.dir_sep in
      if String.starts_with ~prefix path then Ok path
      else Error (`Msg "work path escaped its kind root")

let write_if_changed path content =
  let target = Fpath.v path in
  let* existing =
    if Sys.file_exists path then OS.File.read target |> Result.map Option.some
    else Ok None
  in
  match existing with
  | Some value when String.equal value content -> Ok Unchanged
  | _ ->
      let* _ = OS.Dir.create (Fpath.parent target) in
      let temporary = Fpath.v (path ^ ".tmp") in
      let* () = OS.File.write temporary content in
      let* () = OS.Path.move ~force:true temporary target in
      Ok Written

let manifest_text ~kind ~id ~name ~title ~artifact =
  `Assoc
    [ "schema_version", `Int 1;
      "authority", `String "Sa_plan.Store";
      "kind", `String (kind_name kind);
      "id", `String id;
      "name", `String (Sa_plan.Name.to_string name);
      "title", `String title;
      "artifact", `String (Filename.basename artifact) ]
  |> Yojson.Safe.pretty_to_string
  |> fun text -> text ^ "\n"

let materialize ~root ~kind ~id ~name ~title ~content =
  if String.equal id "" then Error (`Msg "work entity ID must be non-empty")
  else if String.equal title "" then Error (`Msg "work entity title must be non-empty")
  else
    let* directory = path_for ~root ~kind ~name in
    let artifact = Filename.concat directory "artifact.md" in
    let manifest = Filename.concat directory "manifest.json" in
    let* artifact_disposition = write_if_changed artifact content in
    let* manifest_disposition =
      write_if_changed manifest
        (manifest_text ~kind ~id ~name ~title ~artifact)
    in
    let disposition =
      match artifact_disposition, manifest_disposition with
      | Unchanged, Unchanged -> Unchanged
      | _ -> Written
    in
    Ok { directory; artifact; manifest; disposition }
