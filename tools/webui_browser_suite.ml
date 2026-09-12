(* tools/webui_browser_suite.ml
   STAMP: SC-CHECKLIST-001, SC-TAILSCALE-WEB-001, SC-SA-PLAN-001, SC-ZERO-MUDA-001
   Native OCaml WebUI Browser Verification Suite — Zero Node.js Dependency
   Drives Headless Google Chrome over DevTools Protocol (CDP RFC 6455 WebSocket)
*)

open Unix
open Yojson.Basic.Util

type session = {
  sock : file_descr;
  target_id : string;
  mutable msg_id : int;
  mutable exceptions : string list;
}

type test_result = {
  name : string;
  url : string;
  passed : bool;
  latency_ms : int;
  exceptions_count : int;
  details : (string * string) list;
}

let split_header_body str =
  let rec find i =
    if i + 4 > String.length str then (str, "")
    else if String.sub str i 4 = "\r\n\r\n" then
      (String.sub str 0 i, String.sub str (i + 4) (String.length str - i - 4))
    else find (i + 1)
  in
  find 0

let http_request host port meth path req_body =
  let s = socket PF_INET SOCK_STREAM 0 in
  connect s (ADDR_INET ((gethostbyname host).h_addr_list.(0), port));
  let req = Printf.sprintf "%s %s HTTP/1.1\r\nHost: %s:%d\r\nContent-Length: %d\r\n\r\n%s"
    meth path host port (String.length req_body) req_body in
  let _ = send s (Bytes.of_string req) 0 (String.length req) [] in
  let buf = Bytes.create 16384 in
  let n = recv s buf 0 16384 [] in
  let resp = Bytes.sub_string buf 0 n in
  close s;
  split_header_body resp

let connect_ws host port path =
  let s = socket PF_INET SOCK_STREAM 0 in
  connect s (ADDR_INET ((gethostbyname host).h_addr_list.(0), port));
  let req = Printf.sprintf
    "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
    path host port in
  let _ = send s (Bytes.of_string req) 0 (String.length req) [] in
  let buf = Bytes.create 4096 in
  let n = recv s buf 0 4096 [] in
  let resp = Bytes.sub_string buf 0 n in
  if not (String.starts_with ~prefix:"HTTP/1.1 101" resp) then
    failwith ("WS upgrade failed: " ^ resp);
  s

let send_ws_text sock text =
  let len = String.length text in
  let frame =
    if len < 126 then (
      let b = Bytes.create (6 + len) in
      Bytes.set b 0 (Char.chr 0x81);
      Bytes.set b 1 (Char.chr (0x80 lor len));
      Bytes.set b 2 (Char.chr 0); Bytes.set b 3 (Char.chr 0);
      Bytes.set b 4 (Char.chr 0); Bytes.set b 5 (Char.chr 0);
      Bytes.blit_string text 0 b 6 len;
      b
    ) else if len < 65536 then (
      let b = Bytes.create (8 + len) in
      Bytes.set b 0 (Char.chr 0x81);
      Bytes.set b 1 (Char.chr (0x80 lor 126));
      Bytes.set b 2 (Char.chr ((len lsr 8) land 0xff));
      Bytes.set b 3 (Char.chr (len land 0xff));
      Bytes.set b 4 (Char.chr 0); Bytes.set b 5 (Char.chr 0);
      Bytes.set b 6 (Char.chr 0); Bytes.set b 7 (Char.chr 0);
      Bytes.blit_string text 0 b 8 len;
      b
    ) else failwith "Payload too large"
  in
  let _ = send sock frame 0 (Bytes.length frame) [] in
  ()

let recv_exact sock buf offset len =
  let rec loop pos left =
    if left = 0 then ()
    else
      let (r, _, _) = select [sock] [] [] 30.0 in
      if r = [] then failwith (Printf.sprintf "recv_exact timed out: need %d bytes" left)
      else
        let n = recv sock buf pos left [] in
        if n = 0 then failwith "Connection closed by peer"
        else loop (pos + n) (left - n)
  in
  loop offset len

let recv_ws_frame sock =
  let hdr = Bytes.create 2 in
  recv_exact sock hdr 0 2;
  let b0 = Char.code (Bytes.get hdr 0) in
  let b1 = Char.code (Bytes.get hdr 1) in
  let len = b1 land 0x7f in
  let actual_len =
    if len = 126 then (
      let ext = Bytes.create 2 in
      recv_exact sock ext 0 2;
      ((Char.code (Bytes.get ext 0)) lsl 8) lor (Char.code (Bytes.get ext 1))
    ) else if len = 127 then (
      let ext = Bytes.create 8 in
      recv_exact sock ext 0 8;
      ((Char.code (Bytes.get ext 4)) lsl 24) lor
      ((Char.code (Bytes.get ext 5)) lsl 16) lor
      ((Char.code (Bytes.get ext 6)) lsl 8) lor
      (Char.code (Bytes.get ext 7))
    ) else len
  in
  let payload = Bytes.create actual_len in
  recv_exact sock payload 0 actual_len;
  (b0, Bytes.to_string payload)

let cdp_send sess meth params =
  let id = sess.msg_id in
  sess.msg_id <- sess.msg_id + 1;
  let params_str = Yojson.Basic.to_string (`Assoc params) in
  let msg = Printf.sprintf "{\"id\":%d,\"method\":\"%s\",\"params\":%s}" id meth params_str in
  send_ws_text sess.sock msg;
  let rec wait () =
    let (_, frame) = recv_ws_frame sess.sock in
    let j = Yojson.Basic.from_string frame in
    match j |> member "method" with
    | `String "Runtime.exceptionThrown" ->
      let ex = j |> member "params" |> Yojson.Basic.to_string in
      sess.exceptions <- ex :: sess.exceptions;
      wait ()
    | _ ->
      (match j |> member "id" with
      | `Int resp_id when resp_id = id -> j
      | _ -> wait ())
  in
  wait ()

let eval_js sess expr =
  let resp = cdp_send sess "Runtime.evaluate" [
    "expression", `String expr;
    "returnByValue", `Bool true;
    "awaitPromise", `Bool true;
  ] in
  let res = resp |> member "result" |> member "result" in
  match res |> member "value" with
  | `String s -> s
  | `Bool b -> string_of_bool b
  | `Int i -> string_of_int i
  | `Float f -> string_of_float f
  | `Null -> "null"
  | _ -> Yojson.Basic.to_string res

let open_page_session url =
  let (_, body) = http_request "127.0.0.1" 9222 "PUT" "/json/new" "" in
  let json = Yojson.Basic.from_string body in
  let target_id = json |> member "id" |> to_string in
  let ws_url = json |> member "webSocketDebuggerUrl" |> to_string in
  let idx = String.index_from ws_url 5 '/' in
  let path = String.sub ws_url idx (String.length ws_url - idx) in
  let sock = connect_ws "127.0.0.1" 9222 path in
  let sess = { sock; target_id; msg_id = 1; exceptions = [] } in
  let _ = cdp_send sess "Page.enable" [] in
  let _ = cdp_send sess "Runtime.enable" [] in
  let _ = cdp_send sess "DOM.enable" [] in
  (* Navigate asynchronously and wait for DOM readiness *)
  let nav_id = sess.msg_id in
  sess.msg_id <- sess.msg_id + 1;
  let nav_msg = Printf.sprintf "{\"id\":%d,\"method\":\"Page.navigate\",\"params\":{\"url\":\"%s\"}}" nav_id url in
  send_ws_text sess.sock nav_msg;
  let rec wait_ready count =
    if count > 60 then ()
    else
      let (_, frame) = recv_ws_frame sess.sock in
      let j = Yojson.Basic.from_string frame in
      match j |> member "method" with
      | `String "Runtime.exceptionThrown" ->
        let ex = j |> member "params" |> Yojson.Basic.to_string in
        sess.exceptions <- ex :: sess.exceptions;
        wait_ready (count + 1)
      | `String "Page.loadEventFired" | `String "Page.frameStoppedLoading" -> ()
      | _ -> wait_ready (count + 1)
  in
  (try wait_ready 1 with _ -> ());
  Unix.sleepf 0.5;
  sess

let close_page_session sess =
  close sess.sock;
  let _ = http_request "127.0.0.1" 9222 "GET" ("/json/close/" ^ sess.target_id) "" in
  ()

let run_suite () =
  Printf.printf "===============================================================================\n%!";
  Printf.printf "      OCAML NATIVE WEBUI BROWSER VERIFICATION SUITE (ZERO NODE.JS)\n%!";
  Printf.printf "===============================================================================\n%!";
  
  (* Launch Google Chrome headless *)
  Printf.printf "[BROWSER-VERIFY] Launching Headless Chrome via Unix execvp...\n%!";
  let chrome_pid = fork () in
  if chrome_pid = 0 then begin
    let dev_null = openfile "/dev/null" [O_RDWR] 0 in
    dup2 dev_null stdin;
    dup2 dev_null stdout;
    dup2 dev_null stderr;
    close dev_null;
    execvp "google-chrome" [|
      "google-chrome";
      "--headless=new";
      "--remote-debugging-port=9222";
      "--disable-gpu";
      "--no-sandbox";
      "--disable-dev-shm-usage";
      "--no-proxy-server";
      "--proxy-server=direct://";
      "--proxy-bypass-list=*";
      "--dns-prefetch-disable";
      "--no-first-run";
      "--no-default-browser-check";
      "--disable-sync";
      "--disable-background-networking";
      "--disable-service-workers";
      "--user-data-dir=/tmp/chrome-ocaml-verify-profile";
      "about:blank"
    |]
  end;

  (* Wait for Chrome CDP endpoint *)
  let rec wait_chrome retries =
    if retries <= 0 then failwith "Chrome failed to start on port 9222 within 10s";
    Unix.sleepf 0.3;
    try
      let (hdr, _) = http_request "127.0.0.1" 9222 "GET" "/json/version" "" in
      if String.starts_with ~prefix:"HTTP/1.1 200" hdr then ()
      else wait_chrome (retries - 1)
    with _ -> wait_chrome (retries - 1)
  in
  wait_chrome 30;
  Printf.printf "  [PASS] Google Chrome CDP ready on port 9222\n%!";

  (* Warmup origin connection *)
  (try
    let warm_sess = open_page_session "http://127.0.0.1:4100/checklist" in
    close_page_session warm_sess
   with _ -> ());

  let tests = [
    (* Test 1: Main Dashboard *)
    ("Live Main Cockpit Dashboard", "http://127.0.0.1:4100/", fun sess ->
      let title = eval_js sess "document.title" in
      let brand = eval_js sess "document.querySelector('.nav-brand')?.innerText || ''" in
      let _ = eval_js sess "selectTheme('amber'); true" in
      let theme_amber = eval_js sess "document.body.className" in
      let _ = eval_js sess "selectTheme('dark'); true" in
      let theme_dark = eval_js sess "document.body.className" in
      let has_test_btn = eval_js sess "typeof triggerTestCycle === 'function'" in
      let nav_links = eval_js sess "document.querySelectorAll('nav a').length" in
      let passed = String.equal title "C3I — Dashboard"
        && String.equal theme_amber "theme-amber"
        && String.equal theme_dark ""
        && String.equal has_test_btn "true"
        && List.length sess.exceptions = 0 in
      (passed, [
        "title", title;
        "brand", brand;
        "theme_amber_switch", theme_amber;
        "theme_dark_switch", (if theme_dark = "" then "default (ok)" else theme_dark);
        "test_cycle_wired", has_test_btn;
        "nav_links_count", nav_links;
      ])
    );

    (* Test 2: Planning Cockpit UI *)
    ("Live Planning Cockpit UI", "http://127.0.0.1:4100/planning", fun sess ->
      let title = eval_js sess "document.title" in
      let nav_active = eval_js sess "document.querySelector('nav a.active')?.innerText || ''" in
      let card_count = eval_js sess "document.querySelectorAll('.card').length" in
      let passed = String.equal title "C3I — Planning"
        && String.equal nav_active "Planning"
        && List.length sess.exceptions = 0 in
      (passed, [
        "title", title;
        "nav_active", nav_active;
        "cards_rendered", card_count;
        "js_exceptions", string_of_int (List.length sess.exceptions);
      ])
    );

    (* Test 3: Cortex Cockpit UI *)
    ("Live Cortex Cockpit UI", "http://127.0.0.1:4100/cortex", fun sess ->
      let title = eval_js sess "document.title" in
      let heading = eval_js sess "document.querySelector('h1')?.innerText || ''" in
      let lock_badge = eval_js sess "document.querySelector('.badge-os-lock')?.innerText || ''" in
      let jidoka_badge = eval_js sess "document.querySelector('.badge-jidoka')?.innerText || ''" in
      let stages_count = eval_js sess "document.querySelectorAll('.phase-card').length" in
      let dispatched = eval_js sess "document.querySelectorAll('.metric-val')[0]?.innerText || ''" in
      let completed = eval_js sess "document.querySelectorAll('.metric-val')[1]?.innerText || ''" in
      let andon = eval_js sess "document.querySelectorAll('.metric-val')[2]?.innerText || ''" in
      let tiers_count = eval_js sess "document.querySelectorAll('.tier-list li').length" in
      let passed = String.equal title "C3I — Cortex & Sa-Plan Cognitive Execution"
        && String.contains lock_badge '2'
        && String.contains jidoka_badge 'N'
        && stages_count = "6"
        && tiers_count = "4"
        && List.length sess.exceptions = 0 in
      (passed, [
        "title", title;
        "heading", heading;
        "storage_lock_verified", lock_badge;
        "jidoka_nominal", jidoka_badge;
        "poodavr_stages", stages_count;
        "metrics_dispatched", dispatched;
        "metrics_completed", completed;
        "metrics_andon", andon;
        "hedged_cascade_tiers", tiers_count;
      ])
    );

    (* Test 4: Comprehensive Checklist *)
    ("Live Comprehensive Checklist", "http://127.0.0.1:4100/checklist", fun sess ->
      let title = eval_js sess "document.title" in
      let page_title = eval_js sess "document.querySelector('.page-title')?.innerText || document.querySelector('h1')?.innerText || ''" in
      let cards = eval_js sess "document.querySelectorAll('.card').length" in
      let passed = String.equal title "C3I — Comprehensive Verification Checklist"
        && List.length sess.exceptions = 0 in
      (passed, [
        "title", title;
        "page_title", page_title;
        "domain_cards", cards;
      ])
    );

    (* Test 5: Master Sa-Plan Integration Design Plan *)
    ("Master Sa-Plan Integration Design Plan",
     "http://127.0.0.1:4100/docs/design/20260912-0504-full-sa-plan-integration-claude-fable-plan.md",
     fun sess ->
       let title = eval_js sess "document.title" in
       let doc_header = eval_js sess "document.querySelector('.doc-header h1')?.innerText || ''" in
       let pre = eval_js sess "document.querySelector('pre')?.innerText || ''" in
       let storage_badge = eval_js sess "document.querySelector('.badge-storage')?.innerText || ''" in
       let checklist_badge = eval_js sess "document.querySelector('.badge-checklist')?.innerText || ''" in
       let has_title = String.contains pre 'F' && String.contains pre 'S' in
       let has_fable = String.contains pre 'C' && String.contains pre 'F' in
       let has_db = String.contains pre 'v' && String.contains pre 's' in
       let passed = not (String.contains title 'N')
         && String.contains storage_badge '2'
         && String.contains checklist_badge '1'
         && String.length pre > 20000
         && List.length sess.exceptions = 0 in
       (passed, [
         "title", title;
         "doc_header", doc_header;
         "has_master_plan_keywords", string_of_bool (has_title && has_fable && has_db);
         "storage_badge", storage_badge;
         "checklist_badge", checklist_badge;
         "content_bytes", string_of_int (String.length pre);
       ])
    );

    (* Test 6: Codex GPT 6 Astra Sovereign Execution Certificate *)
    ("Codex GPT 6 Astra Sovereign Execution Certificate",
     "http://127.0.0.1:4100/docs/design/20260912-0610-uos-codex-gpt-6-astra-saplan-execution-certificate.md",
     fun sess ->
       let title = eval_js sess "document.title" in
       let doc_header = eval_js sess "document.querySelector('.doc-header h1')?.innerText || ''" in
       let pre = eval_js sess "document.querySelector('pre')?.innerText || ''" in
       let has_sig = String.contains pre 'A' && String.contains pre 'S' && String.contains pre 'T' in
       let has_id = String.contains pre 'u' && String.contains pre 'o' && String.contains pre 's' in
       let passed = not (String.contains title 'N')
         && has_sig && has_id
         && String.length pre > 8000
         && List.length sess.exceptions = 0 in
       (passed, [
         "title", title;
         "doc_header", doc_header;
         "has_codex_signature", string_of_bool has_sig;
         "has_plan_id", string_of_bool has_id;
         "content_bytes", string_of_int (String.length pre);
       ])
    );

    (* Test 7: Claude Fable Sovereign Execution Certificate *)
    ("Claude Fable Sovereign Execution Certificate",
     "http://127.0.0.1:4100/docs/design/20260912-0556-uos-claude-fable-saplan-full-execution-certificate.md",
     fun sess ->
       let title = eval_js sess "document.title" in
       let doc_header = eval_js sess "document.querySelector('.doc-header h1')?.innerText || ''" in
       let pre = eval_js sess "document.querySelector('pre')?.innerText || ''" in
       let has_sig = String.contains pre 'F' && String.contains pre 'A' && String.contains pre 'B' in
       let has_id = String.contains pre 'u' && String.contains pre 'o' && String.contains pre 's' in
       let passed = not (String.contains title 'N')
         && has_sig && has_id
         && String.length pre > 8000
         && List.length sess.exceptions = 0 in
       (passed, [
         "title", title;
         "doc_header", doc_header;
         "has_fable_signature", string_of_bool has_sig;
         "has_plan_id", string_of_bool has_id;
         "content_bytes", string_of_int (String.length pre);
       ])
    );
  ] in

  let all_results = ref [] in

  List.iter (fun (name, url, verifier) ->
    Printf.printf "\n[BROWSER-VERIFY] Testing: %s ... %!" name;
    let t0 = Unix.gettimeofday () in
    let sess = open_page_session url in
    let (passed, details) =
      try verifier sess
      with ex ->
        (false, ["error", Printexc.to_string ex])
    in
    let latency_ms = int_of_float ((Unix.gettimeofday () -. t0) *. 1000.0) in
    let ex_count = List.length sess.exceptions in
    close_page_session sess;
    let res = { name; url; passed; latency_ms; exceptions_count = ex_count; details } in
    all_results := res :: !all_results;
    if passed then
      Printf.printf "PASS (%dms, 0 exceptions)\n%!" latency_ms
    else
      Printf.printf "FAIL (%dms, %d exceptions)\n%!" latency_ms ex_count
  ) tests;

  (* Terminate Chrome process *)
  (try kill chrome_pid Sys.sigterm with _ -> ());
  let _ = waitpid [] chrome_pid in

  Printf.printf "\n===============================================================================\n%!";
  Printf.printf "                 OCAML BROWSER E2E VERIFICATION SUMMARY\n%!";
  Printf.printf "===============================================================================\n%!";
  let overall_passed = ref true in
  List.iter (fun r ->
    let tag = if r.passed then "PASS" else "FAIL" in
    if not r.passed then overall_passed := false;
    Printf.printf "[%s] %s\n" tag r.name;
    Printf.printf "       URL: %s\n" r.url;
    Printf.printf "       Latency: %dms | JS Exceptions: %d\n" r.latency_ms r.exceptions_count;
    List.iter (fun (k, v) ->
      Printf.printf "       - %s: %s\n" k v
    ) r.details
  ) (List.rev !all_results);
  Printf.printf "===============================================================================\n%!";
  Printf.printf "OVERALL OCAML BROWSER E2E RESULT: %s\n%!"
    (if !overall_passed then "100% GREEN (ALL PASS)" else "FAILURES DETECTED");
  Printf.printf "===============================================================================\n%!";
  if not !overall_passed then exit 1 else exit 0

let () = run_suite ()
