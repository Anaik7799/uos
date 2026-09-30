(* Actual payload behavior and authority reporting; no runtime fence is acquired. *)
let () =
  let open Agent_dispatch_hook in
  let checks = ref 0 and failures = ref 0 in
  let check name passed =
    incr checks;
    if not passed then incr failures;
    Printf.printf "%s %s\n" (if passed then "ok  " else "FAIL") name in
  let valid = "{\"tool\":\"zk_query\",\"args\":{\"query\":\"test\"}}" in
  let rendered = validate_tool_payload valid |> render_verdict |> Yojson.Safe.from_string in
  let field name = Yojson.Safe.Util.member name rendered in
  check "known SHA256 vector"
    (sha256_hex "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  check "NUL payload rejected"
    (match validate_tool_payload "a\000b" with FailClosed {error_code=(-2);_}->true|_->false);
  check "raw SQL injection rejected"
    (match validate_tool_payload "SELECT * FROM t; DROP TABLE t" with FailClosed {error_code=(-3);_}->true|_->false);
  check "ordinary payload remains a filter pass"
    (match validate_tool_payload valid with Pass _->true|_->false);
  check "passing filter grants no effect authority" (field "authority" = `String "NONE");
  check "passing filter cannot claim an acquired temporal fence"
    (field "tcm_temporal_fence" = `String "NOT_ACQUIRED");
  check "passing filter cannot claim DMC verification"
    (field "dmc_coherence" = `String "UNVERIFIED");
  check "oversized payload rejected before scanning"
    (match validate_tool_payload (String.make 1_048_577 'a') with FailClosed _->true|_->false);
  check "empty payload rejected"
    (match validate_tool_payload "" with FailClosed {error_code=(-7);_}->true|_->false);
  check "enforcement flag cannot be satisfied by a payload filter"
    (match validate_tool_payload ~require_authority:true valid with
     | FailClosed {error_code=(-5);_}->true|_->false);
  let invalid args = match parse_arguments args with
    | Error (FailClosed {error_code=(-9);_}) -> true | _ -> false in
  check "mixed self-test and enforcement modes rejected"
    (invalid ["--self-test";"--intercept-mcp";"--enforce-dmc-tcm"]);
  check "unknown dispatch option rejected" (invalid ["--intercept-mcp";"--unknown"]);
  check "enforcement without intercept rejected" (invalid ["--enforce-dmc-tcm"]);
  check "duplicate dispatch option rejected" (invalid ["--intercept-mcp";"--intercept-mcp"]);
  check "enforcement ordering preserves authority requirement"
    (parse_arguments ["--intercept-mcp";"--enforce-dmc-tcm"] = Ok (Intercept {require_authority=true})
      && parse_arguments ["--enforce-dmc-tcm";"--intercept-mcp"] = Ok (Intercept {require_authority=true}));
  let r,w=Unix.pipe () in
  let exact="first\r\nsecond\n" in
  ignore(Unix.write_substring w exact 0 (String.length exact));Unix.close w;
  let received=read_payload r in Unix.close r;
  check "input preserves exact bytes" (received=Ok exact);
  let r,w=Unix.pipe () in
  let timed=read_payload ~seconds:0.01 r in Unix.close r;Unix.close w;
  check "open silent input expires"
    (match timed with Error(FailClosed {error_code=(-6);_})->true|_->false);
  let r,w=Unix.pipe () in
  let pid=Unix.fork () in
  if pid=0 then (Unix.close r;
    let oversized=Bytes.make 1_048_577 'x' in
    let rec write offset = if offset<Bytes.length oversized then
      let n=Unix.write w oversized offset (Bytes.length oversized-offset) in write(offset+n) in
    (try write 0 with Unix.Unix_error _->());Unix.close w;Unix._exit 0);
  Unix.close w;
  let overflow=read_payload r in Unix.close r;
  ignore(Unix.waitpid [] pid);
  check "stream byte limit rejects overflow"
    (match overflow with Error(FailClosed {error_code=(-4);_})->true|_->false);
  Printf.printf "%d checks, %d failures\n" !checks !failures;
  exit (if !failures=0 then 0 else 1)
