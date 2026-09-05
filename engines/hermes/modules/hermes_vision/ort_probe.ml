(* The ISOLATION PROBE. Vision_ort_safety runs this as a child, so a
   wrong ordinal is an exit code rather than the harness's death. *)
let () =
  match Vision_ort.probe_create_env () with
  | Ok () ->
      Printf.printf "ok version=%s\n"
        (match Vision_ort.version_string () with Some v -> v | None -> "?");
      exit 0
  | Error e -> prerr_endline ("ort probe failed: " ^ e); exit 1
