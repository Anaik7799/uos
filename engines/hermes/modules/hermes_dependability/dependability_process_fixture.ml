let write_repeated channel character count =
  let chunk = Bytes.make 4096 character |> Bytes.unsafe_to_string in
  let rec loop remaining =
    if remaining > 0 then begin
      let width = min remaining (String.length chunk) in
      output_substring channel chunk 0 width;
      loop (remaining - width)
    end
  in
  loop count

let () =
  match Array.to_list Sys.argv with
  | [ _; "success" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=7\n";
      Printf.eprintf "fixture diagnostic stream\n"
  | [ _; "fail" ] ->
      print_endline "full failure stdout";
      prerr_endline "full failure stderr";
      exit 7
  | [ _; "stderr-flood" ] ->
      write_repeated stderr 'E' 1_048_576;
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=9\n"
  | [ _; "missing-marker" ] ->
      print_endline "fixture completed without a dependability marker"
  | [ _; "duplicate-marker" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=7\n";
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=7\n"
  | [ _; "zero-checks" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=0 failures=0 gc_overlap_cycles=7\n"
  | [ _; "reported-failure" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=1 gc_overlap_cycles=7\n"
  | [ _; "zero-overlap" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=0\n"
  | [ _; "leading-zero" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=0114 failures=0 gc_overlap_cycles=7\n"
  | [ _; "negative-checks" ] ->
      Printf.printf
        "DEPENDABILITY_CHILD checks=-1 failures=0 gc_overlap_cycles=7\n"
  | [ _; "replace-stdout-path"; stdout_path ] ->
      Sys.remove stdout_path;
      let descriptor =
        Unix.openfile stdout_path
          [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] 0o600
      in
      let replacement = Unix.out_channel_of_descr descriptor in
      output_string replacement "replacement pathname object\n";
      close_out replacement;
      Printf.printf
        "DEPENDABILITY_CHILD checks=114 failures=0 gc_overlap_cycles=7\n"
  | [ _; "signal" ] ->
      Unix.kill (Unix.getpid ()) Sys.sigterm;
      Unix.sleepf 1.0
  | [ _; "timeout" ] -> Unix.sleepf 60.0
  | [ _; "ignore-term" ] ->
      Sys.set_signal Sys.sigterm Sys.Signal_ignore;
      Unix.sleepf 60.0
  | [ _; "stop-self" ] ->
      Unix.kill (Unix.getpid ()) Sys.sigstop;
      Unix.sleepf 60.0
  | _ ->
      prerr_endline "unknown dependability fixture mode";
      exit 64
