(* Declarative intent for the vision pipeline. See vision_intent.mli. *)

type codec = H264 | H265 | VP8 | Copy

type source =
  | Test_pattern of { width : int; height : int; rate : int; label : string }
  | Loop_file of { path : string }
  | Udp_ingest of { port : int }

type sink =
  | Hls of { dir : string; segment_seconds : int; window : int }
  | Udp_out of { host : string; port : int }
  | Mp4_file of { path : string }
  | Discard

type intent = {
  source : source;
  codec : codec;
  sink : sink;
  loop : bool;
  realtime : bool;
  duration_s : int option;
}

let codec_name = function H264 -> "h264" | H265 -> "h265" | VP8 -> "vp8" | Copy -> "copy"

let source_name = function
  | Test_pattern _ -> "test_pattern"
  | Loop_file _ -> "loop_file"
  | Udp_ingest _ -> "udp_ingest"

let sink_name = function
  | Hls _ -> "hls" | Udp_out _ -> "udp_out" | Mp4_file _ -> "mp4_file" | Discard -> "discard"

let encoder = function
  | H264 -> "libx264"
  | H265 -> "libx265"
  | VP8 -> "libvpx"
  | Copy -> "copy"

let port_ok p = p >= 1 && p <= 65535

let validate i =
  match i.source with
  | Test_pattern { width; height; _ } when width <= 0 || height <= 0 ->
      Error "test pattern geometry must be positive"
  | Test_pattern { rate; _ } when rate <= 0 -> Error "test pattern rate must be positive"
  | Loop_file { path } when String.trim path = "" -> Error "loop file path is empty"
  | Udp_ingest { port } when not (port_ok port) -> Error "udp ingest port out of range"
  | _ -> (
      match i.sink with
      | Hls { dir; _ } when String.trim dir = "" -> Error "hls directory is empty"
      | Hls { segment_seconds; _ } when segment_seconds <= 0 ->
          Error "hls segment length must be positive"
      | Hls { window; _ } when window <= 0 -> Error "hls window must hold at least one segment"
      | Udp_out { port; _ } when not (port_ok port) -> Error "udp out port out of range"
      | Udp_out { host; _ } when String.trim host = "" -> Error "udp out host is empty"
      | Mp4_file { path } when String.trim path = "" -> Error "mp4 output path is empty"
      | _ -> (
          match i.duration_s with
          | Some d when d <= 0 -> Error "duration must be positive when given"
          | _ -> Ok i))

(* The frame number is drawn by ffmpeg itself (%{n}), so the burnt-in
   number is the ENCODER's frame index rather than something this module
   counts and hopes agrees. That is what a later comparison reads back. *)
let source_argv = function
  | Test_pattern { width; height; rate; label } ->
      let filter =
        Printf.sprintf
          "testsrc2=size=%dx%d:rate=%d,drawtext=text='%s %%{n}':fontsize=28:fontcolor=white:x=20:y=20:box=1:boxcolor=black@0.6"
          width height rate label
      in
      [ "-f"; "lavfi"; "-i"; filter ]
  | Loop_file { path } -> [ "-stream_loop"; "-1"; "-i"; path ]
  | Udp_ingest { port } -> [ "-i"; Printf.sprintf "udp://0.0.0.0:%d" port ]

let sink_argv = function
  | Hls { dir; segment_seconds; window } ->
      [ "-f"; "hls";
        "-hls_time"; string_of_int segment_seconds;
        "-hls_list_size"; string_of_int window;
        (* delete_segments keeps the directory bounded: an unbounded live
           stream that never deletes fills the disk, and a full disk is a
           failure mode that looks like a decoder bug from the browser. *)
        "-hls_flags"; "delete_segments+append_list";
        Filename.concat dir "stream.m3u8" ]
  | Udp_out { host; port } -> [ "-f"; "mpegts"; Printf.sprintf "udp://%s:%d" host port ]
  (* faststart moves the moov atom to the front so the browser can begin
     decoding without fetching the whole file; yuv420p because Chromium
     will not decode the 4:4:4 that libx264 otherwise picks for RGB
     input, and that failure looks exactly like the Play hazard — a
     player that reports readiness and paints nothing. *)
  | Mp4_file { path } -> [ "-movflags"; "+faststart"; "-pix_fmt"; "yuv420p"; "-y"; path ]
  | Discard -> [ "-f"; "null"; "-" ]

let argv i =
  let codec_args =
    match i.codec with
    | Copy -> [ "-c"; "copy" ]
    | c -> [ "-c:v"; encoder c; "-preset"; "ultrafast"; "-tune"; "zerolatency"; "-g"; "30" ]
  in
  List.concat
    [ [ "ffmpeg"; "-hide_banner"; "-loglevel"; "error" ];
      (if i.realtime then [ "-re" ] else []);
      (* -stream_loop belongs before -i and is already emitted by
         Loop_file; for a synthetic source the filter runs forever, so
         loop adds nothing and must not add a second -stream_loop. *)
      source_argv i.source;
      codec_args;
      (match i.duration_s with Some d -> [ "-t"; string_of_int d ] | None -> []);
      sink_argv i.sink ]

(* There is no shell, so the question is only whether a value could be
   MISREAD as syntax if one were ever reintroduced. Newlines and NULs are
   refused outright because they break any log or argv dump; the rest are
   safe as literal argv elements. *)
let argv_is_shell_free i =
  List.for_all
    (fun a -> not (String.exists (fun c -> c = '\n' || c = '\000') a))
    (argv i)

let describe i =
  Printf.sprintf "%s -> %s -> %s%s%s"
    (source_name i.source) (codec_name i.codec) (sink_name i.sink)
    (if i.loop then " (looping)" else "")
    (match i.duration_s with Some d -> Printf.sprintf " for %ds" d | None -> " unbounded")

let looping_test_pattern ~dir =
  { source = Test_pattern { width = 640; height = 360; rate = 15; label = "HERMES" };
    codec = H264;
    sink = Hls { dir; segment_seconds = 1; window = 5 };
    loop = true;
    realtime = true;
    duration_s = None }

(* Real encoded content rather than a synthetic pattern: a decoder path
   that testsrc2 never exercises. Kept realtime so it is paced like a
   live source, and looped so the transport is exercised across the
   file boundary — where a naive packager stalls. *)
let looping_source_file ~path ~dir =
  { source = Loop_file { path };
    codec = H264;
    sink = Hls { dir; segment_seconds = 1; window = 5 };
    loop = true;
    realtime = true;
    duration_s = None }
