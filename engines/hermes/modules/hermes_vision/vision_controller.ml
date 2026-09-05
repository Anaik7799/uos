(* The ffmpeg controller. See vision_controller.mli for the laws. *)

open Vision_ontology

type verdict = Live of string | Absent of string | Unknown of string

type observation = {
  stage : stage;
  verdict : verdict;
  level : Fractal_diagnostic.fractal_level;
  origin : Fractal_diagnostic.origin;
  detail : string;
  elapsed_ms : float;
}

let verdict_name = function Live _ -> "LIVE" | Absent _ -> "ABSENT" | Unknown _ -> "UNKNOWN"
let is_live o = match o.verdict with Live _ -> true | _ -> false

type handle = { hpid : int; hlog : string; hintent : Vision_intent.intent; started : float }

let pid h = h.hpid
let log_path h = h.hlog
let intent_of h = h.hintent

let observe stage verdict detail started =
  { stage; verdict; level = level stage; origin = origin stage; detail;
    elapsed_ms = (Unix.gettimeofday () -. started) *. 1000.0 }

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let rec mkdir_p dir =
  if dir = "" || dir = "/" || Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let on_path exe =
  let dirs = String.split_on_char ':' (try Sys.getenv "PATH" with Not_found -> "") in
  List.exists (fun d -> d <> "" && Sys.file_exists (Filename.concat d exe)) dirs

(* A pid may be REUSED. Signalling one we no longer own kills an
   unrelated process — the stop_pipeline/Provided_unsafe unsafe control
   action. The cmdline is the cheap authority: if it is not an ffmpeg,
   it is not ours. *)
let owns_pid pid =
  match open_in_bin (Printf.sprintf "/proc/%d/cmdline" pid) with
  | exception _ -> false
  | ic ->
      Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
          (* /proc files report a length of ZERO, so in_channel_length
             here returns "" and every pid looks like someone else's —
             which would silently disable this whole safety check while
             its tests passed. Read until EOF instead. *)
          let buf = Buffer.create 256 and chunk = Bytes.create 256 in
          let rec drain () =
            match input ic chunk 0 256 with
            | 0 -> ()
            | n -> Buffer.add_subbytes buf chunk 0 n; drain ()
            | exception End_of_file -> ()
          in
          drain ();
          let body = Buffer.contents buf in
          let k = String.length body and needle = "ffmpeg" in
          let m = String.length needle in
          let rec has i = i + m <= k && (String.sub body i m = needle || has (i + 1)) in
          has 0)

(* ONE PIPELINE OWNS AN OUTPUT DIRECTORY AT A TIME. Two ffmpeg writing
   one playlist corrupts the stream — start_pipeline/Provided_unsafe — so
   the lock is checked BEFORE a process is spawned rather than discovered
   afterwards in a broken segment. A lock whose pid is dead or not ours
   is stale and may be taken. *)
let lock_path dir = Filename.concat dir ".vision.lock"

let started_pipelines : (int * string) list ref = ref []

(* A pid we started is ours by record, whatever /proc says this instant.
   RIGHT AFTER create_process the child may not have exec'd yet, so its
   cmdline is still the parent's and owns_pid answers false — a race that
   would let a second pipeline take a directory we already hold. Our own
   record settles it for our children; owns_pid is the staleness test for
   a lock written by some OTHER process. *)
let lock_holder dir =
  match read_file (lock_path dir) with
  | None -> None
  | Some body -> (
      match int_of_string_opt (String.trim body) with
      | Some pid when List.mem_assoc pid !started_pipelines -> Some pid
      | Some pid when owns_pid pid -> Some pid
      | _ -> None)

let write_lock dir pid =
  try
    let oc = open_out (lock_path dir) in
    output_string oc (string_of_int pid);
    close_out oc
  with _ -> ()

let release_lock dir = try Sys.remove (lock_path dir) with _ -> ()

(* Every started pipeline must be stopped on EVERY exit path, or an
   orphan holds the output directory and corrupts the next run —
   stop_pipeline/Not_provided. The list is declared above, next to
   lock_holder, because the two answer the same question. *)
let stop_pid pid =
  (* the ownership check is the whole point: a reused pid must not be
     signalled *)
  if owns_pid pid then begin
    (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
    let rec settle n =
      if n = 0 then (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ())
      else if owns_pid pid then (Unix.sleepf 0.1; settle (n - 1))
    in
    settle 20
  end

let () =
  at_exit (fun () ->
      List.iter (fun (pid, dir) -> stop_pid pid; release_lock dir) !started_pipelines)

let start intent =
  match Vision_intent.validate intent with
  | Error e -> Error ("invalid intent: " ^ e)
  | Ok intent ->
      if not (on_path "ffmpeg") then Error "ffmpeg is not on PATH"
      else begin
        let sink_dir =
          match intent.Vision_intent.sink with
          | Vision_intent.Hls { dir; _ } -> mkdir_p dir; Some dir
          | _ -> None
        in
        match (match sink_dir with Some d -> lock_holder d | None -> None) with
        | Some holder ->
            Error
              (Printf.sprintf
                 "another pipeline (pid %d) already owns this output directory; two encoders \
                  writing one playlist corrupts the stream"
                 holder)
        | None ->
        let argv = Array.of_list (Vision_intent.argv intent) in
        let log = Filename.concat (Filename.get_temp_dir_name ())
            (Printf.sprintf "hermes-vision-%d.log" (Unix.getpid ())) in
        match Unix.openfile log [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 with
        | exception Unix.Unix_error (e, _, _) ->
            Error ("cannot open log: " ^ Unix.error_message e)
        | fd -> (
            let devnull = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0o644 in
            match Unix.create_process "ffmpeg" argv devnull fd fd with
            | exception Unix.Unix_error (e, _, _) ->
                Unix.close fd; Unix.close devnull;
                Error ("cannot start ffmpeg: " ^ Unix.error_message e)
            | child ->
                Unix.close fd; Unix.close devnull;
                (* claim the directory and register for at_exit in the
                   same breath as the spawn, so no path exists on which a
                   pipeline is started and neither recorded nor cleaned *)
                (match sink_dir with
                 | Some d ->
                     write_lock d child;
                     started_pipelines := (child, d) :: !started_pipelines
                 | None -> ());
                Ok { hpid = child; hlog = log; hintent = intent;
                     started = Unix.gettimeofday () })
      end

let running h =
  match Unix.waitpid [ Unix.WNOHANG ] h.hpid with
  | 0, _ -> true
  | _ -> false
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> false
  | exception Unix.Unix_error _ -> false

let stop h =
  (* goes through stop_pid, which REFUSES to signal a pid that is not
     ours — a reused pid would otherwise kill an unrelated process *)
  stop_pid h.hpid;
  (match h.hintent.Vision_intent.sink with
   | Vision_intent.Hls { dir; _ } -> release_lock dir
   | _ -> ());
  started_pipelines := List.filter (fun (p, _) -> p <> h.hpid) !started_pipelines;
  (try ignore (Unix.waitpid [ Unix.WNOHANG ] h.hpid) with Unix.Unix_error _ -> ())

(* ------------------------------------------------------------ probes *)

let log_errors h =
  match read_file h.hlog with
  | None -> None
  | Some body -> if String.trim body = "" then Some "" else Some (String.trim body)

let probe_source h =
  let started = h.started in
  match log_errors h with
  | None -> observe Source (Unknown "the process log could not be read") h.hlog started
  | Some "" ->
      if running h then
        observe Source (Live "the source process is running and reported no error")
          (Vision_intent.describe h.hintent) started
      else
        observe Source (Absent "the source process exited without producing an error")
          h.hlog started
  | Some errs -> observe Source (Absent "the source reported an error") errs started

let probe_encode h =
  let started = h.started in
  match log_errors h with
  | None -> observe Encode (Unknown "the process log could not be read") h.hlog started
  | Some errs when errs <> "" -> observe Encode (Absent "the encoder reported an error") errs started
  | Some _ ->
      if running h then
        observe Encode (Live "the encoder is running")
          (Vision_intent.codec_name h.hintent.Vision_intent.codec) started
      else observe Encode (Absent "the encoder exited") h.hlog started

(* the playlist lines that name a segment: anything not a #EXT tag *)
let segments_in playlist =
  String.split_on_char '\n' playlist
  |> List.map String.trim
  |> List.filter (fun l -> l <> "" && l.[0] <> '#')

let probe_package ~dir =
  let started = Unix.gettimeofday () in
  let playlist_path = Filename.concat dir "stream.m3u8" in
  match read_file playlist_path with
  | None ->
      (* not there YET is not the same as broken: the pipeline may not
         have reached its first segment boundary. Unknown, not Absent. *)
      observe Package (Unknown "no playlist has been written yet") playlist_path started
  | Some playlist -> (
      match segments_in playlist with
      | [] -> observe Package (Absent "the playlist names no segment") playlist_path started
      | names ->
          let missing =
            List.filter
              (fun n ->
                let p = Filename.concat dir n in
                match read_file p with None -> true | Some b -> String.length b = 0)
              names
          in
          if missing = [] then
            observe Package
              (Live (Printf.sprintf "%d segments named and all present" (List.length names)))
              (String.concat "," names) started
          else
            (* the declared hazard, caught: a playlist that names segments
               which have already been deleted *)
            observe Package
              (Absent
                 (Printf.sprintf "%d of %d named segments are missing or empty"
                    (List.length missing) (List.length names)))
              (String.concat "," missing) started)

(* A minimal HTTP/1.1 GET over Unix sockets: no shell, no curl, and the
   status line is read rather than assumed. *)
let http_get ~host ~port ~path =
  match Unix.getaddrinfo host (string_of_int port) [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ] with
  | [] -> Error "host did not resolve"
  | ai :: _ -> (
      let sock = Unix.socket ai.Unix.ai_family ai.Unix.ai_socktype 0 in
      match Unix.connect sock ai.Unix.ai_addr with
      | exception Unix.Unix_error (e, _, _) ->
          Unix.close sock; Error ("connect: " ^ Unix.error_message e)
      | () -> (
          let req =
            Printf.sprintf "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" path host
          in
          try
            ignore (Unix.write_substring sock req 0 (String.length req));
            let buf = Buffer.create 65536 and chunk = Bytes.create 65536 in
            let rec drain () =
              match Unix.read sock chunk 0 65536 with
              | 0 -> ()
              | n -> Buffer.add_subbytes buf chunk 0 n; drain ()
              | exception Unix.Unix_error _ -> ()
            in
            drain (); Unix.close sock;
            let raw = Buffer.contents buf in
            match String.index_opt raw '\n' with
            | None -> Error "no status line"
            | Some i ->
                let status = String.trim (String.sub raw 0 i) in
                let body =
                  match String.index_opt raw '\r' with
                  | _ -> (
                      (* split on the blank line ending the headers *)
                      let sep = "\r\n\r\n" in
                      let n = String.length raw and k = String.length sep in
                      let rec find j =
                        if j + k > n then None
                        else if String.sub raw j k = sep then Some (j + k)
                        else find (j + 1)
                      in
                      match find 0 with
                      | Some j -> String.sub raw j (n - j)
                      | None -> "")
                in
                Ok (status, body)
          with e -> (try Unix.close sock with _ -> ()); Error (Printexc.to_string e)))

let ok_status s =
  let n = String.length s in
  let rec has i = i + 3 <= n && (String.sub s i 3 = "200" || has (i + 1)) in
  has 0

let probe_serve ~host ~port ~path =
  let started = Unix.gettimeofday () in
  match http_get ~host ~port ~path with
  | Error e -> observe Serve (Unknown ("the server could not be reached: " ^ e)) path started
  | Ok (status, _) when not (ok_status status) ->
      observe Serve (Absent ("the playlist did not return 200: " ^ status)) path started
  | Ok (_, body) -> (
      match segments_in body with
      | [] -> observe Serve (Absent "the served playlist names no segment") path started
      | first :: _ -> (
          (* FETCH A SEGMENT TOO. A served playlist whose segments 404 is
             the declared hazard, and it is invisible if only the
             playlist is fetched. *)
          let dir = Filename.dirname path in
          let seg_path = if dir = "/" then "/" ^ first else dir ^ "/" ^ first in
          match http_get ~host ~port ~path:seg_path with
          | Error e -> observe Serve (Unknown ("segment unreachable: " ^ e)) seg_path started
          | Ok (st, _) when not (ok_status st) ->
              observe Serve (Absent ("segment did not return 200: " ^ st)) seg_path started
          | Ok (_, seg) when String.length seg = 0 ->
              observe Serve (Absent "segment returned 200 but was empty") seg_path started
          | Ok (_, seg) ->
              observe Serve
                (Live (Printf.sprintf "playlist and first segment served (%d bytes)"
                         (String.length seg)))
                seg_path started))

let probe_play ~frames_painted =
  let started = Unix.gettimeofday () in
  match frames_painted with
  | None ->
      observe Play (Unknown "no browser oracle reported; nothing was observed") "no oracle" started
  | Some n when n <= 0 ->
      observe Play (Absent "the player painted no frame") (string_of_int n) started
  | Some n ->
      observe Play (Live (Printf.sprintf "the player painted %d frames" n))
        (string_of_int n) started

let probe_observe ~source_ordinals ~captured_ordinals =
  let started = Unix.gettimeofday () in
  match (source_ordinals, captured_ordinals) with
  | [], _ | _, [] ->
      observe Observe (Unknown "one side produced no ordinals; nothing can be compared")
        (Printf.sprintf "source=%d captured=%d" (List.length source_ordinals)
           (List.length captured_ordinals))
        started
  | src, cap ->
      let common = List.filter (fun o -> List.mem o src) cap in
      (* The declared hazard is comparing a capture against itself. The
         guard is that the ordinals must come from DIFFERENT sides and
         still agree, and that the captured side advanced — a frozen
         frame repeats one ordinal and would otherwise match. *)
      let distinct_captured = List.sort_uniq compare cap in
      if List.length distinct_captured < 2 then
        observe Observe (Absent "the captured ordinals never advanced (frozen frame)")
          (String.concat "," (List.map string_of_int distinct_captured)) started
      else if common = [] then
        observe Observe (Absent "no captured ordinal appears in the source stream")
          (Printf.sprintf "source=%s captured=%s"
             (String.concat "," (List.map string_of_int src))
             (String.concat "," (List.map string_of_int cap)))
          started
      else
        observe Observe
          (Live
             (Printf.sprintf "%d of %d captured ordinals match the source and the capture advanced"
                (List.length common) (List.length cap)))
          (String.concat "," (List.map string_of_int common))
          started

let probe_all h ~dir ~host ~port ~path ~frames_painted ~source_ordinals ~captured_ordinals =
  let obs =
    [ probe_source h; probe_encode h; probe_package ~dir;
      probe_serve ~host ~port ~path; probe_play ~frames_painted;
      probe_observe ~source_ordinals ~captured_ordinals ]
  in
  (* Coverage is built ONLY from Live stages: an Unknown stage cannot
     contribute to a claim of end-to-end coverage, which is the whole
     reason the third verdict exists. *)
  let live = List.filter is_live obs |> List.map (fun o -> o.stage) in
  let segments = List.map Vision_algebra.identity live in
  (obs, Vision_algebra.coverage segments)

let render obs =
  let b = Buffer.create 1024 in
  List.iter
    (fun o ->
      let why = match o.verdict with Live s | Absent s | Unknown s -> s in
      Buffer.add_string b
        (Printf.sprintf "  %-8s %-7s %-11s %s\n    %s\n" (stage_name o.stage)
           (verdict_name o.verdict)
           (Fractal_diagnostic.origin_name o.origin)
           why o.detail))
    obs;
  Buffer.contents b
