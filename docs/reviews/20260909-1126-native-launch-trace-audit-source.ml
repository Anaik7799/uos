#use "topfind";;
#require "unix,yojson,cryptokit,str";;
let require condition message = if not condition then failwith message
let read path limit =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let size = in_channel_length ic in
    require (size <= limit) ("file bound: " ^ path);
    really_input_string ic size)
let sha bytes = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) bytes
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let contains value part = try ignore (Str.search_forward (Str.regexp_string part) value 0); true
  with Not_found -> false
let artifact path = `Assoc ["path", `String path; "sha256", `String (sha (read path 67_108_864))]
let is_elf path = String.starts_with ~prefix:"\127ELF" (read path 67_108_864)
let analyze path =
  let lines = String.split_on_char '\n' (read path 1_048_576) in
  let executions = List.filter_map (fun line ->
    if contains line "execveat(" || contains line "execve resumed" then
      failwith "unsupported execution trace syntax";
    if not (contains line "execve(") then None
    else if String.ends_with ~suffix:" = 0" line then begin
      let executable = Scanf.sscanf line "%d execve(%S" (fun _ executable -> executable) in
      require (not (Filename.is_relative executable)) "relative execution path";
      require (is_elf executable) ("non-ELF executable observed: " ^ executable);
      Some executable
    end else begin
      require (contains line " = -1 ENOENT ") "unknown execution outcome";
      None
    end) lines in
  require (executions <> []) "empty execution trace";
  `Assoc ["trace", artifact path; "successful_execve_count", `Int (List.length executions);
    "native_executables", `List (List.sort_uniq String.compare executions |> List.map artifact);
    "scope", `String "Observed execve trace and current executable bytes; cooperative local filesystem; not a proof about untraced invocations"]
let () =
  require (not (is_elf "/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/bin/erl"))
    "negative control must detect installed wrapper";
  let build = analyze "/tmp/ev-native-direct-build-0638.execve.log" in
  let runtime = analyze "/tmp/ev-native-direct-tests-1123.execve.log" in
  let receipt = "/tmp/ev-native-direct-tests-1123.json" in
  let json = Yojson.Safe.from_string (read receipt 1_048_576) in
  let member = Yojson.Safe.Util.member in
  require (member "exit_code" json = `Int 0) "runtime failure";
  let output = Yojson.Safe.Util.to_string (member "output" json) in
  require (member "output_sha256" json = `String (sha output)) "output digest mismatch";
  let cases = String.split_on_char '\n' output |> List.filter (String.starts_with ~prefix:"PASS ") in
  require (List.length cases = 168 && List.length (List.sort_uniq String.compare cases) = 168)
    "recovery case denominator mismatch";
  let report = `Assoc ["schema", `String "uos.ev-native-trace-review.v1";
    "observed_at_epoch", `Float (Unix.gettimeofday ()); "authority", `String "NONE";
    "build", build; "runtime", runtime; "runtime_receipt", artifact receipt;
    "runtime_case_count", `Int 168; "installed_wrapper_negative_control", `String "REFUSED_AS_NON_ELF";
    "build_task_lease", `String "EXPIRED_WHILE_APPROVAL_PENDING; private observation only";
    "runtime_task_attempt", `Int 2; "ev_admission", `String "NOT_GRANTED"] in
  let out = "/tmp/ev-native-direct-trace-review-1124.json" in
  let fd = Unix.openfile out [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
  let oc = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
    output_string oc (Yojson.Safe.pretty_to_string report ^ "\n"); flush oc; Unix.fsync fd);
  print_endline (Yojson.Safe.to_string (`Assoc ["report",artifact out;"checks",`String "PASS"]))
