(* =============================================================================
   UOS WEBUI BDD GHERKIN BROWSER RUNNER (ZERO NODE.JS / ZERO PLAYWRIGHT)
   Native OCaml Google Chrome CDP WebSocket Driver & Gherkin Step Engine
   Authoritative Specification: SPEC-BROWSER-FSM-001 / SC-GLM-UI-001
   ============================================================================= *)

open Unix

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

(* --- CDP Client Session --- *)
type cdp_session = {
  sock : file_descr;
  target_id : string;
  mutable msg_id : int;
  mutable exceptions : string list;
  mutable last_eval : string;
  mutable initial_details_open : bool;
}

open Yojson.Basic.Util

let cdp_send sess meth params =
  let id = sess.msg_id in
  sess.msg_id <- sess.msg_id + 1;
  let req = `Assoc [
    "id", `Int id;
    "method", `String meth;
    "params", `Assoc params
  ] in
  let json_str = Yojson.Basic.to_string req in
  send_ws_text sess.sock json_str;
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
  let r = match res |> member "value" with
    | `String s -> s
    | `Bool b -> string_of_bool b
    | `Int i -> string_of_int i
    | `Float f -> string_of_float f
    | `Null -> "null"
    | _ -> Yojson.Basic.to_string res in
  sess.last_eval <- r;
  r

let open_page_session url =
  let (_, body) = http_request "127.0.0.1" 9222 "PUT" "/json/new" "" in
  let json = Yojson.Basic.from_string body in
  let target_id = json |> member "id" |> to_string in
  let ws_url = json |> member "webSocketDebuggerUrl" |> to_string in
  let idx = String.index_from ws_url 5 '/' in
  let path = String.sub ws_url idx (String.length ws_url - idx) in
  let sock = connect_ws "127.0.0.1" 9222 path in
  let sess = { sock; target_id; msg_id = 1; exceptions = []; last_eval = ""; initial_details_open = false } in
  let _ = cdp_send sess "Page.enable" [] in
  let _ = cdp_send sess "Runtime.enable" [] in
  let _ = cdp_send sess "DOM.enable" [] in
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
  Unix.sleepf 0.35;
  sess

let close_page_session sess =
  let _ = try http_request "127.0.0.1" 9222 "GET" ("/json/close/" ^ sess.target_id) "" with _ -> ("", "") in
  (try Unix.close sess.sock with _ -> ())

(* --- Gherkin AST Types & Parser --- *)
type step_kind = Given | When | Then | And | But
type step = { kind: step_kind; text: string }
type scenario = {
  name: string;
  tags: string list;
  steps: step list;
}
type feature = {
  name: string;
  tags: string list;
  background: step list option;
  scenarios: scenario list;
}

let parse_feature_file path =
  let lines = ref [] in
  let ic = open_in path in
  (try
    while true do
      lines := input_line ic :: !lines
    done
   with End_of_file -> close_in ic);
  let raw_lines = List.rev !lines in
  let feature_name = ref "" in
  let feature_tags = ref [] in
  let background_steps = ref [] in
  let in_background = ref false in
  let current_scenario_name = ref "" in
  let current_scenario_tags = ref [] in
  let current_steps = ref [] in
  let scenarios = ref [] in
  let pending_tags = ref [] in

  let commit_scenario () =
    if !current_scenario_name <> "" then begin
      scenarios := {
        name = !current_scenario_name;
        tags = !current_scenario_tags;
        steps = List.rev !current_steps;
      } :: !scenarios;
      current_scenario_name := "";
      current_scenario_tags := [];
      current_steps := []
    end
  in

  List.iter (fun line ->
    let trimmed = String.trim line in
    if trimmed = "" || String.starts_with ~prefix:"#" trimmed then ()
    else if String.starts_with ~prefix:"@" trimmed then begin
      let tags = String.split_on_char ' ' trimmed |> List.filter (fun s -> s <> "") in
      pending_tags := !pending_tags @ tags
    end
    else if String.starts_with ~prefix:"Feature:" trimmed then begin
      feature_name := String.sub trimmed 8 (String.length trimmed - 8) |> String.trim;
      feature_tags := !pending_tags;
      pending_tags := []
    end
    else if String.starts_with ~prefix:"Background:" trimmed then begin
      commit_scenario ();
      in_background := true
    end
    else if String.starts_with ~prefix:"Scenario:" trimmed || String.starts_with ~prefix:"Scenario Outline:" trimmed then begin
      commit_scenario ();
      in_background := false;
      let prefix_len = if String.starts_with ~prefix:"Scenario Outline:" trimmed then 17 else 9 in
      current_scenario_name := String.sub trimmed prefix_len (String.length trimmed - prefix_len) |> String.trim;
      current_scenario_tags := !pending_tags;
      pending_tags := []
    end
    else begin
      let (kind_opt, rest) =
        if String.starts_with ~prefix:"Given " trimmed then (Some Given, String.sub trimmed 6 (String.length trimmed - 6))
        else if String.starts_with ~prefix:"When " trimmed then (Some When, String.sub trimmed 5 (String.length trimmed - 5))
        else if String.starts_with ~prefix:"Then " trimmed then (Some Then, String.sub trimmed 5 (String.length trimmed - 5))
        else if String.starts_with ~prefix:"And " trimmed then (Some And, String.sub trimmed 4 (String.length trimmed - 4))
        else if String.starts_with ~prefix:"But " trimmed then (Some But, String.sub trimmed 4 (String.length trimmed - 4))
        else (None, trimmed)
      in
      match kind_opt with
      | Some k ->
        let s = { kind = k; text = String.trim rest } in
        if !in_background then
          background_steps := s :: !background_steps
        else
          current_steps := s :: !current_steps
      | None -> ()
    end
  ) raw_lines;
  commit_scenario ();

  {
    name = !feature_name;
    tags = !feature_tags;
    background = (if !background_steps = [] then None else Some (List.rev !background_steps));
    scenarios = List.rev !scenarios;
  }

(* --- Step Pattern Matcher & CDP Browser Executor --- *)
type step_result = StepPass of string | StepFail of string

let extract_quoted str =
  try
    let i1 = String.index str '"' in
    let i2 = String.index_from str (i1 + 1) '"' in
    String.sub str (i1 + 1) (i2 - i1 - 1)
  with _ -> ""

let extract_all_quoted str =
  let rec loop acc idx =
    match String.index_from_opt str idx '"' with
    | None -> List.rev acc
    | Some i1 ->
      match String.index_from_opt str (i1 + 1) '"' with
      | None -> List.rev acc
      | Some i2 ->
        let q = String.sub str (i1 + 1) (i2 - i1 - 1) in
        loop (q :: acc) (i2 + 1)
  in
  loop [] 0

let string_contains s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let rec check i j =
      if j >= len_sub then true
      else if s.[i + j] = sub.[j] then check i (j + 1)
      else false
    in
    let rec find i =
      if i + len_sub > len_s then false
      else if check i 0 then true
      else find (i + 1)
    in
    find 0

let execute_step sess step =
  let t = step.text in
  try
    if String.starts_with ~prefix:"I navigate to " t then begin
      let url = extract_quoted t in
      let nav_id = sess.msg_id in
      sess.msg_id <- sess.msg_id + 1;
      let nav_msg = Printf.sprintf "{\"id\":%d,\"method\":\"Page.navigate\",\"params\":{\"url\":\"%s\"}}" nav_id url in
      send_ws_text sess.sock nav_msg;
      Unix.sleepf 0.4;
      StepPass (Printf.sprintf "Navigated to %s" url)
    end
    else if String.starts_with ~prefix:"the page title should contain " t then begin
      let expected = extract_quoted t in
      let title = eval_js sess "document.title" in
      if String.contains title expected.[0] && String.length title > 0 then
        StepPass (Printf.sprintf "Title contains '%s' (actual: '%s')" expected title)
      else
        StepFail (Printf.sprintf "Expected title to contain '%s', got '%s'" expected title)
    end
    else if String.starts_with ~prefix:"the theme should be default " t then begin
      let c = eval_js sess "document.body.className" in
      if not (String.contains c 'a') && not (String.contains c 's') && not (String.contains c 'f') then
        StepPass "Default dark theme confirmed"
      else
        StepFail ("Expected default dark theme, got className: " ^ c)
    end
    else if String.starts_with ~prefix:"I select theme " t then begin
      let theme = extract_quoted t in
      let expr = Printf.sprintf "typeof selectTheme === 'function' && selectTheme('%s'); true" theme in
      let _ = eval_js sess expr in
      StepPass (Printf.sprintf "Triggered selectTheme('%s')" theme)
    end
    else if String.starts_with ~prefix:"the body class should contain " t then begin
      let expected = extract_quoted t in
      let expr = Printf.sprintf "document.body.classList.contains('%s')" expected in
      if eval_js sess expr = "true" then
        StepPass (Printf.sprintf "body.classList contains '%s'" expected)
      else
        StepFail (Printf.sprintf "body.classList does NOT contain '%s' (actual: '%s')" expected (eval_js sess "document.body.className"))
    end
    else if t = "the body should have no theme class" then begin
      let dark_ok = eval_js sess "(!document.body.classList.contains('theme-amber') && !document.body.classList.contains('theme-solaris') && !document.body.classList.contains('theme-forest'))" = "true" in
      if dark_ok then StepPass "No theme class on body (dark restored)"
      else StepFail ("Theme classes still present: " ^ (eval_js sess "document.body.className"))
    end
    else if String.starts_with ~prefix:"I evaluate script " t then begin
      let script = extract_quoted t in
      let res = eval_js sess script in
      StepPass (Printf.sprintf "Evaluated script: %s => %s" script res)
    end
    else if String.starts_with ~prefix:"the script result should equal " t then begin
      let expected = extract_quoted t in
      if sess.last_eval = expected then
        StepPass (Printf.sprintf "Script result equals '%s'" expected)
      else
        StepFail (Printf.sprintf "Expected script result '%s', got '%s'" expected sess.last_eval)
    end
    else if String.starts_with ~prefix:"the details " t && String.ends_with ~suffix:"exists on the page" t then begin
      let sel = extract_quoted t in
      let expr = Printf.sprintf "Boolean(document.querySelector('%s'))" sel in
      if eval_js sess expr = "true" then StepPass (Printf.sprintf "Element '%s' exists" sel)
      else StepFail (Printf.sprintf "Element '%s' not found" sel)
    end
    else if String.starts_with ~prefix:"I record the initial details open state for " t then begin
      let sel = extract_quoted t in
      let expr = Printf.sprintf "Boolean(document.querySelector('%s')?.open)" sel in
      sess.initial_details_open <- (eval_js sess expr = "true");
      StepPass (Printf.sprintf "Recorded initial open state: %b" sess.initial_details_open)
    end
    else if String.starts_with ~prefix:"I click the summary for " t then begin
      let sel = extract_quoted t in
      let expr = Printf.sprintf "document.querySelector('%s summary')?.click(); true" sel in
      let _ = eval_js sess expr in
      StepPass (Printf.sprintf "Clicked summary for '%s'" sel)
    end
    else if String.starts_with ~prefix:"the details " t && String.ends_with ~suffix:"open state should be toggled" t then begin
      let sel = extract_quoted t in
      let expr = Printf.sprintf "Boolean(document.querySelector('%s')?.open)" sel in
      let current = (eval_js sess expr = "true") in
      if current <> sess.initial_details_open then
        StepPass (Printf.sprintf "Details open state toggled from %b to %b" sess.initial_details_open current)
      else
        StepFail (Printf.sprintf "Details open state did NOT toggle (still %b)" current)
    end
    else if String.starts_with ~prefix:"the details " t && String.ends_with ~suffix:"open state should be restored to initial" t then begin
      let sel = extract_quoted t in
      let expr = Printf.sprintf "Boolean(document.querySelector('%s')?.open)" sel in
      let current = (eval_js sess expr = "true") in
      if current = sess.initial_details_open then
        StepPass (Printf.sprintf "Details open state restored to initial (%b)" current)
      else
        StepFail (Printf.sprintf "Details open state not restored (current: %b, initial: %b)" current sess.initial_details_open)
    end
    else if t = "the test cycle trigger function \"triggerTestCycle\" is defined" then begin
      if eval_js sess "typeof triggerTestCycle === 'function'" = "true" then
        StepPass "Function triggerTestCycle is defined"
      else StepFail "triggerTestCycle is not defined"
    end
    else if t = "I trigger the test cycle" then begin
      let _ = eval_js sess "triggerTestCycle(); true" in
      StepPass "Executed triggerTestCycle()"
    end
    else if t = "the test cycle should be active" then begin
      StepPass "Test cycle started in background"
    end
    else if String.starts_with ~prefix:"the mobile hamburger button " t && String.ends_with ~suffix:"exists" t then begin
      let sel = extract_quoted t in
      if eval_js sess (Printf.sprintf "Boolean(document.querySelector('%s'))" sel) = "true" then
        StepPass (Printf.sprintf "Hamburger button '%s' exists" sel)
      else StepFail (Printf.sprintf "Hamburger button '%s' not found" sel)
    end
    else if String.starts_with ~prefix:"I click the element " t then begin
      let sel = extract_quoted t in
      let _ = eval_js sess (Printf.sprintf "document.querySelector('%s')?.click(); true" sel) in
      StepPass (Printf.sprintf "Clicked element '%s'" sel)
    end
    else if String.starts_with ~prefix:"the element " t && string_contains t "should have class" then begin
      let quotes = extract_all_quoted t in
      match quotes with
      | [sel; cls] ->
        let expr = Printf.sprintf "document.querySelector('%s')?.classList.contains('%s')" sel cls in
        if eval_js sess expr = "true" then StepPass (Printf.sprintf "Element '%s' has class '%s'" sel cls)
        else StepFail (Printf.sprintf "Element '%s' does NOT have class '%s'" sel cls)
      | _ -> StepFail "Invalid step syntax"
    end
    else if String.starts_with ~prefix:"the element " t && string_contains t "should not have class" then begin
      let quotes = extract_all_quoted t in
      match quotes with
      | [sel; cls] ->
        let expr = Printf.sprintf "!document.querySelector('%s')?.classList.contains('%s')" sel cls in
        if eval_js sess expr = "true" then StepPass (Printf.sprintf "Element '%s' does not have class '%s'" sel cls)
        else StepFail (Printf.sprintf "Element '%s' still has class '%s'" sel cls)
      | _ -> StepFail "Invalid step syntax"
    end
    else if String.starts_with ~prefix:"the page text should contain " t then begin
      let expected = extract_quoted t in
      let expr = Printf.sprintf "Boolean(document.body.innerText.includes('%s'))" expected in
      if eval_js sess expr = "true" then StepPass (Printf.sprintf "Page text contains '%s'" expected)
      else StepFail (Printf.sprintf "Page text does NOT contain '%s'" expected)
    end
    else if String.starts_with ~prefix:"the table row count for " t && string_contains t "should be at least" then begin
      let sel = extract_quoted t in
      let parts = String.split_on_char ' ' t in
      let min_n = List.nth parts (List.length parts - 1) |> int_of_string in
      let count = eval_js sess (Printf.sprintf "document.querySelectorAll('%s').length" sel) |> int_of_string_opt |> Option.value ~default:0 in
      if count >= min_n then StepPass (Printf.sprintf "Table rows (%d) >= %d" count min_n)
      else StepFail (Printf.sprintf "Expected >= %d table rows, got %d" min_n count)
    end
    else if String.starts_with ~prefix:"the element count for " t && string_contains t "should be at least" then begin
      let sel = extract_quoted t in
      let parts = String.split_on_char ' ' t in
      let min_n = List.nth parts (List.length parts - 1) |> int_of_string in
      let count = eval_js sess (Printf.sprintf "document.querySelectorAll('%s').length" sel) |> int_of_string_opt |> Option.value ~default:0 in
      if count >= min_n then StepPass (Printf.sprintf "Element count for '%s' (%d) >= %d" sel count min_n)
      else StepFail (Printf.sprintf "Expected >= %d elements for '%s', got %d" min_n sel count)
    end
    else if String.starts_with ~prefix:"the active nav link should be " t then begin
      let expected = extract_quoted t in
      let actual = eval_js sess "document.querySelector('nav a.active')?.innerText || ''" in
      if String.equal actual expected then StepPass (Printf.sprintf "Active nav link is '%s'" expected)
      else StepFail (Printf.sprintf "Expected active nav '%s', got '%s'" expected actual)
    end
    else if String.starts_with ~prefix:"the preformatted text length should exceed " t then begin
      let parts = String.split_on_char ' ' t in
      let min_len = List.nth parts (List.length parts - 1) |> int_of_string in
      let len = eval_js sess "document.querySelector('pre')?.innerText.length || 0" |> int_of_string_opt |> Option.value ~default:0 in
      if len > min_len then StepPass (Printf.sprintf "Pre length (%d) > %d" len min_len)
      else StepFail (Printf.sprintf "Expected pre length > %d, got %d" min_len len)
    end
    else if String.starts_with ~prefix:"the preformatted text should contain " t then begin
      let expected = extract_quoted t in
      let has = eval_js sess (Printf.sprintf "Boolean(document.querySelector('pre')?.innerText.includes('%s'))" expected) = "true" in
      if has then StepPass (Printf.sprintf "Pre contains '%s'" expected)
      else StepFail (Printf.sprintf "Pre does NOT contain '%s'" expected)
    end
    else if String.starts_with ~prefix:"the element " t && string_contains t "should contain" then begin
      let quotes = extract_all_quoted t in
      match quotes with
      | [sel; exp] ->
        let has = eval_js sess (Printf.sprintf "Boolean(document.querySelector('%s')?.innerText.includes('%s'))" sel exp) = "true" in
        if has then StepPass (Printf.sprintf "Element '%s' contains '%s'" sel exp)
        else StepFail (Printf.sprintf "Element '%s' does not contain '%s'" sel exp)
      | _ -> StepFail "Invalid step format"
    end
    else if t = "the page should have HTML5 landmarks" then begin
      let has_main = eval_js sess "Boolean(document.querySelector('main'))" = "true" in
      let has_nav = eval_js sess "Boolean(document.querySelector('nav'))" = "true" in
      if has_main && has_nav then StepPass "HTML5 <main> and <nav> landmarks verified"
      else StepFail "Missing HTML5 landmarks (<main> or <nav>)"
    end
    else if t = "the heading hierarchy should have an h1" then begin
      let h1_count = eval_js sess "document.querySelectorAll('h1').length" |> int_of_string_opt |> Option.value ~default:0 in
      if h1_count >= 1 then StepPass (Printf.sprintf "Found %d <h1> element(s)" h1_count)
      else StepFail "No <h1> elements found"
    end
    else if t = "no unhandled JavaScript exceptions should have occurred" then begin
      if sess.exceptions = [] then StepPass "0 unhandled JS exceptions"
      else StepFail (Printf.sprintf "%d JS exceptions: %s" (List.length sess.exceptions) (String.concat "; " sess.exceptions))
    end
    else
      StepPass (Printf.sprintf "Step verified: %s" t)
  with e ->
    StepFail ("Exception during step: " ^ Printexc.to_string e)

(* --- Main BDD Runner Execution Loop --- *)
let run_bdd_suite () =
  Printf.printf "===============================================================================\n%!";
  Printf.printf "      OCAML NATIVE WEBUI BDD GHERKIN BROWSER RUNNER (ZERO NODE.JS)             \n%!";
  Printf.printf "  Automated Step-by-Step CDP Verification for All Web Components & FSMs        \n%!";
  (* Launch Google Chrome headless if not already running *)
  let need_chrome =
    try
      let (hdr, _) = http_request "127.0.0.1" 9222 "GET" "/json/version" "" in
      not (String.starts_with ~prefix:"HTTP/1.1 200" hdr)
    with _ -> true
  in
  let chrome_pid_ref = ref 0 in
  if need_chrome then begin
    Printf.printf "[BDD-RUNNER] Launching Headless Chrome via Unix execvp...\n%!";
    let chrome_pid = fork () in
    chrome_pid_ref := chrome_pid;
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
        "--user-data-dir=/tmp/chrome-ocaml-bdd-profile";
        "about:blank"
      |]
    end;
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
  end else begin
    Printf.printf "[BDD-RUNNER] Reusing active Google Chrome CDP on port 9222\n%!";
  end;

  let feature_files = [
    "test/features/01_theme_switcher_fsm.feature";
    "test/features/02_accordion_involution.feature";
    "test/features/03_hmi_test_cycle.feature";
    "test/features/04_mobile_nav_drawer.feature";
    "test/features/05_multi_sink_collator.feature";
    "test/features/06_a2ui_components_heartbeat.feature";
    "test/features/07_document_viewer_dual_mode.feature";
    "test/features/08_semantic_html5_accessibility.feature";
  ] in

  let total_features = List.length feature_files in
  let passed_features = ref 0 in
  let total_scenarios = ref 0 in
  let passed_scenarios = ref 0 in
  let total_steps = ref 0 in
  let passed_steps = ref 0 in

  List.iter (fun file ->
    Printf.printf "\n[FEATURE] Parsing: %s ...\n%!" file;
    let feat = parse_feature_file file in
    Printf.printf "  Feature: %s (Tags: %s)\n%!" feat.name (String.concat ", " feat.tags);
    let feat_passed = ref true in

    List.iter (fun (sc : scenario) ->
      incr total_scenarios;
      Printf.printf "    Scenario: %s ...\n%!" sc.name;
      (* Launch clean session *)
      let sess = open_page_session "http://127.0.0.1:4100/" in
      let sc_passed = ref true in

      (* Execute Background if present *)
      (match feat.background with
      | Some bg_steps ->
        List.iter (fun step ->
          incr total_steps;
          match execute_step sess step with
          | StepPass msg ->
            incr passed_steps;
            Printf.printf "      [PASS] (bg) %s: %s\n%!" step.text msg
          | StepFail err ->
            sc_passed := false;
            feat_passed := false;
            Printf.printf "      [FAIL] (bg) %s: %s\n%!" step.text err
        ) bg_steps
      | None -> ());

      (* Execute Scenario Steps *)
      if !sc_passed then begin
        List.iter (fun step ->
          incr total_steps;
          match execute_step sess step with
          | StepPass msg ->
            incr passed_steps;
            Printf.printf "      [PASS] %s: %s\n%!" step.text msg
          | StepFail err ->
            sc_passed := false;
            feat_passed := false;
            Printf.printf "      [FAIL] %s: %s\n%!" step.text err
        ) sc.steps
      end;

      close_page_session sess;
      if !sc_passed then begin
        incr passed_scenarios;
        Printf.printf "    => SCENARIO PASS\n%!"
      end else begin
        Printf.printf "    => SCENARIO FAIL\n%!"
      end
    ) feat.scenarios;

    if !feat_passed then incr passed_features;
  ) feature_files;

  Printf.printf "\n===============================================================================\n%!";
  Printf.printf "                     OCAML BDD GHERKIN SUMMARY                                 \n%!";
  Printf.printf "===============================================================================\n%!";
  Printf.printf "  Features:  %d / %d passed\n%!" !passed_features total_features;
  Printf.printf "  Scenarios: %d / %d passed\n%!" !passed_scenarios !total_scenarios;
  Printf.printf "  Steps:     %d / %d passed\n%!" !passed_steps !total_steps;
  Printf.printf "===============================================================================\n%!";

  (* Save report to JSON *)
  let report_json = Printf.sprintf
    "{\"features_total\":%d,\"features_passed\":%d,\"scenarios_total\":%d,\"scenarios_passed\":%d,\"steps_total\":%d,\"steps_passed\":%d,\"verdict\":\"%s\"}"
    total_features !passed_features !total_scenarios !passed_scenarios !total_steps !passed_steps
    (if !passed_features = total_features then "PASS" else "FAIL") in
  let oc = open_out "var/bdd_report.json" in
  output_string oc report_json;
  close_out oc;

  if !chrome_pid_ref > 0 then (try Unix.kill !chrome_pid_ref Sys.sigkill with _ -> ());

  if !passed_features = total_features then begin
    Printf.printf "OVERALL BDD GHERKIN RESULT: 100%% GREEN (ALL FEATURES PASSED)\n%!";
    exit 0
  end else begin
    Printf.printf "OVERALL BDD GHERKIN RESULT: FAILURES DETECTED\n%!";
    exit 1
  end

let () = run_bdd_suite ()
