open Bos

let title = "Sa-plan unified software and CLI manual"

let contains haystack needle =
  let length = String.length needle in
  let rec loop offset =
    length = 0
    || offset + length <= String.length haystack
       && (String.equal (String.sub haystack offset length) needle
           || loop (offset + 1))
  in
  loop 0

let requirements =
  [ "front matter", "---";
    "tutorial", "## Tutorial";
    "how-to guides", "## How-to guides";
    "reference", "## Reference";
    "explanation", "## Explanation";
    "troubleshooting", "## Troubleshooting";
    "glossary", "## Glossary";
    "support", "## Support";
    "Diátaxis source", "https://diataxis.fr/";
    "Microsoft source", "https://learn.microsoft.com/en-us/style-guide/welcome/";
    "Google source", "https://developers.google.com/style";
    "plan commands", "### `plan` commands";
    "task commands", "### `task` commands";
    "job commands", "### `job` and `oban` commands";
    "workflow commands", "### `workflow` and `temporal` commands";
    "work commands", "### `work` commands";
    "docs commands", "### `docs` commands";
    "UI commands", "### `ui` commands";
    "exit status", "### Exit status";
    "environment", "### Environment variables";
    "implementation status", "## Implementation status" ]

let validate ~markdown =
  List.filter_map
    (fun (label, marker) ->
      if contains markdown marker then None else Some ("missing " ^ label))
    requirements

let render ~source_path ~markdown =
  Journal_markdown_html.create ~title ~source_path ~markdown
  |> Journal_markdown_html.render

let ( let* ) value next = Result.bind value next

let write_atomic path content =
  let target = Fpath.v path in
  let temporary = Fpath.v (path ^ ".tmp") in
  let* _ = OS.Dir.create (Fpath.parent target) in
  let* () = OS.File.write temporary content in
  OS.Path.move ~force:true temporary target

let sha256_file path =
  let command = Cmd.(v "sha256sum" % path) in
  let* output, _ = OS.Cmd.(run_out command |> out_string) in
  match String.split_on_char ' ' (String.trim output) with
  | digest :: _ when String.length digest = 64 -> Ok digest
  | _ -> Error (`Msg ("invalid SHA-256 output for " ^ path))

let verify_html ~html =
  let expected = "<title>" ^ title ^ "</title>" in
  if not (contains html expected) then Error (`Msg "manual HTML title mismatch")
  else if not (contains html "<html lang=\"en\">") then
    Error (`Msg "manual HTML has no English language declaration")
  else if contains html "<script src=" || contains html "<link rel=\"stylesheet\""
  then Error (`Msg "manual HTML depends on a remote runtime asset")
  else Ok ()

let sha256_text text =
  let temporary = Filename.temp_file "sa-plan-manual-" ".html" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove temporary with Sys_error _ -> ())
    (fun () ->
      let* () = OS.File.write (Fpath.v temporary) text in
      sha256_file temporary)

let verify_url ~url =
  let command =
    Cmd.(v "curl" % "--fail" % "--silent" % "--show-error" % "--location"
         % url)
  in
  let* html, _ = OS.Cmd.(run_out command |> out_string ~trim:false) in
  let* () = verify_html ~html in
  sha256_text html

let render_file ~input ~output =
  let* markdown = OS.File.read (Fpath.v input) in
  match validate ~markdown with
  | [] ->
      let html = render ~source_path:input ~markdown in
      let* () = verify_html ~html in
      let* () = write_atomic output html in
      sha256_file output
  | errors ->
      Error (`Msg ("manual validation failed: " ^ String.concat "; " errors))

let publish ~source ~destination =
  let* html = OS.File.read (Fpath.v source) in
  let* () = verify_html ~html in
  let* source_digest = sha256_file source in
  let* () = write_atomic destination html in
  let* destination_digest = sha256_file destination in
  if String.equal source_digest destination_digest then Ok source_digest
  else Error (`Msg "published manual SHA-256 differs from its source")
