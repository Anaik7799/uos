open Ffmpeg_ontology
open Ffmpeg_algebra
open Ffmpeg_intent

let test_algebra () =
  let f1 = Scale (1920, 1080) in
  let f2 = Scale (1280, 720) in
  let res = compose_filters f1 f2 in
  assert (res = Scale (1280, 720));
  
  let node = { id = "test1"; source = "udp://1.2.3.4"; hw_accel = None; video_codec = Some H264; filters = []; output_format = MPEGTS; sink = "rtsp://out" } in
  let t_node = transmux node WebRTC "ws://out" in
  assert (t_node.video_codec = None);
  assert (t_node.output_format = WebRTC)

let test_intent () =
  let intent = Transmux_Stream { source = "udp://:5000"; sink = "webrtc://out" } in
  let cmd = compile_intent intent in
  assert (cmd = "ffmpeg -i udp://:5000 -c copy -f mpegts webrtc://out")

let () =
  test_algebra ();
  test_intent ();
  print_endline "FFmpeg Swarm Integration tests passed!";
  let self =
    Suite_telemetry.observe ~suite:"test_ffmpeg_swarm" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
