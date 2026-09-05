(* Frame-by-frame comparison as a probe. See the .mli. *)

type verdict =
  | Matches of { psnr : float; offset : float }
  | Differs of { psnr : float; offset : float }
  | Unmeasurable of string

let verdict_name = function
  | Matches _ -> "MATCHES" | Differs _ -> "DIFFERS" | Unmeasurable _ -> "UNMEASURABLE"

(* Measured separation: 54.80 dB for the same content, 9.06 dB for a
   decoy at every offset tried. 30 dB is far above one and far below the
   other, so it is not tuned to either. *)
let default_threshold = 30.0

(* One pipe, not two. The sequential drain of two pipes is what made
   `ops verify` hang forever on its loudest suite; nothing in this
   repository should reintroduce it. *)
let run_capture cmd =
  match Unix.open_process_in ("( " ^ cmd ^ " ) 2>&1") with
  | exception e -> (127, "could not start: " ^ Printexc.to_string e)
  | ic ->
      let buf = Buffer.create 8192 and chunk = Bytes.create 65536 in
      let rec drain () =
        match input ic chunk 0 65536 with
        | 0 -> ()
        | n -> Buffer.add_subbytes buf chunk 0 n; drain ()
        | exception End_of_file -> ()
        | exception Sys_error _ -> ()
      in
      drain ();
      let st = try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127 in
      ((match st with Unix.WEXITED n -> n | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n),
       Buffer.contents buf)

let on_path exe =
  let dirs = String.split_on_char ':' (try Sys.getenv "PATH" with Not_found -> "") in
  List.exists (fun d -> d <> "" && Sys.file_exists (Filename.concat d exe)) dirs

(* ffmpeg prints `average:NN.NN` on the psnr summary line. Parsed rather
   than assumed: output we cannot read is Unmeasurable, never a score. *)
let parse_average out =
  let needle = "average:" in
  let n = String.length out and k = String.length needle in
  let rec find i =
    if i + k > n then None
    else if String.sub out i k = needle then
      let rec till j =
        if j >= n then j
        else match out.[j] with '0' .. '9' | '.' -> till (j + 1) | _ -> j
      in
      let stop = till (i + k) in
      (match float_of_string_opt (String.sub out (i + k) (stop - (i + k))) with
       | Some f -> Some f
       | None -> find (i + 1))
    else find (i + 1)
  in
  find 0

let psnr_at ~reference ~candidate ~skip ~offset ~duration =
  let cmd =
    Printf.sprintf
      "timeout 120 ffmpeg -hide_banner -ss %.2f -t %.2f -i %s -ss %.2f -t %.2f -i %s \
       -filter_complex \
       \"[0:v]scale=640:360,fps=15[a];[1:v]scale=640:360,fps=15[b];[a][b]psnr\" -f null -"
      skip duration (Filename.quote candidate) offset duration (Filename.quote reference)
  in
  match run_capture cmd with
  | 0, out -> parse_average out
  (* a non-zero ffmpeg is not a score of zero: it is no score at all *)
  | _, _ -> None

let compare ?(threshold = default_threshold)
    ?(offsets = [ 0.0; 1.0; 2.0; 3.0; 4.0; 5.0 ]) ?(duration = 3.0) ?(skip = 2.6)
    ~reference ~candidate () =
  if not (on_path "ffmpeg") then Unmeasurable "ffmpeg is not on PATH"
  else if not (Sys.file_exists reference) then Unmeasurable ("no reference: " ^ reference)
  else if not (Sys.file_exists candidate) then Unmeasurable ("no candidate: " ^ candidate)
  else
    let best =
      List.fold_left
        (fun acc offset ->
          match psnr_at ~reference ~candidate ~skip ~offset ~duration with
          | None -> acc
          | Some p -> (
              match acc with
              | Some (bp, _) when bp >= p -> acc
              | _ -> Some (p, offset)))
        None offsets
    in
    match best with
    | None -> Unmeasurable "ffmpeg produced no psnr figure at any offset"
    | Some (p, offset) ->
        if p >= threshold then Matches { psnr = p; offset } else Differs { psnr = p; offset }

let discriminates ?(threshold = default_threshold) ~reference ~candidate ~control () =
  match compare ~threshold ~reference ~candidate () with
  | Unmeasurable why -> Stdlib.Error ("candidate comparison unmeasurable: " ^ why)
  | Differs { psnr; _ } ->
      Stdlib.Error (Printf.sprintf "the candidate does not match the reference (%.2f dB)" psnr)
  | Matches { psnr = mp; offset } -> (
      (* THE CONTROL. Without this, a threshold that accepts everything
         passes, and the comparison proves nothing. *)
      match compare ~threshold ~reference:control ~candidate () with
      | Unmeasurable why -> Stdlib.Error ("control comparison unmeasurable: " ^ why)
      | Matches { psnr = cp; _ } ->
          Stdlib.Error
            (Printf.sprintf
               "the comparison does NOT discriminate: it matched the control too (%.2f dB) — a \
                gate that accepts anything is not a gate"
               cp)
      | Differs { psnr = cp; _ } ->
          Stdlib.Ok
            (Printf.sprintf "match %.2f dB at offset %.1fs; control rejected at %.2f dB (%.1f dB apart)"
               mp offset cp (mp -. cp)))

let observe ?(threshold = default_threshold) ~reference ~candidate () =
  let started = Unix.gettimeofday () in
  let stage = Vision_ontology.Observe in
  let mk verdict detail =
    { Vision_controller.stage; verdict;
      level = Vision_ontology.level stage;
      origin = Vision_ontology.origin stage;
      detail;
      elapsed_ms = (Unix.gettimeofday () -. started) *. 1000.0 }
  in
  match compare ~threshold ~reference ~candidate () with
  | Matches { psnr; offset } ->
      mk (Vision_controller.Live
            (Printf.sprintf "the capture matches the source at %.2f dB" psnr))
        (Printf.sprintf "offset %.1fs, threshold %.1f dB" offset threshold)
  | Differs { psnr; offset } ->
      mk (Vision_controller.Absent
            (Printf.sprintf "the capture does NOT match the source (%.2f dB)" psnr))
        (Printf.sprintf "offset %.1fs, threshold %.1f dB" offset threshold)
  (* nothing proved either way — never folded into Absent *)
  | Unmeasurable why -> mk (Vision_controller.Unknown why) reference
