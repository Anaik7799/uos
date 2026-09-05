let rec walk dir acc =
  if not (Sys.file_exists dir) || not (Sys.is_directory dir) then acc
  else
    Sys.readdir dir |> Array.to_list
    |> List.fold_left
         (fun acc entry ->
           if entry = "_build" || entry = ".git" then acc
           else
             let path = Filename.concat dir entry in
             match Sys.is_directory path with
             | true -> walk path acc
             | false ->
                 if Filename.check_suffix path ".ml" then path :: acc else acc
             | exception Sys_error _ -> acc)
         acc

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        Some (really_input_string channel (in_channel_length channel)))
  with _ -> None

let self = "modules/hermes_ops/ops_config_gate.ml"

let observed () =
  walk "modules" []
  |> List.filter (fun path -> path <> self)
  |> List.concat_map (fun path ->
         match read_file path with
         | None -> []
         | Some body ->
             let length = String.length body in
             let found = ref [] in
             let marker = "Sys.getenv" in
             let marker_length = String.length marker in
             let rec scan index =
               if index + marker_length > length then ()
               else if String.sub body index marker_length = marker then begin
                 let opening = ref (index + marker_length) in
                 while
                   !opening < length
                   && (body.[!opening] = ' ' || body.[!opening] = '_'
                       || body.[!opening] = 'o' || body.[!opening] = 'p'
                       || body.[!opening] = 't')
                 do
                   incr opening
                 done;
                 if !opening < length && body.[!opening] = '"' then begin
                   let closing = ref (!opening + 1) in
                   while !closing < length && body.[!closing] <> '"' do
                     incr closing
                   done;
                   if !closing < length then
                     found :=
                       (String.sub body (!opening + 1)
                          (!closing - !opening - 1), path)
                       :: !found
                 end;
                 scan (index + marker_length)
               end else scan (index + 1)
             in
             scan 0;
             !found)
  |> List.sort_uniq compare

let declared_keys =
  List.map (fun (item : Ops_config.element) -> item.key) Ops_config.elements

let undeclared () =
  observed ()
  |> List.filter (fun (key, _) -> not (List.mem key declared_keys))
  |> List.sort_uniq compare

let unused () =
  let seen = List.map fst (observed ()) in
  Ops_config.elements
  |> List.filter (fun (item : Ops_config.element) ->
         item.supply = Ops_config.Environment && not (List.mem item.key seen))
  |> List.map (fun (item : Ops_config.element) -> item.key)
  |> List.sort compare

let template_drifted () =
  match read_file ".env.template" with
  | None -> Some "missing: .env.template has not been generated"
  | Some on_disk ->
      if on_disk = Ops_config.env_template () then None
      else Some "stale: run `ops config --template`"

let check () =
  let buffer = Buffer.create 2048 in
  let bad = undeclared () in
  let drift = template_drifted () in
  List.iter
    (fun (key, file) ->
      Buffer.add_string buffer
        (Printf.sprintf
           "UNDECLARED: %s read by %s — configuration outside the model\n"
           key file))
    bad;
  List.iter
    (fun key ->
      Buffer.add_string buffer
        (Printf.sprintf "declared but unread: %s\n" key))
    (unused ());
  (match drift with
   | Some reason ->
       Buffer.add_string buffer
         (Printf.sprintf "TEMPLATE DRIFT: .env.template %s\n" reason)
   | None -> ());
  Buffer.add_string buffer
    (Printf.sprintf
       "config: %d elements declared, %d read by code, %d undeclared, template %s\n"
       (List.length Ops_config.elements)
       (List.length (List.sort_uniq compare (List.map fst (observed ()))))
       (List.length bad)
       (match drift with None -> "in sync" | Some _ -> "DRIFTED"));
  (Buffer.contents buffer, if bad <> [] || drift <> None then 1 else 0)
