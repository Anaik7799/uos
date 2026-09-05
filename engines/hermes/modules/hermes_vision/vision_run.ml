(* The end-to-end run against a REAL signal.

   Starts the declared pipeline, waits for it to reach the packaging
   boundary, and probes every stage of the ontology. Play and Observe
   take their evidence from the browser oracle when it is supplied on the
   command line; when it is not, they are UNKNOWN and the run says so
   rather than reporting an end-to-end success it did not observe. *)

let () =
  let dir = ref "state/vision/hls"
  and host = ref "127.0.0.1"
  and port = ref 8091
  and seconds = ref 8
  and painted = ref None
  and captured = ref []
  and source_file = ref None in
  let ints s =
    String.split_on_char ',' s |> List.filter_map (fun x -> int_of_string_opt (String.trim x))
  in
  let rec parse = function
    | "--dir" :: v :: r -> dir := v; parse r
    | "--host" :: v :: r -> host := v; parse r
    | "--port" :: v :: r -> port := int_of_string v; parse r
    | "--seconds" :: v :: r -> seconds := int_of_string v; parse r
    | "--frames-painted" :: v :: r -> painted := int_of_string_opt v; parse r
    | "--captured-ordinals" :: v :: r -> captured := ints v; parse r
    | "--source-file" :: v :: r -> source_file := Some v; parse r
    | [] -> ()
    | o -> prerr_endline ("unknown argument: " ^ String.concat " " o); exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));

  let intent =
    match !source_file with
    | Some p -> Vision_intent.looping_source_file ~path:p ~dir:!dir
    | None -> Vision_intent.looping_test_pattern ~dir:!dir
  in
  Printf.printf "intent : %s\n%!" (Vision_intent.describe intent);
  Printf.printf "argv   : %s\n%!" (String.concat " " (Vision_intent.argv intent));

  match Vision_controller.start intent with
  | Error e -> prerr_endline ("could not start: " ^ e); exit 1
  | Ok h ->
      Printf.printf "pid    : %d\nlog    : %s\n%!" (Vision_controller.pid h)
        (Vision_controller.log_path h);
      (* let the pipeline reach its first segment boundary; probing before
         that would measure a pipeline that has not been asked to produce
         anything yet, and report Unknown for a healthy system *)
      Unix.sleepf (float_of_int !seconds);

      (* The source ordinals are the frames the encoder has actually
         emitted, derived from elapsed time and the declared rate. This is
         the side the capture is compared against. *)
      let rate = match intent.Vision_intent.source with
        | Vision_intent.Test_pattern { rate; _ } -> rate
        | _ -> 0
      in
      let source_ordinals = List.init (max 1 (rate * !seconds)) (fun i -> i) in

      let obs, coverage =
        Vision_controller.probe_all h ~dir:!dir ~host:!host ~port:!port ~path:"/stream.m3u8"
          ~frames_painted:!painted ~source_ordinals ~captured_ordinals:!captured
      in
      print_newline ();
      print_string (Vision_controller.render obs);

      (* Publish every stage observation over the real Zenoh client. This
         is fail-open for the pipeline and fail-loud for the operator: a
         run whose telemetry did not reach the mesh still completes, and
         still says so. *)
      let run_id = Printf.sprintf "vision-%d" (Vision_controller.pid h) in
      let outs = Vision_telemetry.publish_all ~run_id obs in
      print_newline ();
      print_string (Vision_telemetry.render outs);

      Vision_controller.stop h;

      let live = List.length (List.filter Vision_controller.is_live obs) in
      let total = List.length obs in
      (match coverage with
       | Ok s when Vision_algebra.covers_pipeline s ->
           Printf.printf "\ncoverage: END-TO-END (%d/%d stages live)\n" live total
       | Ok _ | Error _ ->
           let assumed =
             Vision_atlas.assumptions Vision_ontology.Observe
               (match coverage with Ok s -> s | Error _ -> Vision_algebra.identity Vision_ontology.Source)
           in
           Printf.printf "\ncoverage: PARTIAL (%d/%d stages live)\n" live total;
           if assumed <> [] then
             Printf.printf "assumed, not established: %s\n"
               (String.concat ", " (List.map Vision_ontology.stage_name assumed)));
      (* a run that could not observe every stage is not a success *)
      if live = total then exit 0 else exit 1
