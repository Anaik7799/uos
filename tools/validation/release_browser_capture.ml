(* Actual 30-second recordings of eight private release routes.
   Requires already installed Playwright/Chrome/FFmpeg; performs no download. *)
let require b message=if not b then failwith message
let save path body=
 let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL]0o600 in
 let oc=Unix.out_channel_of_descr fd in Fun.protect(fun()->output_string oc body;flush oc;Unix.fsync fd)~finally:(fun()->close_out_noerr oc)
let routes=["cockpit","/";"planning","/planning";"mirage","/mirage";"wiki","/wiki";"zk","/zk";"evolution","/homeostasis/evolution";"components","/homeostasis/components";"terminal","/homeostasis/terminal"]
let mono()=Mtime.Span.to_float_ns(Mtime_clock.elapsed())/.1e9
let ()=
 require(Array.length Sys.argv=4)"usage: capture PRIVATE_BASE OUTPUT CHROME";
 let base=Sys.argv.(1)and out=Sys.argv.(2)in
 let prefix="http://nas-1.tail55d152.ts.net:"in
 require(String.starts_with ~prefix base)"Tailnet base required";
 let port=String.sub base(String.length prefix)(String.length base-String.length prefix)in
 require(port<>""&&String.for_all(function '0'..'9'->true|_->false)port)"bad port";
 require(int_of_string port>=49152&&int_of_string port<=65535)"private port required";
 require(not(Sys.file_exists out)&&not(Filename.is_relative out))"new absolute output required";
 let home=Sys.getenv "HOME"in
 List.iter(fun p->require(Sys.file_exists(home^p))("missing preinstalled dependency "^p))
 ["/.cache/playwright-ocaml-driver/1.59.0/node";"/.cache/ms-playwright/ffmpeg-1011/ffmpeg-linux"];
 Unix.mkdir out 0o700;
 Eio_main.run(fun env->Eio.Switch.run(fun sw->
 let pw=Playwright.create ~env ~sw()in
 Fun.protect ~finally:(fun()->Playwright.destroy pw)(fun()->
 let browser=Playwright.BrowserType.launch ~executable_path:Sys.argv.(3) ~headless:true ~timeout:15000.
 ~args:[|"--host-resolver-rules=MAP nas-1.tail55d152.ts.net 127.0.0.1";"--no-proxy-server";"--disable-background-networking"|]
 (Playwright.Playwright.chromium pw)in
 Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
 let pages=List.map(fun(label,path)->
   let context=Playwright.Browser.new_context
     ~viewport:Playwright.Browser.Viewport.{width=1280;height=800}
     ~record_video:Playwright.Browser.Record_video.{dir=Some out;size=None;show_actions=None}browser in
   Playwright.BrowserContext.on_route context(fun event->Eio.Fiber.fork ~sw(fun()->Playwright.Route.abort event.route));
   Playwright.BrowserContext.set_network_interception_patterns
     ~patterns:[|Playwright.BrowserContext.Patterns.{glob=None;regex_source=Some"^https?://(?!nas-1\\.tail55d152\\.ts\\.net:[0-9]+/)";regex_flags=None;url_pattern=None}|]context;
   let page=Playwright.BrowserContext.new_page context in
   ignore(Playwright.Page.goto ~url:(base^path)~timeout:10000. page);
   label,path,context,page,mono())routes in
 let samples=ref[]in
 for tick=0 to 6 do
   List.iter(fun(label,path,_,page,started)->
     let body=Playwright.Page.evaluate ~expression:"(()=>({url:location.href,text_length:document.body.innerText.trim().length,scroll_height:document.documentElement.scrollHeight,source:document.querySelector('#homeostasis-source-time')?.textContent??null,frames:document.querySelectorAll('#homeostasis-live-stream-body tr').length}))()"page in
     let fields=Yojson.Safe.Util.to_assoc body in
     require(Yojson.Safe.Util.to_int(List.assoc"text_length"fields)>40)("empty render "^path);
     require(Playwright.Page.page_errors page=[||])("script error "^path);
     samples:= `Assoc["page",`String label;"tick",`Int tick;"utc_seconds",`Float(Unix.gettimeofday());"elapsed_seconds",`Float(mono()-.started);"observation",body]::!samples;
     ignore(Playwright.Page.evaluate ~expression:(Printf.sprintf"window.scrollTo(0, Math.max(0,document.documentElement.scrollHeight-window.innerHeight)*%f)"(float_of_int tick/.6.))page))pages;
   if tick<6 then Eio.Time.sleep env#clock 5.
 done;
 let receipts=List.map(fun(label,path,context,page,started)->
   let elapsed=mono()-.started in require(elapsed>=30.)"recording too short";
   let video=Playwright.Page.video page in
   Playwright.BrowserContext.close context;
   let artifact=match video with Some x->x|None->failwith("video unavailable "^label)in
   let dest=out^"/"^label^".webm"in Playwright.Artifact.save_as ~path:dest artifact;
   require((Unix.stat dest).st_size>0)"empty video";
   `Assoc["page",`String path;"artifact",`String(label^".webm");"observed_seconds",`Float elapsed;"bytes",`Int(Unix.stat dest).st_size])pages in
 save(out^"/samples.json")(Yojson.Safe.pretty_to_string(`List(List.rev !samples)));
 let report=`Assoc["schema",`String"uos.browser-recording.v1";"status",`String"PASS";"authority",`String"NONE";"routes",`Int 8;"samples",`Int(List.length !samples);"recordings",`List receipts;"limit",`String"Eight routes only; not all233 components or manual acceptance"]in
 save(out^"/report.json")(Yojson.Safe.pretty_to_string report);print_endline(Yojson.Safe.to_string report)
 ))));;

