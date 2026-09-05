let fail label detail =
  Printf.eprintf "FAIL %s: %s\n%!" label detail;
  exit 1

let require label condition detail =
  if condition then Printf.printf "ok %s\n%!" label else fail label detail

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search offset =
    if needle_length = 0 then true
    else if offset + needle_length > haystack_length then false
    else if String.sub haystack offset needle_length = needle then true
    else search (offset + 1)
  in
  search 0

let () =
  let module Journal = Wiki_render.Journal_markdown_html in
  let markdown =
    "# Lossless journal\n\n## Prompt transcript\n\n```text\n" ^
    "use figma & stitch <without loss>\n<script>alert('never')</script>\n" ^
    "```\n"
  in
  let document =
    Journal.create
      ~title:"InfraNodus <superset>"
      ~source_path:"docs/journal/source-prompt.jsonl"
      ~markdown
  in
  let document =
    Journal.with_artifacts document
      [
        Journal.text_artifact
          ~label:"Verbatim prompt ledger"
          ~content:"{\"text\":\"preserve <all> & exact\"}\n";
        Journal.image_artifact
          ~label:"Embedded evidence image"
          ~mime_type:"image/png"
          ~base64:"iVBORw0KGgo=";
        Journal.video_artifact ~label:"journey.webm" ~mime_type:"video/webm"
          ~base64:"d2VibQ==" ~sha256:"abc" ~bytes:4 ~provenance:"capture";
        Journal.download_artifact ~label:"trace.zip" ~mime_type:"application/zip"
          ~base64:"emlw" ~sha256:"def" ~bytes:3 ~provenance:"trace";
      ]
  in
  let first = Journal.render document in
  let second = Journal.render document in
  require "LAW JOURNAL-DETERMINISM"
    (String.equal first second)
    "identical inputs produced different HTML bytes";
  require "LAW PROMPT-CONTENT-PRESERVATION"
    (contains first "use figma &amp; stitch &lt;without loss&gt;")
    "escaped prompt bytes were dropped or normalized";
  require "LAW PROMPT-MARKUP-QUARANTINE"
    (contains first "&lt;script&gt;alert(&#39;never&#39;)&lt;/script&gt;" &&
     not (contains first "<script>alert('never')</script>"))
    "prompt markup escaped its code block";
  require "LAW JOURNAL-PROVENANCE-VISIBLE"
    (contains first "docs/journal/source-prompt.jsonl")
    "source transcript path is not visible";
  require "LAW JOURNAL-SELF-CONTAINED"
    (contains first "<!doctype html>" && contains first "<style>" &&
     not (contains first "<link rel=\"stylesheet\"") &&
     not (contains first "<script src="))
    "HTML depends on a runtime asset";
  require "LAW PROMPT-LEDGER-EMBEDDED"
    (contains first "preserve &lt;all&gt; &amp; exact")
    "verbatim prompt ledger is not embedded in the HTML";
  require "LAW EVIDENCE-ASSET-EMBEDDED"
    (contains first "data:image/png;base64,iVBORw0KGgo=")
    "evidence image is not embedded as a data URI";
  require "LAW MEDIA-VIDEO-TOTALITY"
    (contains first "data:video/webm;base64,d2VibQ==" && contains first "SHA-256 abc")
    "video metadata or bytes missing";
  require "LAW MEDIA-BINARY-TOTALITY"
    (contains first "download=\"trace.zip\"" &&
     contains first "data:application/zip;base64,emlw")
    "binary download metadata or bytes missing"
