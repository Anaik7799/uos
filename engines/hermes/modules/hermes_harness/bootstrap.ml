let executable_check ~which name =
  match which name with Some _ -> Core.Passed | None -> Core.Failed "not found"

let path_check ~exists path =
  if exists path then Core.Passed else Core.Failed "missing"

let reference_root root = Filename.concat root "external/hermes_source"

let classify ~root ~which ~exists ~openrouter_configured =
  [
    ("ocaml", executable_check ~which "ocaml");
    ("dune", executable_check ~which "dune");
    ("cargo", executable_check ~which "cargo");
    ( "rust_release_library",
      path_check ~exists
        (Filename.concat root "external/hermes_tui_rs/target/release/libhermes_tui_rs.so") );
    ("python_reference", executable_check ~which "python3");
    ("source_snapshot", path_check ~exists (reference_root root));
    ( "openrouter_configuration",
      if openrouter_configured then Core.Passed else Core.Failed "missing" );
    ("sa_plan_contract", path_check ~exists (Filename.concat root "sa_plan/dune"));
  ]

let which name =
  match Sys.getenv_opt "PATH" with
  | None -> None
  | Some path ->
      path
      |> String.split_on_char ':'
      |> List.find_map (fun directory ->
             let candidate = Filename.concat directory name in
             try
               Unix.access candidate [ Unix.X_OK ];
               Some candidate
             with Unix.Unix_error _ -> None)

let run ~root =
  classify ~root ~which ~exists:Sys.file_exists
    ~openrouter_configured:(Option.is_some (Sys.getenv_opt "OPENROUTER_API_KEY"))
