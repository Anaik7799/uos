#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "eio_main";;
#require "playwright";;
#require "bos.setup";;
#require "yojson";;
#require "uri";;
#require "str";;
(* @agent_intent Observe the live UOS navigation and reversible page controls in
   four feedback passes. No form submission, authorization action, source mutation,
   or browser-side test JavaScript. Every failure remains in the ledger. *)
open Bos
let get = function Ok x->x | Error(`Msg s)->failwith s
let base = "http://nas-1.tail55d152.ts.net:4100"
let outdir = if Array.length Sys.argv=2 then Sys.argv.(1) else failwith "usage: browser-cycles.ml /tmp/output-directory"
let () = if not(String.starts_with ~prefix:"/tmp/" outdir) then failwith "Output must be scratch evidence"
let write name text = get(OS.File.write(Fpath.v(outdir^"/"^name))text)
let js s = `String s
let has s n = try ignore(Str.search_forward(Str.regexp_string n)s 0);true with Not_found->false
let clip s = if String.length s < 180 then s else String.sub s 0 180
let count page selector = Playwright.Page.locator ~selector page |> Playwright.Locator.count
let http_status url =
  let handle=Curl.init() in
  Fun.protect ~finally:(fun()->Curl.cleanup handle)(fun()->
    Curl.set_url handle url; Curl.set_timeout handle 10;
    Curl.set_writefunction handle (fun bytes->String.length bytes);
    Curl.perform handle; Curl.get_responsecode handle)
let attributes page selector name =
  let loc=Playwright.Page.locator ~selector page in
  let n=Playwright.Locator.count loc in
  if n>4000 then failwith "Component quota exceeded";
  List.init n (fun i-> Playwright.Locator.nth i loc |> Playwright.Locator.get_attribute ~name |> Option.value ~default:"")
let canonical current href =
  let uri=Uri.resolve "http" (Uri.of_string(base^current)) (Uri.of_string href) in
  if Uri.host uri <> Some "nas-1.tail55d152.ts.net" || Uri.port uri <> Some 4100
    || Uri.scheme uri <> Some "http" || Uri.userinfo uri <> None then None
  else let path=Uri.path uri in
    if List.exists(fun prefix->String.starts_with ~prefix path)["/api/";"/ag-ui/"]
       || Uri.query uri<>[] || has path ".." then None
    else Some (if path="" then "/" else path)
let seeds=["/";"/dashboard";"/planning";"/testing";"/features";"/knowledge-explorer";"/zk-matrix";"/pi-startup";"/verify-patrol";"/wiki";"/zk";"/km";"/adrs";"/checklist";"/fractal-matrix";"/verify-matrix";"/docs/";"/files/"]
let pages=ref seeds and results=ref [] and overflow=ref []
let persist () = write "manifest.json" (Yojson.Basic.pretty_to_string(`Assoc[
  "schema",js "uos.browser-cycles.v1";"base",js base;
  "scope",js "Read-only navigational pages and reversible controls; four Chromium passes. An observed control change is not a semantic oracle. No arbitrary function, external-site or cross-browser coverage claim.";
  "pages",`List(List.map js !pages);"unvisited_due_to_quota",`List(List.map js !overflow);
  "results",`List(List.rev !results)])^"\n")
let screenshot page name =
  let raw=Playwright.Page.screenshot ~full_page:false ~timeout:15000. page in
  let bytes=if String.starts_with ~prefix:"\137PNG" raw then raw else Base64.decode_exn raw in
  write name bytes
let page_record env browser cycle width height index route =
  let prefix=Printf.sprintf "cycle-%d-page-%04d" cycle index in
  let ctx=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width;height}
    ~has_touch:(width<840) ~is_mobile:(width<600) ~reduced_motion:`Reduce
    ~record_video:Playwright.Browser.Record_video.{dir=Some outdir;size=Some {width=800;height=600};show_actions=None} browser in
  let video=ref None in
  let record=Fun.protect ~finally:(fun()->Playwright.BrowserContext.close ctx) (fun()->
    let page=Playwright.BrowserContext.new_page ctx in
    let failures=ref [] in
    let check name ok = if not ok then failures:=name::!failures in
    let resp=Playwright.Page.goto ~url:(base^route) ~wait_until:`Domcontentloaded ~timeout:15000. page in
    Eio.Time.sleep (Eio.Stdenv.clock env) 0.15;
    let status=match resp with Some _ -> http_status(base^route) |None->0 in
    check "http_200" (status=200);
    check "navigation_landmark" (count page "nav" >0);
    check "main_landmark" (count page "main" =1);
    check "page_h1" (count page "h1"=1);
    check "document_language" (attributes page "html" "lang" <> [""]);
    check "checklist_component" (count page "details" >0);
    let content=Playwright.Page.content page in
    let title=Playwright.Page.title page in
    check "not_file_error" (not(has title "File Not Found" || has content "Failed to read file"));
    let ids=attributes page "[id]" "id" in
    check "unique_dom_ids" (List.length ids=List.length(List.sort_uniq String.compare ids));
    let hrefs=attributes page "a[href]" "href" in
    let discovered=List.filter_map(canonical route) hrefs |> List.sort_uniq String.compare in
    if cycle=1 then List.iter(fun path->if not(List.mem path !pages) then
      if List.length !pages<500 then pages:= !pages@[path] else overflow:=path::!overflow)discovered;
    let broken_fragments=List.filter(fun href->String.starts_with ~prefix:"#" href && String.length href>1
       && not(List.mem (Uri.pct_decode(String.sub href 1 (String.length href-1))) ids))hrefs in
    check "local_fragment_targets" (broken_fragments=[]);
    let controls=Playwright.Page.locator ~selector:"button,input,select,summary,a[href]" page in
    let control_count=Playwright.Locator.count controls in
    if control_count>4000 then failwith "Control quota exceeded";
    let boxes=List.init control_count(fun i->let loc=Playwright.Locator.nth i controls in
      let rect=Playwright.Locator.bounding_box ~timeout:1000. loc in
      let label=Playwright.Locator.inner_text loc |> clip in
      match rect with
      |None->`Assoc["index",`Int i;"label",js label;"visible",`Bool false]
      |Some b->
        if b.x<(-1.) || b.x+.b.width>float width+.1. then failures:=("control_overflow:"^string_of_int i)::!failures;
        `Assoc["index",`Int i;"label",js label;"visible",`Bool true;
          "box",`List(List.map(fun f->`Float f)[b.x;b.y;b.width;b.height]);
          "target_44px",`Bool(b.width>=44. && b.height>=44.)]) in
    write (prefix^"-dom.html") content;
    write (prefix^"-accessibility.txt") (Playwright.Page.aria_snapshot ~depth:12 ~timeout:10000. page);
    screenshot page (prefix^".png");
    let transitions=ref [] in
    (* Each details component is expanded and restored by actual pointer input. *)
    let summaries=Playwright.Page.locator ~selector:"details > summary" page in
    let summary_count=Playwright.Locator.count summaries in
    for i=0 to summary_count-1 do
      let loc=Playwright.Locator.nth i summaries in
      if Playwright.Locator.is_visible loc then (
        let before=attributes page "details" "open" in
        Playwright.Locator.click ~timeout:1500. loc;
        let after=count page "details[open]" in
        Playwright.Locator.click ~timeout:1500. loc;
        transitions:=`Assoc["component",js("details:"^string_of_int i);"operation",js "open_and_restore";"observed_open_count",`Int after;
          "restored",`Bool(before=attributes page "details" "open")]::!transitions)
    done;
    (* Known source-rendered controls are reversible mode/filter/query observations. *)
    let buttons=Playwright.Page.locator ~selector:"button" page in
    let n=Playwright.Locator.count buttons in
    for i=0 to n-1 do
      let loc=Playwright.Locator.nth i buttons in
      let label=Playwright.Locator.inner_text loc in
      let onclick=Playwright.Locator.get_attribute ~name:"onclick" loc |>Option.value~default:"" in
      let safe=onclick="" || has onclick "toggle" || has onclick "switchView" || has onclick "queryApi" || has onclick "fetchApi" in
      if safe && Playwright.Locator.is_visible loc && Playwright.Locator.is_enabled loc then (
        let before=Playwright.Page.content page in
        (try Playwright.Locator.click ~timeout:1500. loc;
          Eio.Time.sleep(Eio.Stdenv.clock env)0.08;
          let changed=before<>Playwright.Page.content page in
          transitions:=`Assoc["component",js("button:"^string_of_int i);"label",js(clip label);"operation",js "click";"dom_changed",`Bool changed;
            "semantic_verdict",js "REQUIRES_SPECIFIC_EXPECTED_RESULT"]::!transitions
         with exn-> failures:=("button_click_error:"^string_of_int i^":"^clip(Printexc.to_string exn))::!failures))
      else transitions:=`Assoc["component",js("button:"^string_of_int i);"label",js(clip label);"operation",js "UNRUN_HIDDEN_DISABLED_OR_EFFECT_BOUNDARY"]::!transitions
    done;
    Playwright.Page.press ~selector:"body" ~key:"Tab" ~timeout:1000. page;
    check "keyboard_focus_present" (count page ":focus"=1);
    let page_errors=Playwright.Page.page_errors page |>Array.to_list |>List.map(fun e->Playwright.SerializedError.to_yojson e |>Yojson.Safe.to_string) in
    check "no_page_errors" (page_errors=[]);
    screenshot page (prefix^"-after.png");
    video:=Playwright.Page.video page;
    `Assoc["route",js route;"cycle",`Int cycle;"viewport",`List[`Int width;`Int height];
      "http_status",`Int status;"title",js title;"controls",`List boxes;
      "transitions",`List(List.rev !transitions);"links",`List(List.map js hrefs);
      "local_fragment_failures",`List(List.map js broken_fragments);
      "violations",`List(List.map js(List.rev !failures));"page_errors",`List(List.map js page_errors);
      "status",js(if !failures=[] then "OBSERVED_CHECKS_PASS_SEMANTIC_GAPS_REMAIN" else "FAIL");
      "evidence_prefix",js prefix]) in
  Option.iter(fun v->Playwright.Artifact.save_as ~path:(outdir^"/"^prefix^".webm")v)!video;
  record
let () =
  ignore(get(OS.Dir.create ~path:true(Fpath.v outdir)));
  Eio_main.run @@ fun env -> Eio.Switch.run @@ fun sw ->
  let pw=Playwright.create ~env ~sw () in
  Fun.protect ~finally:(fun()->Playwright.destroy pw)(fun()->
    let browser=Playwright.BrowserType.launch ~executable_path:"/opt/google/chrome/chrome" ~headless:true ~timeout:20000.(Playwright.Playwright.chromium pw) in
    Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
      List.iter(fun(cycle,width,height)->
        let rec loop index = if index<List.length !pages then (
          let route=List.nth !pages index in
          let record=try page_record env browser cycle width height index route with exn->
            `Assoc["route",js route;"cycle",`Int cycle;"status",js "ERROR";"error",js(clip(Printexc.to_string exn))] in
          results:=record::!results;persist();
          Printf.printf "cycle=%d page=%d/%d %s\n%!"cycle(index+1)(List.length !pages)route;
          loop(index+1)) in loop 0
      )[1,1440,900;2,390,844;3,768,1024;4,1920,1080]));
  persist()
