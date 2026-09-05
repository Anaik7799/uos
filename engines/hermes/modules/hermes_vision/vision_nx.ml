(* PSNR over raw planes, in Nx. See the .mli: the point is that the
   metric is not ffmpeg judging its own output. *)

let read_plane path expected =
  match open_in_bin path with
  | exception _ -> Error ("cannot read plane: " ^ path)
  | ic ->
      Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
          let n = in_channel_length ic in
          if n <> expected then
            (* a partial read would still produce a number, and that
               number would be meaningless *)
            Error (Printf.sprintf "plane %s is %d bytes, expected %d" path n expected)
          else Ok (really_input_string ic n))

let to_tensor s =
  let n = String.length s in
  Nx.create Nx.float32 [| n |]
    (Array.init n (fun i -> float_of_int (Char.code s.[i])))

let psnr_gray ~ref_plane ~cand_plane ~width ~height =
  let expected = width * height in
  match (read_plane ref_plane expected, read_plane cand_plane expected) with
  | Error e, _ | _, Error e -> Error e
  | Ok a, Ok b ->
      let ta = to_tensor a and tb = to_tensor b in
      let d = Nx.sub ta tb in
      let mse = Nx.item [] (Nx.mean (Nx.mul d d)) in
      if mse <= 0.0 then
        (* identical planes: PSNR is infinite. Reporting a large finite
           number instead would be a quiet lie about a perfect match. *)
        Ok infinity
      else Ok (10.0 *. Float.log10 (255.0 *. 255.0 /. mse))

let extract_gray ~video ~at ~out ~width ~height =
  if not (Sys.file_exists video) then Error ("no such video: " ^ video)
  else
    let cmd =
      Printf.sprintf
        "timeout 60 ffmpeg -hide_banner -loglevel error -ss %.2f -i %s -frames:v 1 -vf \
         scale=%d:%d -pix_fmt gray -f rawvideo -y %s 2>&1"
        at (Filename.quote video) width height (Filename.quote out)
    in
    let ic = Unix.open_process_in cmd in
    let b = Buffer.create 256 in
    (try while true do Buffer.add_channel b ic 1 done with End_of_file -> ());
    match (try Unix.close_process_in ic with Unix.Unix_error _ -> Unix.WEXITED 127) with
    | Unix.WEXITED 0 when Sys.file_exists out -> Ok ()
    | _ -> Error ("ffmpeg could not extract a frame: " ^ String.trim (Buffer.contents b))

let compare_at ~reference ~candidate ~ref_at ~cand_at ~width ~height =
  let r = Filename.temp_file "vision-ref" ".gray"
  and c = Filename.temp_file "vision-cand" ".gray" in
  let cleanup () = (try Sys.remove r with _ -> ()); (try Sys.remove c with _ -> ()) in
  Fun.protect ~finally:cleanup (fun () ->
      match extract_gray ~video:reference ~at:ref_at ~out:r ~width ~height with
      | Error e -> Error e
      | Ok () -> (
          match extract_gray ~video:candidate ~at:cand_at ~out:c ~width ~height with
          | Error e -> Error e
          | Ok () -> psnr_gray ~ref_plane:r ~cand_plane:c ~width ~height))

let agrees_with ~nx ~ffmpeg ~tolerance =
  (* infinity on one side and a large finite figure on the other is
     agreement: both mean "identical as far as this can tell" *)
  if Float.is_integer nx && Float.is_nan nx then false
  else if nx = infinity then ffmpeg > 60.0
  else abs_float (nx -. ffmpeg) <= tolerance
