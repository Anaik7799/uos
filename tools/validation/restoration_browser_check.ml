(* Read-only typed browser evidence, invoked by the UOS Gleam development harness.
   Fixed public route allowlist; no authored page JavaScript or control requests.
   A scoped observation is not system admission. *)
let require b m=if not b then failwith m
let s x=`String x
let root="/home/an/NAS-setup/uos"
let routes=["/static/20261024-0712-recovery-dashboard.html";"/ecology-song";"/";"/planning";"/mirage";"/wiki";"/zk";"/homeostasis/evolution";"/homeostasis/components";"/homeostasis/terminal";"/static/20260930-0633-restoration-dashboard.html"]
let sha x=Cryptokit.hash_string(Cryptokit.Hash.sha256())x|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let save p bytes=
 let fd=Unix.openfile p [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 let ch=Unix.out_channel_of_descr fd in
 Fun.protect(fun()->output_string ch bytes;flush ch;Unix.fsync fd)~finally:(fun()->close_out_noerr ch)
let source_hash()=let ch=open_in_bin __FILE__ in
 Fun.protect(fun()->sha(really_input_string ch(in_channel_length ch)))~finally:(fun()->close_in_noerr ch)
let loc p selector=Playwright.Page.locator ~selector p
let text p selector=Playwright.Locator.inner_text ~timeout:3000.(loc p selector)|>String.trim

(* Policy is pure and independently falsifiable. Only exact public read dependencies. *)
let origin port = "http://nas-1.tail55d152.ts.net:" ^ string_of_int port
let read_paths = ["/static/20261024-0712-recovery-state.json";"/static/dashboard-grid.js";"/static/material.css";"/static/sw-register.js";"/favicon.ico";
 "/api/v1/dashboard";"/api/v1/sse/mesh";"/api/v1/homeostasis/stream";
 "/api/v1/ecology/snapshot";"/static/20260930-0633-restoration-state.json"]
let request_allowed ~port ~route ~url ~meth ~navigation ~redirected =
 let base=origin port in
 meth="GET" && not redirected &&
 if navigation then url=base^route
 else String.starts_with ~prefix:(base^"/") url &&
   let rest=String.sub url(String.length base)(String.length url-String.length base)in
   let path=List.hd(String.split_on_char '?' rest)in
   List.mem path read_paths && (route<>"/" || not(String.starts_with ~prefix:"/api/" path))
let page_identity ~status ~expected_url ~actual_url = status=200 && expected_url=actual_url
let requirements = [
 "01 Time and freshness";"02 Tailscale navigation";"03 Fractal tags";"04 Knowledge links";
 "05 Zero-Muda scope";"06 Native boundaries";"07 Storage interlock";
 "08 C1-C8 coverage";"09 Mathematical gates";"10 Test modalities";"11 Interface regression";
 "12 OTP runtime";"13 Hermes contracts";"14 ZigVM execution";"15 Inference isolation";
 "16 Telemetry correlation";"17 Independent verification";"18 Candidate identity"]
let requirements_match rows =
 List.sort String.compare rows = List.sort String.compare(List.map((^)"UNRUN: ")requirements)
let heading_for ~fixture = function
 | "/" -> "Indrajaal Swarm Dashboard"
 | "/mirage" -> "MirageOS Migration Projection Cockpit"
 | "/static/20261024-0712-recovery-dashboard.html" -> "Recovery & Operational Observation"
 | "/static/20260930-0633-restoration-dashboard.html" -> "Restoration & recovery"
 | "/wiki" | "/zk" -> "Unified Knowledge, Wiki & ZK Explorer"
 | "/planning" -> "C3I Planning Cockpit"
 | "/homeostasis/evolution" | "/homeostasis/components" | "/homeostasis/terminal" ->
   "Homeostasis evidence and model evolution"
 | "/ecology-song" when fixture -> "Ecology chart: development fixture"
 | _ -> failwith "route assertion profile unavailable; no generic PASS"
let selftest () =
 let base=origin 49157 in
 let allow ?(meth="GET") ?(navigation=false) ?(redirected=false) url =
 request_allowed ~port:49157 ~route:"/wiki" ~url ~meth ~navigation ~redirected in
 let checks=[
 "document",allow ~navigation:true (base^"/wiki");
 "asset",allow(base^"/static/material.css?v=22.10.5");
 "reviewed cockpit asset",allow(base^"/static/dashboard-grid.js?v=22.6.1");
 "legacy NIF counts refused",not(allow(base^"/api/v1/plan/status"));
 "recovery legacy dashboard refused",not(request_allowed ~port:49157 ~route:"/" ~url:(base^"/api/v1/dashboard") ~meth:"GET" ~navigation:false ~redirected:false);
 "unknown asset refused",not(allow(base^"/static/dashboard-grid.bundled.js"));
 "same-origin POST refused",not(allow ~meth:"POST"(base^"/api/v1/dashboard"));
 "control GET refused",not(allow(base^"/api/v1/emergency/trigger"));
 "external refused",not(allow"https://example.invalid/static/material.css");
 "socket refused",not(allow"ws://nas-1.tail55d152.ts.net:49157/ws/dashboard");
 "redirect refused",not(allow ~navigation:true ~redirected:true(base^"/wiki"));
 "wrong navigation refused",not(allow ~navigation:true(base^"/zk"));
 "prefix alias refused",not(allow(base^".invalid/static/material.css"));
 "status500 refused",not(page_identity ~status:500 ~expected_url:base ~actual_url:base);
 "wrong final URL refused",not(page_identity ~status:200 ~expected_url:base ~actual_url:(base^"/"));
 "18 exact",requirements_match(List.map((^)"UNRUN: ")requirements);
 "missing requirement refused",not(requirements_match[]);
 "duplicated requirement refused",not(requirements_match(List.init 18(fun _->"UNRUN: 01 Time and freshness")))]in
 List.iter(fun(name,ok)->require ok name;print_endline("PASS "^name))checks;
 Printf.printf "PASS %d policy falsifiers\n"(List.length checks)

(* The binding lacks primitive observed_initializer getters. Own its typed connection;
   decode its actual protocol records rather than cast opaque objects or inject JS. *)
let observed_initializer conn channel decode =
 let guid=Yojson.Safe.Util.(channel |> member "guid" |> to_string)in
 let obj=Hashtbl.find conn.Playwright.Connection.objects guid in
 Eio.Fiber.with_binding Playwright.Connection.current_connection_key conn(fun()->
 match decode obj.initializer_ with Ok v->v|Error e->failwith("observed_initializer: "^e))
let with_driver ~env ~sw f =
 let mgr=Eio.Stdenv.process_mgr env in
 let input_r,input_w=Eio.Process.pipe ~sw mgr in
 let output_r,output_w=Eio.Process.pipe ~sw mgr in
 let child=Playwright.Driver.run ~sw ~process_mgr:mgr ~stdin:input_r ~stdout:output_w()in
 Eio.Flow.close input_r;Eio.Flow.close output_w;
 let conn=Playwright.Connection.create output_r input_w in
 Eio.Fiber.fork ~sw(fun()->Playwright.Connection.run_loop conn);
 let root=Playwright__Api.Internal.create_root conn in
 let pw=Playwright.Root.initialize ~sdk_language:`Javascript root in
 Fun.protect(fun()->f conn pw)~finally:(fun()->
 Eio.Flow.close input_w;Eio.Flow.close output_r;ignore(Eio.Process.await child))


(* A Playwright route callback is not re-entered for every redirect.
   Chromium's response-stage interception pauses before following Location. *)
let refuse_redirects ~sw ~context ~page on_refusal =
 let cdp=Playwright.BrowserContext.new_cdp_session ~page context in
 Playwright.CDPSession.on_event cdp(fun event->
 if event.method_="Fetch.requestPaused"then
 Eio.Fiber.fork ~sw(fun()->
 let open Yojson.Safe.Util in
 let p=Option.get event.params in
 let id=p|>member"requestId"|>to_string in
 let status=match p|>member"responseStatusCode"with `Int x->x|_->0 in
 let redirect=(p|>member"redirectUrl")<>`Null || status>=300&&status<400 in
 let fields=["requestId",s id]in
 let fields=if redirect then(on_refusal();("errorReason",s"Aborted")::fields)else fields in
 ignore(Playwright.CDPSession.send ~method_:(if redirect then "Fetch.failRequest"else "Fetch.continueResponse") ~params:(`Assoc fields)cdp)));
 ignore(Playwright.CDPSession.send ~method_:"Fetch.enable"
 ~params:(`Assoc["patterns",`List[`Assoc["urlPattern",s"*";"requestStage",s"Response"]]])cdp)

(* Offline browser controls exercise the real request callback and status record.
   Markup/forms only: no authored JavaScript and no listener or network effects. *)
let browser_falsifiers chrome =
 Eio_main.run(fun env->Eio.Time.with_timeout_exn env#clock 25.(fun()->Eio.Switch.run(fun sw->
 with_driver ~env ~sw(fun conn pw->
 let browser=Playwright.BrowserType.launch ~executable_path:chrome ~headless:true ~timeout:8000.
 ~args:[|"--disable-background-networking";"--no-proxy-server"|](Playwright.Playwright.chromium pw)in
 Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
 let test mode meth target =
 let context=Playwright.Browser.new_context ~offline:true ~service_workers:`Block ~accept_downloads:`Deny browser in
 Fun.protect ~finally:(fun()->Playwright.BrowserContext.close context)(fun()->
 let denied=ref[] in
 let url=origin 49157^"/wiki"in
 Playwright.BrowserContext.on_route context(fun e->Eio.Fiber.fork ~sw(fun()->
 let r=Playwright.Route.request e.route in
 let i=observed_initializer conn(Playwright.Request.to_yojson r)Playwright.Request.Initializer.of_yojson in
 if request_allowed ~port:49157 ~route:"/wiki" ~url:i.url ~meth:i.method_
 ~navigation:i.is_navigation_request ~redirected:(Option.is_some i.redirected_from)
 then if mode="redirect"then Playwright.Route.fulfill ~status:302
 ~headers:[|Playwright.NameValue.{name="location";value=origin 49157^"/zk"}|]e.route
 else Playwright.Route.fulfill ~status:(if mode="status500"then 500 else 200)
 ~headers:[|Playwright.NameValue.{name="content-type";value="text/html; charset=utf-8"}|]
 ~body:("<html><body><h1>Wrong page</h1><form method='"^meth^"' action='"^target^"'><button type='submit'>Send</button></form><details><summary>Navigation only</summary>Not a checklist</details></body></html>")e.route
 else(denied:=(i.method_,i.url)::!denied;Playwright.Route.abort e.route)));
 let patterns=[|Playwright.BrowserContext.Patterns.{glob=Some"**/*";regex_source=None;regex_flags=None;url_pattern=None}|]in
 Playwright.BrowserContext.set_network_interception_patterns ~patterns context;
 let page=Playwright.BrowserContext.new_page context in
 refuse_redirects ~sw ~context ~page(fun()->denied:=("REDIRECT","refused before follow")::!denied);
 let response=try Playwright.Page.goto ~url ~timeout:4000. page with _->None in
 if mode="status500"then begin
 let response=Option.get response in
 let i=observed_initializer conn(Playwright.Response.to_yojson response)Playwright.Response.Initializer.of_yojson in
 require(not(page_identity ~status:i.status ~expected_url:url ~actual_url:i.url))"actual500 falsely accepted"
 end else if mode="wrongpage"then begin
 let wanted=heading_for ~fixture:false "/wiki"in
 require(not(List.exists(fun h->String.ends_with ~suffix:wanted h)(Playwright.Locator.all_inner_texts(loc page "h1:visible"))))"wrong page falsely accepted";
 require(Playwright.Locator.count(loc page ".uos-verification-checklist")=0)"navigation confused with checklist"
 end else begin
 if mode<>"redirect"then (try Playwright.Locator.click ~timeout:3000.(loc page "button")with _->());
 require(!denied<>[])("request not refused: "^mode)
 end;
 print_endline("PASS actual offline browser "^mode))in
 test "POST" "POST" "/api/v1/emergency/trigger";
 test "forbiddenGET" "GET" "/api/v1/emergency/trigger";
 test "externalGET" "GET" "http://example.invalid/control";
 test "redirect" "GET" "/";
 test "status500" "GET" "/";
 test "wrongpage" "GET" "/";
 print_endline"PASS 6 actual offline browser falsifiers"
 )))))

let ()=
 if Array.length Sys.argv=2 && Sys.argv.(1)="--selftest" then (selftest();exit 0);
 if Array.length Sys.argv=3 && Sys.argv.(1)="--browser-selftest" then (browser_falsifiers Sys.argv.(2);exit 0);
 require(Array.length Sys.argv=5||Array.length Sys.argv=6)"usage: restoration-browser-check ROUTE WIDTH NEW_ABSOLUTE_OUTPUT CHROME [PRIVATE_PORT]";
 let port=if Array.length Sys.argv=6 then int_of_string Sys.argv.(5) else 4100 in
 require(port=4100||port>=49152&&port<=65535)"invalid listener port";
 let address=if port=4100 then "100.87.7.78" else "127.0.0.1" in
 let route=Sys.argv.(1)and width=int_of_string Sys.argv.(2)and out=Sys.argv.(3)and chrome=Sys.argv.(4)in
 require(List.mem route routes)"route is not allowlisted";
 require(width=390||width=1280)"viewport is not allowlisted";
 require(not(Filename.is_relative out)&&not(Sys.file_exists out))"new absolute output required";
 List.iter(fun p->require((Unix.lstat p).st_kind=Unix.S_REG)("preinstalled regular file required: "^p))
 [chrome;Sys.getenv"HOME"^"/.cache/playwright-ocaml-driver/1.59.0/node";Sys.getenv"HOME"^"/.cache/playwright-ocaml-driver/1.59.0/package/cli.js"];
 Unix.mkdir out 0o700;
 let source=source_hash()in
 let url="http://nas-1.tail55d152.ts.net:"^string_of_int port^route in
 let findings=ref[]and observations=ref[]and pictures=ref[]in
 let check label pass=observations:=(label,`Bool pass)::!observations;if not pass then findings:=label::!findings in
 let mono()=Mtime.Span.to_float_ns(Mtime_clock.elapsed())/.1e9 in
 let started=mono()in
 (try Eio_main.run(fun env->Eio.Time.with_timeout_exn env#clock 25.(fun()->Eio.Switch.run(fun sw->
 with_driver ~env ~sw(fun conn pw->
 let browser=Playwright.BrowserType.launch ~executable_path:chrome ~headless:true ~timeout:8000.
 ~args:[|"--host-resolver-rules=MAP nas-1.tail55d152.ts.net "^address;"--no-proxy-server";"--disable-background-networking"|]
 (Playwright.Playwright.chromium pw)in
 Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
 let context=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width;height=900}~reduced_motion:`Reduce ~service_workers:`Block ~accept_downloads:`Deny browser in
 Fun.protect ~finally:(fun()->Playwright.BrowserContext.close context)(fun()->
 let blocked=ref 0 and sockets=ref 0 and denied=ref[] in
 let patterns=[|Playwright.BrowserContext.Patterns.{glob=Some"**/*";regex_source=None;regex_flags=None;url_pattern=None}|]in
 Playwright.BrowserContext.on_route context(fun event->
 Eio.Fiber.fork ~sw(fun()->
 let req=Playwright.Route.request event.route in
 let info=observed_initializer conn(Playwright.Request.to_yojson req)Playwright.Request.Initializer.of_yojson in
 if request_allowed ~port ~route ~url:info.url ~meth:info.method_
 ~navigation:info.is_navigation_request ~redirected:(Option.is_some info.redirected_from)
 then Playwright.Route.continue ~is_fallback:false event.route
 else(begin incr blocked;denied:=(info.method_^" "^info.url)::!denied;Playwright.Route.abort event.route end)));
 Playwright.BrowserContext.set_network_interception_patterns ~patterns context;
 Playwright.BrowserContext.on_web_socket_route context(fun event->
 incr sockets;Eio.Fiber.fork ~sw(fun()->
 Playwright.WebSocketRoute.close_page ~code:1008 ~reason:"Read-only probe refuses sockets" ~was_clean:true event.web_socket_route));
 Playwright.BrowserContext.set_web_socket_interception_patterns ~patterns context;
 let page=Playwright.BrowserContext.new_page context in
 refuse_redirects ~sw ~context ~page(fun()->incr blocked;denied:="REDIRECT refused before follow"::!denied);
 let final_url=ref "" in
 Playwright.Frame.on_navigated(Playwright.Page.main_frame page)(fun e->final_url:=e.url);
 let resp=Playwright.Page.goto ~url ~timeout:8000. page in
 let status,response_url=match resp with None->0,""|Some r->
 let info=observed_initializer conn(Playwright.Response.to_yojson r)Playwright.Response.Initializer.of_yojson in info.status,info.url in
 check "HTTP200_exact_response_URL"(page_identity ~status ~expected_url:url ~actual_url:response_url);
 observations:=("http_status",`Int status)::("response_url",s response_url)::!observations;
 Eio.Time.sleep env#clock 0.5;
 if route="/static/20261024-0712-recovery-dashboard.html" then begin
 let top=Playwright.Page.screenshot ~type_:`Png ~full_page:false ~timeout:5000. page in
 save(out^"/20261024-0752-top.png")top
 end;
 let body=text page "body"in
 check "body_has_content"(String.length body>100);
 check "no_route_fallback"(not(List.exists(fun line->String.starts_with ~prefix:"No route matched:"(String.trim line))(String.split_on_char '\n' body)));
 check "exact_final_URL"(!final_url=url);
 let fixture=port<>4100 && route="/ecology-song"in
 let wanted=heading_for ~fixture route in
 let headings=Playwright.Locator.all_inner_texts(loc page "h1:visible,h2:visible")in
 check "visible_route_heading"(List.exists(fun h->String.ends_with ~suffix:wanted(String.trim h))headings);
 if String.starts_with ~prefix:"/homeostasis/"route then begin
  check "visible_homeostasis_root"(Playwright.Locator.is_visible(loc page ".homeostasis-evolution-hud"));
  if route="/homeostasis/terminal"then check "visible_terminal_projection"(Playwright.Locator.is_visible(loc page "#homeostasis-terminal"))
 end;
 check "links_present"(Playwright.Locator.count(loc page "a[href]")>0);
 if fixture then begin
  let summary=loc page "details > summary:has-text('Fixture evidence')"in
  check "one_fixture_disclosure"(Playwright.Locator.count summary=1);
  Playwright.Locator.press ~key:"Enter"~timeout:3000. summary;
  check "fixture_explicitly_simulated"(String.trim(text page "details")="Fixture evidence\nSimulated chart; no runtime admission.");
  check "fixture_26_bars"(Playwright.Locator.count(loc page "svg rect")=26);
  observations:=("checklist_profile",s"NOT_APPLICABLE_PRIVATE_CHART_FIXTURE")::!observations
 end else if route="/mirage" then begin
  let parent=".uos-mirage-cockpit > details:has(> summary:has-text('Comprehensive verification requirements'))" in
  check "one_mirage_requirements"(Playwright.Locator.count(loc page parent)=1);
  Playwright.Locator.press ~key:"Enter" ~timeout:3000.(loc page(parent^" > summary"));
  let domains=loc page(parent^" > .verification-domain > summary") in
  check "mirage_five_requirement_domains"(Playwright.Locator.count domains=5);
  for i=0 to Playwright.Locator.count domains-1 do Playwright.Locator.press ~key:"Enter" ~timeout:3000.(Playwright.Locator.nth i domains) done;
  let actual=Playwright.Locator.all_inner_texts(loc page(parent^" li:visible"))|>List.map String.trim in
  let expected=List.map((^)"UNVERIFIED ")["CHK-01-TIME";"CHK-02-TAIL";"CHK-03-FRACT";"CHK-04-KM";"CHK-05-MUDA";"CHK-06-GRAPH";"CHK-07-DRIVE";"CHK-08-C1C8";"CHK-09-MATH";"CHK-10-9MOD";"CHK-11-REGR";"CHK-12-GLEAM";"CHK-13-HERMES";"CHK-14-ZIGVM";"CHK-15-MAX";"CHK-16-OTEL";"CHK-17-SOV";"CHK-18-JJ"] in
  check "mirage_18_exact_unverified"(List.sort String.compare actual=List.sort String.compare expected);
  check "mirage_no_blanket_green"(text page(parent^" > p")="No all-green claim is made by this projection surface.");
  let provenance=loc page(parent^" > .verification-provenance > summary") in
  check "mirage_provenance_extension"(Playwright.Locator.count provenance=1);
  Playwright.Locator.press ~key:"Enter" ~timeout:3000. provenance;
  check "mirage_provenance_text"(text page(parent^" > .verification-provenance > p")="EV ceiling93; EV94..109 NOT_ADMITTED. No new EV identifier.");
  observations:=("checklist_profile",s"MIRAGE_UNVERIFIED_REQUIREMENTS_WITH_PROVENANCE")::!observations
 end else if route="/static/20261024-0712-recovery-dashboard.html" then begin
  check "recovery_observation_loaded" (not(String.starts_with ~prefix:"UNAVAILABLE"(text page "#freshness")));
  check "recovery_not_stale" (not(List.mem (text page "#freshness")["STALE";"CLOCK_SKEW";"EXPIRED"]));
  let domains=loc page "#checklist details.chk-domain" in
  check "recovery_five_domains" (Playwright.Locator.count domains=5);
  for i=0 to Playwright.Locator.count domains-1 do
    let d=Playwright.Locator.nth i domains in
    let summary=Playwright.Locator.nth i(loc page "#checklist details.chk-domain > summary") in
    let before=Playwright.Locator.get_attribute ~name:"open" d in
    Playwright.Locator.press ~key:"Enter" ~timeout:3000. summary;
    let after=Playwright.Locator.get_attribute ~name:"open" d in
    check ("recovery_domain_keyboard_"^string_of_int i) (before<>after);
    if after=None then Playwright.Locator.press ~key:"Enter" ~timeout:3000. summary
  done;
  let rows=Playwright.Locator.all_inner_texts(loc page "#checklist li[data-chk]:visible") in
  let has n=List.length(List.filter(fun row->String.starts_with ~prefix:(Printf.sprintf "CHK-%02d " n)(String.trim row))rows)=1 in
  check "recovery_18_unique_visible" (List.length rows=18 && List.for_all has(List.init 18(fun i->i+1)));
  let provenance=text page "#provenance-note" in
  check "recovery_provenance" (String.starts_with ~prefix:"Provenance note: EV ceiling remains 93." provenance);
  check "recovery_actual_tasks" (Playwright.Locator.count(loc page "#task-rows tr")>=100);
  check "recovery_actual_jobs" (Playwright.Locator.count(loc page "#job-rows tr")>0);
  let raw=loc page "#raw-details" in
  check "raw_initially_closed" (Playwright.Locator.get_attribute ~name:"open" raw=None);
  Playwright.Locator.press ~key:"Enter" ~timeout:3000.(loc page "#toggle-source");
  check "raw_keyboard_open" (Playwright.Locator.get_attribute ~name:"open" raw<>None);
  let payload=Yojson.Safe.from_string(text page "#source") in
  check "raw_actual_schema" (Yojson.Safe.Util.(payload |> member "schema" |> to_string)="uos.restoration.snapshot.v1");
  let count=Yojson.Safe.Util.(payload |> member "tasks" |> to_list |> List.length) in
  check "exact_task_row_count" (Playwright.Locator.count(loc page "#task-rows tr")=count);
  check "goal_remains_incomplete" (Yojson.Safe.Util.(payload |> member "goal_met" |> to_bool)=false);
  Playwright.Locator.press ~key:"Enter" ~timeout:3000.(loc page "#toggle-source");
  check "raw_keyboard_closed" (Playwright.Locator.get_attribute ~name:"open" raw=None);
  observations:=("checklist_profile",s"RECOVERY_FRESH_OBSERVATIONS_NOT_GLOBAL_ADMISSION")::!observations
 end else if route="/static/20260930-0633-restoration-dashboard.html" then begin
  let summary=loc page "#checklist > details:first-of-type > summary" in
  check "one_restoration_checklist"(Playwright.Locator.count summary=1);
  Playwright.Locator.press ~key:"Enter" ~timeout:3000. summary;
  let rows=Playwright.Locator.all_inner_texts(loc page "#checks > li:visible") in
  let has n=List.length(List.filter(fun row->String.starts_with ~prefix:(Printf.sprintf "CHK-%02d " n)(String.trim row))rows)=1 in
  check "restoration_18_unique_requirements"(List.for_all has(List.init 18(fun i->i+1)) && List.length rows=19);
  check "restoration_provenance"(List.exists(fun line->String.starts_with ~prefix:"EV ceiling remains93."(String.trim line))(String.split_on_char '\n' body));
  observations:=("checklist_profile",s"RECORDED_RECOVERY_SNAPSHOT_NOT_GLOBAL_ADMISSION")::!observations
 end else begin
  let selector=".uos-verification-checklist"in
  check "one_canonical_checklist"(Playwright.Locator.count(loc page selector)=1);
  let first=loc page selector in
  let summary=loc page(selector^" > summary")in
  check "visible_checklist_summary"(Playwright.Locator.is_visible summary);
  let before=Playwright.Locator.get_attribute ~name:"open"first in
  Playwright.Locator.press ~key:"Enter"~timeout:3000. summary;
  let after=Playwright.Locator.get_attribute ~name:"open"first in
  check "canonical_checklist_keyboard_toggle"(before<>after && after<>None);
  let domains=loc page(selector^" > details > summary")in
  check "five_domains_plus_provenance"(Playwright.Locator.count domains=6);
  for i=0 to Playwright.Locator.count domains-1 do Playwright.Locator.press ~key:"Enter"~timeout:3000.(Playwright.Locator.nth i domains)done;
  let rows=Playwright.Locator.all_inner_texts(loc page(selector^" li:visible"))|>List.map String.trim in
  check "18_exact_visible_UNRUN_requirements"(requirements_match rows);
  let scope=text page selector in
  check "provenance_visible"(String.split_on_char '\n' scope|>List.exists(fun l->String.starts_with ~prefix:"EV ceiling93; EV94..109 NOT_ADMITTED."(String.trim l)));
  check "no_receipts_honest"(String.split_on_char '\n' scope|>List.exists(fun l->String.trim l="No candidate-bound receipts are attached to this view. UNRUN is not PASS."))
 end;
 if route="/"then begin
  check "one_recovery_root"(Playwright.Locator.count(loc page "#uos-recovery-cockpit")=1);
  check "cockpit_observation_scope"(text page "#dash-snapshot-scope"="Observed snapshot only. Live agent health, inference, transport and global admission are UNVERIFIED.");
  check "cockpit_snapshot_received"(Playwright.Locator.count(loc page "#dash-observed-tasks")=1);
  check "cockpit_observation_time"(String.contains(text page "#dash-task-summary")'T');
  check "no_simulated_timeline"(Playwright.Locator.count(loc page "input[type=range]")=0);
  check "no_unobserved_health_dot"(Playwright.Locator.count(loc page "#c3i-health-dot,#c3i-activity")=0);
  Playwright.Locator.press ~key:"Alt+Shift+P" ~timeout:3000.(loc page "body");
  check "no_synthetic_proof_overlay"(Playwright.Locator.count(loc page ".merkle-overlay")=0);
  check "no_synthetic_proof_help"(Playwright.Locator.count(loc page "#c3i-help")=0);
  Eio.Time.sleep env#clock 10.1;
  observations:=("legacy_poll_observation_seconds",`Float 10.1)::!observations;
  let original_rows=Playwright.Locator.count(loc page "#dash-observed-tasks tr")in
  Playwright.Locator.fill ~value:"__no_matching_recovery_task__" ~timeout:3000.(loc page "#dash-search-input");
  check "local_filter_empty"(Playwright.Locator.count(loc page "#dash-observed-tasks tr")=1);
  Playwright.Locator.fill ~value:"" ~timeout:3000.(loc page "#dash-search-input");
  check "local_filter_restore"(Playwright.Locator.count(loc page "#dash-observed-tasks tr")=original_rows);
  Playwright.Locator.click ~timeout:3000.(loc page "#dash-view-toggle [data-view=analytics]");
  check "local_evidence_view"(String.starts_with ~prefix:"Observed snapshot only."(text page "#dash-dynamic-content") && Playwright.Locator.count(loc page "#dash-observed-tasks")=0);
  check "evidence_truthful_scope"(List.exists(fun line->String.trim line="Task completion counts are not test coverage, system health or admission.")(String.split_on_char '\n'(text page "#dash-dynamic-content")));
  Playwright.Locator.click ~timeout:3000.(loc page "#dash-view-toggle [data-view=grid]");
  check "local_tasks_restored"(Playwright.Locator.count(loc page "#dash-observed-tasks tr")=original_rows);
  check "simulation_control_disabled"(Playwright.Locator.get_attribute ~name:"disabled"(loc page ".test-btn")<>None && Playwright.Locator.get_attribute ~name:"onclick"(loc page ".test-btn")=None && text page ".test-btn"="DEMO DISABLED")
 end;
 if route="/mirage"then check "mirage_projection_scope"(Playwright.Locator.is_visible(loc page ".uos-mirage-cockpit"));
 if route="/static/20260930-0633-restoration-dashboard.html"then begin
  check "dashboard_loaded"(text page "#overall"<>"Loading observed state"&&text page "#overall"<>"SNAPSHOT UNAVAILABLE");
  check "dashboard_task_rows"(Playwright.Locator.count(loc page "#task-rows > tr")>=17);
  check "dashboard_18_checks"(Playwright.Locator.count(loc page "#checks > li")>=18)
 end;
 if route="/" || route="/mirage" || route="/static/20261024-0712-recovery-dashboard.html" then begin
  let selector=if route="/"then "#uos-recovery-cockpit"else if route="/mirage"then ".uos-mirage-cockpit"else "main"in
  let fits selector=match Playwright.Locator.bounding_box(Playwright.Locator.nth 0(loc page selector))with
   |None->false|Some rect->let j=Playwright.Rect.to_yojson rect in
    let number key=match Yojson.Safe.Util.member key j with `Float x->x|`Int x->float_of_int x|_->nan in
    number "x">= -.1. && number "x"+.number "width"<=float_of_int width+.1. in
  check "profile_container_within_viewport"(fits selector);
  if route="/static/20261024-0712-recovery-dashboard.html" then begin check "recovery_URL_within_viewport"(fits "#self");check "recovery_scroll_container_within_viewport"(fits ".scroll")end;
  if route="/mirage"then check "mirage_table_within_viewport"(fits ".uos-mirage-cockpit table")
 end;
 let box=Playwright.Locator.bounding_box(loc page "body")in
 (match box with None->check "body_geometry"false|Some r->
  observations:=("body_geometry",Playwright.Rect.to_yojson r)::!observations);
 Playwright.Locator.scroll_into_view_if_needed ~timeout:3000.(loc page "h1");
 Eio.Time.sleep env#clock 0.3;
 let view=Playwright.Page.screenshot ~type_:`Png ~full_page:false ~timeout:5000. page in
 require(String.length view<=8388608)"viewport screenshot too large";
 save(out^"/20261001-1048-viewport.png")view;
 let png=Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:5000. page in
 require(String.length png>=24&&String.length png<=8388608&&String.starts_with ~prefix:"\137PNG\r\n\026\n"png)"invalid screenshot";
 let png_width=List.fold_left(fun n i->(n lsl 8) lor Char.code png.[i])0[16;17;18;19]in
 observations:=("full_page_png_width",`Int png_width)::!observations;
 check "full_page_width_matches_viewport"(png_width=width);
 save(out^"/20261001-1048-page.png")png;
 pictures:=[`Assoc["path",s(out^"/20261001-1048-page.png");"sha256",s(sha png)]];
 let errors=Playwright.Page.page_errors page|>Array.to_list in
 check "no_page_errors"(errors=[]);
 observations:=("page_errors",`List(List.map Playwright.SerializedError.to_yojson errors))::!observations;
 observations:=("headings",`List(List.map s(Playwright.Locator.all_inner_texts(loc page "h1,h2"))))::!observations;
 check "no_forbidden_requests"(!blocked=0);
 check "no_socket_attempts"(!sockets=0);
 observations:=("blocked_requests",`List(List.map s(List.rev !denied)))::("blocked_request_count",`Int !blocked)::("socket_attempts",`Int !sockets)::!observations
 ))))))with e->findings:=("browser_exception:"^Printexc.to_string e)::!findings);
 check "controller_source_unchanged"(source_hash()=source);
 let doc=`Assoc["schema",s"uos.restoration-browser-observation.v1";"observed_utc_seconds",`Float(Unix.gettimeofday());"status",s(if !findings=[]then"PASS"else"HOLD");
 "url",s url;"viewport_width",`Int width;"source_sha256",s source;"elapsed_seconds",`Float(mono()-.started);"application_admitted",`Bool false;
 "observations",`Assoc(List.rev !observations);"screenshots",`List !pictures;"findings",`List(List.map s(List.rev !findings));
 "limits",s"One route and viewport. Read-only navigation and local accordion keyboard interaction; no control activation, accessibility certification or global admission. Visual review is separate."]in
 save(out^"/20261001-1048-receipt.json")(Yojson.Safe.pretty_to_string doc);print_endline(Yojson.Safe.to_string doc);
 if !findings<>[]then exit 1
