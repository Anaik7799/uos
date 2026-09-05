type entry = {
  path : string;
  domain : string;
  digest : string;
}

type domain_summary = {
  domain : string;
  file_count : int;
  digest : string;
}

let excluded_directories =
  [ ".git"; "__pycache__"; "node_modules"; "target"; "build"; ".venv" ]

let sha256_file path =
  match open_in_bin path with
  | exception exn -> Error (Printexc.to_string exn)
  | channel ->
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () ->
          let buffer = Bytes.create 65_536 in
          let rec consume context =
            match input channel buffer 0 (Bytes.length buffer) with
            | 0 ->
                Ok
                  (Digestif.SHA256.get context
                   |> Digestif.SHA256.to_hex)
            | count ->
                consume
                  (Digestif.SHA256.feed_bytes context buffer ~off:0 ~len:count)
            | exception exn -> Error (Printexc.to_string exn)
          in
          consume (Digestif.SHA256.init ()))

let sha256_string value =
  Ok
    (value |> Digestif.SHA256.digest_string
     |> Digestif.SHA256.to_hex)

let first_component path =
  match String.split_on_char '/' path with
  | first :: _ :: _ -> first
  | [ _ ] | [] -> "root"

let rec scan_directory ~root ~relative =
  let directory = if relative = "" then root else Filename.concat root relative in
  let names = Array.to_list (Sys.readdir directory) |> List.sort String.compare in
  List.fold_left
    (fun result name ->
      match result with
      | Error _ -> result
      | Ok entries ->
          let child_relative = if relative = "" then name else relative ^ "/" ^ name in
          let child = Filename.concat root child_relative in
          match (Unix.lstat child).Unix.st_kind with
          | Unix.S_LNK -> Ok entries
          | Unix.S_DIR ->
              if List.mem name excluded_directories then Ok entries
              else
                (match scan_directory ~root ~relative:child_relative with
                | Error _ as error -> error
                | Ok nested -> Ok (entries @ nested))
          | Unix.S_REG ->
              (match sha256_file child with
              | Error _ as error -> error
              | Ok digest ->
                  Ok ({ path = child_relative; domain = first_component child_relative; digest } :: entries))
          | _ -> Ok entries)
    (Ok []) names

let scan ~root =
  try
    if not (Sys.file_exists root) then Error ("reference root does not exist: " ^ root)
    else
      match scan_directory ~root ~relative:"" with
      | Error _ as error -> error
      | Ok entries -> Ok (List.sort (fun left right -> String.compare left.path right.path) entries)
  with Sys_error message | Unix.Unix_error (_, _, message) -> Error message

let snapshot_digest entries =
  let value =
    entries
    |> List.map (fun entry -> entry.path ^ "\\000" ^ entry.domain ^ "\\000" ^ entry.digest ^ "\\n")
    |> String.concat ""
  in
  match sha256_string value with Ok digest -> digest | Error message -> failwith message

let summarize (entries : entry list) =
  let domains =
    entries |> List.map (fun (entry : entry) -> entry.domain) |> List.sort_uniq String.compare
  in
  List.map
    (fun domain ->
      let members = List.filter (fun (entry : entry) -> String.equal entry.domain domain) entries in
      let value =
        members
        |> List.map (fun (entry : entry) -> entry.path ^ "\\000" ^ entry.digest ^ "\\n")
        |> String.concat ""
      in
      { domain; file_count = List.length members; digest = snapshot_digest [ { path = domain; domain; digest = (match sha256_string value with Ok digest -> digest | Error message -> failwith message) } ] })
    domains
