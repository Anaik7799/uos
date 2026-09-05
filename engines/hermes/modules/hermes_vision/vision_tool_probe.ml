(* Probes for the GStreamer and VLC hazards. See the .mli. *)

let run_capture cmd =
  (* one pipe: the sequential drain of two is what hung ops verify *)
  match Unix.open_process_in ("( " ^ cmd ^ " ) 2>&1") with
  | exception e -> (127, "could not start: " ^ Printexc.to_string e)
  | ic ->
      let buf = Buffer.create 8192 and chunk = Bytes.create 65536 in
      let rec drain () =
        match input ic chunk 0 65536 with
        | 0 -> () | n -> Buffer.add_subbytes buf chunk 0 n; drain ()
        | exception End_of_file -> () | exception Sys_error _ -> ()
      in
      drain ();
      let st = try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127 in
      ((match st with Unix.WEXITED n -> n | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n),
       Buffer.contents buf)

let on_path exe =
  String.split_on_char ':' (try Sys.getenv "PATH" with Not_found -> "")
  |> List.exists (fun d -> d <> "" && Sys.file_exists (Filename.concat d exe))

let gst_available () = on_path "gst-launch-1.0"
let vlc_available () = on_path "cvlc"

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k > 0 && go 0

let observe stage verdict detail started =
  { Vision_controller.stage; verdict;
    level = Vision_ontology.level stage;
    origin = Vision_ontology.origin stage;
    detail;
    elapsed_ms = (Unix.gettimeofday () -. started) *. 1000.0 }

let quote = Filename.quote

let gst_produces ?(seconds = 10) ~pipeline ~expect () =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Package in
  if not (gst_available ()) then
    observe stage (Vision_controller.Unknown "gst-launch-1.0 is not on PATH") "" started
  else begin
    (try Sys.remove expect with _ -> ());
    let argv = Vision_gstreamer.argv pipeline in
    let cmd =
      Printf.sprintf "timeout %d %s" seconds (String.concat " " (List.map quote argv))
    in
    let code, out = run_capture cmd in
    let produced = Sys.file_exists expect in
    (* likewise: an element this installation does not have is an
       Environment gap, not a defect in the pipeline we declared *)
    let missing_element = contains out "no element" || contains out "missing a plug-in" in
    (* THE DISTINCTION THAT MATTERS. A timeout is not itself a verdict:
       a bounded live pipeline is SUPPOSED to be killed by it. What
       separates health from the silent-hang hazard is whether an
       artefact appeared before the bound. *)
    if missing_element && not produced then
      observe stage
        (Vision_controller.Unknown
           "this GStreamer installation lacks an element the pipeline needs")
        (String.trim (String.sub out 0 (min 200 (String.length out)))) started
    else if produced then
      observe stage
        (Vision_controller.Live
           (Printf.sprintf "the pipeline produced %s" (Filename.basename expect)))
        (Vision_gstreamer.description pipeline) started
    else if code = 124 then
      observe stage
        (Vision_controller.Absent
           "the pipeline ran to its time bound and produced nothing — the silent-hang hazard")
        (Vision_gstreamer.description pipeline) started
    else
      observe stage
        (Vision_controller.Absent
           (Printf.sprintf "the pipeline exited %d without producing an artefact" code))
        (String.trim (String.sub out 0 (min 300 (String.length out)))) started
  end

let gst_decodes ?(seconds = 10) ~path () =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Encode in
  if not (gst_available ()) then
    observe stage (Vision_controller.Unknown "gst-launch-1.0 is not on PATH") "" started
  else if not (Sys.file_exists path) then
    observe stage (Vision_controller.Unknown ("no such input: " ^ path)) path started
  else
    (* fakesink with -v prints one line per buffer handled, so "did any
       data flow" is answerable. A decodebin whose dynamic pad never
       links prints none, posts no error, and would otherwise look like
       a clean run. *)
    let cmd =
      Printf.sprintf
        "timeout %d gst-launch-1.0 -q filesrc location=%s ! decodebin ! fakesink silent=false -v"
        seconds (quote path)
    in
    let _code, out = run_capture cmd in
    let flowed = contains out "chain" || contains out "New clock" || contains out "handoff" in
    (* A MISSING PLUGIN IS NOT THE HAZARD. GStreamer says "missing a
       plug-in" when it has no decoder for the format, and that is an
       Environment gap: we could not measure, so nothing is proved about
       the pipeline. Reporting it as the dynamic-pad hazard would blame
       our design for an absent codec — measured on this host, where
       GStreamer has no H.264 decoder. *)
    if contains out "missing a plug-in" || contains out "no suitable plugins" then
      observe stage
        (Vision_controller.Unknown
           "GStreamer has no decoder for this format, so nothing could be measured")
        (String.trim (String.sub out 0 (min 200 (String.length out)))) started
    else if flowed then
      observe stage (Vision_controller.Live "decodebin linked and buffers flowed") path started
    else
      observe stage
        (Vision_controller.Absent
           "no buffer reached the sink: the decodebin dynamic pad never linked, and nothing was \
            posted to the bus")
        (String.trim (String.sub out 0 (min 300 (String.length out)))) started

(* Pure, so the classifier is testable without running VLC. Each marker
   is a phrase VLC prints when it forgives something. *)
let leniencies_in out =
  let l = String.lowercase_ascii out in
  List.filter_map
    (fun (needle, leniency) -> if contains l needle then Some leniency else None)
    [ ("discarding", Vision_vlc.Skipped_frames);
      ("late picture", Vision_vlc.Skipped_frames);
      ("picture is too late", Vision_vlc.Skipped_frames);
      (* "using " was too loose — VLC prints it for routine module
         selection, and it fired on a perfectly good file. A marker that
         cannot distinguish normal operation from forgiveness makes the
         probe useless, so only the phrases VLC prints when it FALLS
         BACK are kept. *)
      ("fallback", Vision_vlc.Demuxer_fallback);
      ("cannot peek", Vision_vlc.Demuxer_fallback);
      ("no suitable decoder", Vision_vlc.Codec_fallback);
      ("failed to create", Vision_vlc.Sout_stage_dropped) ]
  |> List.sort_uniq compare

let vlc_decodes ?(seconds = 6) ~path () =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Play in
  if not (vlc_available ()) then
    observe stage (Vision_controller.Unknown "cvlc is not on PATH") "" started
  else if not (Sys.file_exists path) && not (contains path "://") then
    observe stage (Vision_controller.Unknown ("no such input: " ^ path)) path started
  else
    let intent =
      { Vision_vlc.input = path; snapshot_to = None; run_seconds = seconds; verbose = true }
    in
    let argv = Vision_vlc.argv intent in
    let cmd =
      Printf.sprintf "timeout %d %s" (seconds + 6)
        (String.concat " " (List.map quote argv))
    in
    let code, out = run_capture cmd in
    let forgave = leniencies_in out in
    if code = 124 then
      (* the Play_url hazard: VLC retries and buffers forever rather than
         failing, so the run hangs instead of reporting *)
      observe stage
        (Vision_controller.Absent
           "VLC did not exit within its bound despite --play-and-exit — it is still retrying")
        path started
    else if forgave <> [] then
      (* correct behaviour for a player, disqualifying for evidence *)
      observe stage
        (Vision_controller.Absent
           ("VLC played it, but only by forgiving: "
           ^ String.concat ", " (List.map Vision_vlc.leniency_name forgave)))
        (String.concat " | " (List.map Vision_vlc.why_it_hides forgave))
        started
    else
      observe stage (Vision_controller.Live "VLC decoded it and forgave nothing") path started

let all ~dir ~path =
  [ gst_produces
      ~pipeline:(Vision_gstreamer.test_to_hls ~dir)
      ~expect:(Filename.concat dir "gst.m3u8") ();
    gst_decodes ~path ();
    vlc_decodes ~path () ]

(* ------------------------------------------------- OBS and JMeter *)

let obs_available () = on_path "obs"
let jmeter_available () = on_path "jmeter"

(* the integer following a marker, if any *)
let int_after out marker =
  let l = String.lowercase_ascii out and m = String.lowercase_ascii marker in
  let n = String.length l and k = String.length m in
  let rec find i =
    if i + k > n then None
    else if String.sub l i k = m then begin
      let rec skip j = if j < n && not (l.[j] >= '0' && l.[j] <= '9') then skip (j + 1) else j in
      let s = skip (i + k) in
      let rec till j = if j < n && l.[j] >= '0' && l.[j] <= '9' then till (j + 1) else j in
      let e = till s in
      if e > s then int_of_string_opt (String.sub l s (e - s)) else find (i + 1)
    end
    else find (i + 1)
  in
  find 0

let losses_in_log out =
  List.filter_map
    (fun (marker, loss) ->
      match int_after out marker with Some n when n > 0 -> Some (loss, n) | _ -> None)
    [ ("number of lagged frames due to rendering lag", Vision_obs.Render_lag);
      ("number of skipped frames due to encoding lag", Vision_obs.Encoding_lag);
      ("number of dropped frames due to insufficient bandwidth", Vision_obs.Network_drop) ]

let obs_capability c =
  let started = Unix.gettimeofday () in
  let stage = Vision_obs.serves c in
  let mk v d = observe stage v d started in
  if not (obs_available ()) then mk (Vision_controller.Unknown "obs is not on PATH") ""
  else if Vision_obs.gl_required c then
    (* measured on this host: no allowed GL implementation, which is why
       Chromium's compositor exits under Xvfb. UNAVAILABLE, not broken. *)
    mk (Vision_controller.Unknown
          "this capability needs an OpenGL context and this host has none")
      (Vision_obs.name c)
  else mk (Vision_controller.Unknown "not exercised: OBS needs a scene and an output to run")
      (Vision_obs.name c)

let obs_log out =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Observe in
  let mk v d = observe stage v d started in
  let ran = contains (String.lowercase_ascii out) "output" in
  let losses = losses_in_log out in
  if not ran then mk (Vision_controller.Unknown "the log shows no output having run") ""
  else if losses <> [] then
    (* the compositor's signature failure: the output stayed continuous
       and incomplete, and only the counters say so *)
    mk (Vision_controller.Absent
          (Printf.sprintf "the output ran but lost frames in %d of 3 places"
             (List.length losses)))
      (String.concat ", "
         (List.map (fun (l, n) -> Printf.sprintf "%s=%d" (Vision_obs.loss_name l) n) losses))
  else mk (Vision_controller.Live "the output ran and all three loss counters are zero") ""

let contaminants_in_report out =
  let l = String.lowercase_ascii out in
  List.concat
    [ (* a JTL with no assertion column means every 200 passed unexamined *)
      (if contains l "success" && not (contains l "assertion") then [ Vision_jmeter.No_assertion ]
       else []);
      (if contains l "gui mode" || contains l "swing" then [ Vision_jmeter.Gui_mode ] else []);
      (if contains l "full gc" || contains l "garbage" then [ Vision_jmeter.Jvm_pause ] else []) ]
  |> List.sort_uniq compare

let jmeter_report out =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Serve in
  let mk v d = observe stage v d started in
  if String.trim out = "" then mk (Vision_controller.Unknown "no report to read") ""
  else
    let cs = contaminants_in_report out in
    let errors = match int_after out "err:" with Some n -> n | None -> 0 in
    if cs <> [] then
      (* a green report from a contaminated run measures the generator *)
      mk (Vision_controller.Absent
            ("the report measures the generator, not the server: "
            ^ String.concat ", " (List.map Vision_jmeter.contaminant_name cs)))
        (String.concat " | " (List.map Vision_jmeter.why_it_invalidates cs))
    else if errors > 0 then
      mk (Vision_controller.Absent (Printf.sprintf "%d samples failed" errors)) ""
    else mk (Vision_controller.Live "the report is uncontaminated and error-free") ""

(* --------------------------------------------------------- libav *)

let libav_version_skew ~cli_version =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Encode in
  let linked = Vision_libav.avformat () in
  match cli_version with
  | None ->
      observe stage
        (Vision_controller.Unknown "no CLI version to compare the linked library against")
        ("linked libavformat " ^ linked) started
  | Some cli when cli = linked ->
      observe stage
        (Vision_controller.Live "the linked library and the CLI agree")
        ("libavformat " ^ linked) started
  | Some cli ->
      (* every ffmpeg-derived capability claim is then about a different
         library from the one that will decode our frames *)
      observe stage
        (Vision_controller.Absent
           (Printf.sprintf "version skew: linked %s, CLI reports %s" linked cli))
        "capability claims derived from the CLI describe the wrong library" started

let libav_leaks ?(iterations = 60) ?(tolerance_kb = 512) ~path () =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Source in
  if not (Sys.file_exists path) then
    observe stage (Vision_controller.Unknown ("no such input: " ^ path)) path started
  else
    match Vision_libav.open_close_leaks ~iterations path with
    | Error why -> observe stage (Vision_controller.Unknown why) path started
    | Ok (before, after) ->
        let grew = after - before in
        if grew > tolerance_kb then
          observe stage
            (Vision_controller.Absent
               (Printf.sprintf
                  "RSS grew %d kB over %d open/close cycles — a context is not being freed"
                  grew iterations))
            (Printf.sprintf "before %d kB, after %d kB" before after) started
        else
          observe stage
            (Vision_controller.Live
               (Printf.sprintf "%d open/close cycles grew RSS by %d kB (within %d)"
                  iterations grew tolerance_kb))
            (Printf.sprintf "before %d kB, after %d kB" before after) started

let libav_codes ~path =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Encode in
  if not (Sys.file_exists path) then
    observe stage (Vision_controller.Unknown ("no such input: " ^ path)) path started
  else
    let good = Vision_libav_ontology.classify (Vision_libav.open_close path) in
    (* a directory is not media: this must be a REAL error, not EAGAIN or
       EOF, or the classifier would let a genuine failure through as
       "feed me more" *)
    let bad = Vision_libav_ontology.classify (Vision_libav.open_close "/tmp") in
    match (good, Vision_libav_ontology.is_failure bad) with
    | Vision_libav_ontology.Ok_zero, true ->
        observe stage
          (Vision_controller.Live
             "a real file opens as success and a non-media path classifies as a real error")
          path started
    | Vision_libav_ontology.Ok_zero, false ->
        observe stage
          (Vision_controller.Absent
             (Printf.sprintf "a non-media path classified as %s rather than a failure"
                (Vision_libav_ontology.code_name bad)))
          "the return-code protocol would let a genuine failure through" started
    | other, _ ->
        observe stage
          (Vision_controller.Absent
             (Printf.sprintf "a real file did not open cleanly: %s"
                (Vision_libav_ontology.code_name other)))
          path started
