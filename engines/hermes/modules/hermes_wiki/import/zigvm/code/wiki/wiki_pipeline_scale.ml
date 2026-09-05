open Bos

module W = Wiki_render.Docs_wiki
module P = Zigvm_harness_support.Wiki_selfcheck_parallel

let root = ref "."
let output = ref "work/benchmarks/sa-plan/wiki-selfcheck/corpus-scale.json"
let workers = ref 4

let now () = Unix.gettimeofday ()
let milliseconds started = (now () -. started) *. 1000.

let read_file path =
  match OS.File.read (Fpath.v path) with Ok value -> Some value | Error _ -> None

let tracked_markdown root =
  let command =
    Cmd.(v "git" % "-C" % root % "ls-files" % "*.md" % "docs/*.md") in
  match OS.Cmd.(run_out command |> out_string) with
  | Error (`Msg message) -> failwith message
  | Ok (text, _) ->
      text |> String.split_on_char '\n' |> List.filter (fun value -> value <> "")
      |> List.filter (fun rel ->
           let prefix p =
             String.length rel > String.length p
             && String.equal (String.sub rel 0 (String.length p)) p in
           not (String.contains rel '/') || prefix "docs/" || prefix "skills/"
           || prefix "proofs/" || prefix "specs/")
      |> List.sort_uniq compare
      |> List.filter_map (fun rel ->
           Option.map (fun content -> rel, content)
             (read_file (Filename.concat root rel)))

let prefix count values =
  values |> List.filteri (fun index _ -> index < count)

let timed f =
  let started = now () in
  let value = f () in
  value, milliseconds started

let run_size all requested =
  Gc.full_major ();
  let files = prefix (min requested (List.length all)) all in
  let input_bytes =
    List.fold_left (fun total (_, content) -> total + String.length content) 0 files in
  let pages, build_ms = timed (fun () -> W.build files) in
  let context, context_ms = timed (fun () -> W.prepare_render_context pages) in
  let page_array = Array.of_list pages in
  let render page = W.render_page_with_context ~context page in
  let sequential, sequential_ms = timed (fun () -> Array.map render page_array) in
  let parallel, parallel_ms = timed (fun () -> P.map_gss ~workers:!workers render page_array) in
  let byte_equal = Array.for_all2 String.equal sequential parallel.P.values in
  let exactly_once = Array.for_all (( = ) 1) parallel.P.visits in
  let output_bytes = Array.fold_left (fun total html -> total + String.length html) 0 sequential in
  let cold_page_ms, warm_page_ms =
    match pages with
    | [] -> 0., 0.
    | page :: _ ->
        let _, cold = timed (fun () -> W.render_page ~pages page) in
        let _, warm = timed (fun () -> W.render_page ~pages page) in
        cold, warm in
  let naive_ms, naive_equal =
    if List.length pages <= 256 then
      let mismatches, duration = timed (fun () -> W.naive_derived_link_mismatches pages) in
      Some duration, Some (mismatches = [])
    else None, None in
  `Assoc
    [ "requested_pages", `Int requested;
      "pages", `Int (List.length pages);
      "input_bytes", `Int input_bytes;
      "output_bytes", `Int output_bytes;
      "build_ms", `Float build_ms;
      "context_ms", `Float context_ms;
      "sequential_render_ms", `Float sequential_ms;
      "parallel_render_ms", `Float parallel_ms;
      "render_speedup", `Float (if parallel_ms > 0. then sequential_ms /. parallel_ms else 0.);
      "compat_page_cold_ms", `Float cold_page_ms;
      "compat_page_warm_ms", `Float warm_page_ms;
      "compat_page_cache_speedup",
        `Float (if warm_page_ms > 0. then cold_page_ms /. warm_page_ms else 0.);
      "pages_per_second_build",
        `Float (if build_ms > 0. then float_of_int (List.length pages) *. 1000. /. build_ms else 0.);
      "sequential_parallel_byte_equal", `Bool byte_equal;
      "exactly_once", `Bool exactly_once;
      "naive_reference_ms", (match naive_ms with Some value -> `Float value | None -> `Null);
      "naive_reference_equal", (match naive_equal with Some value -> `Bool value | None -> `Null) ]

let write_atomic path content =
  let target = Fpath.v path and temporary = Fpath.v (path ^ ".tmp") in
  match OS.Dir.create (Fpath.parent target) with
  | Error (`Msg message) -> failwith message
  | Ok _ ->
      (match OS.File.write temporary content with
       | Error (`Msg message) -> failwith message
       | Ok () ->
           match OS.Path.move ~force:true temporary target with
           | Ok () -> ()
           | Error (`Msg message) -> failwith message)

let () =
  Arg.parse
    [ "--root", Arg.Set_string root, "Repository root";
      "--output", Arg.Set_string output, "Benchmark JSON output";
      "--workers", Arg.Set_int workers, "Bounded Eio worker count" ]
    (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value)))
    "wiki_pipeline_scale [--root PATH] [--output PATH] [--workers N]";
  let files = tracked_markdown !root in
  if files = [] then failwith "wiki scale benchmark found no tracked Markdown";
  let sizes = [ 64; 128; 256; 512; List.length files ] |> List.sort_uniq compare in
  let rows = List.map (run_size files) sizes in
  if not (List.for_all (fun row ->
      Yojson.Safe.Util.(member "sequential_parallel_byte_equal" row |> to_bool)
      && Yojson.Safe.Util.(member "exactly_once" row |> to_bool)) rows)
  then failwith "wiki scale benchmark semantic differential failed";
  let json =
    `Assoc
      [ "schema", `String "zigvm.wiki-pipeline-scale.v1";
        "root", `String !root;
        "workers", `Int !workers;
        "corpus_files", `Int (List.length files);
        "sizes", `List rows ] in
  write_atomic !output (Yojson.Safe.pretty_to_string json ^ "\n");
  Printf.printf "wiki-pipeline-scale: green (%d sizes, %d files, %d workers) -> %s\n%!"
    (List.length sizes) (List.length files) !workers !output
