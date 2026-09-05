let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function
  | Ok value -> value
  | Error errors -> failwith (String.concat "; " errors)

let contains text fragment =
  let text_length = String.length text in
  let fragment_length = String.length fragment in
  let rec loop offset =
    offset + fragment_length <= text_length
    && (String.sub text offset fragment_length = fragment || loop (offset + 1))
  in
  fragment_length = 0 || loop 0

let parse_json text =
  match Yojson.Safe.from_string text with
  | value -> Some value
  | exception _ -> None

let () =
  let intent = get (Zellij_intent.default ()) in
  let kdl = Zellij_projection.render_config_kdl intent in
  check "P1 KDL derives exact shell, cwd, detach, and serialization intent"
    (contains kdl "default_shell \"/usr/bin/zsh\""
    && contains kdl "default_cwd \"/home/an/dev/ver/harness-bionic\""
    && contains kdl "session_serialization true"
    && contains kdl "serialize_pane_viewport true"
    && contains kdl "on_force_close \"detach\""
    && (not (contains kdl "auto-start"))
    && not (contains kdl "z_connect.sh"));
  check "P2 equal intent renders byte-identical KDL"
    (kdl = Zellij_projection.render_config_kdl intent
    && Zellij_projection.digest kdl = Zellij_projection.digest kdl);
  let unusual =
    get
      (Zellij_intent.make ~install_method:Zellij_intent.Cargo_locked
         ~workspace_root:"/tmp/a\"b\\c\nline" ~config_root:"/tmp/config"
         ~command_root:"/tmp/bin" ~zellij_bin:"/tmp/zellij" ~shell:"/bin/zsh"
         ~sessions:Zellij_intent.all_sessions ~attachment:Zellij_intent.Manual
         ())
  in
  check "P3 KDL string encoder escapes quotes, slashes, and newlines"
    (contains
       (Zellij_projection.render_config_kdl unusual)
       "default_cwd \"/tmp/a\\\"b\\\\c\\nline\"");
  let commands = Zellij_projection.command_links intent in
  check "P4 command projection is exact and name preserving"
    (List.map fst commands
     = [ "zlt-1"; "zlt-2"; "zlt-3"; "zlt-4"; "zlt-5"; "zlt-6" ]
    && List.for_all
         (fun (_, target) ->
           target = "/home/an/.local/bin/zellij-attach-harness-bionic")
         commands);
  let ontology = Zellij_projection.render_ontology_markdown () in
  let atlas = Zellij_projection.render_atlas_markdown () in
  let algebra = Zellij_projection.render_algebra_markdown () in
  let guide = Zellij_projection.render_guide_markdown intent in
  check "P5 Markdown projections are deterministic and source-separated"
    (ontology = Zellij_projection.render_ontology_markdown ()
    && atlas = Zellij_projection.render_atlas_markdown ()
    && algebra = Zellij_projection.render_algebra_markdown ()
    && contains ontology "L0"
    && contains atlas "Documented_only"
    && contains atlas "No_credit"
    && contains algebra "Empty-is-not-success"
    && contains guide "zlt-1"
    && contains guide (Zellij_intent.digest intent));
  let authority = Zellij_projection.render_authority_json () in
  check "P6 authority manifest is JSON with every documentation page"
    (Option.is_some (parse_json authority)
    && List.length Zellij_atlas.documentation_pages = 64
    && contains authority "https://zellij.dev/documentation/toc.html"
    && contains authority "discovered-from-official-toc"
    && List.for_all
         (fun row ->
           match Zellij_atlas.documentation_url row with
           | Some url -> contains authority url
           | None -> false)
         Zellij_atlas.documentation_pages);
  let model = Zellij_projection.render_model_json intent in
  check "P7 machine model is parseable and digest-bound"
    (Option.is_some (parse_json model)
    && contains model (Zellij_intent.digest intent)
    && List.for_all
         (fun name -> contains model name)
         (List.map Zellij_intent.session_name Zellij_intent.all_sessions));
  check "P8 atlas and ontology projections contain one row per authority row"
    (List.for_all
       (fun node -> contains ontology (Zellij_ontology.id node))
       Zellij_ontology.nodes
    && List.for_all
         (fun row -> contains atlas (Zellij_atlas.id row))
         Zellij_atlas.rows);
  let telemetry =
    Suite_telemetry.observe ~suite:"test_zellij_projection" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit telemetry ~targets:[]);
  exit (Suite_telemetry.exit_code telemetry)
