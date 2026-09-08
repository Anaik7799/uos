(* Bounded OCaml/Playwright check of the private homeostasis HTTP handler.
   No service deployment, agent dispatch or runtime-control request is made. *)
let check name condition =
  if not condition then failwith ("FAIL: " ^ name);
  Printf.printf "PASS: %s\n%!" name

let eval page expression = Playwright.Page.evaluate ~expression page
let yes page expression = eval page expression = `Bool true
let wait page expression =
  ignore (Playwright.Page.wait_for_function ~expression ~timeout:8000. page)

let save path bytes =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () -> output_string channel bytes)

let run browser url artifacts =
  List.iter (fun width ->
    let context = Playwright.Browser.new_context
      ~viewport:Playwright.Browser.Viewport.{width; height=800}
      ~reduced_motion:`Reduce browser in
    Fun.protect ~finally:(fun () -> Playwright.BrowserContext.close context) (fun () ->
      let page = Playwright.BrowserContext.new_page context in
      ignore (Playwright.Page.goto ~url ~timeout:10000. page);
      wait page "document.getElementById('homeostasis-stream-status').textContent.includes('CONNECTED / OBSERVED')";
      check (Printf.sprintf "named SSE delivered at %dpx" width)
        (yes page "document.querySelectorAll('#homeostasis-live-stream-body tr').length>0");
      check (Printf.sprintf "no page overflow at %dpx" width)
        (yes page "document.documentElement.scrollWidth<=window.innerWidth");
      check "unknown is not healthy" (yes page "!document.body.textContent.includes('Status: ONLINE') && !document.body.textContent.includes('18/18 Checks Validated')");
      check "API returns observed VM data without invented homeostasis" (yes page "fetch('/api/v1/homeostasis').then(async r=>r.status===200 && (await r.json()).metrics===null)");
      Playwright.Page.press ~selector:".checklist-accordion > summary" ~key:"Enter" page;
      check "checklist opens with keyboard" (yes page "document.querySelector('.checklist-accordion').open");
      save (Filename.concat artifacts (Printf.sprintf "20260908-0045-homeostasis-%d.png" width))
        (Playwright.Page.screenshot ~full_page:true page);
      check "no browser script errors" (Playwright.Page.page_errors page = [||]);
      check "threshold sliders update their accessible output" (yes page "['cpu','memory'].every(function(n){var s=document.getElementById('homeostasis-'+n);s.value='0.2';s.dispatchEvent(new Event('input',{bubbles:true}));return document.getElementById('homeostasis-'+n+'-value').textContent==='0.2';})");
      ignore (eval page "document.getElementById('homeostasis-review').click();true");
      wait page "document.getElementById('homeostasis-review-result').textContent.startsWith('Denied:')";
      check "real control fails closed without authority" true;
      check "review validates threshold boundaries" (yes page "fetch('/api/v1/homeostasis/review?mode=test&cpu_limit=2').then(r=>r.status===400)");
      (* Preserve a complete field schema for injected transport faults. *)
      ignore (eval page "window.fakeFields=Array.from(document.querySelectorAll('[data-field]')).map(c=>({id:c.dataset.field,label:c.dataset.field,value:'UNKNOWN'}));true");
      (* Stop the real subscription before installing a controlled EventSource. *)
      ignore (eval page "window.dispatchEvent(new Event('pagehide')); true");
      check "pagehide visibly closes stream" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('stream closed')");
      if width=1280 then begin
        ignore (eval page "window.EventSource=class extends EventTarget{constructor(){super();window.testSource=this;this.closed=false;}close(){this.closed=true;}};eval(document.querySelector('script').textContent);true");
        ignore (eval page "testSource.onopen();for(let i=0;i<60;i++){testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:JSON.stringify({schema_version:1,control_authority:'none',fields:fakeFields,status:'unavailable',observed_at_us:null,source:'<img id=payload-executed src=x onerror=alert(1)>'})}));}true");
        check "FIFO bound 50 under burst" (yes page "document.querySelectorAll('#homeostasis-live-stream-body tr').length===50");
        check "payload is text, not executable HTML" (yes page "!document.getElementById('payload-executed') && document.querySelector('#homeostasis-live-stream-body').textContent.includes('<img')");
        ignore (eval page "testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:'not JSON'}));true");
        check "malformed frame rejected" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('rejected')");
        ignore (eval page "testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:JSON.stringify({schema_version:1,control_authority:'none',fields:[],status:'unavailable',observed_at_us:null,source:'test:incomplete'})}));true");
        check "partial schema cannot leave old measurements visible" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('rejected')&&Array.from(document.querySelectorAll('[data-field]')).every(c=>c.textContent==='UNKNOWN')");
        ignore (eval page "testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:'x'.repeat(16385)}));true");
        check "oversized frame rejected" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('rejected')");
        ignore (eval page "testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:JSON.stringify({schema_version:1,control_authority:'execute',fields:fakeFields,status:'unavailable',observed_at_us:null,source:'test:authority'})}));true");
        check "event cannot grant execution authority" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('rejected')");


        ignore (eval page "testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:JSON.stringify({schema_version:1,control_authority:'none',fields:fakeFields,status:'observed',observed_at_us:2000000,age_us:0,ttl_us:1000000,source:'test:a'})}));testSource.dispatchEvent(new MessageEvent('homeostasis_status',{data:JSON.stringify({schema_version:1,control_authority:'none',fields:fakeFields,status:'observed',observed_at_us:1000000,age_us:0,ttl_us:1000000,source:'test:a'})}));true");
        check "out-of-order frame rejected" (yes page "document.getElementById('homeostasis-stream-status').textContent.includes('rejected')");
        wait page "document.getElementById('homeostasis-stream-status').textContent.includes('source observation expired')";
        check "source TTL expires without refresh" true;
        ignore (eval page "testSource.onerror();true");
        check "disconnect does not imply health" (yes page "document.getElementById('homeostasis-stream-status').textContent.startsWith('DISCONNECTED')");
        ignore (eval page "window.dispatchEvent(new Event('pagehide'));true");
        check "fake subscription cleaned up" (yes page "testSource.closed");
        ignore (eval page "document.getElementById('homeostasis-mode').value='test';document.getElementById('homeostasis-scenario').value='disturbance';document.getElementById('homeostasis-mode-form').requestSubmit();true");
        wait page "document.getElementById('homeostasis-evidence-status').textContent.startsWith('SIMULATED')&&document.getElementById('value-cpu_pct').textContent==='98.0'";
        check "mode form routes to simulated disturbance data" true;
        ignore (eval page "document.getElementById('homeostasis-review').click();true");
        wait page "document.getElementById('homeostasis-review-result').textContent.includes('exceeds requested thresholds')";
        check "test review responds to selected fixture and thresholds" true;
        ignore (eval page "document.getElementById('homeostasis-mode').value='real';document.getElementById('homeostasis-mode-form').requestSubmit();true");
        wait page "document.getElementById('homeostasis-evidence-status').textContent.startsWith('OBSERVED')&&document.getElementById('value-cpu_pct').textContent==='UNKNOWN'";
        check "return to real data clears simulated physiology" true;
      end
    )) [320; 768; 1280]

let () =
  if Array.length Sys.argv <> 4 then failwith "usage: homeostasis_browser_check PRIVATE_URL ARTIFACT_DIR CHROME_PATH";
  let url = Sys.argv.(1) in
  if not (String.starts_with ~prefix:"http://127.0.0.1:" url) then
    failwith "private loopback fixture only";
  let driver = Filename.concat (Sys.getenv "HOME") ".cache/playwright-ocaml-driver/1.59.0/node" in
  if not (Sys.file_exists driver) then failwith "preinstalled Playwright driver required; no automatic download";
  Eio_main.run @@ fun env -> Eio.Switch.run @@ fun sw ->
  let playwright = Playwright.create ~env ~sw () in
  Fun.protect ~finally:(fun () -> Playwright.destroy playwright) (fun () ->
    let browser = Playwright.BrowserType.launch ~executable_path:Sys.argv.(3)
      ~headless:true ~timeout:15000. (Playwright.Playwright.chromium playwright) in
    Fun.protect ~finally:(fun () -> Playwright.Browser.close browser)
      (fun () -> run browser url Sys.argv.(2)))
