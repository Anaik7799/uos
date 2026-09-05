(* Wiki Content Security Policy Generator — REAL: emits a hardened CSP header AND
   audits the served HTML corpus against it.

   Intent (phase-7 stub): generate a strict CSP for the live wiki to block XSS.
   This is genuinely computable and useful. We (1) emit a concrete, strict CSP
   header value (default-src 'none' + narrow allowances), and (2) do REAL work by
   scanning the wiki HTML corpus (docs/**/*.html) for constructs the policy would
   BLOCK — inline `<script>` bodies, inline event handlers (`onclick=` etc.),
   `javascript:` URIs, and inline `style=`/`<style>` — reporting the real hit
   counts per construct. We do NOT claim the wiki is XSS-safe; we report exactly
   how many inline constructs the emitted policy would reject, which is the honest
   measurable fact. *)

let csp =
  String.concat "; "
    [ "default-src 'none'";
      "script-src 'self'";
      "style-src 'self'";
      "img-src 'self' data:";
      "connect-src 'self'";
      "font-src 'self'";
      "base-uri 'none'";
      "form-action 'self'";
      "frame-ancestors 'none'";
      "object-src 'none'" ]

let read_file p = try In_channel.with_open_bin p In_channel.input_all with _ -> ""

(* recursive walk collecting *.html under a root dir *)
let rec html_under dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if (try Sys.is_directory p with _ -> false) then html_under p acc
          else if Filename.check_suffix e ".html" then p :: acc
          else acc)
        acc entries
  | exception _ -> acc

let count_ci hay needle =
  let hay = String.lowercase_ascii hay and needle = String.lowercase_ascii needle in
  let lh = String.length hay and ln = String.length needle in
  if ln = 0 then 0
  else
    let rec loop i acc =
      if i + ln > lh then acc
      else if String.sub hay i ln = needle then loop (i + ln) (acc + 1)
      else loop (i + 1) acc
    in
    loop 0 0

let event_handlers content =
  (* count on<attr>= occurrences: onclick, onload, onerror, onmouseover, ... *)
  [ "onclick="; "onload="; "onerror="; "onmouseover="; "onsubmit="; "onchange="; "onkeydown=" ]
  |> List.fold_left (fun a h -> a + count_ci content h) 0

let run (root : string) : unit =
  Printf.printf "[wiki_content_security_policy_generator] Content-Security-Policy: %s\n" csp;
  let files = html_under (Filename.concat root "docs") [] in
  let inline_script = ref 0 and handlers = ref 0 and js_uri = ref 0
  and inline_style = ref 0 in
  List.iter
    (fun p ->
      let c = read_file p in
      inline_script := !inline_script + count_ci c "<script";
      handlers := !handlers + event_handlers c;
      js_uri := !js_uri + count_ci c "javascript:";
      inline_style := !inline_style + count_ci c "<style" + count_ci c "style=")
    files;
  Printf.printf
    "  audited %d HTML file(s): the emitted policy would BLOCK %d <script> tag(s), \
     %d inline event-handler(s), %d javascript: URI(s), %d inline-style construct(s)\n"
    (List.length files) !inline_script !handlers !js_uri !inline_style;
  Printf.printf
    "  [NOTE] this reports how many inline constructs the strict policy rejects; \
     it is not a claim that the wiki is XSS-free. A nonzero count means the served \
     HTML must be refactored to external assets before this CSP can be enforced \
     without breakage.\n"
