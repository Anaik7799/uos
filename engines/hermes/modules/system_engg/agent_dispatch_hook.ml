(* Bounded payload filter. Hashing is not signing and this module does not
   acquire a task/runtime fence or establish DMC/TCM conformance. *)

type validation_verdict =
  | Pass of { digest : string; timestamp : string }
  | FailClosed of { reason : string; error_code : int }

let max_payload_bytes = 1_048_576
let refuse error_code reason = FailClosed { reason; error_code }

type command = Self_test | Intercept of { require_authority : bool }

let parse_arguments = function
  | ["--self-test"] -> Ok Self_test
  | ["--intercept-mcp"] -> Ok (Intercept { require_authority = false })
  | ["--intercept-mcp"; "--enforce-dmc-tcm"]
  | ["--enforce-dmc-tcm"; "--intercept-mcp"] ->
      Ok (Intercept { require_authority = true })
  | _ -> Error (refuse (-9) "Invalid or conflicting dispatch modes")

let contains_nul_byte s =
  String.contains s '\x00'

let contains_raw_sql_injection s =
  let upper = String.uppercase_ascii s in
  let patterns = [
    "; DROP TABLE";
    "; DELETE FROM";
    "' OR '1'='1";
    "\" OR \"1\"=\"1";
    "UNION SELECT";
    "-- ";
    "/*";
  ] in
  List.exists (fun p ->
    try
      let _ = Str.search_forward (Str.regexp_string p) upper 0 in
      true
    with Not_found -> false
  ) patterns

let sha256_hex s =
  let h = Cryptokit.Hash.sha256 () in
  h#add_string s;
  Cryptokit.transform_string (Cryptokit.Hexa.encode ()) h#result

let get_iso_timestamp () =
  let t = Unix.gettimeofday () in
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let validate_tool_payload ?(require_authority=false) payload =
  if String.length payload > max_payload_bytes then
    refuse (-4) "Payload exceeds the 1048576-byte input bound"
  else if String.trim payload = "" then refuse (-7) "Empty tool payload"
  else if contains_nul_byte payload then
    FailClosed {
      reason = "TRAFFIC_REJECTED: Embedded NUL byte trapped (memchr code -2)";
      error_code = -2;
    }
  else if contains_raw_sql_injection payload then
    FailClosed {
      reason = "TRAFFIC_REJECTED: Raw unparameterized SQL syntax detected";
      error_code = -3;
    }
  else if require_authority then
    refuse (-5) "DMC/TCM enforcement requires an authenticated effect-time fence adapter; this payload filter grants no authority"
  else
    Pass {
      digest = sha256_hex payload;
      timestamp = get_iso_timestamp ();
    }

(* The caller supplies an exclusively owned input descriptor. Reads preserve
   exact bytes and set it nonblocking; byte/time exhaustion fails closed. *)
let read_payload ?(seconds=5.) fd =
  let now () = Mtime.Span.to_float_ns (Mtime_clock.elapsed ()) /. 1e9 in
  if seconds <= 0. || seconds > 5. || not (Float.is_finite seconds) then
    Error (refuse (-6) "Invalid input deadline")
  else
    let deadline = now () +. seconds in
    let buffer = Buffer.create 4096 and chunk = Bytes.create 4096 in
    let rec read () =
      let remaining = deadline -. now () in
      if remaining <= 0. then Error (refuse (-6) "Tool input deadline exceeded")
      else
        try
          let ready, _, _ = Unix.select [fd] [] [] remaining in
          if ready = [] then read ()
          else match Unix.read fd chunk 0 (Bytes.length chunk) with
          | 0 -> Ok (Buffer.contents buffer)
          | count ->
            if Buffer.length buffer + count > max_payload_bytes then
              Error (refuse (-4) "Payload exceeds the 1048576-byte input bound")
            else (Buffer.add_subbytes buffer chunk 0 count; read ())
        with
        | Unix.Unix_error ((Unix.EINTR | Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> read ()
    in
    try Unix.set_nonblock fd; read ()
    with Unix.Unix_error _ -> Error (refuse (-8) "Tool input read failed")

let render_verdict = function
  | Pass { digest; timestamp } ->
      `Assoc [
        ("verdict", `String "PASS");
        ("scope", `String "PAYLOAD_FILTER_ONLY");
        ("authority", `String "NONE");
        ("dmc_coherence", `String "UNVERIFIED");
        ("tcm_temporal_fence", `String "NOT_ACQUIRED");
        ("payload_sha256", `String digest);
        ("receipt_timestamp", `String timestamp);
      ] |> Yojson.Safe.to_string
  | FailClosed { reason; error_code } ->
      `Assoc [
        ("verdict", `String "FAIL_CLOSED");
        ("authority", `String "NONE");
        ("reason", `String reason);
        ("error_code", `Int error_code);
        ("halt_effect", `Bool true);
      ] |> Yojson.Safe.to_string

let run_self_test () =
  let nul_payload = "hello\x00world" in
  let sql_payload = "SELECT * FROM users; DROP TABLE users;--" in
  let valid_payload = "{\"tool\": \"zk_query\", \"args\": {\"query\": \"DMC\"}}" in

  let v1 = validate_tool_payload nul_payload in
  let v2 = validate_tool_payload sql_payload in
  let v3 = validate_tool_payload valid_payload in

  let pass1 = match v1 with FailClosed { error_code = -2; _ } -> true | _ -> false in
  let pass2 = match v2 with FailClosed { error_code = -3; _ } -> true | _ -> false in
  let pass3 = match v3 with Pass _ -> true | _ -> false in

  if pass1 && pass2 && pass3 then begin
    print_endline "[SELF-TEST PASSED] Three payload-filter examples; authority NONE, DMC/TCM enforcement unverified.";
    print_endline "  - Embedded NUL byte trapping: PASSED (code -2)";
    print_endline "  - Raw SQL injection defense: PASSED (code -3)";
    print_endline "  - Valid payload verification & SHA-256 digestion: PASSED";
    0
  end else begin
    prerr_endline "[SELF-TEST FAILED] Dispatch interceptor invariants violated.";
    1
  end
