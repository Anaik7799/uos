#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "eio_main";;
#require "playwright";;
#require "bos.setup";;
#require "yojson";;
(* @agent_intent Verify the actual Gleam document renderer in an isolated browser
   fixture. Four independent contexts check exact source/rendered transitions.
   No production deployment, form submission, or page-authored test JavaScript. *)
open Bos
let get = function Ok x -> x | Error (`Msg s) -> failwith s
let output = "/tmp/uos-document-navigation-fixed-browser"
let write name data = get(OS.File.write(Fpath.v(output^"/"^name))data)
let s v = `String v
let locator page selector = Playwright.Page.locator ~selector page
let count page selector = Playwright.Locator.count(locator page selector)
let screenshot page name =
  let raw=Playwright.Page.screenshot ~full_page:true ~timeout:15000. page in
  write name (if String.starts_with ~prefix:"\137PNG" raw then raw else Base64.decode_exn raw)
let () =
  ignore(get(OS.Dir.create ~path:true(Fpath.v output)));
  let records=ref [] in
  Eio_main.run @@ fun env -> Eio.Switch.run @@ fun sw ->
  let pw=Playwright.create ~env ~sw () in
  Fun.protect ~finally:(fun()->Playwright.destroy pw)(fun()->
    let browser=Playwright.BrowserType.launch ~executable_path:"/opt/google/chrome/chrome"
      ~headless:true ~timeout:20000.(Playwright.Playwright.chromium pw) in
    Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
      List.iter(fun(cycle,width,height)->
        let ctx=Playwright.Browser.new_context ~viewport:Playwright.Browser.Viewport.{width;height}
          ~has_touch:(width<840) ~is_mobile:(width<600) ~reduced_motion:`Reduce
          ~record_video:Playwright.Browser.Record_video.{dir=Some output;size=Some {width=800;height=600};show_actions=None} browser in
        let video=ref None in
        Fun.protect ~finally:(fun()->Playwright.BrowserContext.close ctx)(fun()->
          let page=Playwright.BrowserContext.new_page ctx in
          let checks=ref [] in
          let check name ok=Printf.printf "cycle=%d %s %b\n%!" cycle name ok;
            checks:=`Assoc["name",s name;"passed",`Bool ok]::!checks in
          ignore(Playwright.Page.goto ~url:"file:///tmp/uos-document-candidate-navigation-fix.html" ~wait_until:`Load ~timeout:20000. page);
          let menu=locator page ".mobile-nav-toggle" and nav=locator page ".document-nav nav" in
          if width<700 then (
            check "mobile_navigation_collapsed" (not(Playwright.Locator.is_visible nav));
            Playwright.Locator.click ~timeout:3000. menu;
            check "mobile_navigation_expands" (Playwright.Locator.is_visible nav && Playwright.Locator.get_attribute ~name:"aria-expanded" menu=Some "true");
            Playwright.Locator.click ~timeout:3000. menu;
            check "mobile_navigation_restores" (not(Playwright.Locator.is_visible nav) && Playwright.Locator.get_attribute ~name:"aria-expanded" menu=Some "false")
          ) else check "desktop_navigation_visible" (Playwright.Locator.is_visible nav);
          let rendered=locator page "#rendered-content" and raw=locator page "#raw-content" in
          check "rendered_visible_initially" (Playwright.Locator.is_visible rendered);
          check "source_hidden_initially" (not(Playwright.Locator.is_visible raw));
          check "heading_parsed" (count page "#rendered-content h1"=1);
          check "code_block_parsed" (count page "#rendered-content pre code"=1);
          check "wiki_link_preserved" (count page "#rendered-content a[href='http://nas-1.tail55d152.ts.net:4100/wiki']"=1);
          check "checklist_collapsed_initially" (count page "details.checklist-card[open]"=0);
          let source_before=Playwright.Locator.inner_text raw in
          let button=locator page "#btn-toggle" in
          Playwright.Locator.click ~timeout:3000. button;
          check "raw_mode_visible" (Playwright.Locator.is_visible raw && not(Playwright.Locator.is_visible rendered));
          check "raw_mode_preserves_source" (Playwright.Locator.inner_text raw=source_before);
          screenshot page (Printf.sprintf "cycle-%d-raw.png" cycle);
          Printf.printf "cycle=%d raw screenshot captured\n%!" cycle;
          Playwright.Locator.click ~timeout:3000. button;
          check "rendered_mode_restored" (Playwright.Locator.is_visible rendered && not(Playwright.Locator.is_visible raw));
          check "source_unchanged_after_roundtrip" (Playwright.Locator.inner_text raw=source_before);
          let summary=locator page "details.checklist-card > summary" in
          Playwright.Locator.click ~timeout:3000. summary;
          check "checklist_expands" (count page "details.checklist-card[open]"=1);
          Playwright.Locator.click ~timeout:3000. summary;
          check "checklist_restores" (count page "details.checklist-card[open]"=0);
          let errors=Playwright.Page.page_errors page |>Array.to_list|>List.map(fun e->Playwright.SerializedError.to_yojson e|>Yojson.Safe.to_string) in
          check "no_page_errors" (errors=[]);
          let prefix=Printf.sprintf "cycle-%d-rendered" cycle in
          screenshot page (prefix^".png");
          write (prefix^".html") (Playwright.Page.content page);
          write (prefix^"-accessibility.txt") (Playwright.Page.aria_snapshot ~depth:12 ~timeout:10000. page);
          let overflowing=ref [] in
          let controls=locator page "button,a[href],summary" in
          for i=0 to Playwright.Locator.count controls-1 do
            match Playwright.Locator.nth i controls |>Playwright.Locator.bounding_box ~timeout:1000. with
            | Some b when b.x < -1. || b.x+.b.width>float width+.1. -> overflowing:=i::!overflowing
            | _ -> ()
          done;
          records:=`Assoc["cycle",`Int cycle;"viewport",`List[`Int width;`Int height];
            "checks",`List(List.rev !checks);"page_errors",`List(List.map s errors);
            "overflowing_control_indices",`List(List.map(fun n->`Int n)!overflowing);
            "scope",s "Isolated actual product-renderer fixture; semantic source toggle and checklist checks. Overflow is separately reported. No live-server, sanitization, full-site or WCAG certification." ]::!records;
          video:=Playwright.Page.video page);
        Option.iter(fun v->Playwright.Artifact.save_as ~path:(output^Printf.sprintf "/cycle-%d.webm" cycle)v)!video
      )[1,1440,900;2,390,844;3,768,1024;4,1920,1080]));
  write "manifest.json" (Yojson.Basic.pretty_to_string(`Assoc["schema",s "uos.document-renderer-browser.v1";"results",`List(List.rev !records)])^"\n")
