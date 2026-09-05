(* Record the current orientation pass into the durable store and read it
   back — durability is a read, not a return code (R22). The values written
   here are the operator's stated pass results; the tool adds only head and
   time, both read from the environment at this boundary (R4: the STORE never
   invents time; the tool's edge is where the environment is observed).

   R19: refuses unknown arguments, writes through the store's transactional
   path, exits non-zero on any refusal. *)

let store_path = "state/hermes/orientation-history.sqlite3"

let git_head () =
  try
    let channel = Unix.open_process_in "git rev-parse --short HEAD" in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> String.trim (input_line channel))
  with _ -> "unknown"

let now_utc () =
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900)
    (t.Unix.tm_mon + 1) t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let usage () =
  prerr_endline
    "orientation_snapshot: record | show\n\
    \  record <pass_id> <key=value> [<key=value> ...]   append a pass and update state\n\
    \  show                                             print current state";
  exit 2

let () =
  match Array.to_list Sys.argv with
  | _ :: "record" :: pass_id :: (_ :: _ as pairs) -> (
      let entries =
        List.map
          (fun pair ->
            match String.index_opt pair '=' with
            | Some i ->
                (String.sub pair 0 i, String.sub pair (i + 1) (String.length pair - i - 1))
            | None ->
                prerr_endline ("not a key=value pair: " ^ pair);
                exit 2)
          pairs
      in
      match Orientation_history.open_store store_path with
      | Error m -> prerr_endline m; exit 1
      | Ok store ->
          Fun.protect
            ~finally:(fun () -> Orientation_history.close store)
            (fun () ->
              match
                Orientation_history.record_pass store ~pass_id ~head:(git_head ())
                  ~recorded_at:(now_utc ()) entries
              with
              | Error m -> prerr_endline m; exit 1
              | Ok () -> (
                  (* Read back: the write is not the evidence, the read is. *)
                  match Orientation_history.counts store with
                  | Error m -> prerr_endline m; exit 1
                  | Ok (state_n, history_n, passes) ->
                      Printf.printf
                        "recorded %d entr(ies) under %s -> %s\nstate %d · history %d · passes %d\n"
                        (List.length entries) pass_id store_path state_n history_n passes)))
  | _ :: [ "show" ] -> (
      if not (Sys.file_exists store_path) then begin
        (* Absence is a disclosed state, never an invented empty one (R2). *)
        Printf.printf "no orientation store at %s\n" store_path;
        exit 0
      end;
      match Orientation_history.open_store store_path with
      | Error m -> prerr_endline m; exit 1
      | Ok store ->
          Fun.protect
            ~finally:(fun () -> Orientation_history.close store)
            (fun () ->
              match Orientation_history.state store with
              | Error m -> prerr_endline m; exit 1
              | Ok rows ->
                  List.iter
                    (fun (key, value, pass_id, recorded_at) ->
                      Printf.printf "%-28s %s   [%s %s]\n" key value pass_id recorded_at)
                    rows))
  | _ -> usage ()
