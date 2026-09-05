open Bos

let ( let* ) result next = Result.bind result next

module Bundle = Journal_bundle_core.Journal_bundle
module Bundle_io = Journal_bundle_runtime.Journal_bundle_io
module Telemetry = Journal_bundle_runtime.Journal_bundle_telemetry

type args = {
  input : string;
  output : string;
  title : string;
  root : string;
  sources : string list;
  text_artifacts : string list;
  assets : string list;
}

type mode =
  | Legacy of args
  | Manifest of { path : string; report : string option; pool_size : int }

let parse_args () =
  let input = ref "" in
  let output = ref "" in
  let title = ref "" in
  let root = ref "." in
  let sources = ref [] in
  let text_artifacts = ref [] in
  let assets = ref [] in
  let manifest = ref "" in
  let report = ref "" in
  let pool_size = ref (max 1 (min 16 (Domain.recommended_domain_count () - 2))) in
  Arg.parse
    [
      ("--manifest", Arg.Set_string manifest, "Approach B bundle manifest path");
      ("--report", Arg.Set_string report, "Approach B publication report path");
      ("--pool-size", Arg.Set_int pool_size, "Bounded artifact acquisition/encoding pool size");
      ("--input", Arg.Set_string input, "Markdown journal path");
      ("--output", Arg.Set_string output, "Generated HTML path");
      ("--title", Arg.Set_string title, "HTML document title");
      ("--root", Arg.Set_string root, "Repository root for wiki resolution");
      ("--source", Arg.String (fun path -> sources := path :: !sources),
       "Canonical prompt transcript path; repeat for a transcript chain");
      ("--asset", Arg.String (fun path -> assets := path :: !assets),
       "Evidence image to embed; repeat for multiple assets");
      ("--text-artifact", Arg.String (fun path -> text_artifacts := path :: !text_artifacts),
       "Text contract/specification to embed; repeat for multiple artifacts");
    ]
    (fun unexpected -> raise (Arg.Bad ("unexpected argument: " ^ unexpected)))
    "render_journal_html (--manifest PATH | --input PATH --output PATH --title TITLE --source PATH)";
  if !manifest <> "" then
    if !input <> "" || !output <> "" || !title <> "" || !sources <> [] ||
       !text_artifacts <> [] || !assets <> [] then
      Error (`Msg "--manifest cannot be combined with legacy input/artifact flags")
    else if !pool_size < 1 then Error (`Msg "--pool-size must be at least one")
    else
      Ok
        (Manifest
           { path = !manifest;
             report = if !report = "" then None else Some !report;
             pool_size = !pool_size })
  else if !input = "" || !output = "" || !title = "" || !sources = [] then
    Error (`Msg "--input, --output, --title, and at least one --source are required")
  else
    Ok
      (Legacy
         { input = !input; output = !output; title = !title;
           root = !root;
           sources = List.rev !sources;
           text_artifacts = List.rev !text_artifacts;
           assets = List.rev !assets })

let mime_type path =
  if Filename.check_suffix path ".png" then "image/png"
  else if Filename.check_suffix path ".jpg" || Filename.check_suffix path ".jpeg"
  then "image/jpeg"
  else if Filename.check_suffix path ".webp" then "image/webp"
  else if Filename.check_suffix path ".svg" then "image/svg+xml"
  else "application/octet-stream"

let read_image_artifact path =
  let* bytes = OS.File.read (Fpath.v path) in
  Ok
    (Wiki_render.Journal_markdown_html.image_artifact
       ~label:(Filename.basename path)
       ~mime_type:(mime_type path)
       ~base64:(Base64.encode_string bytes))

let read_image_artifacts paths =
  List.fold_left
    (fun accumulated path ->
      let* artifacts = accumulated in
      let* artifact = read_image_artifact path in
      Ok (artifact :: artifacts))
    (Ok []) paths
  |> Result.map List.rev

let read_prompt_ledgers paths =
  List.fold_left
    (fun accumulated path ->
      let* ledgers = accumulated in
      let* content = OS.File.read (Fpath.v path) in
      Ok ((path, content) :: ledgers))
    (Ok []) paths
  |> Result.map List.rev

let read_text_artifacts paths =
  List.fold_left
    (fun accumulated path ->
      let* artifacts = accumulated in
      let* content = OS.File.read (Fpath.v path) in
      Ok
        (Wiki_render.Journal_markdown_html.text_artifact
           ~label:("Embedded text artifact — " ^ path) ~content
         :: artifacts))
    (Ok []) paths
  |> Result.map List.rev

let markdown_files root =
  let docs = Filename.concat root "docs" in
  let rec walk directory accumulated =
    try
      Array.fold_left
        (fun result name ->
          let* paths = result in
          let path = Filename.concat directory name in
          if Sys.is_directory path then walk path paths
          else if Filename.check_suffix path ".md" then Ok (path :: paths)
          else Ok paths)
        (Ok accumulated) (Sys.readdir directory)
    with Sys_error message -> Error (`Msg message)
  in
  let* paths = walk docs [] in
  Ok (List.sort compare paths)

let wiki_rendered_body_with_count ~root ~input =
  let* paths = markdown_files root in
  let* corpus =
    List.fold_left
      (fun accumulated path ->
        let* entries = accumulated in
        let* content = OS.File.read (Fpath.v path) in
        Ok ((path, content) :: entries))
      (Ok []) paths
  in
  let pages = Wiki_render.Docs_wiki.build (List.rev corpus) in
  match List.find_opt (fun (page : Wiki_render.Docs_wiki.page) ->
          String.equal page.path input) pages with
  | Some page -> Ok (page.html, List.length pages)
  | None -> Error (`Msg ("journal is absent from wiki corpus: " ^ input))

let wiki_rendered_body_from_pages ~input pages =
  match List.find_opt
          (fun (page : Wiki_render.Docs_wiki.page) -> String.equal page.path input)
          pages
  with
  | Some page -> Ok (page.html, List.length pages)
  | None -> Error (`Msg ("journal is absent from wiki corpus: " ^ input))

let wiki_rendered_body ~root ~input =
  wiki_rendered_body_with_count ~root ~input |> Result.map fst

let render args =
  let input = Fpath.v args.input in
  let output = Fpath.v args.output in
  let temporary = Fpath.v (args.output ^ ".tmp") in
  let* markdown = OS.File.read input in
  let* rendered_body = wiki_rendered_body ~root:args.root ~input:args.input in
  let* prompt_ledgers = read_prompt_ledgers args.sources in
  let* text_artifacts = read_text_artifacts args.text_artifacts in
  let* image_artifacts = read_image_artifacts args.assets in
  let prompt_artifacts =
    List.map
      (fun (path, content) ->
        Wiki_render.Journal_markdown_html.text_artifact
          ~label:("Canonical verbatim prompt ledger — " ^ path) ~content)
      prompt_ledgers
  in
  let source_paths = String.concat ", " args.sources in
  let html =
    Wiki_render.Journal_markdown_html.create
      ~title:args.title ~source_path:source_paths ~markdown
    |> fun document ->
       Wiki_render.Journal_markdown_html.with_rendered_body document rendered_body
    |> fun document ->
       Wiki_render.Journal_markdown_html.with_artifacts document
         (prompt_artifacts @ text_artifacts @ image_artifacts)
    |> Wiki_render.Journal_markdown_html.render
  in
  let* () = OS.File.write temporary html in
  let* () = OS.Path.move ~force:true temporary output in
  let prompt_bytes =
    List.fold_left (fun total (_, content) -> total + String.length content)
      0 prompt_ledgers
  in
  Ok (String.length markdown, prompt_bytes,
      List.length image_artifacts, String.length html)

let read_string path =
  match OS.File.read (Fpath.v path) with
  | Ok content -> Ok content
  | Error (`Msg message) -> Error message

let relative_label ~root path =
  let prefix = if Filename.check_suffix root "/" then root else root ^ "/" in
  if String.length path > String.length prefix &&
     String.sub path 0 (String.length prefix) = prefix then
    String.sub path (String.length prefix) (String.length path - String.length prefix)
  else path

let lookup acquired path =
  match List.assoc_opt path acquired with
  | Some content -> Ok content
  | None -> Error (`Msg ("acquired artifact is absent: " ^ path))

let publication_report ~bundle ~pool_size ~duration_ms ~run_timestamp ~html
    ~sha256_fixity ~telemetry ~input_fingerprint ~wiki_cache_hit publications =
  let warm_path_within_budget =
    (not wiki_cache_hit) ||
    Telemetry.within_warm_path_budget ~duration_ms
  in
  `Assoc
    [ ("schema_version", `Int 1);
      ("bundle", Bundle.report_to_yojson bundle);
      ("run_timestamp", `String run_timestamp);
      ("timestamp_format", `String "yyyy-mm-dd-hhss");
      ("clock_source", `String "host-clock; admitted by harness --check-time at delivery gate");
      ("content_fingerprint_sha256", `String (Bundle.fingerprint html));
      ("preservation",
       `Assoc
         [ ("profile", `String "OAIS-inspired SIP/AIP/DIP version 1");
           ("sip",
            `Assoc
              [ ("prompt_ledgers", `Int (List.length (Bundle.prompt_ledgers bundle)));
                ("declared_artifacts",
                 `Int
                   (List.length (Bundle.prompt_ledgers bundle) +
                    List.length (Bundle.text_artifacts bundle) +
                    List.length (Bundle.image_artifacts bundle) +
                    List.length (Bundle.media_artifacts bundle))) ]);
           ("aip",
            `Assoc
              [ ("format", `String "self-contained HTML5");
                ("fixity_algorithm", `String "SHA-256");
                ("fixity", `String sha256_fixity);
                ("cache_fingerprint_sha256",
                 `String (Bundle.fingerprint html));
                ("cache_fingerprint_scope",
                 `String "change detection only; not authenticity") ]);
           ("dip",
            `Assoc
              [ ("copies", `Int (List.length publications));
                ("format", `String "HTML5") ]);
           ("open_formats",
            `List
              (List.map (fun value -> `String value)
                 [ "Markdown"; "JSON"; "JSONL"; "HTML5"; "PNG"; "WebM"; "ZIP" ]));
           ("metadata_profile", `String "Dublin Core mapped project YAML v1");
           ("preservation_action",
            `String "recompute SHA-256 and verify fanout equality on every publication run") ]);
      ("input_fingerprint_sha256", `String input_fingerprint);
      ("wiki_cache_hit", `Bool wiki_cache_hit);
      ("html_bytes", `Int (String.length html));
      ("duration_ms", `Int duration_ms);
      ("warm_path_budget_ms", `Int Telemetry.warm_path_budget_ms);
      ("warm_path_within_budget", `Bool warm_path_within_budget);
      ("pool_size", `Int pool_size);
      ("render_count", `Int 1);
      ("zero_muda_renders_avoided", `Int (max 0 (List.length publications - 1)));
      ("artifact_count",
       `Int
         (List.length (Bundle.prompt_ledgers bundle) +
          List.length (Bundle.text_artifacts bundle) +
          List.length (Bundle.image_artifacts bundle) +
          List.length (Bundle.media_artifacts bundle)));
      ("publications",
       `List
         (List.map
            (fun (publication : Bundle_io.publication) ->
              `Assoc
                [ ("path", `String publication.path);
                  ("disposition",
                   `String (Bundle_io.disposition_name publication.disposition)) ])
            publications));
      ("metrics", Telemetry.render_metrics telemetry) ]

let now_ns () =
  Unix.gettimeofday () *. 1_000_000_000. |> Int64.of_float

let measurement ?work_items ?bytes ?domains ?wiki_notes ?artifacts () =
  Telemetry.{ work_items; bytes; domains; wiki_notes; artifacts }

let render_manifest ~path ~report ~pool_size =
  let process_started = Unix.gettimeofday () in
  let run_timestamp = Bundle.format_human_timestamp process_started in
  let events_rev = ref [] in
  let sequence = ref 0 in
  let sink = ref None in
  let current_events () = List.rev !events_rev in
  let persist () =
    match !sink with
    | None -> Ok ()
    | Some (bundle, trace_id) ->
        let events = current_events () in
        let summary = Telemetry.fold events in
        let* () =
          match Bundle.dashboard bundle with
          | None -> Ok ()
          | Some dashboard ->
              let content =
                Telemetry.render_dashboard
                  ~title:(Bundle.title bundle ^ " — bundle pipeline") summary
              in
              let* _ = Bundle_io.publish ~content ~outputs:[ dashboard ] in
              Ok ()
        in
        (match Bundle.otel_log bundle with
         | None -> Ok ()
         | Some otel_log ->
             let content =
               Telemetry.render_otel_file ~trace_id events
               |> Yojson.Safe.pretty_to_string
               |> fun value -> value ^ "\n"
             in
             let* _ = Bundle_io.publish ~content ~outputs:[ otel_log ] in
             Ok ())
  in
  let emit stage status stage_measurement =
    incr sequence;
    let event =
      Telemetry.make ~sequence:!sequence ~timestamp_ns:(now_ns ()) ~stage
        ~status ~measurement:stage_measurement ()
    in
    events_rev := event :: !events_rev;
    Printf.printf "%s\n%!" (Telemetry.render_tui [ event ]);
    persist ()
  in
  let run_stage stage success_measurement operation =
    let stage_started = Unix.gettimeofday () in
    let* () = emit stage Telemetry.Started Telemetry.empty_measurement in
    match operation () with
    | Ok value ->
        let duration_ms =
          int_of_float ((Unix.gettimeofday () -. stage_started) *. 1000.)
        in
        let* () =
          emit stage (Telemetry.Completed { duration_ms })
            (success_measurement value)
        in
        Ok value
    | Error (`Msg message) as error ->
        let duration_ms =
          int_of_float ((Unix.gettimeofday () -. stage_started) *. 1000.)
        in
        ignore
          (emit stage (Telemetry.Failed { message; duration_ms })
             Telemetry.empty_measurement);
        error
  in
  let* manifest_text = OS.File.read (Fpath.v path) in
  let trace_id = Bundle.fingerprint manifest_text in
  let* raw =
    run_stage Telemetry.Decode
      (fun _ -> measurement ~work_items:1 ~bytes:(String.length manifest_text) ())
      (fun () ->
        match Bundle.decode manifest_text with
        | Ok raw -> Ok raw
        | Error message -> Error (`Msg message))
  in
  let* bundle =
    run_stage Telemetry.Validate
      (fun bundle ->
        measurement
          ~work_items:
            (1 + List.length (Bundle.outputs bundle) +
             List.length (Bundle.prompt_ledgers bundle) +
             List.length (Bundle.text_artifacts bundle) +
             List.length (Bundle.image_artifacts bundle) +
             List.length (Bundle.media_artifacts bundle))
          ~artifacts:
            (List.length (Bundle.prompt_ledgers bundle) +
             List.length (Bundle.text_artifacts bundle) +
             List.length (Bundle.image_artifacts bundle) +
             List.length (Bundle.media_artifacts bundle))
          ())
      (fun () ->
        match Bundle.validate_at ~invocation_root:(Sys.getcwd ())
                ~manifest_directory:(Filename.dirname path)
                ~exists:Sys.file_exists ~read:read_string raw with
        | Ok bundle -> Ok bundle
        | Error violations ->
            Error
              (`Msg
                (violations
                 |> List.map Bundle.violation_name
                 |> String.concat ", ")))
  in
  sink := Some (bundle, trace_id);
  let* () = persist () in
  let images = Bundle.image_artifacts bundle in
  let media = Bundle.media_artifacts bundle in
  let* () =
    run_stage Telemetry.Materialize
      (fun () -> measurement ~work_items:(List.length images + List.length media) ())
      (fun () ->
        let* () = List.fold_left
          (fun accumulated image ->
            let* () = accumulated in
            Bundle_io.materialize_image image)
          (Ok ()) images in
        List.fold_left
          (fun accumulated (artifact : Bundle.media_artifact) ->
            let* () = accumulated in
            if Sys.file_exists artifact.path then Ok ()
            else match artifact.source with
              | None -> Error (`Msg ("missing durable media: " ^ artifact.path))
              | Some source ->
                  let* content = OS.File.read (Fpath.v source) in
                  let* _ = Bundle_io.publish ~content ~outputs:[ artifact.path ] in
                  Ok ())
          (Ok ()) media)
  in
  let* wiki_paths =
    run_stage Telemetry.Discover
      (fun paths -> measurement ~work_items:(List.length paths) ())
      (fun () -> markdown_files (Bundle.root bundle))
  in
  let paths =
    Bundle.input bundle ::
    (Bundle.prompt_ledgers bundle @ Bundle.text_artifacts bundle @
     List.map (fun (image : Bundle.image_artifact) -> image.path) images @
     List.map (fun (artifact : Bundle.media_artifact) -> artifact.path) media @
     wiki_paths)
    |> List.sort_uniq String.compare
  in
  let* acquired =
    run_stage Telemetry.Acquire
      (fun acquired ->
        measurement ~work_items:(List.length acquired)
          ~bytes:
            (List.fold_left
               (fun total (_, content) -> total + String.length content)
               0 acquired)
          ~domains:pool_size ())
      (fun () -> Bundle_io.acquire_files ~pool_size paths)
  in
  let* markdown = lookup acquired (Bundle.input bundle) in
  let input_fingerprint =
    manifest_text ^ "\n" ^
    (acquired
     |> List.map (fun (artifact_path, content) ->
          artifact_path ^ ":" ^ Bundle.fingerprint content)
     |> String.concat "\n")
    |> Bundle.fingerprint
  in
  let report_path =
    match report with Some path -> Some path | None -> Bundle.report bundle
  in
  let report_path =
    Option.map
      (fun report_path ->
        if Filename.is_relative report_path then
          Filename.concat (Bundle.root bundle) report_path
        else report_path)
      report_path
  in
  let wiki_cache_path =
    match report_path with
    | Some report_path -> report_path ^ ".wiki-cache.html"
    | None -> List.hd (Bundle.outputs bundle) ^ ".wiki-cache.html"
  in
  let cache_hit =
    match report_path with
    | Some report_path when Sys.file_exists report_path && Sys.file_exists wiki_cache_path ->
        (match OS.File.read (Fpath.v report_path) with
         | Ok prior ->
             Bundle.report_input_fingerprint prior = Some input_fingerprint
         | Error _ -> false)
    | _ -> false
  in
  let* zk_pages =
    run_stage Telemetry.Zk
      (fun pages ->
        let notes =
          Option.fold ~none:(List.length wiki_paths) ~some:List.length pages
        in
        measurement ~work_items:notes ~wiki_notes:notes ())
      (fun () ->
        if cache_hit then Ok None
        else
          let* corpus =
            List.fold_left
              (fun accumulated wiki_path ->
                let* entries = accumulated in
                let* content = lookup acquired wiki_path in
                Ok ((wiki_path, content) :: entries))
              (Ok []) wiki_paths
            |> Result.map List.rev
          in
          Ok (Some (Wiki_render.Docs_wiki.build corpus)))
  in
  let* rendered_body, wiki_notes =
    run_stage Telemetry.Wiki
      (fun (_, notes) -> measurement ~work_items:notes ~wiki_notes:notes ())
      (fun () ->
        if cache_hit then
          let* body = OS.File.read (Fpath.v wiki_cache_path) in
          Ok (body, List.length wiki_paths)
        else
          match zk_pages with
          | None -> Error (`Msg "ZK model absent on a wiki cache miss")
          | Some pages ->
              let* body, notes =
                wiki_rendered_body_from_pages ~input:(Bundle.input bundle) pages
              in
              let* _ =
                Bundle_io.publish ~content:body ~outputs:[ wiki_cache_path ]
              in
              Ok (body, notes))
  in
  let build_html () =
    let* prompt_artifacts =
      List.fold_left
        (fun accumulated artifact_path ->
          let* artifacts = accumulated in
          let* content = lookup acquired artifact_path in
          Ok
            (Wiki_render.Journal_markdown_html.text_artifact
               ~label:
                 ("Canonical verbatim prompt ledger — " ^
                  relative_label ~root:(Bundle.root bundle) artifact_path)
               ~content
             :: artifacts))
        (Ok []) (Bundle.prompt_ledgers bundle)
      |> Result.map List.rev
    in
    let* text_artifacts =
      List.fold_left
        (fun accumulated artifact_path ->
          let* artifacts = accumulated in
          let* content = lookup acquired artifact_path in
          Ok
            (Wiki_render.Journal_markdown_html.text_artifact
               ~label:
                 ("Embedded text artifact — " ^
                  relative_label ~root:(Bundle.root bundle) artifact_path)
               ~content
             :: artifacts))
        (Ok []) (Bundle.text_artifacts bundle)
      |> Result.map List.rev
    in
    let image_results =
      Bundle_io.map_ordered ~pool_size
        (fun (image : Bundle.image_artifact) ->
          let* bytes = lookup acquired image.path in
          Ok
            (Wiki_render.Journal_markdown_html.image_artifact
               ~label:(Filename.basename image.path)
               ~mime_type:(mime_type image.path)
               ~base64:(Base64.encode_string bytes)))
        images
    in
    let* image_artifacts =
      List.fold_left
        (fun accumulated result ->
          let* artifacts = accumulated in
          let* artifact = result in
          Ok (artifact :: artifacts))
        (Ok []) image_results
      |> Result.map List.rev
    in
    let media_results =
      Bundle_io.map_ordered ~pool_size
        (fun (artifact : Bundle.media_artifact) ->
          let* bytes = lookup acquired artifact.path in
          let sha256 = Bundle.fingerprint bytes in
          let base64 = Base64.encode_string bytes in
          let provenance = relative_label ~root:(Bundle.root bundle) artifact.path in
          match artifact.kind with
          | Bundle.Text ->
              Ok (Wiki_render.Journal_markdown_html.text_artifact
                    ~label:artifact.label ~content:bytes)
          | Bundle.Image ->
              Ok (Wiki_render.Journal_markdown_html.image_artifact
                    ~label:artifact.label ~mime_type:artifact.mime_type ~base64)
          | Bundle.Video ->
              Ok (Wiki_render.Journal_markdown_html.video_artifact
                    ~label:artifact.label ~mime_type:artifact.mime_type ~base64
                    ~sha256 ~bytes:(String.length bytes) ~provenance)
          | Bundle.Trace | Bundle.Binary ->
              Ok (Wiki_render.Journal_markdown_html.download_artifact
                    ~label:artifact.label ~mime_type:artifact.mime_type ~base64
                    ~sha256 ~bytes:(String.length bytes) ~provenance))
        media
    in
    let* media_artifacts =
      List.fold_left
        (fun accumulated result ->
          let* artifacts = accumulated in
          let* artifact = result in
          Ok (artifact :: artifacts))
        (Ok []) media_results
      |> Result.map List.rev
    in
    let source_paths =
      Bundle.prompt_ledgers bundle
      |> List.map (relative_label ~root:(Bundle.root bundle))
      |> String.concat ", "
    in
    Ok
      (Wiki_render.Journal_markdown_html.create
         ~title:(Bundle.title bundle) ~source_path:source_paths ~markdown
       |> fun document ->
          Wiki_render.Journal_markdown_html.with_rendered_body document
            rendered_body
       |> fun document ->
          Wiki_render.Journal_markdown_html.with_artifacts document
            (prompt_artifacts @ text_artifacts @ image_artifacts @ media_artifacts)
       |> Wiki_render.Journal_markdown_html.render)
  in
  let artifact_count =
    List.length (Bundle.prompt_ledgers bundle) +
    List.length (Bundle.text_artifacts bundle) + List.length images + List.length media
  in
  let* html =
    run_stage Telemetry.Render
      (fun html ->
        measurement ~work_items:artifact_count ~bytes:(String.length html)
          ~domains:pool_size ~wiki_notes ~artifacts:artifact_count ())
      build_html
  in
  let* publications, sha256_fixity =
    run_stage Telemetry.Publish
      (fun (publications, _) ->
        measurement ~work_items:(List.length publications)
          ~bytes:(String.length html) ())
      (fun () ->
        let* publications =
          Bundle_io.publish ~content:html ~outputs:(Bundle.outputs bundle)
        in
        let fixity_results =
          Bundle_io.map_ordered ~pool_size Bundle_io.sha256_file
            (Bundle.outputs bundle)
        in
        let* fixities =
          List.fold_left
            (fun accumulated result ->
              let* values = accumulated in
              let* value = result in
              Ok (value :: values))
            (Ok []) fixity_results
          |> Result.map List.rev
        in
        match fixities with
        | [] -> Error (`Msg "OAIS fixity requires at least one publication")
        | first :: rest when List.for_all (String.equal first) rest ->
            Ok (publications, first)
        | _ -> Error (`Msg "OAIS SHA-256 fanout fixity mismatch"))
  in
  let* () =
    if Bundle.valid_human_timestamp run_timestamp then Ok ()
    else Error (`Msg ("CTRL-TIME generated invalid timestamp: " ^ run_timestamp))
  in
  let report_started = Unix.gettimeofday () in
  let* () = emit Telemetry.Report Telemetry.Started Telemetry.empty_measurement in
  let report_duration_ms =
    int_of_float ((Unix.gettimeofday () -. report_started) *. 1000.)
  in
  let* () =
    emit Telemetry.Report (Telemetry.Completed { duration_ms = report_duration_ms })
      (measurement ~work_items:1 ())
  in
  let duration_ms =
    int_of_float ((Unix.gettimeofday () -. process_started) *. 1000.)
  in
  let telemetry = Telemetry.fold (current_events ()) in
  let budget_violations = Telemetry.budget_violations telemetry in
  let* () =
    match budget_violations with
    | [] -> Ok ()
    | violations ->
        Error
          (`Msg
            (violations
             |> List.map Telemetry.budget_violation_name
             |> String.concat ", "))
  in
  let* () =
    if (not cache_hit) ||
       Telemetry.within_warm_path_budget ~duration_ms
    then Ok ()
    else
      Error
        (`Msg
          (Printf.sprintf "warm-path-budget-exceeded(%dms>=%dms)"
             duration_ms Telemetry.warm_path_budget_ms))
  in
  let report_json =
    publication_report ~bundle ~pool_size ~duration_ms ~run_timestamp ~html
      ~sha256_fixity ~telemetry
      ~input_fingerprint ~wiki_cache_hit:cache_hit publications
  in
  let* () =
    match report_path with
    | None -> Ok ()
    | Some report_path ->
        let content = Yojson.Safe.pretty_to_string report_json ^ "\n" in
        let* _ = Bundle_io.publish ~content ~outputs:[ report_path ] in
        Ok ()
  in
  Ok (report_json, publications)

let () =
  match parse_args () with
  | Error (`Msg message) ->
      Printf.eprintf "render_journal_html: %s\n%!" message;
      exit 2
  | Ok (Legacy args) ->
      (match render args with
       | Ok (markdown_bytes, prompt_bytes, asset_count, html_bytes) ->
           Printf.printf
             "rendered %d Markdown bytes + %d prompt bytes + %d assets to %d self-contained HTML bytes\n%!"
             markdown_bytes prompt_bytes asset_count html_bytes
       | Error (`Msg message) ->
           Printf.eprintf "render_journal_html: %s\n%!" message;
           exit 1)
  | Ok (Manifest { path; report; pool_size }) ->
      (match render_manifest ~path ~report ~pool_size with
       | Ok (report_json, publications) ->
           Yojson.Safe.pretty_to_channel stdout report_json;
           output_char stdout '\n';
           Printf.printf "bundle outputs: %d\n%!" (List.length publications)
       | Error (`Msg message) ->
           Printf.eprintf "render_journal_html: %s\n%!" message;
           exit 1)
