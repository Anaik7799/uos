(* Serve the vision control plane over Zenoh until stopped. *)
let () =
  let dir = ref "state/vision/hls" in
  let rec parse = function
    | "--dir" :: v :: r -> dir := v; parse r
    | [] -> ()
    | o -> prerr_endline ("unknown argument: " ^ String.concat " " o); exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));
  let intent = Vision_intent.looping_test_pattern ~dir:!dir in
  match Vision_controller.start intent with
  | Error e -> prerr_endline ("cannot start pipeline: " ^ e); exit 1
  | Ok h ->
      let handle = ref h in
      let comps = [ Vision_control.ffmpeg_component ~intent ~dir:!dir ~handle ] in
      Printf.printf "[vision-control] serving %s/*\n%!" Vision_control.key_prefix;
      (match Vision_control.serve comps with
       | Ok () -> ()
       | Error e -> prerr_endline ("cannot serve: " ^ e); Vision_controller.stop !handle; exit 1)
