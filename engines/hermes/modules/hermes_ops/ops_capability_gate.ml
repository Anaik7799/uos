let directory_names_with ~root ~required =
  match Sys.readdir root with
  | exception Sys_error _ -> []
  | entries ->
      entries |> Array.to_list
      |> List.filter (fun name ->
             Sys.file_exists (Filename.concat (Filename.concat root name) required))
      |> List.sort_uniq compare

let tracked_skill_names ~root = directory_names_with ~root ~required:"SKILL.md"

let tracked_agent_names ~root =
  match Sys.readdir root with
  | exception Sys_error _ -> []
  | entries ->
      entries |> Array.to_list
      |> List.filter (fun name -> Filename.check_suffix name ".md")
      |> List.map Filename.remove_extension |> List.sort_uniq compare

let projected_rule_ids ~path =
  let channel = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
      let rec loop acc =
        match input_line channel with
        | line ->
            let id =
              if String.length line >= 6 && String.sub line 0 4 = "## R" then
                match String.index_from_opt line 4 ' ' with
                | Some stop -> Some (String.sub line 3 (stop - 3))
                | None -> None
              else None
            in
            loop (match id with None -> acc | Some value -> value :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

let projected_rule_titles ~path =
  let channel = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
      let heading_separator = " — " in
      let separator_length = String.length heading_separator in
      let rec loop acc =
        match input_line channel with
        | line ->
            let rule =
              if String.length line >= 6 && String.sub line 0 4 = "## R" then
                match String.index_from_opt line 4 ' ' with
                | Some separator_at
                  when separator_at + separator_length <= String.length line
                       && String.sub line separator_at separator_length
                          = heading_separator ->
                    let id = String.sub line 3 (separator_at - 3) in
                    let title =
                      String.sub line (separator_at + separator_length)
                        (String.length line - separator_at - separator_length)
                    in
                    Some (id, title)
                | _ -> None
              else None
            in
            loop (match rule with None -> acc | Some value -> value :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

let validate ~root =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  let ids =
    List.map (fun (declaration : Ops_capability.declaration) -> declaration.id)
      Ops_capability.all
  in
  if ids = [] then add "registry is empty";
  if List.length ids <> List.length (List.sort_uniq compare ids) then
    add "declaration ids are not unique";
  List.iter
    (fun (declaration : Ops_capability.declaration) ->
      let expected_prefix = Ops_capability.string_of_kind declaration.kind ^ "." in
      if not
           (String.length declaration.id > String.length expected_prefix
           && String.sub declaration.id 0 (String.length expected_prefix)
              = expected_prefix)
      then add (declaration.id ^ ": id prefix does not match kind");
      if String.trim declaration.purpose = ""
         || String.trim declaration.authority = ""
         || String.trim declaration.owner = ""
      then add (declaration.id ^ ": missing purpose, authority, or owner");
      List.iter
        (fun dependency ->
          if not (List.mem dependency ids) then
            add (declaration.id ^ ": unknown dependency " ^ dependency))
        declaration.dependencies;
      (match declaration.implementation with
      | Ops_capability.Judgment_only reason when String.trim reason = "" ->
          add (declaration.id ^ ": empty judgment reason")
      | Ops_capability.Judgment_only _ -> ()
      | Ops_capability.Command command ->
          if String.trim command = "" || declaration.path = [] then
            add (declaration.id ^ ": command or path is empty");
          let surfaces =
            List.map fst declaration.surfaces |> List.sort_uniq compare
          in
          if
            surfaces
            <> List.sort compare
                 [ Ops_capability.Ocaml_api; Ops_capability.Cli;
                   Ops_capability.Mcp; Ops_capability.Zenoh ]
          then add (declaration.id ^ ": four-surface mapping is incomplete"));
      List.iter
        (fun projection ->
          if not (Sys.file_exists (Filename.concat root projection)) then
            add (declaration.id ^ ": missing projection " ^ projection))
        declaration.projections)
    Ops_capability.all;
  if
    tracked_skill_names ~root:(Filename.concat root ".claude/skills")
    <> (Ops_capability.all
       |> List.filter_map (fun (declaration : Ops_capability.declaration) ->
              match declaration.kind with
              | Ops_capability.Skill ->
                  Some
                    (String.sub declaration.id 6 (String.length declaration.id - 6))
              | _ -> None)
       |> List.sort compare)
  then add "tracked skill projection differs from OCaml authority";
  if
    tracked_agent_names ~root:(Filename.concat root ".claude/agents")
    <> (Ops_capability.all
       |> List.filter_map (fun (declaration : Ops_capability.declaration) ->
              match declaration.kind with
              | Ops_capability.Agent ->
                  Some
                    (String.sub declaration.id 6 (String.length declaration.id - 6))
              | _ -> None)
       |> List.sort compare)
  then add "tracked agent projection differs from OCaml authority";
  let mandatory_rules = Filename.concat root "docs/hermes/mandatory-rules.md" in
  if projected_rule_ids ~path:mandatory_rules <> Ops_capability.rule_ids () then
    add "mandatory-rules projection differs from OCaml authority";
  if projected_rule_titles ~path:mandatory_rules <> Ops_capability.rule_titles then
    add "mandatory-rules title projection differs from OCaml authority";
  List.rev !errors
