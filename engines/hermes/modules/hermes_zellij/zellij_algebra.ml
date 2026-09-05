type observation = {
  session : Zellij_intent.session;
  command_present : bool;
  session_live : bool;
  cwd_matches : bool;
}

let make_observation ~session ~command_present ~session_live ~cwd_matches =
  { session; command_present; session_live; cwd_matches }

let session value = value.session
let command_present value = value.command_present
let session_live value = value.session_live
let cwd_matches value = value.cwd_matches

let normalize observations =
  let sorted =
    List.sort
      (fun left right ->
        Zellij_intent.compare_session left.session right.session)
      observations
  in
  let rec duplicate_names acc = function
    | left :: (right :: _ as tail) when left.session = right.session ->
        duplicate_names (Zellij_intent.session_name left.session :: acc) tail
    | _ :: tail -> duplicate_names acc tail
    | [] -> List.rev acc
  in
  match duplicate_names [] sorted with
  | [] -> Ok sorted
  | names ->
      Error
        (List.map (fun name -> "duplicate session observation: " ^ name) names)

let complete observations =
  match normalize observations with
  | Error _ -> false
  | Ok normalized ->
      List.map (fun value -> value.session) normalized
      = Zellij_intent.all_sessions
      && List.for_all
           (fun value ->
             value.command_present && value.session_live && value.cwd_matches)
           normalized

let command_session_bijection mappings =
  let expected =
    List.map
      (fun session -> (Zellij_intent.session_name session, session))
      Zellij_intent.all_sessions
  in
  let compare (left_name, left_session) (right_name, right_session) =
    let by_session = Zellij_intent.compare_session left_session right_session in
    if by_session = 0 then String.compare left_name right_name else by_session
  in
  List.sort compare mappings = expected

let ensure_session target observations =
  observations
  |> List.map (fun value ->
      if value.session = target then { value with session_live = true }
      else value)
  |> List.sort (fun left right ->
      Zellij_intent.compare_session left.session right.session)

let join left right =
  {
    session = left.session;
    command_present = left.command_present || right.command_present;
    session_live = left.session_live || right.session_live;
    cwd_matches = left.cwd_matches || right.cwd_matches;
  }

let union left right =
  match (normalize left, normalize right) with
  | Error errors, _ | _, Error errors -> Error errors
  | Ok left, Ok right ->
      let find session values =
        List.find_opt (fun value -> value.session = session) values
      in
      Zellij_intent.all_sessions
      |> List.filter_map (fun session ->
          match (find session left, find session right) with
          | Some left, Some right -> Some (join left right)
          | Some value, None | None, Some value -> Some value
          | None, None -> None)
      |> normalize
