(* @agent_intent: Observe the actual ecology page through typed OCaml Playwright.
   No script injection, service mutation, capability dispatch or package download.
   @laws: Accept iff violations=[]; a sample is live only after >=6 elapsed seconds
   and a strictly advancing cycle; candidate/run identity must stay constant.
   Usage: ecology-browser-check URL NEW_ABSOLUTE_OUTPUT CHROME EXPECTED_REVISION
          ecology-browser-check selftest
   URL must be canonical Tailnet :4110 or an explicitly staged high port. *)

open Yojson.Safe.Util
type observation = {
  elapsed : float; cycle : int; invocations : int; participants : int;
  rows : string list; andon : string; refresh_state : string; refresh_text : string;
}
type violation = Missing_render | Wrong_participants | Invalid_andon | Not_live
  | Counter_stalled | Counter_reversed | Too_short | Browser_error | Identity_changed
type verdict = Accept | Reject of violation list
let name = function Missing_render->"missing_render" | Wrong_participants->"wrong_participants"
  | Invalid_andon->"invalid_andon" | Not_live->"not_live" | Counter_stalled->"counter_stalled"
  | Counter_reversed->"counter_reversed" | Too_short->"too_short"
  | Browser_error->"browser_error" | Identity_changed->"identity_changed"
let require b msg = if not b then failwith msg
let s x=`String x
let json x=Yojson.Safe.pretty_to_string x^"\n"
let mono()=Mtime.Span.to_float_ns(Mtime_clock.elapsed())/.1e9
let bounded text limit= require(String.length text<=limit) "observation byte bound exceeded";text
let hex n text=String.length text=n && String.for_all(function '0'..'9'|'a'..'f'->true|_->false)text
let sha bytes=Cryptokit.hash_string(Cryptokit.Hash.sha256())bytes
  |>Cryptokit.transform_string(Cryptokit.Hexa.encode())
let save path bytes=
  let fd=Unix.openfile path [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL;Unix.O_CLOEXEC]0o600 in
  let oc=Unix.out_channel_of_descr fd in
  Fun.protect(fun()->output_string oc bytes;flush oc;Unix.fsync fd)~finally:(fun()->close_out_noerr oc)
let regular p=let st=Unix.lstat p in require(st.st_kind=Unix.S_REG) ("preinstalled regular file required: "^p)
let root="/home/an/NAS-setup/uos"
let source=root^"/tools/validation/ecology_browser_check.ml"
let source_hash()=let ic=open_in_bin source in Fun.protect(fun()->sha(really_input_string ic(in_channel_length ic)))~finally:(fun()->close_in_noerr ic)
let origin url=
  let prefix="http://nas-1.tail55d152.ts.net:" and suffix="/ecology" in
  require(String.starts_with ~prefix url && String.ends_with ~suffix url) "canonical ecology URL required";
  let port=String.sub url(String.length prefix)(String.length url-String.length prefix-String.length suffix)in
  require(port<>"" && String.for_all(function '0'..'9'->true|_->false)port) "invalid target port";
  let n=int_of_string port in require(n=4110 || n>=49152&&n<=65535) "4110 or private staged port required";
  prefix^port
let andon_valid text=
  let lines=String.split_on_char '\n' text in
  List.for_all(fun capability->List.exists(fun line->List.exists(fun phase->
    let prefix=capability^": "^phase in
    line=prefix || String.starts_with ~prefix:(prefix^" ")line)
    ["ready";"stopped";"recovering"])lines)["modular_max";"openrouter_free"]
let observation_violations x=
  (if x.participants=26 && List.length x.rows=26 &&
      List.length(List.sort_uniq String.compare x.rows)=26 && List.for_all((<>)"")x.rows then [] else [Wrong_participants]) @
  (if andon_valid x.andon then [] else [Invalid_andon]) @
  (if x.refresh_state="live" then [] else [Not_live])
let assess ~rendered ~errors ~identity_same first last=
  let violations=(if rendered then [] else [Missing_render]) @
    observation_violations first @ observation_violations last @
    (if last.elapsed-.first.elapsed>=6. then [] else [Too_short]) @
    (if last.cycle>first.cycle then [] else [Counter_stalled]) @
    (if last.invocations>=first.invocations then [] else [Counter_reversed]) @
    (if errors=[] then [] else [Browser_error]) @
    (if identity_same then [] else [Identity_changed]) in
  match List.sort_uniq compare violations with []->Accept|xs->Reject xs
let observation_json x=`Assoc[
  "elapsed_seconds",`Float x.elapsed;"cycle",`Int x.cycle;"invocations",`Int x.invocations;
  "participants",`Int x.participants;"row_ids",`List(List.map s x.rows);
  "andon",s x.andon;"refresh_state",s x.refresh_state;"refresh_text",s x.refresh_text]
let locator page selector=Playwright.Page.locator ~selector page
let text page selector=Playwright.Locator.inner_text ~timeout:3000. (locator page selector)|>String.trim
let counter page selector=
  let raw=text page selector in require(raw<>"" && String.for_all(function '0'..'9'->true|_->false)raw) "invalid displayed counter";
  int_of_string raw
let observe started page={
  elapsed=mono()-.started;cycle=counter page "#ecology-cycle";
  invocations=counter page "#ecology-invocations";participants=counter page "#ecology-participants";
  rows=Playwright.Locator.all_inner_texts(locator page "#ecology-participant-rows > tr > td:first-child")|>List.map String.trim;
  andon=text page "#ecology-service-andon";
  refresh_state=Option.value ~default:"missing" (Playwright.Locator.get_attribute ~name:"data-state" ~timeout:3000. (locator page "#ecology-refresh-status"));
  refresh_text=text page "#ecology-refresh-status";
}
let screenshot out label page=
  let bytes=Playwright.Page.screenshot ~type_:`Png ~full_page:true ~timeout:10000. page |>fun b->bounded b(8*1024*1024) in
  require(String.starts_with ~prefix:"\137PNG\r\n\026\n" bytes) "screenshot is not PNG";
  let path=out^"/"^label^".png" in save path bytes;
  `Assoc["path",s path;"sha256",s(sha bytes);"bytes",`Int(String.length bytes)]
let errors page=
  let scripts=Playwright.Page.page_errors page |>Array.to_list|>List.map(fun e->
    Playwright.SerializedError.to_yojson e |>Yojson.Safe.to_string|>fun t->bounded t 16384) in
  let console=Playwright.Page.console_messages page |>Array.to_list|>List.filter_map(fun (m:Playwright.Page.Messages.t)->
    if m.type_="error" then Some(bounded m.text 16384) else None) in
  scripts@console
let identity page base expected=
  let response=Playwright.Page.goto ~url:(base^"/api/v1/runtime/identity") ~timeout:8000. page in
  let response=Option.get response in
  let doc=Playwright.Response.body response |>fun t->bounded t 65536|>Yojson.Safe.from_string in
  require(doc|>member "schema"|>to_string="uos.web-runtime-identity.v1") "identity schema";
  require(doc|>member "otp_release"|>to_string="29") "actual OTP29 required";
  require(String.starts_with ~prefix:"17."(doc|>member "erts_version"|>to_string)) "actual ERTS17 required";
  require(doc|>member "runtime_ready"|>to_bool) "runtime not ready";
  require(doc|>member "identity_consistent"|>to_bool) "runtime identity inconsistent";
  require(not(doc|>member "application_admitted"|>to_bool)) "admission must remain false";
  require(doc|>member "declared_candidate_revision"|>to_string=expected) "declared runtime candidate differs";
  doc
let same_identity first last=
  List.for_all(fun key->member key first=member key last)["run_id";"os_pid";"declared_candidate_revision";"started_utc_us"]
let run url out chrome expected=
  let base=origin url in require(hex 40 expected) "expected declared revision must be 40 lowercase hex";
  let address=if String.ends_with ~suffix:":4110" base then "100.87.7.78" else "127.0.0.1" in
  require(not(Filename.is_relative out) && not(Sys.file_exists out)) "new absolute artifact directory required";
  regular chrome;
  let driver=Sys.getenv "HOME" ^"/.cache/playwright-ocaml-driver/1.59.0" in
  regular(driver^"/node");regular(driver^"/package/cli.js");
  Unix.mkdir out 0o700;
  let started=mono() and code=source_hash() and observations=ref[] and pictures=ref[] in
  let now=Unix.gmtime(Unix.gettimeofday())in
  let stamp=Printf.sprintf "%04d%02d%02d-%02d%02d"(now.tm_year+1900)(now.tm_mon+1)now.tm_mday now.tm_hour now.tm_sec in
  let receipt_path=out^"/"^stamp^"-receipt.json" in
  let finish doc=let doc=`Assoc(("receipt_path",s receipt_path)::("observed_utc_seconds",`Float(Unix.gettimeofday()))::to_assoc doc)in
    save receipt_path(json doc);print_string(json doc) in
  try
    let result=Eio_main.run(fun env->Eio.Time.with_timeout_exn env#clock 55. (fun()->Eio.Switch.run(fun sw->
      let pw=Playwright.create ~env ~sw()in
      Fun.protect ~finally:(fun()->Playwright.destroy pw)(fun()->
        let browser=Playwright.BrowserType.launch ~executable_path:chrome ~headless:true ~timeout:12000.
          ~args:[|"--host-resolver-rules=MAP nas-1.tail55d152.ts.net "^address;"--no-proxy-server";"--disable-background-networking"|]
          (Playwright.Playwright.chromium pw)in
        Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
          let context=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width=1280;height=900} ~reduced_motion:`Reduce browser in
          Fun.protect ~finally:(fun()->Playwright.BrowserContext.close context)(fun()->
            let blocked=ref 0 in
            Playwright.BrowserContext.on_route context(fun event->incr blocked;Eio.Fiber.fork ~sw(fun()->Playwright.Route.abort event.route));
            let port=String.sub base(String.length "http://nas-1.tail55d152.ts.net:")(String.length base-String.length "http://nas-1.tail55d152.ts.net:") in
            Playwright.BrowserContext.set_network_interception_patterns
              ~patterns:[|Playwright.BrowserContext.Patterns.{glob=None;regex_source=Some("^https?://(?!nas-1\\.tail55d152\\.ts\\.net:"^port^"/)");regex_flags=None;url_pattern=None}|]context;
            let page=Playwright.BrowserContext.new_page context in
            let first_identity=identity page base expected in
            ignore(Playwright.Page.goto ~url ~timeout:8000. page);
            Playwright.Locator.wait_for ~state:`Visible ~timeout:8000. (locator page "#ecology-service-andon");
            let refresh_deadline=mono()+.8. in
            let rec wait_live()=
              let value=Playwright.Locator.get_attribute ~name:"data-state" ~timeout:1000. (locator page "#ecology-refresh-status")in
              if value<>Some "live" then (require(mono()<refresh_deadline) "live refresh unavailable";Eio.Time.sleep env#clock 0.2;wait_live())in
            wait_live();
            let rendered=Playwright.Locator.is_visible(locator page "h1") &&
              text page "h1"="UOS LIVING SWARM ECOLOGY" && String.length(text page "body")>1000 in
            let first=observe started page in observations:=[first];
            pictures:=[screenshot out (stamp^"-initial") page];
            Eio.Time.sleep env#clock 6.2;
            let last=observe started page in observations:=[first;last];
            pictures:= !pictures@[screenshot out (stamp^"-after-live-refresh") page];
            let browser_errors=errors page in
            let final_identity=identity page base expected in
            let browser_errors=browser_errors@errors page in
            let verdict=assess ~rendered ~errors:browser_errors ~identity_same:(same_identity first_identity final_identity) first last in
            let violations=match verdict with Accept->[]|Reject xs->List.map name xs in
            let violations=if !blocked=0 then violations else "external_request_blocked"::violations in
            `Assoc["schema",s"uos.ecology-browser-evidence.v1";"status",s(if violations=[] then "PASS" else "FAIL");
              "authority",s"NONE";"application_admitted",`Bool false;"url",s url;
              "declared_candidate",s expected;"source_sha256",s code;"browser_executable",s chrome;"driver_version",s"1.59.0";
              "resolver",s("explicit canonical FQDN mapping to "^address);
              "samples",`List(List.map observation_json !observations);"screenshots",`List !pictures;
              "identity_before",first_identity;"identity_after",final_identity;
              "browser_errors",`List(List.map s browser_errors);"violations",`List(List.map s violations);
              "elapsed_seconds",`Float(mono()-.started);
              "limits",`List(List.map s["One 1280x900 Chromium page; no whole-product or accessibility claim.";"Read-only DOM and identity requests; no backend activation or service effects.";"Runtime candidate is declared metadata; package attestation is a separate gate."])]))))))in
    require(source_hash()=code) "controller source changed during observation";
    finish result;if result|>member "status"|>to_string<>"PASS" then exit 1
  with e->
    let doc=`Assoc["schema",s"uos.ecology-browser-evidence.v1";"status",s"FAIL";"authority",s"NONE";"application_admitted",`Bool false;
      "url",s url;"declared_candidate",s expected;"source_sha256",s code;"error",s(Printexc.to_string e);
      "samples",`List(List.map observation_json !observations);"screenshots",`List !pictures;"elapsed_seconds",`Float(mono()-.started)] in
    finish doc;exit 1
let selftest()=
  let base={elapsed=0.;cycle=4;invocations=3;participants=26;rows=List.init 26 string_of_int;
    andon="modular_max: stopped — startup_recovery_required\nopenrouter_free: ready";refresh_state="live";refresh_text="Live snapshot"}in
  let final={base with elapsed=6.2;cycle=10;invocations=8}in
  let accepted a b=assess ~rendered:true ~errors:[] ~identity_same:true a b=Accept in
  let checks=ref 0 in let check b= require b "controller law failed";incr checks in
  check(accepted base final);check(not(accepted base {final with elapsed=5.9}));
  check(not(accepted base {final with cycle=4}));check(not(accepted base {final with participants=25}));
  check(not(accepted base {final with rows=List.init 26(fun _->"same")}));
  check(not(accepted base {final with andon="green"}));check(not(accepted base {final with refresh_state="stale"}));
  check(not(accepted base {final with invocations=2}));
  check(assess ~rendered:false ~errors:[] ~identity_same:true base final<>Accept);
  check(assess ~rendered:true ~errors:["exception"] ~identity_same:true base final<>Accept);
  check(assess ~rendered:true ~errors:[] ~identity_same:false base final<>Accept);
  check(origin "http://nas-1.tail55d152.ts.net:4110/ecology"="http://nas-1.tail55d152.ts.net:4110");
  let rejected u=try ignore(origin u);false with _->true in
  check(rejected "http://127.0.0.1:4110/ecology");check(rejected "http://nas-1.tail55d152.ts.net:4100/ecology");
  print_string(json(`Assoc["status",s"PASS";"checks",`Int !checks;"scope",s"independent finite observation mutants; browser not run";"application_admitted",`Bool false]))
let ()=try match Array.to_list Sys.argv with
  | [_;"selftest"]->selftest()
  | [_;url;out;chrome;expected]->run url out chrome expected
  | _->failwith "usage: ecology-browser-check URL NEW_ABSOLUTE_OUTPUT CHROME EXPECTED_REVISION | selftest"
with e->prerr_endline(json(`Assoc["status",s"FAIL";"error",s(Printexc.to_string e);"application_admitted",`Bool false]));exit 1
