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
 let failure_mode=Array.length Sys.argv=4 && Sys.argv.(3)="--unavailable" in
 let history_long=Array.length Sys.argv=4 && Sys.argv.(3)="--history-long" in
 require(Array.length Sys.argv=3 || failure_mode || history_long)"unknown scenario";
 let out=Sys.argv.(1)in require(not(Sys.file_exists out))"new output required";Unix.mkdir out 0o700;
 let init_data=Yojson.Safe.Util.(Yojson.Safe.from_file Sys.argv.(2)|>member"init_data"|>to_string)in
 let sdk_for denied="window.Telegram={WebApp:{initData:"^Yojson.Safe.to_string(`String (if denied then init_data^"0" else init_data))^",ready:function(){},expand:function(){}}};"in
 let rows=ref[]in
 Eio_main.run(fun env->Eio.Time.with_timeout_exn env#clock 35.(fun()->Eio.Switch.run(fun sw->
 with_driver ~env ~sw(fun conn pw->
 let browser=Playwright.BrowserType.launch ~executable_path:"/opt/google/chrome/chrome" ~headless:true ~timeout:8000.
 ~args:[|"--no-proxy-server";"--disable-background-networking";"--host-resolver-rules=MAP nas-1.tail55d152.ts.net 100.87.7.78"|](Playwright.Playwright.chromium pw)in
 Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
 List.iter(fun(mode,width,height,page_path)->
 let context=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width;height}
 ~service_workers:`Block ~accept_downloads:`Deny browser in
 Fun.protect ~finally:(fun()->Playwright.BrowserContext.close context)(fun()->
 let denied=ref[]and posts=ref 0 in
 let patterns=[|Playwright.BrowserContext.Patterns.{glob=Some"**/*";regex_source=None;regex_flags=None;url_pattern=None}|]in
 Playwright.BrowserContext.on_route context(fun event->Eio.Fiber.fork ~sw(fun()->
 let i=observed_initializer conn(Playwright.Request.to_yojson(Playwright.Route.request event.route))Playwright.Request.Initializer.of_yojson in
 if i.url="https://telegram.org/js/telegram-web-app.js" && mode<>"sdk-blocked"then
 Playwright.Route.fulfill ~status:200 ~headers:[|Playwright.NameValue.{name="content-type";value="text/javascript"}|] ~body:(sdk_for(mode="identity-denied")) event.route
 else if Option.is_none i.redirected_from &&
 ((i.method_="GET"&&(i.url=base^page_path||i.url=base^"/mini-app/client.js"))||
 (i.method_="POST"&&i.url=base^"/mini-app/api/data"))
 then(if i.method_="POST"then incr posts;Playwright.Route.continue ~is_fallback:false event.route)
 else(denied:=(i.method_^" "^i.url)::!denied;Playwright.Route.abort event.route)));
 Playwright.BrowserContext.set_network_interception_patterns ~patterns context;
 Playwright.BrowserContext.on_web_socket_route context(fun event->Eio.Fiber.fork ~sw(fun()->Playwright.WebSocketRoute.close_page ~code:1008 ~reason:"private fixture disallows sockets" ~was_clean:true event.web_socket_route));
 Playwright.BrowserContext.set_web_socket_interception_patterns ~patterns context;
 let page=Playwright.BrowserContext.new_page context in
 refuse_redirects ~sw ~context ~page(fun()->denied:="redirect"::!denied);
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
 else if failure_mode then(require(!posts=1)"one failed-backend POST";require(final="The data source is unavailable or not configured.")"backend failure state absent";require(text page "#mini-fields"="")"failed backend data exposed")
 else(require(!posts=1)"exactly one authenticated POST";require(String.starts_with ~prefix:"Observed at "final)"authenticated observation";let fields=text page "#mini-fields" in
 if page_path="/mini-app/tasks" then (require(contains fields "Task FENCE")"task fields absent";require(contains fields "executing (lease expired)")"expired lease hidden")
 else (require(contains fields "NOT_GRANTED")"admission disclaimer absent";
 if page_path="/mini-app/fmea" then(require(String.starts_with ~prefix:"Assessments" fields)"FMEA metadata must precede details";require(contains fields "uos/telegram-runtime/20261001-1150")"FMEA plan absent";require(contains fields "RPN")"FMEA risks absent")
 else if page_path="/mini-app/chat" then(require(contains fields "Retained private reply42")"history absent";require(not(contains fields "OTHER_USER_SECRET"))"other user leak";require(contains fields "Only this user")"history scope absent";if history_long then require(contains fields "LONG_HISTORY_TEXT_")"long history missing")
 else if page_path="/mini-app/containers" then(require(contains fields "Local Podman inventory")"Podman scope absent";require(contains fields "Container count")"Podman count absent";require(contains fields "Rootless")"Podman namespace absent")
 else(require(String.starts_with ~prefix:"Candidate" fields)"candidate must precede details";require(contains fields "CHK-18-JJ")"verification catalog incomplete";require(contains fields "UNKNOWN")"missing evidence hidden")));
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
 ))(if history_long then ["mobile-history-long",390,844,"/mini-app/chat"] else if failure_mode then ["history-unavailable",390,844,"/mini-app/chat";"containers-unavailable",390,844,"/mini-app/containers";"fmea-unavailable",390,844,"/mini-app/fmea";"verification-unavailable",1280,800,"/mini-app/verify"] else ["mobile-history",390,844,"/mini-app/chat";"mobile-containers",390,844,"/mini-app/containers";"identity-denied",390,844,"/mini-app/fmea";"sdk-blocked",390,844,"/mini-app/tasks";"mobile-authenticated",390,844,"/mini-app/tasks";"desktop-authenticated",1280,800,"/mini-app/tasks";"mobile-fmea",390,844,"/mini-app/fmea";"desktop-verification",1280,800,"/mini-app/verify"])
 )))));
 let report=`Assoc["status",s"PASS_PRIVATE_BROWSER_FIXTURE";"observed_utc",`Float(Unix.gettimeofday());"scope",s"Actual Chromium, Mist ingress, Gleam authentication and native private Sa-plan reader; Telegram SDK identity supplied by explicit synthetic fixture, not real Telegram acceptance";"rows",`List(List.rev !rows)]in
 save(out^"/report.json")(Yojson.Safe.pretty_to_string report);print_endline(Yojson.Safe.to_string report)
