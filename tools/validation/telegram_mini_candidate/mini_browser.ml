let require b m=if not b then failwith m
let s x=`String x
let root="/home/an/NAS-setup/uos"
let routes=["/ecology-song";"/";"/planning";"/mirage";"/wiki";"/zk";"/homeostasis/evolution";"/homeostasis/components";"/homeostasis/terminal";"/static/20260930-0633-restoration-dashboard.html"]
let sha x=Cryptokit.hash_string(Cryptokit.Hash.sha256())x|>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let save p bytes=
 let fd=Unix.openfile p [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
 let ch=Unix.out_channel_of_descr fd in
 Fun.protect(fun()->output_string ch bytes;flush ch;Unix.fsync fd)~finally:(fun()->close_out_noerr ch)
let source_hash()=let ch=open_in_bin(root^"/tools/validation/restoration_browser_check.ml")in
 Fun.protect(fun()->sha(really_input_string ch(in_channel_length ch)))~finally:(fun()->close_in_noerr ch)
let loc p selector=Playwright.Page.locator ~selector p
let text p selector=Playwright.Locator.inner_text ~timeout:3000.(loc p selector)|>String.trim

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
let base_control_action="http://nas-1.tail55d152.ts.net:49134/mini-app/api/action"
let refuse_redirects ?(drop_action_response=(fun()->false)) ~sw ~context ~page on_refusal =
 let cdp=Playwright.BrowserContext.new_cdp_session ~page context in
 Playwright.CDPSession.on_event cdp(fun event->
 if event.method_="Fetch.requestPaused"then
 Eio.Fiber.fork ~sw(fun()->
 let open Yojson.Safe.Util in
 let p=Option.get event.params in
 let id=p|>member"requestId"|>to_string in
 let status=match p|>member"responseStatusCode"with `Int x->x|_->0 in
 let redirect=(p|>member"redirectUrl")<>`Null || status>=300&&status<400 in
 let drop_action=drop_action_response() && (try p|>member"request"|>member"url"|>to_string=base_control_action with _->false)in
 let fields=["requestId",s id]in
 let fields=if redirect || drop_action then(if redirect then on_refusal();("errorReason",s"Aborted")::fields)else fields in
 ignore(Playwright.CDPSession.send ~method_:(if redirect || drop_action then "Fetch.failRequest"else "Fetch.continueResponse") ~params:(`Assoc fields)cdp)));
 ignore(Playwright.CDPSession.send ~method_:"Fetch.enable"
 ~params:(`Assoc["patterns",`List[`Assoc["urlPattern",s"*";"requestStage",s"Response"]]])cdp)



let contains text needle =
 let rec loop i = if i + String.length needle > String.length text then false
 else if String.sub text i (String.length needle) = needle then true else loop (i+1) in loop 0

let png_width bytes =
 require(String.length bytes >= 24 && String.sub bytes 0 8 = "\137PNG\r\n\026\n")"PNG header";
 let byte i=Char.code bytes.[i] in
 (byte 16 lsl 24) lor (byte 17 lsl 16) lor (byte 18 lsl 8) lor byte 19

let base="http://nas-1.tail55d152.ts.net:49134"
let () =
 require(Array.length Sys.argv=3 || Array.length Sys.argv=4)"usage: mini_browser OUT SIGNED_FIXTURE_JSON [--unavailable]";
 let config_failure=Array.length Sys.argv=4 && Sys.argv.(3)="--config-unavailable" in
 let config_mode=Array.length Sys.argv=4 && (Sys.argv.(3)="--config" || config_failure) in
 let health_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--health" in
 let chat_recovery=Array.length Sys.argv=4 && Sys.argv.(3)="--chat-recovery" in
 let chat_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--chat" in
 let memory_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--memory" in
 let control_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--control" in
 let telemetry_failure=Array.length Sys.argv=4 && Sys.argv.(3)="--telemetry-unavailable" in
 let zenoh_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--zenoh" in
 let failure_mode=config_failure || Array.length Sys.argv=4 && Sys.argv.(3)="--unavailable" in
 let history_long=Array.length Sys.argv=4 && Sys.argv.(3)="--history-long" in
 require(Array.length Sys.argv=3 || config_mode || failure_mode || history_long || zenoh_mode || telemetry_failure || control_mode || memory_mode || chat_mode || chat_recovery || health_mode)"unknown scenario";
 let out=Sys.argv.(1)in require(not(Sys.file_exists out))"new output required";Unix.mkdir out 0o700;
 let init_data=Yojson.Safe.Util.(Yojson.Safe.from_file Sys.argv.(2)|>member"init_data"|>to_string)in
 let pending_script=if chat_recovery then "sessionStorage.setItem(\"uos-mini-chat-request-v1\","^Yojson.Safe.to_string(`String(Yojson.Safe.to_string(Yojson.Safe.Util.(Yojson.Safe.from_file Sys.argv.(2)|>member"pending"))))^");" else "" in
 let sdk_for denied="window.Telegram={WebApp:{initData:"^Yojson.Safe.to_string(`String (if denied then init_data^"0" else init_data))^",ready:function(){},expand:function(){}}};"^pending_script in
 let rows=ref[]in
 Eio_main.run(fun env->Eio.Time.with_timeout_exn env#clock 100.(fun()->Eio.Switch.run(fun sw->
 with_driver ~env ~sw(fun conn pw->
 let browser=Playwright.BrowserType.launch ~executable_path:"/opt/google/chrome/chrome" ~headless:true ~timeout:8000.
 ~args:[|"--no-proxy-server";"--disable-background-networking";"--host-resolver-rules=MAP nas-1.tail55d152.ts.net 100.87.7.78"|](Playwright.Playwright.chromium pw)in
 Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
 List.iter(fun(mode,width,height,page_path)->
 let context=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width;height}
 ~service_workers:`Block ~accept_downloads:`Deny browser in
 Fun.protect ~finally:(fun()->Playwright.BrowserContext.close context)(fun()->
 let denied=ref[]and posts=ref 0 and fail_posts=ref false and control_posts=ref 0 and abort_control=ref false and drop_response=ref false in
 let patterns=[|Playwright.BrowserContext.Patterns.{glob=Some"**/*";regex_source=None;regex_flags=None;url_pattern=None}|]in
 Playwright.BrowserContext.on_route context(fun event->Eio.Fiber.fork ~sw(fun()->
 let i=observed_initializer conn(Playwright.Request.to_yojson(Playwright.Route.request event.route))Playwright.Request.Initializer.of_yojson in
 if i.url="https://telegram.org/js/telegram-web-app.js" && mode<>"sdk-blocked"then
 Playwright.Route.fulfill ~status:200 ~headers:[|Playwright.NameValue.{name="content-type";value="text/javascript"}|] ~body:(sdk_for(mode="identity-denied")) event.route
 else if Option.is_none i.redirected_from &&
 ((i.method_="GET"&&(i.url=base^page_path||i.url=base^"/mini-app/client.js"))||
 (i.method_="POST"&&(i.url=base^"/mini-app/api/data" || (control_mode || memory_mode || chat_mode || chat_recovery) && (i.url=base^"/mini-app/api/action" || i.url=base^"/mini-app/api/action-receipt"))))
 then(if i.url=base^"/mini-app/api/action" then incr control_posts;if i.method_="POST"then incr posts;if (!abort_control && i.url=base^"/mini-app/api/action") || !fail_posts && i.method_="POST" then Playwright.Route.abort event.route else Playwright.Route.continue ~is_fallback:false event.route)
 else(denied:=(i.method_^" "^i.url)::!denied;Playwright.Route.abort event.route)));
 Playwright.BrowserContext.set_network_interception_patterns ~patterns context;
 Playwright.BrowserContext.on_web_socket_route context(fun event->Eio.Fiber.fork ~sw(fun()->Playwright.WebSocketRoute.close_page ~code:1008 ~reason:"private fixture disallows sockets" ~was_clean:true event.web_socket_route));
 Playwright.BrowserContext.set_web_socket_interception_patterns ~patterns context;
 if zenoh_mode then Playwright.BrowserContext.clock_install context;
 if memory_mode || chat_recovery then (Playwright.BrowserContext.on_dialog context(fun event->Eio.Fiber.fork ~sw(fun()->Playwright.Dialog.accept event.dialog)));
 let page=Playwright.BrowserContext.new_page context in
 if memory_mode || chat_recovery then Playwright.Page.update_subscription ~event:`Dialog ~enabled:true page;
 refuse_redirects ~drop_action_response:(fun()-> !drop_response) ~sw ~context ~page(fun()->denied:="redirect"::!denied);
 let response=Playwright.Page.goto ~url:(base^page_path) ~timeout:7000. page in
 let status=match response with None->0|Some r->(observed_initializer conn(Playwright.Response.to_yojson r)Playwright.Response.Initializer.of_yojson).status in
 require(status=200)"HTTP status";
 require(Playwright.Locator.count(loc page "input[type=checkbox]")=18)"18 checkpoints";
 let before=text page "#mini-status"in
 Playwright.Locator.press ~key:"Enter" ~timeout:2000.(loc page "#mini-refresh");
 let rec wait n=let value=text page "#mini-status"in
 if value=before||String.starts_with ~prefix:"Loading"value then(if n=0 then failwith"UI request timeout"else(Eio.Time.sleep env#clock 0.05;wait(n-1)))else value in
 let final=wait 100 in
 save(out^"/"^mode^"-preassert.json")(Yojson.Safe.pretty_to_string(`Assoc["status",s final;"fields",s(text page "#mini-fields");"posts",`Int !posts]));
 if mode="sdk-blocked"then(require(!posts=0)"SDK-less request made network call";require(String.starts_with ~prefix:"Telegram authentication is unavailable"final)"SDK-less status")
 else if mode="identity-denied"then(require(!posts=1)"one refused POST";require(String.starts_with ~prefix:"Authentication expired or access is not allowed."final)"denial state absent";require(text page "#mini-fields"="")"denied data exposed")
 else if telemetry_failure then(require(!posts=1)"one telemetry outage POST";require(final="The data service is unavailable or not configured.")"telemetry outage status absent";require(text page "#mini-fields"="")"telemetry outage fields exposed")
 else if failure_mode then(require(!posts=1)"one failed-backend POST";require(final="The data source is unavailable or not configured.")"backend failure state absent";require(text page "#mini-fields"="")"failed backend data exposed")
 else(require(!posts=1)"exactly one authenticated POST";require(String.starts_with ~prefix:"Observed at "final)"authenticated observation";let fields=text page "#mini-fields" in
 if page_path="/mini-app/tasks" then (require(contains fields "Task FENCE")"task fields absent";require(contains fields "executing (lease expired)")"expired lease hidden")
 else (require(contains fields "NOT_GRANTED")"admission disclaimer absent";
 if page_path="/mini-app/config" then(require(contains fields "Declared configuration only")"config scope absent";require(contains fields "Not confirmed")"config deployment disclaimer absent";require(contains fields "Configuration source")"config provenance absent";require(contains fields "Container group")"config detail absent";require(not(contains fields "PRIVATE_IMAGE_MARKER" || contains fields "PRIVATE_PATH_MARKER"))"private config field leak")
 else if page_path="/mini-app/telemetry" then(require(contains fields "No fleet")"telemetry scope absent";require(contains fields "Collector epoch")"epoch absent";require(contains fields "Not implemented")"pending controls absent";require(contains fields "VM total memory MiB")"VM units absent")
 else if page_path="/mini-app/dashboard" then(require(contains fields "UNKNOWN")"global health falsely asserted";require(contains fields "Scope")"dashboard scope absent")
 else if page_path="/mini-app/zenoh" then(require(contains fields "Topic count")"topic list absent";require(not(contains fields "other-user"))"other-user topic leak")
 else if page_path="/mini-app/fmea" then(require(String.starts_with ~prefix:"Assessments" fields)"FMEA metadata must precede details";require(contains fields "uos/telegram-runtime/20261001-1150")"FMEA plan absent";require(contains fields "RPN")"FMEA risks absent")
 else if page_path="/mini-app/chat" then(require(memory_mode || chat_mode || chat_recovery || contains fields "Retained private reply42")"history absent";require(not(contains fields "OTHER_USER_SECRET"))"other user leak";require(contains fields "Only this user")"history scope absent";if history_long then require(contains fields "LONG_HISTORY_TEXT_")"long history missing")
 else if page_path="/mini-app/health" then(require(contains fields "no remote fleet")"health scope absent";require(contains fields "Sensor policy")"sensor limits absent")
 else if page_path="/mini-app/containers" then(require(contains fields "Local Podman inventory")"Podman scope absent";require(contains fields "Container count")"Podman count absent";require(contains fields "Rootless")"Podman namespace absent")
 else(require(String.starts_with ~prefix:"Candidate" fields)"candidate must precede details";require(contains fields "CHK-18-JJ")"verification catalog incomplete";require(contains fields "UNKNOWN")"missing evidence hidden")));

 if config_mode && not failure_mode && mode<>"identity-denied" && mode<>"sdk-blocked" then (
   save(out^"/"^mode^"-positive.png")(Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:2500. page);
   fail_posts:=true;Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
   let rec clear n=if text page "#mini-fields"="" && not(String.starts_with ~prefix:"Loading"(text page "#mini-status"))then()
    else if n=0 then failwith"config stale data survived outage"else(Eio.Time.sleep env#clock 0.05;clear(n-1))in clear 100;
   require(!control_posts=0)"config page dispatched an effect";
   save(out^"/"^mode^"-config.json")(Yojson.Safe.to_string(`Assoc["status",s"PASS";"outage_clears_stale_data",`Bool true;"no_control_posts",`Bool true]));
 );
 if health_mode then (
   let count=Playwright.Locator.count(loc page "#mini-health-grid button")in require(count>0)"device grid empty";
   let ids=List.init count(fun i->Option.get(Playwright.Locator.get_attribute ~name:"data-device" ~timeout:1000.(loc page(Printf.sprintf"#mini-health-grid button:nth-child(%d)"(i+1)))))in
   require(ids=List.sort String.compare ids)"unstable device order";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-health-grid button:first-child");
   require(contains(text page "#mini-health-detail")"Device: ")"device details absent";
   let select value=ignore(Playwright.Locator.select_option ~options:[|Playwright.Frame.Options.{value_or_label=None;value=Some value;label=None;index=None}|] ~timeout:2000.(loc page "#mini-health-filter"))in
   select "unknown";require(Playwright.Locator.count(loc page "#mini-health-grid button:not([data-grade=unknown])")=0)"filter leaked other grade";
   require(Playwright.Locator.count(loc page "#mini-health-grid button")>0)"unassessed inventory absent";
   select "critical";require(Playwright.Locator.count(loc page "#mini-health-grid button:not([data-grade=critical])")=0)"critical filter incorrect";
   select "all";require(Playwright.Locator.count(loc page "#mini-health-grid button")=count)"all filter lost devices";
   save(out^"/"^mode^"-positive.png")(Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:2500. page);
   fail_posts:=true;Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
   let rec clear n=if Playwright.Locator.count(loc page "#mini-health-grid button")=0 && text page "#mini-health-detail"="" && not(String.starts_with ~prefix:"Loading"(text page "#mini-status"))then()
    else if n=0 then failwith"stale health data survived outage"else(Eio.Time.sleep env#clock 0.05;clear(n-1))in clear 100;
   require(text page "#mini-health-status"="No current device observation.")"outage detail";
   save(out^"/"^mode^"-health.json")(Yojson.Safe.pretty_to_string(`Assoc["status",s"PASS";"devices",`Int count;"filter_and_details",`Bool true;"outage_clears_stale_data",`Bool true]));
 );
 if memory_mode then (
   let rec await_memory prefix n = let value=text page "#mini-memory-status" in
     if String.starts_with ~prefix value then value else if n=0 then failwith("memory UI timeout: "^value)
     else(Eio.Time.sleep env#clock 0.05;await_memory prefix(n-1)) in
   let read() =
     let old= !posts in Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
     let rec wait n=if !posts>old && String.starts_with ~prefix:"Observed at "(text page "#mini-status")then()
       else if n=0 then failwith"memory readback"else(Eio.Time.sleep env#clock 0.05;wait(n-1))in wait 100 in
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-memory-clear");
   ignore(await_memory "Confirmed:" 160);
   require(!control_posts=1)"clear sent once";read();
   require(contains(text page "#mini-fields")"No stored complete exchanges")"clear readback not empty";
   drop_response:=true;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-memory-reset");
   ignore(await_memory "The outcome is unknown." 120);
   drop_response:=false;require(!control_posts=2)"lost response repeated effect";
   read();Playwright.Locator.click ~timeout:2000.(loc page "#mini-memory-receipt");
   ignore(await_memory "Confirmed:" 120);require(!control_posts=2)"receipt check repeated effect";
   read();abort_control:=true;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-memory-clear");
   ignore(await_memory "The outcome is unknown." 100);
   require(!control_posts=3)"pre-network refusal repeated effect";
   ignore(Playwright.Page.reload ~timeout:5000. page);
   ignore(await_memory "An earlier request needs a receipt check." 100);
   read();Playwright.Locator.click ~timeout:2000.(loc page "#mini-memory-receipt");
   ignore(await_memory "Outcome: receipt_not_found." 100);
   Eio.Time.sleep env#clock 0.2;require(!control_posts=3)"reload or receipt repeated effect";
   save(out^"/"^mode^"-memory.json")(Yojson.Safe.pretty_to_string(`Assoc[
     "status",s"PASS";"clear_readback",`Bool true;"reset_lost_response_recovered",`Bool true;
     "no_automatic_replay",`Bool true;"reload_preserves_pending",`Bool true]));
 );

 if chat_recovery then (
   let read_status=text page "#mini-chat-status" in
   require(String.starts_with ~prefix:"An earlier send needs a receipt check." read_status)"pending crash request absent";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-abandon");
   let rec wait n = let v=text page "#mini-chat-status" in
     if String.starts_with ~prefix:"Pending request closed locally." v then ()
     else if n=0 then failwith("abandon timeout "^v)else(Eio.Time.sleep env#clock 0.05;wait(n-1))in wait 200;
   require(!control_posts=1)"abandon not exactly one action";
   save(out^"/crash-recovery.json")(Yojson.Safe.pretty_to_string(`Assoc[
     "status",s"PASS";"explicit_abandon_after_actor_crash",`Bool true;"no_model_resend",`Bool true]));
 );

 if chat_mode then (
   let rec await_chat prefix n = let value=text page "#mini-chat-status" in
     if String.starts_with ~prefix value then value else if n=0 then failwith("chat UI timeout: "^value)
     else(Eio.Time.sleep env#clock 0.05;await_chat prefix(n-1)) in
   let read() =
     let old= !posts in Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
     let rec wait n=if !posts>old && String.starts_with ~prefix:"Observed at "(text page "#mini-status")then()
       else if n=0 then failwith"chat readback"else(Eio.Time.sleep env#clock 0.05;wait(n-1))in wait 100 in
   Playwright.Locator.fill ~value:"Browser chat request" ~timeout:2000.(loc page "#mini-chat-prompt");
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-send");
   ignore(await_chat "Reply saved." 400);
   require(!control_posts=1)"send once";
   require(text page "#mini-chat-reply"="Fixture reply <script>not executed</script>")"literal reply text";
   require(Playwright.Locator.count(loc page "#mini-chat-reply script")=0)"reply HTML injection";
   read();require(contains(text page "#mini-fields")"Browser chat request")"chat persisted history";
   drop_response:=true;
   Playwright.Locator.fill ~value:"Lost response request" ~timeout:2000.(loc page "#mini-chat-prompt");
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-send");
   ignore(await_chat "Outcome unknown." 400);
   drop_response:=false;require(!control_posts=2)"lost response repeated send";
   ignore(Playwright.Page.reload ~timeout:5000. page);
   ignore(await_chat "An earlier send needs a receipt check." 100);
   read();Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-receipt");
   ignore(await_chat "Reply saved." 160);require(!control_posts=2)"receipt recovery repeated model action";
   read();abort_control:=true;
   Playwright.Locator.fill ~value:"Network refused request" ~timeout:2000.(loc page "#mini-chat-prompt");
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-send");
   ignore(await_chat "Outcome unknown." 100);
   read();Playwright.Locator.click ~timeout:2000.(loc page "#mini-chat-receipt");
   ignore(await_chat "Outcome: receipt_not_found." 100);
   require(!control_posts=3)"missing receipt retried send";
   save(out^"/"^mode^"-chat.json")(Yojson.Safe.pretty_to_string(`Assoc[
     "status",s"PASS";"send_and_history",`Bool true;"literal_reply",`Bool true;
     "lost_response_reload_recovery",`Bool true;"no_automatic_retry",`Bool true]));
 );

 if control_mode then (
   let rec await_control prefix n = let value=text page "#mini-control-status" in
     if String.starts_with ~prefix value then value else if n=0 then failwith("control UI timeout: "^value)
     else(Eio.Time.sleep env#clock 0.05;await_control prefix(n-1)) in
   let select value=ignore(Playwright.Locator.select_option ~options:[|Playwright.Frame.Options.{value_or_label=None;value=Some value;label=None;index=None}|] ~timeout:2000.(loc page "#mini-control-level"))in
   let current=text page "#mini-fields" in
   let target=if contains current "notice" then "info" else "notice" in
   select target;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-control-apply");
   let confirmed=await_control "Confirmed:" 160 in
   require(!control_posts=1)"one explicit control POST";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
   let rec await_read n = if String.starts_with ~prefix:"Observed at "(text page "#mini-status")then()else if n=0 then failwith"control readback"else(Eio.Time.sleep env#clock 0.05;await_read(n-1))in
   await_read 100;
   require(contains(text page "#mini-fields")target)"logger readback absent";
   select "warning";drop_response:=true;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-control-apply");
   ignore(await_control "The request outcome is unknown." 100);
   drop_response:=false;
   require(!control_posts=2)"lost response resubmitted effect";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-control-receipt");
   ignore(await_control "Confirmed:" 100);
   require(!control_posts=2)"terminal receipt resubmitted effect";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
   await_read 100;
   select "error";abort_control:=true;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-control-apply");
   ignore(await_control "The request outcome is unknown." 100);
   Eio.Time.sleep env#clock 0.25;require(!control_posts=3)"uncertain request automatically retried";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-control-receipt");
   ignore(await_control "Receipt: receipt_not_found." 100);
   require(!control_posts=3)"receipt lookup repeated mutation";
   ignore(Playwright.Page.reload ~timeout:5000. page);
   ignore(await_control "An earlier request needs a receipt check." 100);
   require(!control_posts=3)"reload repeated mutation";
   save(out^"/"^mode^"-control.json")(Yojson.Safe.pretty_to_string(`Assoc[
     "status",s"PASS";"confirmed",s confirmed;"single_submission",`Bool true;
     "unknown_not_retried",`Bool true;"receipt_only_lookup",`Bool true;"reload_preserves_pending",`Bool true]));
 );

 if zenoh_mode then (
   let select key=ignore(Playwright.Locator.select_option ~options:[|Playwright.Frame.Options.{value_or_label=None;value=Some key;label=None;index=None}|] ~timeout:2000. (loc page "#mini-topic")) in
   let rec await needle n =
     if contains(text page "#mini-fields")needle && String.starts_with ~prefix:"Observed at "(text page "#mini-status") then ()
     else if n=0 then failwith("Zenoh UI missing "^needle)
     else(Eio.Time.sleep env#clock 0.05;await needle(n-1)) in
   select "uos/tui/recovery/telegram-mini/20261025-0258/topic-a";
   await "SECOND_RETAINED_SAMPLE_" 100;
   require(Playwright.Locator.count(loc page "#mini-fields script")=0)"sample executed as script";
   let first_posts= !posts in
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-live");
   let rec await_posts count n=if !posts>=count && String.starts_with ~prefix:"Observed at "(text page "#mini-status") then ()
     else if n=0 then failwith"polling did not query"else(Eio.Time.sleep env#clock 0.05;await_posts count(n-1))in
   await_posts(first_posts+2)100;
   let before_manual= !posts in
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-refresh");
   await_posts(before_manual+1)100;
   Eio.Time.sleep env#clock 2.3;
   require(!posts=before_manual+2)"manual refresh left a duplicate polling timer";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-live");
   let stopped= !posts in Eio.Time.sleep env#clock 2.3;
   require(!posts=stopped)"stop left polling active";
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-live");
   await_posts(stopped+1)100;
   Playwright.BrowserContext.clock_fast_forward ~ticks_number:300001. context;
   Eio.Time.sleep env#clock 0.1;
   require(text page "#mini-live"="Start live refresh")"polling exceeded five minute budget";
   require(contains(text page "#mini-live-status")"Five-minute")"time limit not explained";
   let ended= !posts in Eio.Time.sleep env#clock 0.2;
   require(!posts=ended)"time-limit emitted extra read";
   save(out^"/zenoh-positive-mobile.png")(Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:2500. page);
   fail_posts:=true;
   Playwright.Locator.click ~timeout:2000.(loc page "#mini-live");
   let rec await_failure n=if text page "#mini-live"="Start live refresh" && text page "#mini-fields"="" && not(String.starts_with ~prefix:"Loading"(text page "#mini-status")) then () else if n=0 then failwith"network failure did not stop and clear" else(Eio.Time.sleep env#clock 0.05;await_failure(n-1))in
   await_failure 100;
   let failed_posts= !posts in Eio.Time.sleep env#clock 2.3;
   require(!posts=failed_posts)"failed request left polling active";
   save(out^"/zenoh-interactions.json")(Yojson.Safe.pretty_to_string(`Assoc[
     "status",s"PASS";"selection",`Bool true;"polling",`Bool true;"manual_stop",`Bool true;"manual_refresh_single_timer",`Bool true;
     "five_minute_stop",`Bool true;"literal_payload",`Bool true;"network_failure_stops",`Bool true;"posts",`Int !posts]));
 );
 for n=1 to 6 do Playwright.Locator.click ~timeout:1000.(loc page(Printf.sprintf"section details:nth-of-type(%d) summary"n))done;
 Playwright.Locator.check ~timeout:1000.(loc page "#CHK-01-TIME");
 Playwright.Locator.press ~key:"Control+Home" ~timeout:1000.(loc page "body");
 let viewport_screenshot=out^"/"^mode^"-viewport.png"in save viewport_screenshot(Playwright.Page.screenshot ~type_:`Png ~full_page:false ~timeout:2500. page);
 let screenshot=out^"/"^mode^".png"in
 let png=Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:2500. page in
 save screenshot png;let actual_width=png_width png in
 save(out^"/"^mode^"-geometry.json")(Yojson.Safe.to_string(`Assoc["viewport_width",`Int width;"full_page_png_width",`Int actual_width]));
 require(actual_width=width)"horizontal overflow beyond viewport";
 let errors=Array.to_list(Playwright.Page.page_errors page)in require(errors=[])"page script errors";
 rows:=`Assoc["mode",s mode;"path",s page_path;"viewport",`List[`Int width;`Int height];"http_status",`Int status;"status_text",s final;"fields",s(text page "#mini-fields");"posts",`Int !posts;"checkpoints",`Int 18;"full_page_png_width",`Int actual_width;"screenshot",s screenshot;"denied",`List(List.map s !denied);"page_errors",`List[]]::!rows
 ))(if config_failure then ["config-unavailable",390,844,"/mini-app/config"] else if config_mode then ["mobile-config",390,844,"/mini-app/config";"desktop-config",1280,800,"/mini-app/config";"identity-denied",390,844,"/mini-app/config";"sdk-blocked",390,844,"/mini-app/config"] else if health_mode then ["mobile-health",390,844,"/mini-app/health";"desktop-health",1280,800,"/mini-app/health"] else if chat_recovery then ["mobile-chat-recovery",390,844,"/mini-app/chat"] else if chat_mode then ["mobile-chat",390,844,"/mini-app/chat";"desktop-chat",1280,800,"/mini-app/chat"] else if memory_mode then ["mobile-memory",390,844,"/mini-app/chat";"desktop-memory",1280,800,"/mini-app/chat"] else if control_mode then ["mobile-control",390,844,"/mini-app/telemetry";"desktop-control",1280,800,"/mini-app/telemetry"] else if telemetry_failure then ["telemetry-unavailable",390,844,"/mini-app/telemetry"] else if zenoh_mode then ["mobile-zenoh",390,844,"/mini-app/zenoh"] else if history_long then ["mobile-history-long",390,844,"/mini-app/chat"] else if failure_mode then ["history-unavailable",390,844,"/mini-app/chat";"containers-unavailable",390,844,"/mini-app/containers";"fmea-unavailable",390,844,"/mini-app/fmea";"verification-unavailable",1280,800,"/mini-app/verify"] else ["mobile-telemetry",390,844,"/mini-app/telemetry";"desktop-telemetry",1280,800,"/mini-app/telemetry";"mobile-dashboard",390,844,"/mini-app/dashboard";"desktop-dashboard",1280,800,"/mini-app/dashboard";"mobile-history",390,844,"/mini-app/chat";"mobile-containers",390,844,"/mini-app/containers";"identity-denied",390,844,"/mini-app/fmea";"sdk-blocked",390,844,"/mini-app/tasks";"mobile-authenticated",390,844,"/mini-app/tasks";"desktop-authenticated",1280,800,"/mini-app/tasks";"mobile-fmea",390,844,"/mini-app/fmea";"desktop-verification",1280,800,"/mini-app/verify"])
 )))));
 let report=`Assoc["status",s"PASS_PRIVATE_BROWSER_FIXTURE";"observed_utc",`Float(Unix.gettimeofday());"scope",s"Actual Chromium, Mist ingress, Gleam authentication and native private Sa-plan reader; Telegram SDK identity supplied by explicit synthetic fixture, not real Telegram acceptance";"rows",`List(List.rev !rows)]in
 save(out^"/report.json")(Yojson.Safe.pretty_to_string report);print_endline(Yojson.Safe.to_string report)
