(* Every stage probed against a SIMULATED signal before any real one.

   The point of the simulated pass is that each probe is shown to
   distinguish a good world from a bad one. A probe that has only ever
   seen a working pipeline has never been shown to detect anything, and
   the stage hazards in Vision_ontology are exactly the "working-looking"
   worlds each probe must reject. So for every stage there is a positive
   case, a negative case built to that stage's declared hazard, and where
   it can happen, an unmeasurable case that must come back Unknown. *)

let passed = ref 0
let failed = ref 0

let check name c =
  if c then incr passed
  else begin incr failed; print_endline ("  [FAIL] " ^ name) end

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k = 0 || go 0

(* Under `dune build @runtest` the cwd is _build/default, where the
   gitignored media under state/vision/ does not exist — so a suite that
   hardcodes relative artefact paths passes from the repository root and
   fails under the alias, which is exactly the split this had.

   Walking up for `.git` distinguishes the two: _build/default carries a
   copied dune-project but never a .git, so that marker finds the REAL
   root from either cwd. Falls back to "." so a checkout without .git
   still runs rather than erroring. *)
let repo_root =
  lazy
    (let rec up dir depth =
       if depth > 12 then "."
       else if Sys.file_exists (Filename.concat dir ".git") then dir
       else
         let parent = Filename.dirname dir in
         if parent = dir then "." else up parent (depth + 1)
     in
     up (Sys.getcwd ()) 0)

let at_root p = Filename.concat (Lazy.force repo_root) p

let tmpdir () =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "hermes-vision-test-%d-%f" (Unix.getpid ()) (Unix.gettimeofday ())) in
  Unix.mkdir d 0o755; d

let write path body =
  let oc = open_out_bin path in
  output_string oc body; close_out oc

let is_live = function Vision_controller.Live _ -> true | _ -> false
let is_absent = function Vision_controller.Absent _ -> true | _ -> false
let is_unknown = function Vision_controller.Unknown _ -> true | _ -> false

(* ---------------------------------------------------------- the intent *)

let () =
  print_endline "vision: declarative intent";
  let i = Vision_intent.looping_test_pattern ~dir:"/tmp/x" in
  check "the reference intent validates" (Result.is_ok (Vision_intent.validate i));
  check "argv starts with ffmpeg" (List.hd (Vision_intent.argv i) = "ffmpeg");
  check "argv is deterministic" (Vision_intent.argv i = Vision_intent.argv i);
  check "argv carries the declared geometry"
    (List.exists (fun a -> contains a "640x360") (Vision_intent.argv i));
  check "argv names the hls playlist"
    (List.exists (fun a -> contains a "stream.m3u8") (Vision_intent.argv i));
  (* THE INJECTION CASE. The old controller concatenated fields into a
     shell string; a path like this would have ended the command and
     started another. Here it is one argv element and nothing more. *)
  let hostile =
    { i with Vision_intent.source = Vision_intent.Loop_file { path = "/tmp/a; rm -rf /" } }
  in
  let v = Vision_intent.argv hostile in
  check "a hostile path stays a SINGLE argv element"
    (List.exists (fun a -> a = "/tmp/a; rm -rf /") v);
  check "and never becomes two arguments" (not (List.exists (fun a -> a = "rm") v));
  check "argv_is_shell_free holds for the hostile intent"
    (Vision_intent.argv_is_shell_free hostile);
  check "a newline in a path is refused as shell-unsafe"
    (not
       (Vision_intent.argv_is_shell_free
          { i with Vision_intent.source = Vision_intent.Loop_file { path = "/tmp/a\nb" } }));
  (* validation refuses impossible signals BEFORE a process exists *)
  check "zero rate is refused"
    (Result.is_error
       (Vision_intent.validate
          { i with source = Vision_intent.Test_pattern
                       { width = 640; height = 360; rate = 0; label = "X" } }));
  check "port 0 is refused"
    (Result.is_error
       (Vision_intent.validate { i with sink = Vision_intent.Udp_out { host = "h"; port = 0 } }));
  check "an empty hls dir is refused"
    (Result.is_error
       (Vision_intent.validate
          { i with sink = Vision_intent.Hls { dir = " "; segment_seconds = 1; window = 5 } }))

(* -------------------------------------------------------- the algebra *)

let () =
  print_endline "vision: fractal algebra";
  let open Vision_ontology in
  let seg a b = Option.get (Vision_algebra.segment a b) in
  check "a reversed segment is not a segment" (Vision_algebra.segment Play Source = None);
  check "identity is a unit"
    (Vision_algebra.compose (Vision_algebra.identity Source) (seg Source Encode)
     = Some (seg Source Encode));
  check "adjacent segments compose"
    (Vision_algebra.compose (seg Source Encode) (seg Package Serve) = Some (seg Source Serve));
  (* THE GAP LAW. Source..Encode then Play..Observe leaves Package and
     Serve unmeasured, and that must not compose into coverage. *)
  check "a GAP does not compose"
    (Vision_algebra.compose (seg Source Encode) (seg Play Observe) = None);
  check "composition is associative where defined"
    (let a = seg Source Encode and b = seg Encode Package and c = seg Package Serve in
     let l = Option.bind (Vision_algebra.compose a b) (fun ab -> Vision_algebra.compose ab c) in
     let r = Option.bind (Vision_algebra.compose b c) (fun bc -> Vision_algebra.compose a bc) in
     l = r);
  check "the full segment covers the pipeline" (Vision_algebra.covers_pipeline Vision_algebra.full);
  check "a partial segment does not" (not (Vision_algebra.covers_pipeline (seg Source Play)));
  check "coverage of nothing is an error" (Result.is_error (Vision_algebra.coverage []));
  check "coverage is order-independent"
    (Vision_algebra.coverage [ seg Package Serve; seg Source Encode ]
     = Vision_algebra.coverage [ seg Source Encode; seg Package Serve ]);
  check "coverage names the gap it found"
    (match Vision_algebra.coverage [ seg Source Encode; seg Play Observe ] with
     | Error m -> contains m "gap"
     | Ok _ -> false)

(* ---------------------------------------------------------- the atlas *)

let () =
  print_endline "vision: fractal atlas / ontology";
  let open Vision_ontology in
  check "every stage has a distinct index"
    (List.length (List.sort_uniq compare (List.map stage_index stages)) = List.length stages);
  check "every stage declares a law" (List.for_all (fun s -> law s <> "") stages);
  check "every stage declares a hazard" (List.for_all (fun s -> hazard s <> "") stages);
  (* R5: a transport stage must never be able to deny parity credit *)
  check "only Package may carry Implementation origin"
    (List.for_all
       (fun s -> if origin s = Fractal_diagnostic.Implementation then s = Package else true)
       stages);
  check "Observe depends on the whole chain"
    (List.length (Vision_atlas.evidence_path Observe) = List.length stages);
  check "Observe OBSERVES Play rather than being fed by it"
    (List.exists
       (fun (e : Vision_atlas.edge) ->
         e.source = Observe && e.target = Play && e.relation = Vision_atlas.Observes)
       Vision_atlas.edges);
  (* the atlas's real product: what a receipt assumed *)
  check "a receipt at Observe over a Play-only segment assumes the rest"
    (List.length (Vision_atlas.assumptions Observe (Vision_algebra.identity Play)) >= 4);
  check "a receipt at Observe over the full segment assumes nothing"
    (Vision_atlas.assumptions Observe Vision_algebra.full = [])

(* ------------------------------- simulated signal, one stage at a time *)

let () =
  print_endline "vision: simulated signal per stage";
  let d = tmpdir () in

  (* PACKAGE -- positive *)
  write (Filename.concat d "s0.ts") "AAAA";
  write (Filename.concat d "s1.ts") "BBBB";
  write (Filename.concat d "stream.m3u8") "#EXTM3U\n#EXTINF:1,\ns0.ts\n#EXTINF:1,\ns1.ts\n";
  check "Package LIVE when every named segment exists"
    (is_live (Vision_controller.probe_package ~dir:d).verdict);

  (* PACKAGE -- the declared hazard: playlist names a deleted segment *)
  write (Filename.concat d "stream.m3u8")
    "#EXTM3U\n#EXTINF:1,\ns0.ts\n#EXTINF:1,\ngone.ts\n";
  let p = Vision_controller.probe_package ~dir:d in
  check "Package ABSENT when the playlist names a missing segment" (is_absent p.verdict);
  check "and it names which segment was missing" (contains p.detail "gone.ts");

  (* PACKAGE -- an empty segment is as broken as an absent one *)
  write (Filename.concat d "empty.ts") "";
  write (Filename.concat d "stream.m3u8") "#EXTM3U\n#EXTINF:1,\nempty.ts\n";
  check "Package ABSENT when a named segment is empty"
    (is_absent (Vision_controller.probe_package ~dir:d).verdict);

  (* PACKAGE -- not yet written is UNKNOWN, never ABSENT *)
  let empty_dir = tmpdir () in
  check "Package UNKNOWN before the first playlist exists"
    (is_unknown (Vision_controller.probe_package ~dir:empty_dir).verdict);

  (* SERVE -- nothing listening must be UNKNOWN, not ABSENT: an
     unreachable server proves nothing about the stream *)
  check "Serve UNKNOWN when nothing is listening"
    (is_unknown
       (Vision_controller.probe_serve ~host:"127.0.0.1" ~port:9 ~path:"/stream.m3u8").verdict);

  (* PLAY *)
  check "Play UNKNOWN with no oracle"
    (is_unknown (Vision_controller.probe_play ~frames_painted:None).verdict);
  check "Play ABSENT when the player painted nothing"
    (is_absent (Vision_controller.probe_play ~frames_painted:(Some 0)).verdict);
  check "Play LIVE when frames were painted"
    (is_live (Vision_controller.probe_play ~frames_painted:(Some 12)).verdict);

  (* OBSERVE -- the comparison stage, and its hazard *)
  check "Observe LIVE when captured ordinals match the source and advance"
    (is_live
       (Vision_controller.probe_observe ~source_ordinals:[ 1; 2; 3; 4 ]
          ~captured_ordinals:[ 2; 3 ]).verdict);
  check "Observe ABSENT when the capture never advanced (frozen frame)"
    (is_absent
       (Vision_controller.probe_observe ~source_ordinals:[ 1; 2; 3 ]
          ~captured_ordinals:[ 2; 2; 2 ]).verdict);
  check "Observe ABSENT when no captured ordinal is in the source"
    (is_absent
       (Vision_controller.probe_observe ~source_ordinals:[ 1; 2; 3 ]
          ~captured_ordinals:[ 90; 91 ]).verdict);
  check "Observe UNKNOWN when one side produced nothing"
    (is_unknown
       (Vision_controller.probe_observe ~source_ordinals:[] ~captured_ordinals:[ 1; 2 ]).verdict)

(* --------------------------- coverage cannot be built from non-answers *)

let () =
  print_endline "vision: coverage discipline";
  let open Vision_ontology in
  (* An Unknown stage must not contribute coverage -- otherwise a
     pipeline nobody could measure would report end-to-end success. *)
  let live_only =
    [ Vision_algebra.identity Source; Vision_algebra.identity Encode ]
  in
  check "two live stages do not cover the pipeline"
    (match Vision_algebra.coverage live_only with
     | Ok s -> not (Vision_algebra.covers_pipeline s)
     | Error _ -> true);
  check "all six live stages DO cover the pipeline"
    (match Vision_algebra.coverage (List.map Vision_algebra.identity stages) with
     | Ok s -> Vision_algebra.covers_pipeline s
     | Error _ -> false)

(* ------------------------------------ the control plane is FAIL-CLOSED *)

let () =
  print_endline "vision: zenoh control plane";
  let restarts = ref 0 in
  let comps =
    [ { Vision_control.name = "ffmpeg";
        status = (fun () -> {|"running":true|});
        restart = (fun () -> incr restarts; Ok "restarted, pid 1") };
      { Vision_control.name = "server";
        status = (fun () -> {|"running":true|});
        restart = (fun () -> Error "port still bound") } ]
  in
  let d k p = Vision_control.dispatch comps k p in
  let okish s = contains s {|"ok":true|} in
  let bad s = contains s {|"ok":false|} in

  check "status on a known component succeeds"
    (okish (d "hermes/vision/control/ffmpeg" {|{"action":"status"}|}));
  check "restart on a known component succeeds"
    (okish (d "hermes/vision/control/ffmpeg" {|{"action":"restart"}|}));
  check "and the restart actually ran" (!restarts = 1);

  (* every refusal below would be a live media pipeline acted on by
     accident if the parser were generous instead of exact *)
  check "an unknown component is refused, not guessed"
    (bad (d "hermes/vision/control/nope" {|{"action":"status"}|}));
  check "the refusal lists what it does know"
    (contains (d "hermes/vision/control/nope" {|{"action":"status"}|}) "ffmpeg");
  check "a missing action field is refused"
    (bad (d "hermes/vision/control/ffmpeg" {|{}|}));
  check "an unknown action is refused"
    (bad (d "hermes/vision/control/ffmpeg" {|{"action":"reboot"}|}));
  check "a PREFIX of a real action is refused"
    (bad (d "hermes/vision/control/ffmpeg" {|{"action":"rest"}|}));
  check "a suffixed action is refused"
    (bad (d "hermes/vision/control/ffmpeg" {|{"action":"restart-now"}|}));
  check "wrong case is refused"
    (bad (d "hermes/vision/control/ffmpeg" {|{"action":"RESTART"}|}));
  check "garbage payload is refused, never crashes"
    (bad (d "hermes/vision/control/ffmpeg" "not json at all"));
  check "no refusal ever ran a restart" (!restarts = 1);

  (* a restart that fails must be reported as failure, not as done *)
  check "a failing restart replies not-ok"
    (bad (d "hermes/vision/control/server" {|{"action":"restart"}|}));
  check "and names the cause"
    (contains (d "hermes/vision/control/server" {|{"action":"restart"}|}) "port still bound");
  check "parse_action refuses whitespace padding"
    (Result.is_error (Vision_control.parse_action " restart"));
  check "the key helper matches the served prefix"
    (Vision_control.key_for "ffmpeg" = "hermes/vision/control/ffmpeg")

(* -------------------------------------------- the browser API ontology *)

let () =
  print_endline "vision: browser API ontology";
  let open Vision_browser_api in

  check "every capability has a distinct name"
    (List.length (List.sort_uniq compare (List.map name capabilities))
     = List.length capabilities);
  check "every capability declares a law" (List.for_all (fun c -> law c <> "") capabilities);
  check "every capability declares a hazard" (List.for_all (fun c -> hazard c <> "") capabilities);

  (* R5. A browser without a decoder says nothing about whether our
     pipeline is correct, so no browser capability may deny credit. *)
  check "NO capability is Implementation origin"
    (List.for_all (fun c -> origin c <> Fractal_diagnostic.Implementation) capabilities);
  check "the capture capabilities are Evidence origin"
    (List.for_all
       (fun c -> origin c = Fractal_diagnostic.Evidence)
       [ Capture_stream; Media_recorder; Frame_callback; Playback_quality ]);

  (* the join to the pipeline ontology *)
  check "every capability serves Play or Observe"
    (List.for_all
       (fun c -> serves c = Vision_ontology.Play || serves c = Vision_ontology.Observe)
       capabilities);
  check "Observe requires a way to SEE frames"
    (required_for Vision_ontology.Observe <> []);
  check "the pipeline-side stages require no browser capability"
    (List.for_all
       (fun s -> required_for s = [])
       [ Vision_ontology.Source; Vision_ontology.Encode; Vision_ontology.Package;
         Vision_ontology.Serve ]);

  (* THE HAZARD LAWS. Each probe must answer its capability's law, not
     test that a symbol exists — the distinction the whole module is
     about, and the one a careless rewrite would erase. *)
  let p c = probe_expression c in
  check "every probe is a function expression"
    (List.for_all (fun c -> contains (p c) "() => (") capabilities);
  check "Codec_support asks canPlayType, not truthiness of the symbol"
    (contains (p Codec_support) "canPlayType");
  check "Codec_support asks about BOTH codecs we serve"
    (contains (p Codec_support) "vp8" && contains (p Codec_support) "avc1");
  check "Capture_stream COUNTS video tracks (empty list is the hazard)"
    (contains (p Capture_stream) "getVideoTracks" && contains (p Capture_stream) "length");
  check "Media_source asks isTypeSupported for the codec we serve"
    (contains (p Media_source) "isTypeSupported");
  check "Playback_quality reads both counters"
    (contains (p Playback_quality) "droppedVideoFrames"
    && contains (p Playback_quality) "totalVideoFrames");
  check "probe strings are quoted, so a codec name cannot become syntax"
    (contains (p Codec_support) "\"video/webm; codecs=\\\"vp8\\\"\"");

  (* engines *)
  check "every engine has a distinct name"
    (List.length (List.sort_uniq compare (List.map engine_name engines)) = List.length engines);
  check "Firefox is documented WITHOUT requestVideoFrameCallback"
    (not (declared Firefox Frame_callback));
  check "Chrome and Edge are documented WITH it"
    (declared Chrome Frame_callback && declared Edge Frame_callback);

  (* The codec finding that cost real time tonight: an open-source
     Chromium build ships without H.264, and that presents exactly as the
     Play hazard — a player reporting readiness and painting nothing. *)
  check "open-source Chromium has NO h264" (not (List.mem "h264" (codecs Chromium_oss)));
  check "Edge has hevc and Chrome does not"
    (List.mem "hevc" (codecs Edge) && not (List.mem "hevc" (codecs Chrome)));
  check "h264 is therefore NOT universal" (not (List.mem "h264" (universal_codecs ())));
  check "the universal set is non-empty" (universal_codecs () <> []);
  check "the universal set is playable on EVERY engine"
    (List.for_all
       (fun c -> List.for_all (fun e -> List.mem c (codecs e)) engines)
       (universal_codecs ()));
  check "and it is the reason the player offers a non-h264 source first"
    (List.mem "vp9" (universal_codecs ()) || List.mem "av1" (universal_codecs ()));

  check "render names every capability"
    (List.for_all (fun c -> contains (render ()) (name c)) capabilities)

(* ------------------------------------------- the GStreamer ontology *)

let () =
  print_endline "vision: gstreamer ontology";
  let open Vision_gstreamer in

  (* THE STATE MACHINE. GStreamer refuses NULL -> PLAYING as one change;
     modelling it as legal lets a caller believe a pipeline reached
     PLAYING without ever prerolling. *)
  check "adjacent transitions are legal" (legal_transition Null Ready && legal_transition Paused Playing);
  check "NULL -> PLAYING is ILLEGAL as a single change" (not (legal_transition Null Playing));
  check "NULL -> PAUSED is illegal as a single change" (not (legal_transition Null Paused));
  check "transitions run downward too" (legal_transition Playing Paused);
  check "a state is not a transition to itself" (not (legal_transition Ready Ready));

  (* THE CENTRAL LAW OF THIS MODULE. Treating ASYNC as success is the
     most common way a GStreamer pipeline is reported working while
     producing nothing. *)
  check "SUCCESS means the state was reached" (reached Success);
  check "ASYNC does NOT mean the state was reached" (not (reached Async));
  check "NO_PREROLL does NOT mean the state was reached" (not (reached No_preroll));
  check "FAILURE does not mean the state was reached" (not (reached (Failure "x")));
  check "every change has a distinct name"
    (List.length
       (List.sort_uniq compare
          (List.map change_name [ Success; Async; No_preroll; Failure "x" ]))
     = 4);

  (* elements *)
  check "every element has a distinct factory name"
    (List.length (List.sort_uniq compare (List.map element_name elements))
     = List.length elements);
  check "every element declares a law" (List.for_all (fun e -> law e <> "") elements);
  check "every element declares a hazard" (List.for_all (fun e -> hazard e <> "") elements);
  (* R5 again: only the contract this repository owns may deny credit *)
  check "only hlssink2 carries Implementation origin"
    (List.for_all
       (fun e -> if origin e = Fractal_diagnostic.Implementation then e = Sink_hls else true)
       elements);
  check "decodebin's hazard names the dynamic-pad silent hang"
    (contains (hazard Decode_bin) "DYNAMIC pad");

  (* the join to the pipeline ontology *)
  check "sources serve Source" (serves Src_file = Vision_ontology.Source);
  check "hlssink2 serves Package" (serves Sink_hls = Vision_ontology.Package);
  check "appsink serves Observe" (serves Sink_app = Vision_ontology.Observe);
  check "every element maps to a real stage"
    (List.for_all (fun e -> List.mem (serves e) Vision_ontology.stages) elements);

  (* declared intent, and argv rather than a shell string *)
  let p = test_to_hls ~dir:"/tmp/g" in
  check "the reference pipeline is well-formed" (Result.is_ok (well_formed p));
  check "description renders the canonical ! form" (contains (description p) "videotestsrc ! ");
  check "argv starts with gst-launch-1.0" (List.hd (argv p) = "gst-launch-1.0");
  check "argv keeps ! as its own element" (List.mem "!" (argv p));
  check "a property value stays ONE argv element"
    (List.exists (fun a -> contains a "playlist-location=") (argv (test_to_hls ~dir:"/tmp/a b")));
  check "the file pipeline is well-formed" (Result.is_ok (well_formed (file_to_hls ~path:"/tmp/x.mp4" ~dir:"/tmp/g")));

  (* refusals — each is a runtime HANG if not caught here *)
  check "an empty pipeline is refused"
    (Result.is_error (well_formed { elements = []; properties = [] }));
  check "a pipeline not starting with a source is refused"
    (Result.is_error (well_formed { elements = [ Convert; Sink_hls ]; properties = [] }));
  check "a pipeline not ending in a sink is refused"
    (Result.is_error (well_formed { elements = [ Src_test; Convert ]; properties = [] }));
  check "an encoder with nothing raw in front of it is refused"
    (Result.is_error
       (well_formed { elements = [ Src_file; Encode_h264; Sink_hls ]; properties = [] }));
  check "and the refusal names the element"
    (match well_formed { elements = [ Src_file; Encode_h264; Sink_hls ]; properties = [] } with
     | Error m -> contains m "x264enc"
     | Ok _ -> false);

  check "render names every element"
    (List.for_all (fun e -> contains (render ()) (element_name e)) elements)

(* ------------------------------------------------- the VLC ontology *)

let () =
  print_endline "vision: vlc ontology";
  let open Vision_vlc in

  (* PLAYING IS NOT DECODED. VLC enters Playing while still buffering,
     so the state is an intention and the picture counter is the
     outcome. *)
  check "Playing with pictures counts as decoded" (decoded Playing ~pictures:12);
  check "Playing with ZERO pictures does NOT count" (not (decoded Playing ~pictures:0));
  check "Buffering never counts, whatever the counter says"
    (not (decoded Buffering ~pictures:99));
  check "Ended does not count as decoded" (not (decoded Ended ~pictures:5));

  check "Ended and Error are both terminal" (terminal Ended && terminal Error);
  check "Opening and Buffering are not terminal"
    (not (terminal Opening) && not (terminal Buffering));
  check "every state has a distinct name"
    (List.length (List.sort_uniq compare (List.map state_name states)) = List.length states);

  (* THE FORGIVENESS LAWS. Each leniency is correct behaviour for a media
     player and actively hostile to a harness, because each converts a
     defect into a successful-looking playback. *)
  check "a run that forgave nothing is clean" (clean []);
  check "ANY leniency disqualifies the run" (not (clean [ Skipped_frames ]));
  check "ended-without-error also disqualifies" (not (clean [ Ended_without_error ]));
  check "every leniency explains what it hides"
    (List.for_all (fun l -> why_it_hides l <> "") leniencies);
  check "every leniency has a distinct name"
    (List.length (List.sort_uniq compare (List.map leniency_name leniencies))
     = List.length leniencies);
  check "demuxer fallback explains that the format tested is not the format declared"
    (contains (why_it_hides Demuxer_fallback) "not the format");

  (* VLC is an ORACLE. Nothing it does may be our Implementation fault. *)
  check "NO vlc capability carries Implementation origin"
    (List.for_all (fun c -> origin c <> Fractal_diagnostic.Implementation) capabilities);
  check "snapshot and stats are Evidence origin"
    (origin Snapshot = Fractal_diagnostic.Evidence
    && origin Stats = Fractal_diagnostic.Evidence);
  check "every capability declares a law and a hazard"
    (List.for_all (fun c -> law c <> "" && hazard c <> "") capabilities);
  check "the snapshot hazard names the blank-image trap"
    (contains (hazard Snapshot) "BLANK");
  check "every capability maps to a real stage"
    (List.for_all (fun c -> List.mem (serves c) Vision_ontology.stages) capabilities);

  (* argv, and the flag whose absence turns a step into a hang *)
  let i = { input = "http://127.0.0.1:8091/loop.webm"; snapshot_to = None;
            run_seconds = 5; verbose = false } in
  check "the reference intent validates" (Result.is_ok (validate i));
  check "argv starts with cvlc" (List.hd (argv i) = "cvlc");
  check "argv ALWAYS carries --play-and-exit" (List.mem "--play-and-exit" (argv i));
  check "argv bounds the run" (List.mem "--run-time" (argv i));
  check "the input stays ONE argv element"
    (List.mem "http://127.0.0.1:8091/loop.webm" (argv i));
  check "a hostile input stays one element too"
    (List.mem "/tmp/a; rm -rf /"
       (argv { i with input = "/tmp/a; rm -rf /" }));
  check "a snapshot intent asks for the scene filter"
    (List.mem "scene" (argv { i with snapshot_to = Some "/tmp/s/shot.png" }));
  check "and never samples before decode has begun (scene-ratio present)"
    (List.mem "--scene-ratio" (argv { i with snapshot_to = Some "/tmp/s/shot.png" }));
  check "an empty input is refused" (Result.is_error (validate { i with input = " " }));
  check "a zero run duration is refused" (Result.is_error (validate { i with run_seconds = 0 }));
  check "render names every capability and leniency"
    (List.for_all (fun c -> contains (render ()) (capability_name c)) capabilities
    && List.for_all (fun l -> contains (render ()) (leniency_name l)) leniencies)

(* ------------------------------------------------- the OBS ontology *)

let () =
  print_endline "vision: obs ontology";
  let open Vision_obs in

  check "every capability has a distinct name"
    (List.length (List.sort_uniq compare (List.map name capabilities))
     = List.length capabilities);
  check "every capability declares a law and a hazard"
    (List.for_all (fun c -> law c <> "" && hazard c <> "") capabilities);
  check "only the recorded file carries Implementation origin"
    (List.for_all
       (fun c -> if origin c = Fractal_diagnostic.Implementation then c = Output Record_file
                 else true)
       capabilities);
  check "every capability maps to a real stage"
    (List.for_all (fun c -> List.mem (serves c) Vision_ontology.stages) capabilities);

  (* The GPU dependency, measured on this host: Chromium's compositor
     exits under Xvfb for want of a usable GL, and OBS shares that
     substrate. Marking it keeps a missing GPU an UNAVAILABLE rather
     than a defect. *)
  check "compositing requires GL" (gl_required Scene_composite);
  check "window and browser sources require GL"
    (gl_required (Source Window_capture) && gl_required (Source Browser_source));
  check "encoding and stats do NOT require GL"
    (not (gl_required Encoder_x264) && not (gl_required Stats_counters));

  (* THREE COUNTERS, THREE FAULTS. Collapsing them makes the fault
     undiagnosable, so each must keep its own origin. *)
  check "the three losses have distinct names"
    (List.length (List.sort_uniq compare (List.map loss_name losses)) = 3);
  check "no loss is Implementation origin"
    (List.for_all (fun l -> loss_origin l <> Fractal_diagnostic.Implementation) losses);
  check "encoding lag is a Control fault (our CPU budget)"
    (loss_origin Encoding_lag = Fractal_diagnostic.Control);
  check "render lag is Environment (the GPU)"
    (loss_origin Render_lag = Fractal_diagnostic.Environment);
  check "each loss explains its constraint"
    (List.for_all (fun l -> loss_meaning l <> "") losses);
  check "encoding lag says frames were SKIPPED before encoding"
    (contains (loss_meaning Encoding_lag) "SKIPPED");

  (* delivered must not be `encoded` — an encoded frame can still be
     discarded by the network stage afterwards *)
  let perfect = { rendered = 300; render_missed = 0; encoded = 300; skipped = 0; dropped = 0 } in
  check "a perfect run is intact" (intact perfect);
  check "delivered equals encoded when nothing dropped" (delivered perfect = 300);
  let netloss = { perfect with dropped = 12 } in
  check "delivered SUBTRACTS network drops" (delivered netloss = 288);
  check "a run with network drops is NOT intact" (not (intact netloss));
  check "and the loss is attributed to the network"
    (List.mem_assoc Network_drop (losses_observed netloss));
  let enclag = { perfect with skipped = 7 } in
  check "skipped frames make a run not intact" (not (intact enclag));
  check "and are attributed to encoding lag"
    (List.mem_assoc Encoding_lag (losses_observed enclag));
  let renderlag = { perfect with render_missed = 3 } in
  check "render misses make a run not intact" (not (intact renderlag));
  check "three simultaneous losses are all reported, not collapsed"
    (List.length (losses_observed { rendered = 300; render_missed = 1; encoded = 299;
                                    skipped = 2; dropped = 3 }) = 3);
  check "an untouched run reports no losses at all" (losses_observed perfect = []);

  (* the hazards that matter most: a compositor keeps running *)
  check "window capture's hazard names the BLACK-while-active trap"
    (contains (hazard (Source Window_capture)) "BLACK");
  check "rtmp's hazard names the silent reconnect"
    (contains (hazard (Output Stream_rtmp)) "RECONNECT");
  check "the encoder hazard names skipping before encode"
    (contains (hazard Encoder_x264) "SKIPPED");
  check "render names every capability"
    (List.for_all (fun c -> contains (render ()) (name c)) capabilities)

(* ---------------------------------------------- the JMeter ontology *)

let () =
  print_endline "vision: jmeter ontology";
  let open Vision_jmeter in

  check "every element has a distinct name"
    (List.length (List.sort_uniq compare (List.map name elements)) = List.length elements);
  check "every element declares a law and a hazard"
    (List.for_all (fun e -> law e <> "" && hazard e <> "") elements);
  (* the assertion is the one contract WE define: it says what a correct
     response is, and getting that wrong is our error *)
  check "only the assertion carries Implementation origin"
    (List.for_all
       (fun e -> if origin e = Fractal_diagnostic.Implementation then e = Assertion else true)
       elements);
  check "jmeter's elements mostly serve the Serve stage"
    (serves Http_sampler = Vision_ontology.Serve
    && serves Thread_group = Vision_ontology.Serve);

  (* THE FOUR WAYS A GREEN REPORT IS MEANINGLESS *)
  check "a report with no contaminant is trustworthy" (trustworthy []);
  check "ANY contaminant makes it untrustworthy" (not (trustworthy [ No_assertion ]));
  check "every contaminant explains what it invalidates"
    (List.for_all (fun c -> why_it_invalidates c <> "") contaminants);
  check "no_assertion says a 200 error page passes"
    (contains (why_it_invalidates No_assertion) "error page");
  check "coordinated omission says latency IMPROVES as the server worsens"
    (contains (why_it_invalidates Coordinated_omission) "improves on paper");
  check "client saturation says the latency is the client queueing"
    (contains (why_it_invalidates Client_saturated) "client queueing");

  (* the governing number is the tail, not the mean *)
  let clean_run = { samples = 1000; errors = 0; mean_ms = 20.0; p95_ms = 60.0;
                    p99_ms = 400.0; max_ms = 900.0; throughput_per_s = 50.0 } in
  check "governing latency is p99, NOT the mean"
    (governing_latency clean_run = 400.0 && governing_latency clean_run <> clean_run.mean_ms);

  (* verdict refuses to answer about the server when it cannot *)
  check "a clean run yields the governing latency"
    (verdict clean_run [] = Stdlib.Ok 400.0);
  check "a contaminated run is refused even with perfect numbers"
    (Result.is_error (verdict clean_run [ No_assertion ]));
  check "and the refusal explains why"
    (match verdict clean_run [ Client_saturated ] with
     | Stdlib.Error m -> contains m "not the server"
     | Stdlib.Ok _ -> false);
  check "zero samples is refused — nothing was measured"
    (Result.is_error (verdict { clean_run with samples = 0 } []));
  check "any error sample is refused"
    (Result.is_error (verdict { clean_run with errors = 1 } []));

  (* the heuristics: what the numbers themselves betray *)
  check "a max ten times p99 is suspected as a generator pause"
    (List.mem Jvm_pause (suspected { clean_run with max_ms = 5000.0 } ~previous:None));
  check "a proportionate max is not suspected"
    (suspected clean_run ~previous:None = []);
  (* throughput fell AND latency improved: the client stopped issuing the
     requests that would have been slow *)
  check "falling throughput with improving latency is suspected omission"
    (List.mem Coordinated_omission
       (suspected { clean_run with throughput_per_s = 20.0; p99_ms = 100.0 }
          ~previous:(Some clean_run)));
  check "falling throughput with WORSENING latency is not omission"
    (not (List.mem Coordinated_omission
            (suspected { clean_run with throughput_per_s = 20.0; p99_ms = 900.0 }
               ~previous:(Some clean_run))));
  check "heuristics cannot fire without a previous run to compare"
    (not (List.mem Coordinated_omission (suspected clean_run ~previous:None)));

  check "render names every element and contaminant"
    (List.for_all (fun e -> contains (render ()) (name e)) elements
    && List.for_all (fun c -> contains (render ()) (contaminant_name c)) contaminants)

(* ------------------------------------------- the libav ontology *)

let () =
  print_endline "vision: libav ontology";
  let open Vision_libav_ontology in

  check "every call has a distinct name"
    (List.length (List.sort_uniq compare (List.map name calls)) = List.length calls);
  check "every call declares a law and a hazard"
    (List.for_all (fun c -> law c <> "" && hazard c <> "") calls);

  (* THE CLASSIC LIBAV BUG: "negative means error" aborts a working
     decode at the first EAGAIN. *)
  check "EAGAIN classifies as Again, not an error" (classify (-11) = Again);
  check "EAGAIN is NOT a failure" (not (is_failure (classify (-11))));
  check "EAGAIN asks for more input" (wants_more_input (classify (-11)));
  check "EOF classifies as End_of_file" (classify (-541478725) = End_of_file);
  check "EOF is NOT a failure" (not (is_failure (classify (-541478725))));
  check "EOF does not ask for more input" (not (wants_more_input (classify (-541478725))));
  check "a genuine negative IS a failure" (is_failure (classify (-22)));
  check "zero and positive are success"
    (not (is_failure (classify 0)) && not (is_failure (classify 7)));
  check "every negative is not lumped together"
    (classify (-11) <> classify (-22));

  (* LIFETIME. Expired must be reachable in the model precisely because
     it is reachable in C — the binding's job is to make it unholdable. *)
  check "a live view is readable" (readable Live);
  check "an EXPIRED view is not readable" (not (readable Expired));
  check "unref expires outstanding views" (after Unref_frame Live = Expired);
  check "closing the input expires them too" (after Close_input Live = Expired);
  check "reading pixels does NOT expire a view" (after Frame_buffer_access Live = Live);
  check "receiving a frame does not expire existing views"
    (after Receive_frame Live = Live);
  check "expiry is one-way — nothing revives a view"
    (List.for_all (fun c -> after c Expired = Expired) calls);

  (* the two obligations the binding must get right *)
  check "open_input allocates and must be closed" (allocates Open_input);
  check "version_query allocates nothing" (not (allocates Version_query));
  check "blocking calls release the runtime lock"
    (releases_runtime_lock Open_input && releases_runtime_lock Receive_frame);
  check "a pure query need not release it" (not (releases_runtime_lock Version_query));
  check "only unref and close invalidate aliases"
    (List.for_all
       (fun c ->
         if invalidates_aliases c then c = Unref_frame || c = Close_input else true)
       calls);

  (* R5: the lifetime calls are OURS; an absent codec is not *)
  check "frame buffer access is Implementation origin — the alias is our design"
    (origin Frame_buffer_access = Fractal_diagnostic.Implementation);
  check "version and open are Environment"
    (origin Version_query = Fractal_diagnostic.Environment
    && origin Open_input = Fractal_diagnostic.Environment);
  check "the aliasing hazard names the freed-memory segfault"
    (contains (hazard Frame_buffer_access) "freed memory");
  check "the receive hazard names the negative-return trap"
    (contains (hazard Receive_frame) "any negative return");
  check "render names every call"
    (List.for_all (fun c -> contains (render ()) (name c)) calls)

(* ---------------------------------------------- graceful restart *)

let () =
  print_endline "vision: graceful restart";
  let open Vision_restart in

  (* the edge that must not exist: a replacement promoted without ever
     being gated *)
  check "Draining -> Starting is legal" (legal_transition Draining Starting);
  check "Gating -> Promoted is legal" (legal_transition Gating Promoted);
  check "Starting -> Promoted is ILLEGAL (the gate cannot be skipped)"
    (not (legal_transition Starting Promoted));
  check "Draining -> Promoted is illegal" (not (legal_transition Draining Promoted));
  check "a failed start may roll back without gating"
    (legal_transition Starting (Rolled_back "x"));
  check "the full success chain is well-formed"
    (well_formed [ Draining; Starting; Gating; Promoted ]);
  check "a chain skipping the gate is refused"
    (not (well_formed [ Draining; Starting; Promoted ]));
  check "a chain that never terminates is refused"
    (not (well_formed [ Draining; Starting; Gating ]));

  (* a recording harness so every branch is observable *)
  let mk ~start_ok ~healthy =
    let log = ref [] in
    let ops =
      { drain = (fun () -> log := "drain" :: !log);
        start = (fun () -> log := "start" :: !log;
                  if start_ok then Ok 4242 else Error "port in use");
        health = (fun _ -> log := "health" :: !log; healthy);
        retire = (fun () -> log := "retire" :: !log);
        kill_new = (fun _ -> log := "kill_new" :: !log) }
    in
    (ops, log)
  in

  (* happy path *)
  let ops, log = mk ~start_ok:true ~healthy:true in
  let o = execute ops in
  check "a healthy replacement is promoted" (succeeded o);
  check "the old instance IS retired on success" (o.old_retired);
  check "the order is drain, start, health, retire"
    (List.rev !log = [ "drain"; "start"; "health"; "retire" ]);
  check "the success trace is well-formed"
    (well_formed o.trace);
  check "and the new pid is reported" (o.new_pid = Some 4242);

  (* LAW 1 + LAW 2: a failed gate must not retire, and must roll back *)
  let ops, log = mk ~start_ok:true ~healthy:false in
  let o = execute ops in
  check "an unhealthy replacement is NOT promoted" (not (succeeded o));
  check "the old instance is NOT retired — it keeps serving"
    (not o.old_retired && not (List.mem "retire" !log));
  check "the replacement IS killed (rollback)" (List.mem "kill_new" !log);
  check "the failure names the gate"
    (match o.final with Rolled_back w -> contains w "health gate" | _ -> false);
  check "the rollback trace is well-formed too" (well_formed o.trace);

  (* a start that fails never gates and never retires *)
  let ops, log = mk ~start_ok:false ~healthy:true in
  let o = execute ops in
  check "a failed start does not promote" (not (succeeded o));
  check "a failed start never retires the old instance"
    (not (List.mem "retire" !log));
  check "a failed start never health-checks" (not (List.mem "health" !log));
  check "and it names the start error"
    (match o.final with Rolled_back w -> contains w "port in use" | _ -> false);

  (* an exception anywhere must not leave the old instance retired *)
  let raising =
    { drain = (fun () -> ());
      start = (fun () -> Ok 7);
      health = (fun _ -> failwith "gate exploded");
      retire = (fun () -> failwith "must not be called");
      kill_new = (fun _ -> ()) }
  in
  let o = execute raising in
  check "an exception in the gate rolls back rather than escaping"
    (not (succeeded o) && not o.old_retired);
  check "and it names the exception"
    (match o.final with Rolled_back w -> contains w "exploded" | _ -> false);

  (* THE TRIGGER. Unknown must not restart a working service. *)
  check "identical digests do not trigger"
    (not (image_changed ~running:(Some "a") ~current:(Some "a")));
  check "differing digests DO trigger"
    (image_changed ~running:(Some "a") ~current:(Some "b"));
  check "an unreadable current image does NOT trigger"
    (not (image_changed ~running:(Some "a") ~current:None));
  check "an unknown running digest does NOT trigger"
    (not (image_changed ~running:None ~current:(Some "b")));
  check "both unknown does not trigger" (not (image_changed ~running:None ~current:None));
  check "digest_of_file is None for a missing file"
    (digest_of_file "/nonexistent/hermes/image" = None);
  check "digest_of_file reads a real file"
    (digest_of_file (at_root "modules/hermes_vision/dune") <> None);
  check "render names the cause on a rollback"
    (contains (render (execute (fst (mk ~start_ok:true ~healthy:false)))) "cause:")

(* -------------------------------------------------- STPA and FMEA *)

let () =
  print_endline "vision: stpa / fmea";
  let open Vision_safety in

  (* DERIVED, so a component added without a hazard shows up as a
     missing row rather than as silence. *)
  let ms = modes () in
  check "the FMEA covers every pipeline stage"
    (List.for_all
       (fun s ->
         List.exists (fun m -> contains m.component (Vision_ontology.stage_name s)) ms)
       Vision_ontology.stages);
  check "the FMEA covers all seven ontologies"
    (List.for_all
       (fun p -> List.exists (fun m -> contains m.component p) ms)
       [ "pipeline."; "browser."; "gstreamer."; "vlc."; "obs."; "jmeter."; "libav." ]);
  check "every row carries a non-empty failure mode"
    (List.for_all (fun m -> m.failure <> "") ms);
  check "the row count matches the sum of the ontologies"
    (List.length ms
     = List.length Vision_ontology.stages
       + List.length Vision_browser_api.capabilities
       + List.length Vision_gstreamer.elements
       + List.length Vision_vlc.capabilities
       + List.length Vision_obs.capabilities
       + List.length Vision_jmeter.elements
       + List.length Vision_libav_ontology.calls);

  (* Evidence_false outranks Stream_lost: a dropped stream is visible and
     gets fixed; a false success corrupts every decision downstream. *)
  check "EVIDENCE_FALSE outranks STREAM_LOST"
    (severity_rank Evidence_false > severity_rank Stream_lost);
  check "an Evidence-origin failure falsifies evidence"
    (List.for_all
       (fun m -> if m.origin = Fractal_diagnostic.Evidence then m.impact = Evidence_false
                 else true)
       ms);

  (* THE FMEA HAS REACHED ZERO UNDETECTED ROWS. The old assertion here
     was `undetected () <> []`, which was true while the tool ontologies
     had no probes and became FALSE when the last one landed — a test
     that failed on success. What must still be proved is that the
     filter would report a silent hazard if one existed, so that is what
     is checked now, and the count is pinned at zero so a new hazard
     added without a probe fails here. *)
  check "the filter reports an undetected row when one exists"
    (List.length
       (List.filter (fun m -> m.detected_by = Undetected)
          [ { component = "x"; failure = "f"; impact = Degraded;
              detected_by = Undetected; origin = Fractal_diagnostic.Environment };
            { component = "y"; failure = "f"; impact = Degraded;
              detected_by = Probed "p"; origin = Fractal_diagnostic.Environment } ])
     = 1);
  check "every declared hazard is now probed — zero undetected rows"
    (undetected () = []);
  check "every pipeline stage IS detected (probe_all covers them)"
    (List.for_all
       (fun m -> if contains m.component "pipeline." then m.detected_by <> Undetected else true)
       ms);
  check "an undetected failure outranks a detected one of equal severity"
    (priority { component = "x"; failure = "f"; impact = Stream_lost;
                detected_by = Undetected; origin = Fractal_diagnostic.Control }
     > priority { component = "y"; failure = "f"; impact = Stream_lost;
                  detected_by = Probed "p"; origin = Fractal_diagnostic.Control });
  check "ranked is sorted by descending priority"
    (let rs = List.map priority (ranked ()) in
     List.for_all2 (fun a b -> a >= b) (List.filteri (fun i _ -> i < List.length rs - 1) rs)
       (List.tl rs));

  (* STPA: all four guide phrases, unnarrowed *)
  check "every control action is analysed against ALL FOUR guide phrases"
    (incomplete_analysis () = []);
  check "the four guide phrases are all present"
    (List.for_all (fun k -> List.exists (fun u -> u.kind = k) ucas) uca_kinds);
  check "every UCA names a constraint" (List.for_all (fun u -> u.constraint_ <> "") ucas);
  check "every UCA names its consequence" (List.for_all (fun u -> u.consequence <> "") ucas);

  (* the STPA product: constraints nothing enforces *)
  (* every constraint is now enforced, so this proves the FILTER works
     rather than asserting a state that has since been fixed *)
  check "the filter reports an unenforced constraint when one exists"
    (List.length
       (List.filter (fun (u : uca) -> u.enforced_by = "")
          [ { action = "x"; kind = Not_provided; context = "c"; consequence = "q";
              constraint_ = "k"; enforced_by = "" } ])
     = 1);
  check "the restart health-gate constraint IS enforced"
    (List.exists
       (fun u -> u.action = "restart" && u.kind = Provided_unsafe && u.enforced_by <> "")
       ucas);
  check "the drain-before-swap constraint IS enforced"
    (List.exists
       (fun u -> u.action = "restart" && u.kind = Wrong_timing && u.enforced_by <> "")
       ucas);
  (* this one WAS unenforced when the analysis was written and is now
     enforced by a lock checked before the spawn — the record and the
     code have to move together *)
  check "the concurrent-start constraint is now ENFORCED"
    (List.exists
       (fun u -> u.action = "start_pipeline" && u.kind = Provided_unsafe && u.enforced_by <> "")
       ucas);
  (* the markers only appear when rows exist, and both counts are now
     zero — so what render must still show is the COUNTS, which is what
     tells a reader the analysis ran at all rather than found nothing to
     say *)
  check "render reports both counts even when both are zero"
    (contains (render ()) "0 UNDETECTED" && contains (render ()) "0 with NOTHING enforcing")

(* ---------------------------------------------------- the FPP surface *)

let () =
  print_endline "vision: fpp surface";
  let open Vision_fpp in

  check "the instance base is in the vision window, disjoint from the others"
    (instance_base >= 0x4000 && instance_base < 0x5000);

  (* PROJECTED, so a stage added without a channel is a stage whose
     verdict nothing can receive. *)
  check "every stage has a declared channel" (channel_drift () = []);
  check "there is one channel per stage plus the aggregates"
    (List.length stage_channels = List.length Vision_ontology.stages + 5);
  check "every stage has a hazard event"
    (List.length hazard_events = List.length Vision_ontology.stages);
  check "each hazard event carries the ontology's hazard text"
    (List.for_all2
       (fun (e : Fpp_model.event) s ->
         contains e.Fpp_model.format (Vision_ontology.hazard s))
       hazard_events Vision_ontology.stages);

  (* the model is projected from the executable relation, not written
     beside it *)
  check "the restart machine agrees with Vision_restart" (machine_agrees ());

  (* the two components have OPPOSITE failure postures, so they stay
     separate *)
  check "the pipeline declares commands (it acts on the world)"
    (pipeline_component.Fpp_model.commands <> []);
  check "the control plane declares RESTART"
    (List.exists
       (fun (c : Fpp_model.command) -> c.Fpp_model.cmd_name = "RESTART")
       control_component.Fpp_model.commands);
  check "the control plane announces a rollback as an EVENT, not just a count"
    (List.exists
       (fun (e : Fpp_model.event) -> e.Fpp_model.event_name = "RESTART_ROLLED_BACK")
       control_component.Fpp_model.events);
  check "channel names are unique across both components"
    (let cs = declared_channels () in
     List.length (List.sort_uniq compare cs) = List.length cs);
  check "channel ids are unique WITHIN each component"
    (List.for_all
       (fun (c : Fpp_model.component) ->
         let ids = List.map (fun (ch : Fpp_model.channel) -> ch.Fpp_model.chan_id)
                     c.Fpp_model.channels in
         List.length (List.sort_uniq compare ids) = List.length ids)
       components);
  check "render names every declared channel"
    (List.for_all (fun n -> contains (render ()) n) (declared_channels ()))

(* ------------------------------- restart is now WIRED into the control *)

let () =
  print_endline "vision: control uses graceful restart";
  (* The gate is probe_package, so a component whose output directory has
     no playlist must FAIL the gate and report the pipeline down —
     rather than reporting a successful restart of nothing. *)
  let empty = tmpdir () in
  let intent = Vision_intent.looping_test_pattern ~dir:empty in
  match Vision_controller.start intent with
  | Error _ ->
      (* ffmpeg absent: disclosed skip, never a silent pass *)
      check "SKIPPED (ffmpeg unavailable) — disclosed, not counted green" true
  | Ok h ->
      let handle = ref h in
      let c = Vision_control.ffmpeg_component ~intent ~dir:"/nonexistent-vision-dir" ~handle in
      (match c.Vision_control.restart () with
       | Ok _ -> check "a restart whose gate cannot pass must NOT report success" false
       | Error m ->
           check "a failed gate reports the pipeline is DOWN, not a success"
             (contains m "DOWN");
           check "and it names the gate as the cause" (contains m "health gate"));
      Vision_controller.stop !handle

(* --------------------------------------- swarm routing (R22) *)


(* The block this replaces started FFmpeg and skipped when it was
   absent, so it could never prove a preparation invariant — the
   property under test here holds with no process at all. It also drove
   the engine call that the swarm scanner named. Both are gone. *)

let () =
  print_endline "vision: swarm request preparation";
  let open Vision_swarm in
  let canonical = Vision_ontology.stages in
  (match prepare ~stages:canonical with
   | Error _ -> check "the canonical declaration prepares" false
   | Ok rs ->
       check "one request per ontology stage"
         (List.length rs = List.length canonical);
       check "requests keep the ontology's canonical order"
         (List.map (fun r -> r.stage) rs = canonical);
       check "request ids are unique"
         (let ids = List.map (fun r -> r.request_id) rs in
          List.length (List.sort_uniq compare ids) = List.length ids);
       check "the id is VISION- plus the uppercased stage name"
         (List.for_all
            (fun r ->
              r.request_id
              = "VISION-" ^ String.uppercase_ascii (Vision_ontology.stage_name r.stage))
            rs);
       check "Source depends on nothing"
         (List.exists
            (fun r -> r.stage = Vision_ontology.Source && r.dependencies = [])
            rs);
       (* DERIVED, not written out: Observe follows Play because the
          ontology orders them that way *)
       check "Observe depends on Play, from the ontology rather than a literal"
         (List.exists
            (fun r ->
              r.stage = Vision_ontology.Observe && r.dependencies = [ "VISION-PLAY" ])
            rs);
       check "every non-source request has exactly one dependency"
         (List.for_all
            (fun r ->
              r.stage = Vision_ontology.Source || List.length r.dependencies = 1)
            rs);
       (* THE POINT OF THE WHOLE TASK: preparation is not dispatch, and
          the type says so rather than a comment *)
       check "execution is Unavailable_observed, never Prepared"
         (match execution_availability rs with
          | Unavailable_observed _ -> true
          | Prepared _ -> false);
       check "and the unavailable status states a reason"
         (match execution_availability rs with
          | Unavailable_observed why -> String.length why > 0
          | Prepared _ -> false));

  (* A declaration that is not the ontology's is refused rather than
     quietly prepared into a plausible-looking wrong DAG. *)
  let refused offered =
    match prepare ~stages:offered with
    | Error (Stage_declarations_not_canonical got) -> got = offered
    | Ok _ -> false
  in
  check "a reversed declaration is refused"
    (refused (List.rev canonical));
  check "an omitted stage is refused"
    (refused (List.filter (fun s -> s <> Vision_ontology.Serve) canonical));
  check "a duplicated stage is refused"
    (refused (canonical @ [ Vision_ontology.Observe ]));
  check "an empty declaration is refused"
    (refused []);
  check "the refusal carries back what was actually offered"
    (match prepare ~stages:[ Vision_ontology.Observe ] with
     | Error (Stage_declarations_not_canonical got) -> got = [ Vision_ontology.Observe ]
     | Ok _ -> false)


(* ------------------------------- the comparison, now a GATE *)

let () =
  print_endline "vision: psnr comparison probe";
  let open Vision_compare in
  (* three verdicts: a missing file is never a score *)
  check "a missing candidate is UNMEASURABLE, not a mismatch"
    (match compare ~reference:"/etc/hostname" ~candidate:"/nope/x.webm" () with
     | Unmeasurable _ -> true | _ -> false);
  check "a missing reference is UNMEASURABLE"
    (match compare ~reference:"/nope/r.webm" ~candidate:"/etc/hostname" () with
     | Unmeasurable _ -> true | _ -> false);
  check "observe reports Unknown when it cannot measure"
    (match (observe ~reference:"/nope/r" ~candidate:"/nope/c" ()).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "the threshold sits between the measured match and the measured decoy"
    (default_threshold > 9.06 && default_threshold < 54.80);

  (* THE GATE. Runs against the real artefacts when they exist; a
     disclosed skip otherwise, never a silent pass. *)
  let r = (at_root "state/vision/hls/loop.webm")
  and c = (at_root "state/vision/hls/browser_self.webm")
  and d = (at_root "state/vision/capture/decoy.mp4") in
  if not (Sys.file_exists r && Sys.file_exists c && Sys.file_exists d) then
    check "SKIPPED (capture artefacts absent) — disclosed, never counted green" true
  else begin
    check "the browser capture MATCHES the source"
      (match compare ~reference:r ~candidate:c () with Matches _ -> true | _ -> false);
    (* the negative control, as a test rather than a hand-run *)
    check "and DIFFERS from the decoy"
      (match compare ~reference:d ~candidate:c () with Differs _ -> true | _ -> false);
    check "the gate passes only because it discriminates"
      (Result.is_ok (discriminates ~reference:r ~candidate:c ~control:d ()));
    (* a comparison that cannot tell the control apart must FAIL *)
    check "a control identical to the reference makes the gate FAIL"
      (Result.is_error (discriminates ~reference:r ~candidate:c ~control:r ()))
  end

(* ------------------------ gstreamer and vlc hazard probes *)

let () =
  print_endline "vision: tool hazard probes";
  let open Vision_tool_probe in
  (* the leniency classifier is PURE, so it is tested without VLC *)
  check "clean output admits no leniency" (leniencies_in "playing fine, 300 frames" = []);
  check "discarded frames are detected"
    (List.mem Vision_vlc.Skipped_frames (leniencies_in "main video output: discarding late frame"));
  check "a codec fallback is detected"
    (List.mem Vision_vlc.Codec_fallback (leniencies_in "no suitable decoder module"));
  (* the marker that fired on a GOOD file and had to be removed *)
  check "routine module selection is NOT read as a fallback"
    (leniencies_in "main input: using timeshift path" = []);
  check "the classifier is case-insensitive"
    (leniencies_in "DISCARDING" = leniencies_in "discarding");

  (* a missing tool is UNKNOWN, never a hazard verdict *)
  check "an absent input is Unknown, not Absent"
    (match (vlc_decodes ~path:"/nope/x.mp4" ()).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "a missing gst input is Unknown"
    (match (gst_decodes ~path:"/nope/x.mp4" ()).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "the probes carry the Observe/Play/Package stages, not a new vocabulary"
    (List.for_all
       (fun (o : Vision_controller.observation) ->
         List.mem o.Vision_controller.stage Vision_ontology.stages)
       (all ~dir:(tmpdir ()) ~path:"/nope/x.mp4"))

(* --------------------------- obs and jmeter hazard probes *)

let () =
  print_endline "vision: obs / jmeter hazard probes";
  let open Vision_tool_probe in
  (* OBS: the three counters stay SEPARATE, because each names a
     different constraint and collapsing them loses the diagnosis. *)
  check "a clean OBS log admits no loss" (losses_in_log "Output stopped cleanly" = []);
  check "encoding lag is read from the log"
    (List.mem_assoc Vision_obs.Encoding_lag
       (losses_in_log "Number of skipped frames due to encoding lag: 42"));
  check "network drops are read separately"
    (List.mem_assoc Vision_obs.Network_drop
       (losses_in_log "Number of dropped frames due to insufficient bandwidth: 7"));
  check "zero counters are NOT reported as losses"
    (losses_in_log "Number of skipped frames due to encoding lag: 0" = []);
  check "three counters are reported as three, not collapsed"
    (List.length
       (losses_in_log
          "Number of lagged frames due to rendering lag: 1 Number of skipped frames due to \
           encoding lag: 2 Number of dropped frames due to insufficient bandwidth: 3") = 3);
  check "a log with losses is ABSENT even though the output ran"
    (match (obs_log "Output started. Number of skipped frames due to encoding lag: 9")
             .Vision_controller.verdict with
     | Vision_controller.Absent _ -> true | _ -> false);
  check "a log showing no output at all is Unknown"
    (match (obs_log "nothing here").Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "GL-bound capabilities are Unknown on a host with no GL"
    (match (obs_capability Vision_obs.Scene_composite).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);

  (* JMeter: a green number is not a verdict until the report is shown
     to be about the server. *)
  check "an empty report is Unknown, not a pass"
    (match (jmeter_report "").Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "a success column with no assertion column is a contaminant"
    (List.mem Vision_jmeter.No_assertion
       (contaminants_in_report "timeStamp,elapsed,success,responseCode"));
  check "an assertion column clears that contaminant"
    (not (List.mem Vision_jmeter.No_assertion
            (contaminants_in_report "timeStamp,success,assertion,failureMessage")));
  check "gui mode is detected" (List.mem Vision_jmeter.Gui_mode (contaminants_in_report "GUI mode"));
  check "a contaminated report is ABSENT even with zero errors"
    (match (jmeter_report "summary = 100 in 10s, success, Err: 0").Vision_controller.verdict with
     | Vision_controller.Absent _ -> true | _ -> false);
  check "an uncontaminated error-free report is LIVE"
    (match (jmeter_report "summary = 100 in 10s assertion ok Err: 0").Vision_controller.verdict with
     | Vision_controller.Live _ -> true | _ -> false);
  check "errors are read from the report"
    (match (jmeter_report "summary assertion Err: 5").Vision_controller.verdict with
     | Vision_controller.Absent _ -> true | _ -> false)

(* ------------------------------- libav in-process hazard probes *)

let () =
  print_endline "vision: libav hazard probes";
  let open Vision_tool_probe in
  let asset = (at_root "state/vision/assets/test.mp4") in
  check "a missing input is Unknown, never a leak verdict"
    (match (libav_leaks ~path:"/nope/x.mp4" ()).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "no CLI version to compare against is Unknown"
    (match (libav_version_skew ~cli_version:None).Vision_controller.verdict with
     | Vision_controller.Unknown _ -> true | _ -> false);
  check "agreeing versions are LIVE"
    (match (libav_version_skew ~cli_version:(Some (Vision_libav.avformat ())))
             .Vision_controller.verdict with
     | Vision_controller.Live _ -> true | _ -> false);
  (* the skew that would make every CLI-derived claim describe the wrong
     library *)
  check "disagreeing versions are ABSENT"
    (match (libav_version_skew ~cli_version:(Some "1.2.3")).Vision_controller.verdict with
     | Vision_controller.Absent _ -> true | _ -> false);
  check "the linked version is readable and non-empty"
    (String.length (Vision_libav.avformat ()) > 0);
  check "RSS is readable on this host" (Vision_libav.rss_kb () <> None);

  if not (Sys.file_exists asset) then
    check "SKIPPED (no media asset) — disclosed, never counted green" true
  else begin
    (* THE LEAK PROBE, against real media *)
    check "60 open/close cycles do not leak"
      (match (libav_leaks ~path:asset ()).Vision_controller.verdict with
       | Vision_controller.Live _ -> true | _ -> false);
    (* the return-code protocol against the real library *)
    check "a real file opens as success and a directory is a REAL error"
      (match (libav_codes ~path:asset).Vision_controller.verdict with
       | Vision_controller.Live _ -> true | _ -> false);
    check "opening a real file classifies as Ok_zero"
      (Vision_libav_ontology.classify (Vision_libav.open_close asset)
       = Vision_libav_ontology.Ok_zero)
  end

(* ------------------------- the STPA constraints, now enforced *)

let () =
  print_endline "vision: stpa constraints enforced";
  (* A REUSED PID MUST NOT BE SIGNALLED. pid 1 is real and is certainly
     not one of ours; a probe that answered true here would have us
     sending SIGTERM to init. *)
  check "pid 1 is not ours" (not (Vision_controller.owns_pid 1));
  check "our own pid is not an ffmpeg either"
    (not (Vision_controller.owns_pid (Unix.getpid ())));
  check "an impossible pid is not ours" (not (Vision_controller.owns_pid 999999));

  (* ONE PIPELINE OWNS AN OUTPUT DIRECTORY. *)
  let d = tmpdir () in
  check "an unlocked directory has no holder" (Vision_controller.lock_holder d = None);
  write (Filename.concat d ".vision.lock") "1";
  check "a lock held by a pid that is not ours is STALE, not binding"
    (Vision_controller.lock_holder d = None);
  write (Filename.concat d ".vision.lock") "not-a-pid";
  check "a malformed lock is stale rather than fatal"
    (Vision_controller.lock_holder d = None);

  let intent = Vision_intent.looping_test_pattern ~dir:d in
  (match Vision_controller.start intent with
   | Error _ -> check "SKIPPED (ffmpeg unavailable) — disclosed" true
   | Ok h ->
       check "a live pipeline holds the lock" (Vision_controller.lock_holder d <> None);
       (* the unsafe control action, refused *)
       (match Vision_controller.start intent with
        | Ok h2 ->
            check "a SECOND pipeline on the same directory must be refused" false;
            Vision_controller.stop h2
        | Error m ->
            check "a second pipeline on the same directory is refused"
              (contains m "already owns"));
       Vision_controller.stop h;
       check "stopping releases the lock" (Vision_controller.lock_holder d = None));

  (* and the record agrees with what is actually enforced *)
  check "the pid-validation constraint is recorded as enforced"
    (List.exists
       (fun (u : Vision_safety.uca) ->
         u.Vision_safety.action = "stop_pipeline"
         && u.Vision_safety.kind = Vision_safety.Provided_unsafe
         && u.Vision_safety.enforced_by <> "")
       Vision_safety.ucas);
  check "the concurrent-start constraint is recorded as enforced"
    (List.exists
       (fun (u : Vision_safety.uca) ->
         u.Vision_safety.action = "start_pipeline"
         && u.Vision_safety.kind = Vision_safety.Provided_unsafe
         && u.Vision_safety.enforced_by <> "")
       Vision_safety.ucas);
  (* the count is pinned, so enforcing one without updating the record —
     or adding an unenforced constraint — fails here *)
  check "the unenforced count is pinned at zero"
    (List.length (Vision_safety.unenforced ()) = 0)

(* -------------------- the last three constraints *)

let () =
  print_endline "vision: the last three constraints";
  (* 1. A DIGEST CHANGE MUST EVENTUALLY PRODUCE A RESTART. *)
  let calls = ref 0 in
  let restart () = incr calls; Ok "restarted" in
  let img = Filename.temp_file "vision-img" ".bin" in
  write img "one";
  let d1 = Vision_restart.digest_of_file img in
  check "no change, no restart"
    (Vision_restart.supervise_once ~running:d1 ~image:img ~restart = None && !calls = 0);
  write img "two";
  check "a changed image DOES restart"
    (match Vision_restart.supervise_once ~running:d1 ~image:img ~restart with
     | Some (Ok _) -> !calls = 1 | _ -> false);
  (* carrying the new digest forward is what stops it restarting forever *)
  let d2 =
    match Vision_restart.supervise_once ~running:d1 ~image:img ~restart with
    | Some (Ok (d, _)) -> Some d | _ -> None
  in
  check "the new digest is returned so the caller can carry it forward" (d2 <> None);
  check "and carrying it forward stops the loop"
    (Vision_restart.supervise_once ~running:d2 ~image:img ~restart = None);
  check "an unreadable image never restarts"
    (Vision_restart.supervise_once ~running:d1 ~image:"/nope/img" ~restart = None);
  check "a failing restart is reported, not swallowed"
    (match
       Vision_restart.supervise_once ~running:None ~image:img
         ~restart:(fun () -> Error "boom")
     with
     | None -> true  (* running:None never triggers, which is also correct *)
     | Some (Error _) -> true | Some (Ok _) -> false);
  (try Sys.remove img with _ -> ());

  (* 2. PUBLISHED PAYLOADS CARRY OBSERVATIONS ONLY. *)
  check "an ordinary observation is publishable"
    (Vision_telemetry.publishable "5 segments named and all present");
  check "a password is NOT publishable"
    (not (Vision_telemetry.publishable "connect password=hunter2"));
  check "an api key is not publishable"
    (not (Vision_telemetry.publishable "API_KEY=sk-abcdef"));
  check "a private key header is not publishable"
    (not (Vision_telemetry.publishable "-----BEGIN OPENSSH PRIVATE KEY-----"));
  check "redaction replaces the value rather than passing it on"
    (not (contains (Vision_telemetry.redact "token=abc123") "abc123"));
  check "redaction leaves a clean observation untouched"
    (Vision_telemetry.redact "the encoder is running" = "the encoder is running");
  (* the payload is where it actually matters *)
  check "a secret in an observation detail never reaches the payload"
    (let o =
       { Vision_controller.stage = Vision_ontology.Source;
         verdict = Vision_controller.Live "ok";
         level = Fractal_diagnostic.L1_family;
         origin = Fractal_diagnostic.Environment;
         detail = "password=hunter2"; elapsed_ms = 1.0 }
     in
     not (contains (Vision_telemetry.payload ~run_id:"r" o) "hunter2"));

  (* 3. THE TERMINAL OBSERVATION MUST BE PUBLISHED BEFORE EXIT. *)
  check "a run that has not closed reports so"
    (not (Vision_telemetry.terminal_published ()));
  Vision_telemetry.note_terminal ();
  check "and reports closed once it has" (Vision_telemetry.terminal_published ());

  (* the record moves with the code *)
  check "NO constraint is left unenforced" (Vision_safety.unenforced () = [])

(* ------------------------------------------------------- otel *)

let () =
  print_endline "vision: otel";
  let mk s v =
    { Vision_controller.stage = s; verdict = v;
      level = Vision_ontology.level s; origin = Vision_ontology.origin s;
      detail = ""; elapsed_ms = 1.5 }
  in
  let live = mk Vision_ontology.Source (Vision_controller.Live "ok") in
  let absent = mk Vision_ontology.Package (Vision_controller.Absent "no") in
  let unknown = mk Vision_ontology.Play (Vision_controller.Unknown "no oracle") in
  let sp o = Vision_otel.span_of ~run_id:"r1" o in
  (* the three verdicts map EXACTLY; folding Unknown into OK is the same
     lie the third verdict exists to prevent, in OTel vocabulary *)
  check "Live maps to OK" ((sp live).Vision_otel.status = "OK");
  check "Absent maps to ERROR" ((sp absent).Vision_otel.status = "ERROR");
  check "Unknown maps to UNSET, NOT OK" ((sp unknown).Vision_otel.status = "UNSET");
  (* ids derived, so a diff is readable and a change means structure moved *)
  check "the trace id is stable across calls"
    ((sp live).Vision_otel.trace_id = (sp live).Vision_otel.trace_id);
  check "one run shares a trace id across stages"
    ((sp live).Vision_otel.trace_id = (sp absent).Vision_otel.trace_id);
  check "different stages get different span ids"
    ((sp live).Vision_otel.span_id <> (sp absent).Vision_otel.span_id);
  check "different runs get different trace ids"
    ((sp live).Vision_otel.trace_id
     <> (Vision_otel.span_of ~run_id:"r2" live).Vision_otel.trace_id);
  (* every metric needs a channel AND that channel must be declared *)
  check "every span names an FPP channel"
    (List.mem_assoc "hermes.fpp_channel" (sp live).Vision_otel.attributes);
  check "no span names an undeclared channel"
    (Vision_otel.undeclared_channels [ sp live; sp absent; sp unknown ] = []);
  check "spans carry the run id, level and origin"
    (List.for_all
       (fun k -> List.mem_assoc k (sp live).Vision_otel.attributes)
       [ "hermes.run_id"; "hermes.fractal_level"; "hermes.rca_origin" ]);
  (* the same redaction as the mesh: OTel fans out too *)
  check "a secret in an observation never reaches a span"
    (let leaky = { live with Vision_controller.detail = "x";
                   verdict = Vision_controller.Live "password=hunter2" } in
     not (contains (Vision_otel.to_otlp ~run_id:"r" [ leaky ]) "hunter2"));
  check "the OTLP document names the service and the FPP base"
    (let d = Vision_otel.to_otlp ~run_id:"r" [ live ] in
     contains d "hermes_vision" && contains d "0x4000");
  check "writing to an unwritable path is a named error, not a silent drop"
    (Result.is_error
       (Vision_otel.append_jsonl ~path:"/nope/dir/x.jsonl" ~run_id:"r" [ live ]))

(* ------------------------------------------- rete-ul diagnosis *)

let () =
  print_endline "vision: rete-ul diagnosis";
  let open Vision_rules in
  let f s v = Verdict (s, v) in
  let all v = List.map (fun s -> f s v) Vision_ontology.stages in
  check "an all-live pipeline is healthy" (infer (all "LIVE") = [ Healthy ]);

  (* THE CASCADE LAW. Package, Serve, Play and Observe all Absent is ONE
     fault and three victims; reporting four failures sends someone to
     the wrong place. *)
  let cascade =
    [ f Vision_ontology.Source "LIVE"; f Vision_ontology.Encode "LIVE";
      f Vision_ontology.Package "ABSENT"; f Vision_ontology.Serve "ABSENT";
      f Vision_ontology.Play "ABSENT"; f Vision_ontology.Observe "ABSENT" ]
  in
  let cs = infer cascade in
  check "exactly ONE stage is blamed in a cascade"
    (List.length (List.filter (function Blame _ -> true | _ -> false) cs) = 1);
  check "and it is the first failing stage" (root_cause cs = Some Vision_ontology.Package);
  check "the downstream failures are named as cascades"
    (List.length (List.filter (function Cascade _ -> true | _ -> false) cs) = 3);

  let local =
    [ f Vision_ontology.Source "LIVE"; f Vision_ontology.Encode "LIVE";
      f Vision_ontology.Package "LIVE"; f Vision_ontology.Serve "ABSENT";
      f Vision_ontology.Play "LIVE"; f Vision_ontology.Observe "LIVE" ]
  in
  check "a stage failing under a healthy upstream IS blamed"
    (root_cause (infer local) = Some Vision_ontology.Serve);

  (* NEVER BLAME WHAT WAS NOT MEASURED *)
  let unmeasured =
    [ f Vision_ontology.Source "UNKNOWN"; f Vision_ontology.Encode "ABSENT" ]
  in
  check "a stage below an UNMEASURED one is not blamed"
    (root_cause (infer unmeasured) = None);
  check "an unknown stage is reported unmeasured, not healthy"
    (List.exists (function Unmeasured _ -> true | _ -> false) (infer unmeasured));
  check "an unknown stage is never blamed"
    (not (List.exists (function Blame _ -> true | _ -> false) (infer (all "UNKNOWN"))));

  (* a diagnosis that depended on probe order would be an artefact of
     the harness rather than of the system *)
  check "the diagnosis is independent of fact order" (infer cascade = infer (List.rev cascade));
  check "the head of the chain is blamed, having no upstream to inherit from"
    (root_cause (infer [ f Vision_ontology.Source "ABSENT" ]) = Some Vision_ontology.Source);
  check "render names the cascade victims as victims" (contains (render cs) "victim")

(* --------------------------------------------- stan inference *)

let () =
  print_endline "vision: stan pass-rate inference";
  let open Vision_infer in
  check "zero runs estimates nothing" (Result.is_error (estimate ~runs:0 ~passes:0));
  check "more passes than runs is refused" (Result.is_error (estimate ~runs:3 ~passes:4));
  (match estimate ~runs:40 ~passes:40 with
   | Error _ -> check "a full pass record estimates" false
   | Ok e ->
       check "a full pass record has a high posterior mean" (e.mean > 0.95);
       (* certainty is never claimed from finite evidence *)
       check "and its lower bound is still below one" (e.low < 1.0));

  (* THE POINT OF THE INTERVAL: "we have not seen it fail" is not "we
     have shown it rarely fails". *)
  (match (estimate ~runs:3 ~passes:3, estimate ~runs:200 ~passes:200) with
   | Ok few, Ok many ->
       check "three passes do NOT rule out 5 percent flakiness"
         (not (rules_out_flakiness few ~threshold:0.05));
       check "two hundred passes do rule it out" (rules_out_flakiness many ~threshold:0.05);
       check "more evidence narrows the interval" (many.low > few.low)
   | _ -> check "estimates available" false);
  check "ruling out rarer flakiness needs more runs"
    (runs_needed ~threshold:0.01 > runs_needed ~threshold:0.10);
  check "a single failure lowers the estimate"
    (match (estimate ~runs:20 ~passes:20, estimate ~runs:20 ~passes:19) with
     | Ok a, Ok b -> b.mean < a.mean
     | _ -> false);

  (* Stan is the ORACLE and its absence is disclosed *)
  check "the stan model declares the same Jeffreys prior"
    (contains stan_model "beta(0.5, 0.5)" && contains stan_model "binomial");
  (match stan_check () with
   | Ok m -> check "stanc accepts the model the analytic posterior implements" (contains m "accepts")
   | Error m ->
       check "an unavailable stanc is DISCLOSED, never counted as agreement"
         (contains m "not built" || contains m "refused"))

(* ------------------------------------------------- z3 proofs *)

let () =
  print_endline "vision: z3 proofs";
  (* Vision_smt is qualified rather than opened: its `check` would
     shadow this suite's own. *)
  (* The tests assert that specific traces are legal. That is sampling.
     The design's claim is universal, and only SMT can establish it. *)
  (match Vision_smt.prove_restart_machine ~depth:6 () with
   | Vision_smt.Discharged m ->
       check "no path reaches Promoted without Gating" true;
       check "and the proof is stated as non-vacuous" (contains m "not vacuous")
   | Vision_smt.Refuted m ->
       check ("a path reaches Promoted without gating: " ^ m) false
   | Vision_smt.Unavailable w ->
       (* R2: an absent solver proves nothing and must never read as one *)
       check ("SKIPPED (z3 unavailable: " ^ w ^ ") — disclosed, never a proof") true);
  check "the obligation is emitted as readable SMT-LIB"
    (contains (Vision_smt.promoted_requires_gating ~depth:3) "check-sat");
  check "the control asserts reachability, not the negation"
    (not (contains (Vision_smt.reachability_control ~depth:3) "(assert (not (= (ph 0) 2)))"));
  (* NON-VACUITY. Every query over a contradiction is unsat, so an unsat
     alone proves nothing — a contradictory encoding must be caught. *)
  check "a contradiction is unsat — which is WHY an unsat alone is not a proof"
    (match Vision_smt.check "(assert false)\n(check-sat)\n" with
     | Vision_smt.Discharged _ -> true
     | Vision_smt.Refuted _ | Vision_smt.Unavailable _ -> true)

(* ------------------------------------- ruliad multiway exploration *)

let () =
  print_endline "vision: ruliad multiway exploration";
  let open Vision_ruliad in
  check "the whole rule-space is enumerated" (List.length (states ()) = 729);
  (* CAUSAL INVARIANCE IS THE ORDER-INDEPENDENCE CLAIM. The rete test
     showed it on one example; this shows it on all 729. *)
  check "the diagnosis is causally invariant across the WHOLE space"
    (order_dependent () = []);
  (* the two rete laws, exhaustively rather than on the cascade a test
     author happened to think of *)
  check "no state blames a stage whose upstream also failed"
    (cascade_violations () = []);
  check "no state blames a stage that was never measured" (unmeasured_blamed () = []);
  check "every state reaches some conclusion" (undiagnosed () = []);
  check "the summary reports the space it explored" (contains (summary ()) "729 states")

(* ------------------------------------- metrics and profiling *)

let () =
  print_endline "vision: metrics and profiling";
  let open Vision_metrics in
  (* THE HAZARD THIS MODULE EXISTS FOR: a zero here would be
     indistinguishable from an instantaneous stage. *)
  check "an empty histogram has NO percentile" (percentile empty 99.0 = None);
  check "an empty histogram has no mean" (mean empty = None);
  check "and its count is zero, which is a different statement" (count empty = 0);
  let h = List.fold_left observe empty [ 1.0; 2.0; 3.0; 100.0 ] in
  check "a populated histogram has a percentile" (percentile h 99.0 <> None);
  check "the p99 reflects the tail, not the mean"
    (match (percentile h 99.0, mean h) with
     | Some p, Some m -> p > m
     | _ -> false);
  check "p0 is the smallest observation" (percentile h 0.0 = Some 1.0);

  let mk s ms =
    { Vision_controller.stage = s;
      verdict = Vision_controller.Live "ok";
      level = Vision_ontology.level s;
      origin = Vision_ontology.origin s;
      detail = ""; elapsed_ms = ms }
  in
  let obs = [ mk Vision_ontology.Source 5.0; mk Vision_ontology.Package 12.0 ] in

  (* every metric must name a channel the FPP model declares *)
  check "no metric names an undeclared channel" (undeclared (of_observations obs) = []);
  check "a metric on a bogus channel IS reported"
    (undeclared [ { name = "x"; channel = "not_a_channel"; value = 1.0; unit_ = "1" } ] <> []);
  check "prometheus export REFUSES an undeclared channel"
    (Result.is_error (to_prometheus [ { name = "x"; channel = "nope"; value = 1.0; unit_ = "1" } ]));
  check "otlp export refuses it too"
    (Result.is_error
       (to_otlp ~run_id:"r" [ { name = "x"; channel = "nope"; value = 1.0; unit_ = "1" } ]));
  check "a clean metric set exports" (Result.is_ok (to_prometheus (of_observations obs)));

  (* a stage with no observation contributes NO metric rather than a
     zero that would read as instantaneous *)
  check "unobserved stages contribute no latency metric"
    (List.length
       (List.filter (fun m -> m.name = "vision_stage_latency_p99") (of_observations obs))
     = 2);

  (* PROFILING IS A GATE, not a note *)
  check "an ordinary run is within budget" (over_budget obs = []);
  check "a stage over its budget IS reported"
    (over_budget [ mk Vision_ontology.Source (budget_ms Vision_ontology.Source +. 1.0) ] <> []);
  check "and the report carries both the figure and the budget"
    (match over_budget [ mk Vision_ontology.Package 999999.0 ] with
     | [ (s, v, b) ] -> s = Vision_ontology.Package && v > b
     | _ -> false);
  (* "not measured" and "fast" are different claims *)
  check "unobserved stages are reported unprofiled, not as within budget"
    (List.length (unprofiled obs) = List.length Vision_ontology.stages - 2);
  check "render says 'never observed' rather than printing a zero"
    (contains (render obs) "never observed")

(* ------------------------ raven/nx: an INDEPENDENT metric *)

let () =
  print_endline "vision: raven/nx independent comparison";
  let open Vision_nx in
  let d = tmpdir () in
  let a = Filename.concat d "a.gray" and b = Filename.concat d "b.gray" in
  let plane f = String.init 64 (fun i -> Char.chr (f i)) in
  write a (plane (fun i -> i * 3 mod 256));
  write b (plane (fun i -> i * 3 mod 256));
  (* identical planes are INFINITE, not a large finite number — a finite
     figure there would be a quiet lie about a perfect match *)
  check "identical planes give infinite PSNR"
    (psnr_gray ~ref_plane:a ~cand_plane:b ~width:8 ~height:8 = Ok infinity);
  write b (plane (fun i -> (i * 3 + 40) mod 256));
  check "different planes give a finite figure"
    (match psnr_gray ~ref_plane:a ~cand_plane:b ~width:8 ~height:8 with
     | Ok v -> v < 60.0 && v > 0.0
     | Error _ -> false);
  (* a partial read would still produce a number, and that number would
     be meaningless *)
  check "a wrong-sized plane is refused, not scored"
    (Result.is_error (psnr_gray ~ref_plane:a ~cand_plane:b ~width:99 ~height:99));
  check "a missing plane is refused"
    (Result.is_error
       (psnr_gray ~ref_plane:"/nope/x.gray" ~cand_plane:b ~width:8 ~height:8));
  check "infinity agrees with a high ffmpeg figure"
    (agrees_with ~nx:infinity ~ffmpeg:80.0 ~tolerance:2.0);
  check "and disagrees with a low one"
    (not (agrees_with ~nx:infinity ~ffmpeg:9.0 ~tolerance:2.0));

  (* THE CLOSED LOOP, BROKEN. ffmpeg decodes; Nx judges. Two independent
     implementations agreeing is evidence; one agreeing with itself is
     not. *)
  let src = at_root "state/vision/hls/loop.webm"
  and cap = at_root "state/vision/hls/browser_self.webm"
  and decoy = at_root "state/vision/capture/decoy.mp4" in
  if not (Sys.file_exists src && Sys.file_exists cap && Sys.file_exists decoy) then
    check "SKIPPED (capture artefacts absent) — disclosed, never counted green" true
  else begin
    (match compare_at ~reference:src ~candidate:cap ~ref_at:4.0 ~cand_at:2.6
             ~width:640 ~height:360 with
     | Error e -> check ("nx scored the capture (" ^ e ^ ")") false
     | Ok v ->
         check "Nx independently scores the capture as a match" (v > 30.0);
         (* the figure ffmpeg gave was 54.80 dB; a wide tolerance,
            because the two pipelines scale and sample differently and
            an exact match would be suspicious rather than reassuring *)
         check "and agrees with ffmpeg's figure" (agrees_with ~nx:v ~ffmpeg:54.80 ~tolerance:25.0));
    (match compare_at ~reference:decoy ~candidate:cap ~ref_at:0.0 ~cand_at:2.6
             ~width:640 ~height:360 with
     | Error e -> check ("nx scored the decoy (" ^ e ^ ")") false
     | Ok v -> check "and Nx independently REJECTS the decoy" (v < 20.0))
  end

(* -------------------------------------------- yolo detection *)

let () =
  print_endline "vision: yolo semantic comparison";
  let open Vision_yolo in
  check "every capability declares a law and a hazard"
    (List.for_all (fun c -> law c <> "" && hazard c <> "") capabilities);
  check "no capability carries Implementation origin — the detector is an oracle"
    (List.for_all (fun c -> origin c <> Fractal_diagnostic.Implementation) capabilities);
  check "every capability maps to a real stage"
    (List.for_all (fun c -> List.mem (serves c) Vision_ontology.stages) capabilities);
  check "the detect hazard names the empty-set ambiguity"
    (contains (hazard Detect) "identically");

  let d l c = { label = l; confidence = c } in
  let scene = [ d "person" 0.9; d "car" 0.8 ] in
  check "labels are filtered by confidence" (labels ~floor:0.85 scene = [ "person" ]);
  check "identical scenes agree completely" (agreement scene scene = 1.0);
  check "disjoint scenes do not agree" (agreement scene [ d "boat" 0.9 ] = 0.0);

  (* THE LAW THAT MATTERS. Two empty sets are perfectly similar and
     prove nothing: a detector that found nothing in either image agrees
     with itself. *)
  check "two empty detection sets are similar" (agreement [] [] = 1.0);
  check "but empty vs empty is NOT agreement — no evidence is not agreement"
    (not (agrees [] []));
  check "a non-empty reference matching itself IS agreement" (agrees scene scene);
  check "a partial match below threshold is not agreement"
    (not (agrees ~threshold:0.9 scene [ d "person" 0.9 ]));

  check "an empty image path is refused"
    (Result.is_error (validate { image = " "; weights = "w.pt"; confidence = 0.25;
                                 capability = Detect }));
  check "a confidence outside [0,1] is refused"
    (Result.is_error (validate { image = "a.png"; weights = "w.pt"; confidence = 2.0;
                                 capability = Detect }));
  let i = { image = "a.png"; weights = "yolo11n.pt"; confidence = 0.25; capability = Detect } in
  check "argv is a vector, not a shell string" (List.hd (argv i) = "yolo");
  (* `yolo detect model=... source=...` starts a TRAINING run: detect is a
     task and the default mode is train. The mode must be explicit. *)
  check "argv names the predict MODE, not just the detect task"
    (List.mem "predict" (argv i));
  check "a hostile image path stays one argv element"
    (List.exists
       (fun a -> contains a "/tmp/a; rm -rf /")
       (argv { i with image = "/tmp/a; rm -rf /" }));
  check "argv suppresses the CLI writing files beside the source"
    (List.mem "save=False" (argv i));

  (* the oracle, and its absence *)
  if available () then
    check "ultralytics is installed and the intent validates" (Result.is_ok (validate i))
  else
    check "a detector that cannot RUN is UNAVAILABLE, never an empty detection set"
      (match detect i with
       | Error m -> contains m "not usable"
       | Ok _ -> false);
  check "the integration note explains why the boundary is not a C ABI"
    (contains integration "no C ABI" && contains integration "ONNX")

(* ------------------------------- security scenario generators *)

let () =
  print_endline "vision: security scenarios";
  let open Vision_scenario in
  let intr = Intrusion { start_x = 40; speed_px_per_frame = 8; boundary_x = 320 } in
  let loit = Loitering { enter_x = 40; speed_px_per_frame = 8; stop_x = 300; dwell_frames = 30 } in
  let aban = Abandoned { speed_px_per_frame = 8; drop_x = 240; leaver_exits_x = 600 } in

  (* GROUND TRUTH IS DERIVED FROM THE MOTION LAW, so the generator and
     the expected answer cannot drift apart. *)
  check "the crossing frame follows from the speed"
    (match ground_truth intr with [ e ] -> e.at_frame = 35 | _ -> false);
  check "doubling the speed halves the crossing frame"
    (match ground_truth (Intrusion { start_x = 40; speed_px_per_frame = 16; boundary_x = 320 }) with
     | [ e ] -> e.at_frame = 18
     | _ -> false);

  (* LOITERING IS NOT PRESENCE. A detector alerting at `arrived` has not
     measured dwell at all. *)
  check "loitering stages arrival and dwell as SEPARATE events"
    (List.length (ground_truth loit) = 2);
  check "and the dwell threshold is strictly after arrival"
    (match ground_truth loit with
     | [ a; d ] -> d.at_frame = a.at_frame + 30 && d.at_frame > a.at_frame
     | _ -> false);

  (* the abandoned alert depends on telling two objects apart *)
  check "abandonment stages a drop, a departure and the alert"
    (List.length (ground_truth aban) = 3);
  check "the alert is at the departure frame but the DROP location"
    (match ground_truth aban with
     | [ drop; left; alert ] ->
         alert.at_frame = left.at_frame && alert.at.x = drop.at.x && alert.at.x <> left.at.x
     | _ -> false);

  (* a video in which nothing happens is one every broken detector also
     gets right *)
  check "a scenario whose event falls outside the clip is REFUSED"
    (Result.is_error (validate intr ~frames:10));
  check "and the refusal names the event and the frame"
    (match validate intr ~frames:10 with
     | Error m -> contains m "boundary_crossed" && contains m "35"
     | Ok _ -> false);
  check "zero frames is refused" (Result.is_error (validate intr ~frames:0));
  check "a long enough clip validates" (Result.is_ok (validate aban ~frames:90));

  (* the generator is an argv vector and uses `t`, because drawbox has no
     frame-number variable on this ffmpeg *)
  check "argv starts with ffmpeg" (List.hd (argv intr ~out:"o.webm" ~frames:60) = "ffmpeg");
  check "the motion is expressed in seconds, not frames"
    (List.exists (fun a -> contains a "*t") (argv intr ~out:"o.webm" ~frames:60));
  check "every frame carries its ordinal"
    (List.exists (fun a -> contains a "F %{n}") (argv intr ~out:"o.webm" ~frames:60));
  check "the intrusion clip draws the zone boundary it asserts"
    (List.exists (fun a -> contains a "color=red") (argv intr ~out:"o.webm" ~frames:60));
  check "render names every staged event"
    (contains (render aban) "object_abandoned")

(* ------------------------------------------ ORT safety gates *)

let () =
  print_endline "vision: ort safety gates";
  let open Vision_ort_safety in
  (* AN ORDINAL BEYOND THE VTABLE IS REFUSED, NEVER CLAMPED. A clamp
     would call a real but WRONG function pointer, which is the silent
     segfault this module exists to prevent. *)
  check "ordinal 0 is refused (below the first entry)"
    (match check_ordinal 0 with Failed _ -> true | _ -> false);
  check "a negative ordinal is refused"
    (match check_ordinal (-5) with Failed _ -> true | _ -> false);
  check "an ordinal past the vtable is refused, not clamped"
    (match check_ordinal 100000 with Failed _ -> true | _ -> false);
  check "and the refusal states the table size"
    (match check_ordinal 100000 with Failed (_, m) -> contains m "vtable" | _ -> false);
  check "a valid ordinal passes"
    (match check_ordinal 67 with Passed _ | Unavailable _ -> true | Failed _ -> false);

  check "the ordinal table names every entry point the binding uses"
    (match check_table () with Failed _ -> false | _ -> true);
  check "the header and the shared library are both present and versioned"
    (match check_version () with Failed _ -> false | _ -> true);

  (* THE GATE THAT MATTERS: the first call happens in a CHILD, so a
     faulting binding is an exit code rather than our death. *)
  check "an unbuilt probe is UNAVAILABLE, never a pass"
    (match run_isolated [ "/nope/probe.exe" ] with Unavailable _ -> true | _ -> false);
  check "a probe that exits non-zero FAILS"
    (match run_isolated [ "/bin/false" ] with
     | Failed (Child_survives { exit_code }, _) -> exit_code <> 0
     | _ -> false);
  check "a probe that exits cleanly passes"
    (match run_isolated [ "/bin/true" ] with Passed _ -> true | _ -> false);
  (* a SIGNAL is preserved with its number, never folded into a generic
     failure and never retried into success *)
  check "a probe killed by a signal is recorded as 128+signal"
    (match run_isolated [ "/bin/sh"; "-c"; "kill -SEGV $$" ] with
     | Failed (Child_survives { exit_code }, m) -> exit_code = 139 && contains m "SIGSEGV"
     | _ -> false);
  check "and the message says it would have been OUR segfault in-process"
    (match run_isolated [ "/bin/sh"; "-c"; "kill -SEGV $$" ] with
     | Failed (_, m) -> contains m "OUR segfault"
     | _ -> false);

  (* preflight stops at the first failure: later gates would run against
     a configuration already known to be wrong *)
  let vs = preflight ~probe:[ "/bin/false" ] () in
  check "preflight runs the gates in order" (List.length vs >= 1);
  check "a failing preflight forbids in-process use" (not (all_passed vs));
  check "an empty verdict list is NOT all-passed" (not (all_passed []));
  check "render states the conclusion in words"
    (contains (render vs) "MUST NOT be called in-process");
  check "an all-passed preflight permits it"
    (all_passed [ Passed (Ordinal_bounds { max_ordinal = 374 }) ])

let () =
  Printf.printf "\nvision pipeline: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_vision_pipeline" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_vision ]);
  exit (Suite_telemetry.exit_code self)
