(* Fractal ontology of VLC. See the .mli: VLC's character is
   forgiveness, and forgiveness is the hazard. *)

type state =
  | Nothing_special | Opening | Buffering | Playing | Paused | Stopped | Ended | Error

let states =
  [ Nothing_special; Opening; Buffering; Playing; Paused; Stopped; Ended; Error ]

let state_name = function
  | Nothing_special -> "NothingSpecial" | Opening -> "Opening" | Buffering -> "Buffering"
  | Playing -> "Playing" | Paused -> "Paused" | Stopped -> "Stopped"
  | Ended -> "Ended" | Error -> "Error"

(* Both Ended and Error end the run. Keeping them distinct matters
   because VLC reaches Ended on input it could not fully decode, so
   Ended alone is not evidence the media was intact. *)
let terminal = function Ended | Error | Stopped -> true | _ -> false

(* PLAYING IS NOT DECODED. VLC enters Playing while still buffering, so
   treating the state as proof of decode reads an intention rather than
   an outcome. The picture counter is the outcome. *)
let decoded state ~pictures = state = Playing && pictures > 0

type leniency =
  | Skipped_frames
  | Demuxer_fallback
  | Codec_fallback
  | Sout_stage_dropped
  | Ended_without_error

let leniencies =
  [ Skipped_frames; Demuxer_fallback; Codec_fallback; Sout_stage_dropped; Ended_without_error ]

let leniency_name = function
  | Skipped_frames -> "skipped_frames"
  | Demuxer_fallback -> "demuxer_fallback"
  | Codec_fallback -> "codec_fallback"
  | Sout_stage_dropped -> "sout_stage_dropped"
  | Ended_without_error -> "ended_without_error"

let why_it_hides = function
  | Skipped_frames ->
      "corrupt frames were dropped and playback continued, so a damaged stream looks watchable"
  | Demuxer_fallback ->
      "a different demuxer was chosen than the container declared, so the format under test \
       is not the format that was exercised"
  | Codec_fallback ->
      "a software decoder replaced the expected one, so a hardware-path defect is invisible"
  | Sout_stage_dropped ->
      "a missing stream-output module was skipped rather than refused, so the chain that ran \
       is not the chain that was declared"
  | Ended_without_error ->
      "playback reached Ended on input it could not fully read, so a truncated file reports \
       the same terminal state as a whole one"

(* The only verdict a harness may treat as evidence about the media. *)
let clean = function [] -> true | _ -> false

type capability =
  | Play_url | Play_file | Sout_transcode | Sout_standard | Snapshot | Stats

let capabilities = [ Play_url; Play_file; Sout_transcode; Sout_standard; Snapshot; Stats ]

let capability_name = function
  | Play_url -> "play_url" | Play_file -> "play_file"
  | Sout_transcode -> "sout_transcode" | Sout_standard -> "sout_standard"
  | Snapshot -> "snapshot" | Stats -> "stats"

let level = function
  | Play_url -> Fractal_diagnostic.L4_fixture
  | Play_file -> Fractal_diagnostic.L1_family
  | Sout_transcode -> Fractal_diagnostic.L2_capability
  | Sout_standard -> Fractal_diagnostic.L3_contract
  | Snapshot -> Fractal_diagnostic.L6_receipt
  | Stats -> Fractal_diagnostic.L5_trace

(* VLC is an ORACLE, never an author. Nothing it does can be an
   Implementation fault of ours: when VLC cannot play our stream that is
   evidence about the stream, and when VLC is absent or miscompiled that
   is the environment. Under R5 neither may deny parity credit. *)
let origin = function
  | Snapshot | Stats -> Fractal_diagnostic.Evidence
  | Play_url | Play_file | Sout_transcode | Sout_standard -> Fractal_diagnostic.Environment

let law = function
  | Play_url -> "the URL opens and pictures are decoded from it"
  | Play_file -> "the file opens and pictures are decoded from it"
  | Sout_transcode -> "the transcode chain runs with the codecs that were declared"
  | Sout_standard -> "the output reaches the declared destination in the declared mux"
  | Snapshot -> "a decoded frame is written to disk and is non-empty"
  | Stats -> "decoded and lost picture counters are readable and advance"

let hazard = function
  | Play_url ->
      "VLC retries and buffers indefinitely on an unreachable URL rather than failing, so the \
       run hangs instead of reporting"
  | Play_file -> "a truncated file plays to Ended and reports no error at all"
  | Sout_transcode ->
      "an unavailable codec silently falls back, so the chain that ran is not the one declared"
  | Sout_standard -> "the destination is unreachable and output is discarded without a diagnostic"
  | Snapshot ->
      "a snapshot is written before the first frame decodes, producing a valid but BLANK image \
       that compares as a real capture"
  | Stats -> "the counters read zero both before playback starts and when it never starts"

let serves = function
  | Play_url -> Vision_ontology.Serve
  | Play_file -> Vision_ontology.Source
  | Sout_transcode -> Vision_ontology.Encode
  | Sout_standard -> Vision_ontology.Package
  | Snapshot -> Vision_ontology.Observe
  | Stats -> Vision_ontology.Play

type intent = {
  input : string;
  snapshot_to : string option;
  run_seconds : int;
  verbose : bool;
}

let validate i =
  (* Stdlib.Error is qualified because this module's own `state` type
     has an Error constructor that would otherwise shadow it. *)
  if String.trim i.input = "" then Stdlib.Error "vlc input is empty"
  else if i.run_seconds <= 0 then Stdlib.Error "vlc run duration must be positive"
  else
    match i.snapshot_to with
    | Some p when String.trim p = "" -> Stdlib.Error "snapshot path is empty"
    | _ -> Stdlib.Ok i

let argv i =
  List.concat
    [ [ "cvlc"; "--intf"; "dummy"; "--no-audio" ];
      (* WITHOUT THIS VLC NEVER EXITS on end-of-input, and a step that
         hangs is indistinguishable from one still working — the same
         failure mode that made ops verify hang on its loudest suite. *)
      [ "--play-and-exit" ];
      [ "--run-time"; string_of_int i.run_seconds ];
      (if i.verbose then [ "-vv" ] else [ "--quiet" ]);
      (match i.snapshot_to with
       | Some p ->
           [ "--video-filter"; "scene"; "--scene-path"; Filename.dirname p;
             "--scene-prefix"; Filename.remove_extension (Filename.basename p);
             "--scene-format"; "png";
             (* one snapshot per N frames; 15 avoids the blank-first-frame
                hazard by never sampling before decode has begun *)
             "--scene-ratio"; "15" ]
       | None -> []);
      [ i.input ];
      [ "vlc://quit" ] ]

let render () =
  let b = Buffer.create 1536 in
  Buffer.add_string b "vlc ontology (oracle, never author)\n";
  List.iter
    (fun c ->
      Buffer.add_string b
        (Printf.sprintf "  %-16s %-14s %-12s serves=%s\n    law:    %s\n    hazard: %s\n"
           (capability_name c)
           (Fractal_diagnostic.level_name (level c))
           (Fractal_diagnostic.origin_name (origin c))
           (Vision_ontology.stage_name (serves c))
           (law c) (hazard c)))
    capabilities;
  Buffer.add_string b "  leniencies (each hides a defect):\n";
  List.iter
    (fun l ->
      Buffer.add_string b (Printf.sprintf "    %-20s %s\n" (leniency_name l) (why_it_hides l)))
    leniencies;
  Buffer.contents b
