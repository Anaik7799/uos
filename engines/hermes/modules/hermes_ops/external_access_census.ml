type finding = { path : string; line : int; rule : string }
type rule_count = { rule : string; count : int }

let is_quoted_tag_byte = function
  | 'a' .. 'z' | '_' | '0' .. '9' -> true
  | _ -> false

let find_substring_from source ~start needle =
  let source_length = String.length source in
  let needle_length = String.length needle in
  let rec loop offset =
    if offset + needle_length > source_length then None
    else if String.sub source offset needle_length = needle then Some offset
    else loop (offset + 1)
  in
  loop start

let quoted_string_at source offset =
  let length = String.length source in
  if source.[offset] <> '{' then None
  else
    let rec tag_end cursor =
      if cursor < length && is_quoted_tag_byte source.[cursor] then tag_end (cursor + 1)
      else cursor
    in
    let delimiter_end = tag_end (offset + 1) in
    if delimiter_end >= length || source.[delimiter_end] <> '|' then None
    else
      let tag = String.sub source (offset + 1) (delimiter_end - offset - 1) in
      Some (tag, delimiter_end + 1)

let character_literal_end source offset =
  let length = String.length source in
  if source.[offset] <> '\'' || offset + 2 >= length then None
  else if source.[offset + 1] <> '\\' then
    if source.[offset + 2] = '\'' then Some (offset + 3) else None
  else
    let rec closing cursor =
      if cursor >= length then None
      else if source.[cursor] = '\'' then Some (cursor + 1)
      else closing (cursor + 1)
    in
    closing (offset + 3)

let code_only source =
  let length = String.length source in
  let output = Buffer.create length in
  let offset = ref 0 in
  let comment_depth = ref 0 in
  let in_code_string = ref false in
  let in_comment_string = ref false in
  while !offset < length do
    let byte = source.[!offset] in
    let next = if !offset + 1 < length then Some source.[!offset + 1] else None in
    if !comment_depth > 0 then begin
      if !in_comment_string then begin
        if byte = '\\' then begin
          Buffer.add_string output "  ";
          offset := min length (!offset + 2)
        end else begin
          if byte = '"' then in_comment_string := false;
          Buffer.add_char output (if byte = '\n' then '\n' else ' ');
          incr offset
        end
      end else if byte = '"' then begin
        in_comment_string := true;
        Buffer.add_char output ' ';
        incr offset
      end else if byte = '(' && next = Some '*' then begin
        incr comment_depth; Buffer.add_string output "  "; offset := !offset + 2
      end else if byte = '*' && next = Some ')' then begin
        decr comment_depth; Buffer.add_string output "  "; offset := !offset + 2
      end else begin
        Buffer.add_char output (if byte = '\n' then '\n' else ' '); incr offset
      end
    end
    else if !in_code_string then
      if byte = '\\' then offset := min length (!offset + 2)
      else begin
        if byte = '"' then in_code_string := false;
        if byte = '\n' then Buffer.add_char output '\n' else Buffer.add_char output ' ';
        incr offset
      end
    else if byte = '(' && next = Some '*' then begin
      incr comment_depth; Buffer.add_string output "  "; offset := !offset + 2
    end
    else
      match quoted_string_at source !offset with
      | Some (tag, body_start) ->
          let closing = "|" ^ tag ^ "}" in
          (match find_substring_from source ~start:body_start closing with
           | None -> invalid_arg "unterminated OCaml quoted string"
           | Some close_start ->
               for cursor = !offset to close_start + String.length closing - 1 do
                 Buffer.add_char output (if source.[cursor] = '\n' then '\n' else ' ')
               done;
               offset := close_start + String.length closing)
      | None ->
          match character_literal_end source !offset with
          | Some literal_end ->
              while !offset < literal_end do Buffer.add_char output ' '; incr offset done
          | None ->
              if byte = '"' then begin in_code_string := true; Buffer.add_char output ' ' end
              else Buffer.add_char output byte;
              incr offset
  done;
  if !comment_depth <> 0 then invalid_arg "unterminated OCaml comment";
  if !in_code_string then invalid_arg "unterminated OCaml string literal";
  Buffer.contents output

let patterns =
  [ "Sqlite3.db_open", "R31-SQLITE-DIRECT";
    "Sqlite3.exec", "R31-SQLITE-DIRECT";
    "Unix.system", "R31-SHELL-DIRECT";
    "Sys.command", "R31-SHELL-DIRECT";
    "Unix.open_process", "R31-PROCESS-DIRECT";
    "Unix.create_process", "R31-PROCESS-DIRECT";
    "Unix.socket", "R31-NETWORK-DIRECT";
    "Unix.connect", "R31-NETWORK-DIRECT";
    "Unix.getaddrinfo", "R31-NETWORK-DIRECT" ]

let line_at source offset =
  let line = ref 1 in
  for index = 0 to min offset (String.length source) - 1 do
    if source.[index] = '\n' then incr line
  done;
  !line

let findings_for (path, source) =
  match code_only source with
  | exception Invalid_argument _ ->
      [ { path; line = 1; rule = "R31-CENSUS-UNPARSABLE" } ]
  | code ->
      let findings = ref [] in
      List.iter
        (fun (needle, rule) ->
          let rec scan offset =
            match find_substring_from code ~start:offset needle with
            | None -> ()
            | Some found ->
                findings := { path; line = line_at code found; rule } :: !findings;
                scan (found + String.length needle)
          in
          scan 0)
        patterns;
      List.rev !findings

let inspect_sources sources = List.concat_map findings_for sources

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let rec source_files directory =
  Sys.readdir directory |> Array.to_list |> List.sort String.compare
  |> List.concat_map (fun entry ->
      let path = Filename.concat directory entry in
      if Sys.is_directory path then source_files path
      else match Filename.extension path with ".ml" | ".mli" -> [ path ] | _ -> [])

let controlled_owner path =
  Filename.basename path = "external_access_census.ml"

let inspect_tree ~root =
  source_files root
  |> List.filter (fun path -> not (controlled_owner path))
  |> List.map (fun path -> path, read_file path)
  |> inspect_sources

let counts_by_rule findings =
  let increment rule counts =
    let rec loop acc = function
      | [] -> List.rev ({ rule; count = 1 } :: acc)
      | item :: rest when item.rule = rule ->
          List.rev_append acc ({ item with count = item.count + 1 } :: rest)
      | item :: rest -> loop (item :: acc) rest
    in
    loop [] counts
  in
  findings
  |> List.fold_left
       (fun counts (finding : finding) -> increment finding.rule counts) []
  |> List.sort (fun left right -> String.compare left.rule right.rule)
