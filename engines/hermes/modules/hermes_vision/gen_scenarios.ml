let run argv =
  let a = Array.of_list argv in
  let pid = Unix.create_process a.(0) a Unix.stdin Unix.stdout Unix.stderr in
  match Unix.waitpid [] pid with _, Unix.WEXITED c -> c | _ -> 1

let () =
  let dir = "state/vision/scenarios" in
  let scenarios =
    [ (Vision_scenario.Intrusion { start_x = 40; speed_px_per_frame = 8; boundary_x = 320 }, 60);
      (Vision_scenario.Loitering { enter_x = 40; speed_px_per_frame = 8; stop_x = 300;
                                   dwell_frames = 30 }, 90);
      (Vision_scenario.Abandoned { speed_px_per_frame = 8; drop_x = 240;
                                   leaver_exits_x = 600 }, 90) ]
  in
  List.iter
    (fun (s, frames) ->
      match Vision_scenario.validate s ~frames with
      | Error e -> Printf.printf "%s REFUSED: %s\n" (Vision_scenario.name s) e
      | Ok _ ->
          let out = Filename.concat dir (Vision_scenario.name s ^ ".webm") in
          let c = run (Vision_scenario.argv s ~out ~frames) in
          Printf.printf "%s exit=%d %s\n" (Vision_scenario.name s) c
            (if Sys.file_exists out then string_of_int (Unix.stat out).Unix.st_size ^ " bytes"
             else "MISSING");
          print_string (Vision_scenario.render s))
    scenarios
