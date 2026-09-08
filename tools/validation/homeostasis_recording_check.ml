(* Thirty verified live update cycles per recording, three browser contexts at a
   time. These are application scenario evolutions, not system deployments. *)
let components = ["provenance";"controls";"pid";"phase";"physiology";"runtime";"pareto";"quorum";"stream";"checklist"]
let tasks = List.concat_map (fun mode ->
  List.map (fun page -> (mode,page,"all")) ["homeostasis";"homeostasis/evolution";"homeostasis/terminal"]
  @ List.map (fun component -> (mode,"homeostasis/components",component)) components
) ["real";"test"]

let eval page expression = Playwright.Page.evaluate ~expression page
let check label value = if value <> `Bool true then failwith (label ^ ": " ^ Yojson.Safe.to_string value)
let safe value = String.map (function '/' -> '-' | c -> c) value
let save_json path json = let ch=open_out path in Fun.protect ~finally:(fun()->close_out ch) (fun()->output_string ch (Yojson.Safe.pretty_to_string json ^ "\n"))

let batch env browser base artifacts tasks =
  let opened = List.map (fun (mode,path,component) ->
    let name = "20260908-0045-" ^ mode ^ "-" ^ safe path ^ "-" ^ component in
    let context=Playwright.Browser.new_context
      ~viewport:Playwright.Browser.Viewport.{width=1280;height=1000}
      ~record_video:Playwright.Browser.Record_video.{dir=Some artifacts;size=Some Playwright.Browser.Size.{width=1280;height=1000};show_actions=None}
      browser in
    let page=Playwright.BrowserContext.new_page context in
    ignore (Playwright.Page.add_init_script ~source:"window.recordedFrame=null;var NativeSource=window.EventSource;window.EventSource=class extends NativeSource{constructor(url){super(url);this.addEventListener('homeostasis_status',function(e){window.recordedFrame=JSON.parse(e.data);});}};" page);
    let url=base ^ "/" ^ path ^ "?mode=" ^ mode ^ "&scenario=nominal&cycle=1&component=" ^ component in
    ignore(Playwright.Page.goto ~url ~timeout:10000. page);
    ignore(Playwright.Page.wait_for_function ~expression:"window.recordedFrame!==null" ~timeout:8000. page);
    if component="checklist" then Playwright.Page.press ~selector:".checklist-accordion > summary" ~key:"Enter" page;
    (mode,path,component,name,context,page,ref [])
  ) tasks in
  Fun.protect ~finally:(fun()->List.iter(fun(_,_,_,_,context,_,_)->try Playwright.BrowserContext.close context with _->()) opened) (fun()->
    for cycle=1 to 30 do
      Eio.Time.sleep env#clock 1.0;
      List.iter(fun(mode,path,component,name,_,page,receipts)->
        check (name ^ " field denotation") (eval page "Array.isArray(recordedFrame.fields)&&recordedFrame.fields.every(function(f){var cell=document.getElementById('value-'+f.id);return cell&&cell.textContent===f.value&&Number(cell.dataset.updates)>0;})");
        check (name ^ " source mode") (eval page (if mode="real" then "recordedFrame.status==='observed'&&recordedFrame.metrics===null&&recordedFrame.runtime.process_count>0" else "recordedFrame.status==='simulated'&&recordedFrame.observed_at_us===null"));
        check (name ^ " authority") (eval page "recordedFrame.control_authority==='none'&&!document.body.textContent.includes('Status: ONLINE')");
        if path="homeostasis/terminal" then check (name ^ " terminal refresh") (eval page "recordedFrame.fields.every(f=>document.getElementById('homeostasis-terminal').textContent.includes(f.label+': '+f.value))");
        if component="controls" && cycle=4 then
          check (name ^ " threshold outputs") (eval page "['cpu','memory'].every(function(n){var s=document.getElementById('homeostasis-'+n);s.value='0.2';s.dispatchEvent(new Event('input',{bubbles:true}));return document.getElementById('homeostasis-'+n+'-value').textContent==='0.2';})");
        if component="controls" && cycle=5 then Playwright.Page.locator ~selector:"#homeostasis-review" page |> Playwright.Locator.click;
        if component="controls" && cycle=6 then check (name ^ " review response") (eval page (if mode="real" then "document.getElementById('homeostasis-review-result').textContent.startsWith('Denied:')" else "document.getElementById('homeostasis-review-result').textContent.includes('exceeds requested thresholds')"));
        if component="all" && path<>"homeostasis/terminal" then
          ignore(eval page (Printf.sprintf "document.querySelectorAll('section[data-component]')[%d].scrollIntoView({block:'start'});true" ((cycle-1) mod 11)));
        let observed=eval page "({frames:Number(document.getElementById('frame-marker').dataset.count),status:recordedFrame.status,source_time:recordedFrame.observed_at_us,fields:recordedFrame.fields.length,generation:document.getElementById('value-generation').textContent})" in
        receipts := (`Assoc["cycle",`Int cycle;"observed",observed]) :: !receipts
      ) opened;
      Printf.printf "cycle %d/30: %d page/component views verified\n%!" cycle (List.length opened)
    done;
    List.iter(fun(mode,path,component,name,context,page,receipts)->
      check (name ^ " page errors") (`Bool (Playwright.Page.page_errors page=[||]));
      let video=Playwright.Page.video page in
      Playwright.BrowserContext.close context;
      (match video with Some artifact->Playwright.Artifact.save_as ~path:(Filename.concat artifacts (name ^ ".webm")) artifact | None->failwith "missing recorded video");
      save_json (Filename.concat artifacts (name ^ ".json")) (`Assoc[
        "mode",`String mode;"page",`String path;"component",`String component;
        "cycles",`List(List.rev !receipts);"scope",`String "private HTTP handler and browser; no production cutover";
      ]);
      Printf.printf "PASS recording: %s\n%!" name
    ) opened)

let rec chunks = function []->[] | a::b::c::rest->[a;b;c]::chunks rest | rest->[rest]
let () =
  if Array.length Sys.argv<>4 then failwith "usage: recording-check PRIVATE_BASE ARTIFACT_DIR CHROME_PATH";
  let base=Sys.argv.(1) in
  if not(String.starts_with ~prefix:"http://127.0.0.1:" base) then failwith "private loopback fixture only";
  let driver=Filename.concat(Sys.getenv "HOME") ".cache/playwright-ocaml-driver/1.59.0/node" in
  if not(Sys.file_exists driver) then failwith "preinstalled driver required";
  Eio_main.run @@ fun env -> Eio.Switch.run @@ fun sw ->
  let playwright=Playwright.create ~env ~sw () in
  Fun.protect ~finally:(fun()->Playwright.destroy playwright)(fun()->
    let browser=Playwright.BrowserType.launch ~headless:true ~executable_path:Sys.argv.(3) ~timeout:15000. (Playwright.Playwright.chromium playwright) in
    Fun.protect ~finally:(fun()->Playwright.Browser.close browser)(fun()->
      List.iter(batch env browser base Sys.argv.(2))(chunks tasks)))
