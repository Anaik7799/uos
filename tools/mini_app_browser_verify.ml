(* mini_app_browser_verify.ml — drive the Telegram Mini App surface of a
   dedicated UOS web instance through the Chrome DevTools Protocol and record
   observed evidence: one screenshot per page, a screencast video of the whole
   journey, the data API verdict for every page, the client's negative
   authentication cases, an interactive live-refresh journey, and Zenoh
   data/control traffic (start command consumed from the bus, every page
   result published to a stored key space and read back).

   What this verifies: the UOS-served Mini App pages, the client script, the
   initData HMAC validation, the per-page observers and the fail-closed paths.
   What it does not touch: the production cockpit on 4100, any Telegram
   account, any real bot token. The instance it starts is configured with a
   verification-only token minted here and never written anywhere but the
   child's environment; the initData it signs is for an allowlisted user id
   given on the command line.

   Host utilities used: google-chrome (headless, CDP), ffmpeg (frames -> mp4),
   erl from the project toolchain (uos_env). Pure OCaml otherwise:
   unix, yojson, cryptokit, base64. *)

open Unix

let member = Yojson.Basic.Util.member
let to_string_opt j = match j with `String s -> Some s | _ -> None
let now_s () = Unix.gettimeofday ()

let utc_iso t =
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (tm.tm_year + 1900) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let utc_prefix t =
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d%02d%02d-%02d%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
    tm.tm_hour tm.tm_sec

let log fmt = Printf.ksprintf (fun s -> prerr_endline ("[mini-verify] " ^ s)) fmt

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let write_file path data =
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc

let mkdir_p path =
  let parts = String.split_on_char '/' path in
  let rec go acc = function
    | [] -> ()
    | p :: rest ->
        let acc = if acc = "" then p else acc ^ "/" ^ p in
        (if acc <> "" && not (Sys.file_exists acc) then Unix.mkdir acc 0o755);
        go acc rest
  in
  go (if String.length path > 0 && path.[0] = '/' then "/" else "") parts

let sha256_hex s =
  Cryptokit.transform_string (Cryptokit.Hexa.encode ()) (Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s)

let hmac_sha256 ~key msg =
  let h = Cryptokit.MAC.hmac_sha256 key in
  h#add_string msg;
  h#result

let hex s = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) s

let pct_encode s =
  let b = Buffer.create (String.length s * 3) in
  String.iter
    (fun c ->
      match c with
      | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '~' -> Buffer.add_char b c
      | c -> Buffer.add_string b (Printf.sprintf "%%%02X" (Char.code c)))
    s;
  Buffer.contents b

let slug_of_path p =
  String.map (fun c -> if c = '/' then '-' else c) (String.sub p 1 (String.length p - 1))

(* ---------------------------------------------------------------- HTTP *)

type http_response = { status : int; headers : (string * string) list; body : string }

let split_header_body str =
  let rec find i =
    if i + 4 > String.length str then (str, "")
    else if String.sub str i 4 = "\r\n\r\n" then
      (String.sub str 0 i, String.sub str (i + 4) (String.length str - i - 4))
    else find (i + 1)
  in
  find 0

let parse_status head =
  match String.split_on_char ' ' (List.hd (String.split_on_char '\n' head)) with
  | _ :: code :: _ -> ( try int_of_string (String.trim code) with _ -> 0)
  | _ -> 0

let parse_headers head =
  List.filter_map
    (fun line ->
      match String.index_opt line ':' with
      | Some i ->
          Some
            ( String.lowercase_ascii (String.trim (String.sub line 0 i)),
              String.trim (String.sub line (i + 1) (String.length line - i - 1)) )
      | None -> None)
    (List.tl (String.split_on_char '\n' head))

let http host port meth path ?(headers = []) ?(timeout = 15.0) body =
  let s = socket PF_INET SOCK_STREAM 0 in
  setsockopt_float s SO_RCVTIMEO timeout;
  connect s (ADDR_INET (inet_addr_of_string host, port));
  let extra = String.concat "" (List.map (fun (k, v) -> k ^ ": " ^ v ^ "\r\n") headers) in
  let req =
    Printf.sprintf "%s %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\nContent-Length: %d\r\n%s\r\n%s"
      meth path host port (String.length body) extra body
  in
  ignore (send s (Bytes.of_string req) 0 (String.length req) []);
  let buf = Buffer.create 65536 in
  let chunk = Bytes.create 65536 in
  (* stop at Content-Length: the instance keeps connections open despite
     Connection: close, and waiting for EOF costs the whole receive timeout *)
  let complete () =
    let s = Buffer.contents buf in
    let head, body = split_header_body s in
    if head = s then false
    else
      match List.assoc_opt "content-length" (parse_headers head) with
      | Some n -> ( try String.length body >= int_of_string n with _ -> false)
      | None -> false
  in
  let rec loop () =
    if complete () then ()
    else
      match recv s chunk 0 65536 [] with
      | 0 -> ()
      | n ->
          Buffer.add_subbytes buf chunk 0 n;
          loop ()
      | exception Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> ()
  in
  loop ();
  close s;
  let head, body = split_header_body (Buffer.contents buf) in
  { status = parse_status head; headers = parse_headers head; body }

let http_try host port meth path ?headers ?timeout body =
  try Some (http host port meth path ?headers ?timeout body) with _ -> None

(* ------------------------------------------------------------ WebSocket *)

let connect_ws host port path =
  let s = socket PF_INET SOCK_STREAM 0 in
  connect s (ADDR_INET (inet_addr_of_string host, port));
  let req =
    Printf.sprintf
      "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
      path host port
  in
  ignore (send s (Bytes.of_string req) 0 (String.length req) []);
  let buf = Bytes.create 4096 in
  let n = recv s buf 0 4096 [] in
  let resp = Bytes.sub_string buf 0 n in
  if not (String.length resp >= 12 && String.sub resp 0 12 = "HTTP/1.1 101") then
    failwith ("WS upgrade failed: " ^ resp);
  s

let send_ws_text sock text =
  let len = String.length text in
  let header =
    if len < 126 then Bytes.of_string (Printf.sprintf "%c%c" (Char.chr 0x81) (Char.chr (0x80 lor len)))
    else if len < 65536 then
      Bytes.of_string
        (Printf.sprintf "%c%c%c%c" (Char.chr 0x81) (Char.chr (0x80 lor 126))
           (Char.chr ((len lsr 8) land 0xff))
           (Char.chr (len land 0xff)))
    else
      let b = Bytes.create 10 in
      Bytes.set b 0 (Char.chr 0x81);
      Bytes.set b 1 (Char.chr (0x80 lor 127));
      for i = 0 to 7 do
        Bytes.set b (2 + i) (Char.chr ((len lsr (8 * (7 - i))) land 0xff))
      done;
      b
  in
  let mask = Bytes.of_string "\000\000\000\000" in
  let frame = Bytes.concat Bytes.empty [ header; mask; Bytes.of_string text ] in
  let total = Bytes.length frame in
  let rec push off =
    if off < total then push (off + send sock frame off (total - off) [])
  in
  push 0

exception Ws_timeout

let recv_exact ?(timeout = 30.0) sock buf offset len =
  let rec loop pos left =
    if left = 0 then ()
    else
      let r, _, _ = select [ sock ] [] [] timeout in
      if r = [] then raise Ws_timeout
      else
        let n = recv sock buf pos left [] in
        if n = 0 then failwith "websocket closed by peer" else loop (pos + n) (left - n)
  in
  loop offset len

(* Returns None when nothing arrives within [timeout]. *)
let recv_ws_frame ?(timeout = 30.0) sock =
  let r, _, _ = select [ sock ] [] [] timeout in
  if r = [] then None
  else begin
    let hdr = Bytes.create 2 in
    recv_exact ~timeout sock hdr 0 2;
    let b0 = Char.code (Bytes.get hdr 0) in
    let b1 = Char.code (Bytes.get hdr 1) in
    let len = b1 land 0x7f in
    let actual_len =
      if len = 126 then begin
        let ext = Bytes.create 2 in
        recv_exact sock ext 0 2;
        (Char.code (Bytes.get ext 0) lsl 8) lor Char.code (Bytes.get ext 1)
      end
      else if len = 127 then begin
        let ext = Bytes.create 8 in
        recv_exact sock ext 0 8;
        let v = ref 0 in
        for i = 0 to 7 do
          v := (!v lsl 8) lor Char.code (Bytes.get ext i)
        done;
        !v
      end
      else len
    in
    let payload = Bytes.create actual_len in
    recv_exact sock payload 0 actual_len;
    let opcode = b0 land 0x0f in
    if opcode = 0x8 then failwith "websocket close frame";
    Some (opcode, Bytes.to_string payload)
  end

(* ------------------------------------------------------------------ CDP *)

type session = {
  sock : file_descr;
  target_id : string;
  mutable msg_id : int;
  mutable exceptions : string list;
  mutable console : string list;
  mutable responses : (string * int) list; (* url, status *)
  mutable frames : int;
  frames_dir : string;
  mutable screencast : bool;
  (* request interception: Chrome pauses every request; this tool fetches it
     from the instance over plain HTTP and fulfils it, so the browser's own
     network stack is never on the path. Every exchange is recorded here. *)
  mutable fetched : (string * string * int * int) list; (* method, url, status, bytes *)
  intercept_host : string;
  intercept_port : int;
  telegram_js : string option; (* cached official telegram-web-app.js body *)
}

let raw_send sess meth params =
  let id = sess.msg_id in
  sess.msg_id <- sess.msg_id + 1;
  let msg =
    Yojson.Basic.to_string
      (`Assoc [ ("id", `Int id); ("method", `String meth); ("params", `Assoc params) ])
  in
  if Sys.getenv_opt "MINI_VERIFY_DEBUG" <> None then
    log "send %d %s len=%d" id meth (String.length msg);
  send_ws_text sess.sock msg;
  id

let fulfil sess request_id code headers body =
  ignore
    (raw_send sess "Fetch.fulfillRequest"
       [ ("requestId", `String request_id); ("responseCode", `Int code);
         ("responseHeaders", `List (List.map (fun (k, v) -> `Assoc [ ("name", `String k); ("value", `String v) ]) headers));
         ("body", `String (Base64.encode_string body)) ])

let serve_intercepted sess p =
  let request_id = match member "requestId" p with `String s -> s | _ -> "" in
  let req = member "request" p in
  let url = match member "url" req with `String s -> s | _ -> "" in
  let meth = match member "method" req with `String s -> s | _ -> "GET" in
  let headers =
    match member "headers" req with
    | `Assoc l -> List.filter_map (fun (k, v) -> match v with `String s -> Some (k, s) | _ -> None) l
    | _ -> []
  in
  let post = match member "postData" req with `String s -> s | _ -> "" in
  let is_instance =
    let prefix = Printf.sprintf "http://%s:%d/" sess.intercept_host sess.intercept_port in
    String.length url >= String.length prefix && String.sub url 0 (String.length prefix) = prefix
  in
  let cors = [ ("access-control-allow-origin", "*"); ("access-control-allow-headers", "content-type"); ("access-control-allow-methods", "GET, POST, OPTIONS") ] in
  if is_instance && meth = "OPTIONS" then begin
    (* CORS preflight raised by the content-injected document (null origin) *)
    sess.fetched <- (meth, url, 204, 0) :: sess.fetched;
    fulfil sess request_id 204 cors ""
  end
  else if is_instance then begin
    let path =
      let prefix_len = String.length (Printf.sprintf "http://%s:%d" sess.intercept_host sess.intercept_port) in
      String.sub url prefix_len (String.length url - prefix_len)
    in
    let forward = List.filter (fun (k, _) -> List.mem (String.lowercase_ascii k) [ "content-type"; "accept"; "user-agent"; "accept-language" ]) headers in
    match http_try sess.intercept_host sess.intercept_port meth path ~headers:forward ~timeout:15.0 post with
    | Some r ->
        let keep = List.filter (fun (k, _) -> List.mem k [ "content-type"; "cache-control"; "x-content-type-options"; "referrer-policy"; "allow" ]) r.headers in
        sess.fetched <- (meth, url, r.status, String.length r.body) :: sess.fetched;
        fulfil sess request_id r.status (keep @ cors) r.body
    | None ->
        sess.fetched <- (meth, url, 0, 0) :: sess.fetched;
        fulfil sess request_id 502 [ ("content-type", "text/plain") ] "instance unreachable"
  end
  else if url = "https://telegram.org/js/telegram-web-app.js" then begin
    match sess.telegram_js with
    | Some body ->
        sess.fetched <- (meth, url, 200, String.length body) :: sess.fetched;
        fulfil sess request_id 200 [ ("content-type", "application/javascript") ] body
    | None ->
        sess.fetched <- (meth, url, 404, 0) :: sess.fetched;
        fulfil sess request_id 404 [ ("content-type", "text/plain") ] ""
  end
  else begin
    sess.fetched <- (meth, url, 403, 0) :: sess.fetched;
    fulfil sess request_id 403 [ ("content-type", "text/plain") ] "blocked by verifier"
  end

(* window.fetch inside a content-injected document calls the __uosFetch binding;
   the tool performs the HTTP exchange with the instance and resolves the page
   promise through Runtime.evaluate (fire-and-forget: a nested await here
   would consume the outer call's response). *)
let serve_binding sess payload =
  let j = try Yojson.Basic.from_string payload with _ -> `Null in
  let id = match member "id" j with `Int i -> i | _ -> 0 in
  let url = match member "url" j with `String s -> s | _ -> "" in
  let meth = match member "method" j with `String s -> s | _ -> "GET" in
  let body = match member "body" j with `String s -> s | _ -> "" in
  let headers = match member "headers" j with `Assoc l -> List.filter_map (fun (k, v) -> match v with `String s -> Some (String.lowercase_ascii k, s) | _ -> None) l | _ -> [] in
  let prefix = Printf.sprintf "http://%s:%d/" sess.intercept_host sess.intercept_port in
  let status, resp_headers, resp_body =
    if String.length url >= String.length prefix && String.sub url 0 (String.length prefix) = prefix then begin
      let path = String.sub url (String.length prefix - 1) (String.length url - String.length prefix + 1) in
      match http_try sess.intercept_host sess.intercept_port meth path ~headers ~timeout:15.0 body with
      | Some r -> (r.status, List.filter (fun (k, _) -> k = "content-type") r.headers, r.body)
      | None -> (0, [], "")
    end
    else (403, [ ("content-type", "text/plain") ], "blocked by verifier")
  in
  sess.fetched <- (meth, url, status, String.length resp_body) :: sess.fetched;
  let expr =
    Printf.sprintf "window.__uosResolve(%d,%d,%s,%s);'resolved'" id status
      (Yojson.Basic.to_string (`Assoc (List.map (fun (k, v) -> (k, `String v)) resp_headers)))
      (Yojson.Basic.to_string (`String resp_body))
  in
  ignore (raw_send sess "Runtime.evaluate" [ ("expression", `String expr); ("returnByValue", `Bool true) ])

let handle_event sess j =
  match member "method" j with
  | `String "Fetch.requestPaused" -> serve_intercepted sess (member "params" j)
  | `String "Runtime.bindingCalled" -> (
      match member "params" j |> member "name" with
      | `String "__uosFetch" -> serve_binding sess (match member "params" j |> member "payload" with `String s -> s | _ -> "")
      | _ -> ())
  | `String "Runtime.exceptionThrown" ->
      let d = member "params" j |> member "exceptionDetails" in
      let text =
        match member "exception" d |> member "description" with
        | `String s -> s
        | _ -> ( match member "text" d with `String s -> s | _ -> Yojson.Basic.to_string d)
      in
      sess.exceptions <- text :: sess.exceptions
  | `String "Runtime.consoleAPICalled" ->
      let args = member "params" j |> member "args" in
      let text =
        match args with
        | `List l ->
            String.concat " "
              (List.map (fun a -> match member "value" a with `String s -> s | v -> Yojson.Basic.to_string v) l)
        | _ -> ""
      in
      sess.console <- text :: sess.console
  | `String "Network.responseReceived" ->
      let r = member "params" j |> member "response" in
      let url = match member "url" r with `String s -> s | _ -> "" in
      let status = match member "status" r with `Int i -> i | _ -> 0 in
      sess.responses <- (url, status) :: sess.responses
  | `String "Page.screencastFrame" ->
      let p = member "params" j in
      (match member "data" p with
      | `String b64 ->
          sess.frames <- sess.frames + 1;
          let path = Printf.sprintf "%s/frame-%05d.jpg" sess.frames_dir sess.frames in
          (match Base64.decode b64 with Ok bytes -> write_file path bytes | Error _ -> ())
      | _ -> ());
      let sid = match member "sessionId" p with `Int i -> i | _ -> 0 in
      ignore (raw_send sess "Page.screencastFrameAck" [ ("sessionId", `Int sid) ])
  | _ -> ()

(* Read frames until the response with [id] arrives; events are dispatched. *)
let debug = Sys.getenv_opt "MINI_VERIFY_DEBUG" <> None

let await_response sess id =
  let rec wait () =
    match recv_ws_frame ~timeout:30.0 sess.sock with
    | None -> failwith (Printf.sprintf "CDP response %d timed out" id)
    | Some (op, frame) when op = 0x1 -> (
        if debug then
          log "await %d: op=%d len=%d head=%s" id op (String.length frame)
            (String.sub frame 0 (min 110 (String.length frame)));
        let j = Yojson.Basic.from_string frame in
        match member "id" j with
        | `Int rid when rid = id -> j
        | `Int _ -> wait ()
        | _ ->
            handle_event sess j;
            wait ())
    | Some (op, frame) ->
        if debug then log "await %d: non-text op=%d len=%d" id op (String.length frame);
        wait ()
  in
  wait ()

let cdp sess meth params = await_response sess (raw_send sess meth params)

(* Drain events for [seconds]; keeps screencast frames flowing. *)
let pump sess seconds =
  let deadline = now_s () +. seconds in
  let rec loop () =
    let left = deadline -. now_s () in
    if left > 0.0 then
      match recv_ws_frame ~timeout:left sess.sock with
      | None -> ()
      | Some (op, frame) ->
          (if op = 0x1 then
             let j = Yojson.Basic.from_string frame in
             match member "id" j with `Int _ -> () | _ -> handle_event sess j);
          loop ()
  in
  loop ()

let eval_js sess expr =
  let resp =
    cdp sess "Runtime.evaluate"
      [ ("expression", `String expr); ("returnByValue", `Bool true); ("awaitPromise", `Bool true) ]
  in
  let res = member "result" resp |> member "result" in
  match member "value" res with
  | `String s -> s
  | `Bool b -> string_of_bool b
  | `Int i -> string_of_int i
  | `Float f -> Printf.sprintf "%g" f
  | `Null -> "null"
  | v -> Yojson.Basic.to_string v

let open_session cdp_port frames_dir ~intercept_host ~intercept_port ~telegram_js =
  let r = http "127.0.0.1" cdp_port "PUT" "/json/new?about:blank" "" in
  let j = Yojson.Basic.from_string r.body in
  let target_id = match member "id" j with `String s -> s | _ -> failwith "no target id" in
  let ws_url = match member "webSocketDebuggerUrl" j with `String s -> s | _ -> failwith "no ws url" in
  let idx = String.index_from ws_url 5 '/' in
  let path = String.sub ws_url idx (String.length ws_url - idx) in
  let sock = connect_ws "127.0.0.1" cdp_port path in
  let sess =
    { sock; target_id; msg_id = 1; exceptions = []; console = []; responses = []; frames = 0; frames_dir; screencast = false;
      fetched = []; intercept_host; intercept_port; telegram_js }
  in
  ignore (cdp sess "Page.enable" []);
  ignore (cdp sess "Runtime.enable" []);
  ignore (cdp sess "Runtime.addBinding" [ ("name", `String "__uosFetch") ]);
  ignore (cdp sess "Network.enable" []);
  ignore
    (cdp sess "Fetch.enable"
       [ ("patterns", `List [ `Assoc [ ("urlPattern", `String "*"); ("requestStage", `String "Request") ] ]) ]);
  ignore
    (cdp sess "Emulation.setDeviceMetricsOverride"
       [ ("width", `Int 430); ("height", `Int 932); ("deviceScaleFactor", `Int 2); ("mobile", `Bool true) ]);
  sess

let close_session cdp_port sess =
  (try ignore (cdp sess "Page.stopScreencast" []) with _ -> ());
  (try close sess.sock with _ -> ());
  ignore (http_try "127.0.0.1" cdp_port "GET" ("/json/close/" ^ sess.target_id) "")

let navigate sess url =
  let id = raw_send sess "Page.navigate" [ ("url", `String url) ] in
  ignore (await_response sess id);
  (* wait for the load event, dispatching everything else *)
  let deadline = now_s () +. 20.0 in
  let rec wait () =
    if now_s () < deadline then
      match recv_ws_frame ~timeout:(deadline -. now_s ()) sess.sock with
      | None -> false
      | Some (op, frame) when op = 0x1 -> (
          let j = Yojson.Basic.from_string frame in
          match member "method" j with
          | `String "Page.loadEventFired" -> true
          | `String _ ->
              handle_event sess j;
              wait ()
          | _ -> wait ())
      | Some _ -> wait ()
    else false
  in
  wait ()

(* Alternative load path for shells where Chrome's main-frame navigation never
   completes (wave 7a, L-38): the page HTML is fetched by this tool, a <base>
   pointing at the instance is inserted, the signed initData is placed in the
   blank frame's location hash, and the document is installed with
   Page.setDocumentContent. Every subresource (official Telegram script,
   client.js, the data API POST and its CORS preflight) then reaches the Fetch
   interception layer and is served by this tool. Returns the frame id. *)
let load_by_content sess ~instance_host ~instance_port ~path ~hash_param =
  match http_try instance_host instance_port "GET" path ~timeout:10.0 "" with
  | Some r when r.status = 200 ->
      let base = Printf.sprintf "<base href=\"http://%s:%d%s\">" instance_host instance_port path in
      (* the two external script tags are replaced by inline copies at the end
         of the body, and window.fetch is routed through the __uosFetch binding
         so no browser-side network request is needed at all *)
      let script_tags =
        "<script defer src=\"https://telegram.org/js/telegram-web-app.js\"></script><script defer src=\"/mini-app/client.js\"></script>"
      in
      let strip s =
        match String.index_opt s '<' with
        | None -> s
        | Some _ ->
            let n = String.length script_tags in
            let rec go i acc =
              if i + n <= String.length s && String.sub s i n = script_tags then go (i + n) acc
              else if i < String.length s then go (i + 1) (acc ^ String.make 1 s.[i])
              else acc
            in
            go 0 ""
      in
      let client_js =
        match http_try instance_host instance_port "GET" "/mini-app/client.js" ~timeout:10.0 "" with
        | Some c when c.status = 200 -> c.body
        | _ -> ""
      in
      let shim =
        "<script>window.__uosPending={};window.__uosSeq=0;\n"
        ^ "window.fetch=function(url,opts){return new Promise(function(res,rej){var id=++window.__uosSeq;window.__uosPending[id]={res:res,rej:rej};"
        ^ "var h={};if(opts&&opts.headers){for(var k in opts.headers){h[k]=opts.headers[k];}}"
        ^ "window.__uosFetch(JSON.stringify({id:id,url:new URL(url,document.baseURI).href,method:(opts&&opts.method)||'GET',headers:h,body:(opts&&opts.body)||null}));});};\n"
        ^ "window.__uosResolve=function(id,status,headers,body){var p=window.__uosPending[id];if(!p)return;delete window.__uosPending[id];"
        ^ "if(status===0){p.rej(new TypeError('instance unreachable'));return;}var r=new Response(body,{status:status,headers:headers});p.res(r);};</script>\n"
      in
      let inline = shim ^ "<script>" ^ (match sess.telegram_js with Some t -> t | None -> "") ^ "</script>\n<script>" ^ client_js ^ "</script>\n" in
      let body0 = strip r.body in
      let html =
        let with_base =
          let lower = String.lowercase_ascii body0 in
          let rec find i = if i + 5 > String.length lower then None else if String.sub lower i 5 = "<head" then Some i else find (i + 1) in
          match find 0 with
          | Some i ->
              let close = String.index_from body0 i '>' in
              String.sub body0 0 (close + 1) ^ base ^ String.sub body0 (close + 1) (String.length body0 - close - 1)
          | None -> base ^ body0
        in
        let lower = String.lowercase_ascii with_base in
        let marker = "</body>" in
        let rec find i = if i + 7 > String.length lower then None else if String.sub lower i 7 = marker then Some i else find (i + 1) in
        match find 0 with
        | Some i -> String.sub with_base 0 i ^ inline ^ String.sub with_base i (String.length with_base - i)
        | None -> with_base ^ inline
      in
      (* about:blank needs no load-event wait; waiting for one costs 20 s per page *)
      ignore (cdp sess "Page.navigate" [ ("url", `String "about:blank") ]);
      pump sess 0.3;
      ignore (eval_js sess (Printf.sprintf "location.hash=%s;'hash'" (Yojson.Basic.to_string (`String hash_param))));
      let tree = cdp sess "Page.getFrameTree" [] in
      let frame_id = match member "result" tree |> member "frameTree" |> member "frame" |> member "id" with `String s -> s | _ -> "" in
      ignore (cdp sess "Page.setDocumentContent" [ ("frameId", `String frame_id); ("html", `String html) ]);
      pump sess 1.0;
      true
  | _ -> false

let screenshot sess path =
  let r = cdp sess "Page.captureScreenshot" [ ("format", `String "png") ] in
  match member "result" r |> member "data" with
  | `String b64 -> (
      match Base64.decode b64 with
      | Ok bytes ->
          write_file path bytes;
          String.length bytes
      | Error _ -> 0)
  | _ -> 0

(* ------------------------------------------------------- initData mint *)

type mint = { init_data : string; auth_date : int; user_json : string; hash : string }

let mint_init_data ~token ~user_id ~auth_date ?(tamper = false) ?(omit_user = false) () =
  let user_json =
    Printf.sprintf
      "{\"id\":%d,\"first_name\":\"UOS Verifier\",\"last_name\":\"CDP\",\"username\":\"uos_verifier\",\"language_code\":\"en\"}"
      user_id
  in
  let params =
    [ ("auth_date", string_of_int auth_date); ("query_id", "AAHdF6IQAAAAAN0XohDhrOrc") ]
    @ if omit_user then [] else [ ("user", user_json) ]
  in
  let sorted = List.sort (fun (a, _) (b, _) -> compare a b) params in
  let dcs = String.concat "\n" (List.map (fun (k, v) -> k ^ "=" ^ v) sorted) in
  let secret = hmac_sha256 ~key:"WebAppData" token in
  let h = hex (hmac_sha256 ~key:secret dcs) in
  let h =
    if tamper then
      let last = h.[63] in
      String.sub h 0 63 ^ String.make 1 (if last = '0' then '1' else '0')
    else h
  in
  let qs = String.concat "&" (List.map (fun (k, v) -> k ^ "=" ^ pct_encode v) params) ^ "&hash=" ^ h in
  { init_data = qs; auth_date; user_json; hash = h }

(* --------------------------------------------------------------- Zenoh *)

let zenoh_put base key value =
  let host, port =
    match String.split_on_char ':' (List.nth (String.split_on_char '/' base) 2) with
    | [ h; p ] -> (h, int_of_string p)
    | [ h ] -> (h, 8080)
    | _ -> ("127.0.0.1", 8080)
  in
  match
    http_try host port "PUT" ("/" ^ key) ~headers:[ ("content-type", "application/json") ] ~timeout:5.0 value
  with
  | Some r -> r.status
  | None -> 0

let zenoh_get base key =
  let host, port =
    match String.split_on_char ':' (List.nth (String.split_on_char '/' base) 2) with
    | [ h; p ] -> (h, int_of_string p)
    | [ h ] -> (h, 8080)
    | _ -> ("127.0.0.1", 8080)
  in
  match http_try host port "GET" ("/" ^ key) ~timeout:5.0 "" with
  | Some r when r.status = 200 -> (
      try
        match Yojson.Basic.from_string r.body with
        | `List (first :: _) -> Some (member "value" first)
        | _ -> None
      with _ -> None)
  | _ -> None

(* ------------------------------------------------------------- Chrome *)

let spawn_chrome chrome cdp_port profile log_path =
  let args =
    [| chrome; "--headless=new"; "--no-sandbox"; "--disable-gpu"; "--hide-scrollbars"; "--no-first-run";
       "--disable-extensions"; "--disable-background-networking"; "--window-size=430,932";
       "--remote-debugging-port=" ^ string_of_int cdp_port; "--user-data-dir=" ^ profile; "about:blank" |]
  in
  let fd = openfile log_path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 in
  let pid = create_process chrome args stdin fd fd in
  close fd;
  pid

let wait_http host port path timeout =
  let deadline = now_s () +. timeout in
  let rec loop () =
    match http_try host port "GET" path ~timeout:2.0 "" with
    | Some r when r.status > 0 -> Some r
    | _ ->
        if now_s () < deadline then (
          sleepf 0.5;
          loop ())
        else None
  in
  loop ()

(* ------------------------------------------------------- UOS instance *)

(* The server also opens TLS on port+1 and panics without priv/ssl/{cert,key}.pem
   relative to its working directory. The instance therefore runs from its own
   directory under the output tree with a throwaway self-signed pair minted by
   the host's openssl; no production key is read or copied. *)
let ensure_throwaway_tls cwd =
  let ssl = Filename.concat cwd "priv/ssl" in
  mkdir_p ssl;
  let cert = Filename.concat ssl "cert.pem" and key = Filename.concat ssl "key.pem" in
  if not (Sys.file_exists cert && Sys.file_exists key) then begin
    let pid =
      create_process "openssl"
        [| "openssl"; "req"; "-x509"; "-newkey"; "rsa:2048"; "-nodes"; "-days"; "1"; "-subj";
           "/CN=mini-app-verify.invalid"; "-keyout"; key; "-out"; cert |]
        stdin stderr stderr
    in
    match waitpid [] pid with
    | _, WEXITED 0 -> ()
    | _ -> failwith "openssl could not mint the throwaway certificate"
  end

let spawn_instance ~app_dir ~cwd ~port ~env_extra ~log_path =
  ensure_throwaway_tls cwd;
  let build = Filename.concat app_dir "build/dev/erlang" in
  let ebins =
    Array.to_list (Sys.readdir build)
    |> List.map (fun d -> Filename.concat (Filename.concat build d) "ebin")
    |> List.filter Sys.file_exists
  in
  let pa = List.concat_map (fun e -> [ "-pa"; e ]) ebins in
  let eval = Printf.sprintf "cepaf_gleam@web@server:start(%d), timer:sleep(infinity)." port in
  let argv = Array.of_list ([ "erl"; "-noshell" ] @ pa @ [ "-eval"; eval ]) in
  let env = Array.append (Unix.environment ()) (Array.of_list env_extra) in
  match fork () with
  | 0 ->
      (try
         chdir cwd;
         let fd = openfile log_path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 in
         dup2 fd stdout;
         dup2 fd stderr;
         close fd;
         execvpe "erl" argv env
       with e ->
         prerr_endline ("instance exec failed: " ^ Printexc.to_string e);
         exit 127)
  | pid -> pid

let kill_tree pid =
  (try kill pid Sys.sigterm with _ -> ());
  (try ignore (waitpid [ WNOHANG ] pid) with _ -> ());
  sleepf 1.0;
  (try kill pid Sys.sigkill with _ -> ());
  try ignore (waitpid [] pid) with _ -> ()

(* --------------------------------------------------------------- main *)

let pages =
  [ "/mini-app/dashboard"; "/mini-app/health"; "/mini-app/alerts"; "/mini-app/immune"; "/mini-app/tasks";
    "/mini-app/inference"; "/mini-app/chat"; "/mini-app/config"; "/mini-app/containers"; "/mini-app/federation";
    "/mini-app/verify"; "/mini-app/fmea"; "/mini-app/telemetry"; "/mini-app/zenoh" ]

let terminal_status s =
  s <> "" && s <> "Loading current data…"
  && (String.length s >= 11 && String.sub s 0 11 = "Observed at"
     || List.exists (fun p -> String.length s >= String.length p && String.sub s 0 (String.length p) = p)
          [ "Authentication"; "Access to"; "The data"; "The available observation"; "Telegram authentication" ])

let probe_js =
  "JSON.stringify({status:(document.getElementById('mini-status')||{}).textContent||'',fields:document.querySelectorAll('#mini-fields dt').length,tg:!!(window.Telegram&&window.Telegram.WebApp&&window.Telegram.WebApp.initData),page:(document.getElementById('mini-app')||{dataset:{}}).dataset.page||'',topics:document.querySelectorAll('#mini-topic option').length,title:document.title,live:(document.getElementById('mini-live-status')||{}).textContent||''})"

let settle sess timeout =
  let deadline = now_s () +. timeout in
  let rec loop last =
    let raw = eval_js sess probe_js in
    let j = Yojson.Basic.from_string raw in
    let status = match member "status" j with `String s -> s | _ -> "" in
    if terminal_status status || now_s () >= deadline then j
    else (
      pump sess 0.25;
      loop j)
  in
  loop `Null

let str j k = match member k j with `String s -> s | `Null -> "" | v -> Yojson.Basic.to_string v
let int_of j k = match member k j with `Int i -> i | _ -> 0

let api_probe host port init_data path =
  let body = Yojson.Basic.to_string (`Assoc [ ("init_data", `String init_data); ("path", `String path) ]) in
  match
    http_try host port "POST" "/mini-app/api/data" ~headers:[ ("content-type", "application/json") ] ~timeout:10.0 body
  with
  | None -> (0, "unreachable", 0)
  | Some r ->
      let st, nf =
        try
          let j = Yojson.Basic.from_string r.body in
          ( (match member "status" j with `String s -> s | _ -> (match member "error" j with `String e -> e | _ -> "")),
            match member "fields" j with `Assoc l -> List.length l | _ -> 0 )
        with _ -> ("", 0)
      in
      (r.status, st, nf)

let () =
  let base = ref "http://127.0.0.1:4190" in
  let user_id = ref 0 in
  let out = ref "" in
  let cdp_port = ref 9333 in
  let chrome = ref "google-chrome" in
  let ffmpeg = ref "ffmpeg" in
  let zenoh = ref "http://127.0.0.1:8080" in
  let run_id = ref "" in
  let app_dir = ref "" in
  let plan = ref "" in
  let candidate = ref "" in
  let require_start = ref false in
  let set_content = ref false in
  Arg.parse
    [ ("--base", Arg.Set_string base, "instance base URL (default http://127.0.0.1:4190)");
      ("--user-id", Arg.Set_int user_id, "allowlisted Telegram user id to sign initData for");
      ("--out", Arg.Set_string out, "output directory for screens, frames, video, receipt");
      ("--cdp-port", Arg.Set_int cdp_port, "Chrome DevTools port (default 9333)");
      ("--chrome", Arg.Set_string chrome, "chrome binary");
      ("--ffmpeg", Arg.Set_string ffmpeg, "ffmpeg binary");
      ("--zenoh", Arg.Set_string zenoh, "Zenoh REST base (default http://127.0.0.1:8080)");
      ("--run-id", Arg.Set_string run_id, "run identifier (default UTC prefix)");
      ("--app-dir", Arg.Set_string app_dir, "apps/cepaf_gleam dir; when given, a dedicated instance is started on the base port");
      ("--plan", Arg.Set_string plan, "Sa-plan id for the tasks page observer");
      ("--candidate", Arg.Set_string candidate, "candidate commit recorded in the receipt");
      ("--require-zenoh-start", Arg.Set require_start, "refuse to run until a start command is read from Zenoh");
      ("--set-content", Arg.Set set_content, "load pages by Page.setDocumentContent with every subresource served through Fetch interception (for shells where main-frame navigation never completes)") ]
    (fun _ -> ())
    "mini_app_browser_verify";
  if !user_id = 0 || !out = "" then (
    prerr_endline "usage: --user-id N --out DIR [--app-dir apps/cepaf_gleam] [--plan ID] ...";
    exit 2);
  let started = now_s () in
  if !run_id = "" then run_id := utc_prefix started;
  let host, port =
    match String.split_on_char ':' (List.nth (String.split_on_char '/' !base) 2) with
    | [ h; p ] -> (h, int_of_string p)
    | _ -> ("127.0.0.1", 4190)
  in
  let out = !out in
  let screens = Filename.concat out "screens" and frames = Filename.concat out "frames" in
  List.iter mkdir_p [ out; screens; frames; Filename.concat out "profile" ];
  let zk = "indrajaal/telegram/mini_app_verify/" ^ !run_id in
  (* control plane: the start command must be on the bus *)
  let zenoh_control =
    if !require_start then (
      let deadline = now_s () +. 60.0 in
      let rec wait () =
        match zenoh_get !zenoh (zk ^ "/cmd") with
        | Some (`String "start") -> "start_consumed"
        | Some (`Assoc _ as v) when (match member "command" v with `String "start" -> true | _ -> false) -> "start_consumed"
        | _ -> if now_s () < deadline then (sleepf 0.5; wait ()) else "start_missing"
      in
      let r = wait () in
      if r <> "start_consumed" then (
        log "no start command on %s/cmd; refusing to run" zk;
        exit 3);
      r)
    else "not_required"
  in
  (* verification-only token: random, never persisted *)
  let token =
    let rng = Cryptokit.Random.device_rng "/dev/urandom" in
    let raw = Cryptokit.Random.string rng 24 in
    "4190" ^ string_of_int (int_of_float (now_s ()) mod 1_000_000) ^ ":VERIFY" ^ hex raw
  in
  (* every child is killed on any exit path, including an uncaught exception *)
  let children : int list ref = ref [] in
  at_exit (fun () -> List.iter kill_tree !children);
  (* the official Telegram Web App script is fetched once by the host's curl
     (plain OCaml has no TLS here) and served to the browser through the
     interception layer, so the real library parses the signed initData *)
  let telegram_js =
    let path = Filename.concat out "telegram-web-app.js" in
    let pid =
      create_process "curl" [| "curl"; "-s"; "-m"; "20"; "-o"; path; "https://telegram.org/js/telegram-web-app.js" |] stdin stderr stderr
    in
    match waitpid [] pid with
    | _, WEXITED 0 when Sys.file_exists path && (stat path).st_size > 1000 -> Some (read_file path)
    | _ -> None
  in
  log "telegram-web-app.js %s" (match telegram_js with Some s -> Printf.sprintf "cached (%d bytes)" (String.length s) | None -> "unavailable; shim fallback");
  (match http_try host port "GET" "/mini-app/dashboard" ~timeout:2.0 "" with
  | Some r when !app_dir <> "" ->
      log "port %d already answers (%d); a stale instance is running, refusing to start another" port r.status;
      exit 6
  | _ -> ());
  let instance_pid =
    if !app_dir <> "" then begin
      let env =
        [ "UOS_TELEGRAM_MINI_BOT_TOKEN=" ^ token;
          Printf.sprintf "UOS_TELEGRAM_MINI_IDENTITIES=[{\"user_id\":%d}]" !user_id;
          (* grants are concrete keys (zenoh/rest.valid_key admits no wildcard): the
             start command, the first page's result and the run summary *)
          Printf.sprintf
            "UOS_TELEGRAM_MINI_ZENOH_GRANTS=[{\"user_id\":%d,\"topic\":\"%s/cmd\"},{\"user_id\":%d,\"topic\":\"%s/page/mini-app-dashboard\"},{\"user_id\":%d,\"topic\":\"%s/summary\"}]"
            !user_id zk !user_id zk !user_id zk ]
        @ (if !plan <> "" then [ "UOS_TELEGRAM_MINI_PLAN=" ^ !plan ] else [])
      in
      let cwd = Filename.concat out "instance" in
      mkdir_p cwd;
      let pid = spawn_instance ~app_dir:!app_dir ~cwd ~port ~env_extra:env ~log_path:(Filename.concat out "instance.log") in
      children := pid :: !children;
      log "instance pid %d on %s" pid !base;
      Some pid
    end
    else None
  in
  let finish code =
    (match instance_pid with Some pid -> kill_tree pid | None -> ());
    exit code
  in
  (match wait_http host port "/mini-app/dashboard" 60.0 with
  | Some r when r.status = 200 -> log "instance serving (%d)" r.status
  | Some r ->
      log "instance answered %d for the dashboard" r.status;
      finish 4
  | None ->
      log "instance never answered";
      finish 4);
  let chrome_pid = spawn_chrome !chrome !cdp_port (Filename.concat out "profile") (Filename.concat out "chrome.log") in
  children := chrome_pid :: !children;
  let chrome_version =
    match wait_http "127.0.0.1" !cdp_port "/json/version" 20.0 with
    | Some r -> ( try str (Yojson.Basic.from_string r.body) "Browser" with _ -> "unknown")
    | None ->
        log "chrome never answered on %d" !cdp_port;
        kill_tree chrome_pid;
        finish 5
  in
  log "chrome %s" chrome_version;
  let now_unix () = int_of_float (now_s ()) in
  let valid = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix ()) () in
  let hash_param = "#tgWebAppData=" ^ pct_encode valid.init_data ^ "&tgWebAppVersion=7.10&tgWebAppPlatform=weba" in
  let sess = open_session !cdp_port frames ~intercept_host:host ~intercept_port:port ~telegram_js in
  ignore
    (cdp sess "Page.startScreencast"
       [ ("format", `String "jpeg"); ("quality", `Int 70); ("maxWidth", `Int 430); ("maxHeight", `Int 932); ("everyNthFrame", `Int 1) ]);
  sess.screencast <- true;
  let page_results = ref [] in
  let zenoh_put_ok = ref 0 and zenoh_get_ok = ref 0 in
  let auth_sources = ref [] in
  List.iteri
    (fun i path ->
      (* fresh initData per page: the server's freshness law refuses auth_date older than 300 s *)
      let valid = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix ()) () in
      let hash_param = "#tgWebAppData=" ^ pct_encode valid.init_data ^ "&tgWebAppVersion=7.10&tgWebAppPlatform=weba" in
      let url = !base ^ path ^ hash_param in
      sess.responses <- [];
      sess.exceptions <- [];
      sess.fetched <- [];
      let loaded =
        if !set_content then load_by_content sess ~instance_host:host ~instance_port:port ~path ~hash_param
        else navigate sess url
      in
      pump sess 0.6;
      let pre = Yojson.Basic.from_string (eval_js sess probe_js) in
      let auth_source =
        if str pre "tg" = "true" then "telegram-web-app.js"
        else begin
          (* official script unavailable (offline?): install the documented shim *)
          ignore
            (eval_js sess
               (Printf.sprintf
                  "window.Telegram={WebApp:{initData:%s,platform:'uos-verify',version:'7.10',ready(){},expand(){}}};'shim'"
                  (Yojson.Basic.to_string (`String valid.init_data))));
          "shim"
        end
      in
      auth_sources := auth_source :: !auth_sources;
      ignore (eval_js sess "document.getElementById('mini-refresh').click();'clicked'");
      let settled = settle sess 12.0 in
      pump sess 0.4;
      let shot = Filename.concat screens (Printf.sprintf "%02d-%s.png" (i + 1) (slug_of_path path)) in
      let shot_bytes = screenshot sess shot in
      let api_status, api_field, api_nf = api_probe host port valid.init_data path in
      let data_calls =
        List.filter_map
          (fun (m, u, s, _) -> if m = "POST" && String.length u >= 18 && String.sub u (String.length u - 18) 18 = "/mini-app/api/data" then Some (u, s) else None)
          sess.fetched
      in
      let browser_api_status = match data_calls with (_, s) :: _ -> s | [] -> 0 in
      let intercepted =
        `List
          (List.rev_map
             (fun (m, u, s, b) -> `Assoc [ ("method", `String m); ("url", `String u); ("status", `Int s); ("bytes", `Int b) ])
             sess.fetched)
      in
      let status = str settled "status" in
      let verdict =
        if not loaded then "LOAD_TIMEOUT"
        else if String.length status >= 11 && String.sub status 0 11 = "Observed at" then "OBSERVED"
        else if status = "The data source is unavailable or not configured." then "FAIL_CLOSED_UNAVAILABLE"
        else if String.length status >= 20 && String.sub status 0 20 = "The available observ" then "STALE"
        else if status = "" then "NO_STATUS"
        else "REFUSED:" ^ status
      in
      let result =
        `Assoc
          [ ("page", `String path); ("url_loaded", `Bool loaded); ("auth_source", `String auth_source);
            ("data_page_attr", `String (str settled "page")); ("title", `String (str settled "title"));
            ("status_text", `String status); ("rendered_fields", `Int (int_of settled "fields"));
            ("topic_options", `Int (int_of settled "topics")); ("browser_api_status", `Int browser_api_status);
            ("api_http_status", `Int api_status); ("api_observation_status", `String api_field);
            ("api_fields", `Int api_nf); ("js_exceptions", `List (List.map (fun e -> `String e) sess.exceptions));
            ("intercepted", intercepted);
            ("screenshot", `String shot); ("screenshot_bytes", `Int shot_bytes); ("verdict", `String verdict) ]
      in
      let key = zk ^ "/page/" ^ slug_of_path path in
      let body = Yojson.Basic.to_string result in
      if zenoh_put !zenoh key body = 200 then incr zenoh_put_ok;
      (match zenoh_get !zenoh key with
      | Some v when Yojson.Basic.to_string v = body || (match v with `String s -> s = body | _ -> false) -> incr zenoh_get_ok
      | Some (`Assoc _ as v) when str v "page" = path -> incr zenoh_get_ok
      | _ -> ());
      log "%-24s %-26s api=%d/%s fields=%d auth=%s" path verdict api_status api_field (int_of settled "fields") auth_source;
      page_results := result :: !page_results)
    pages;
  (* interactive journey: topic selection and live refresh on the zenoh page *)
  let interactive =
    let valid = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix ()) () in
    let hash_param = "#tgWebAppData=" ^ pct_encode valid.init_data ^ "&tgWebAppVersion=7.10&tgWebAppPlatform=weba" in
    let url = !base ^ "/mini-app/zenoh" ^ hash_param in
    (if !set_content then ignore (load_by_content sess ~instance_host:host ~instance_port:port ~path:"/mini-app/zenoh" ~hash_param)
     else ignore (navigate sess url));
    pump sess 0.6;
    if str (Yojson.Basic.from_string (eval_js sess probe_js)) "tg" <> "true" then
      ignore
        (eval_js sess
           (Printf.sprintf "window.Telegram={WebApp:{initData:%s,ready(){},expand(){}}};'shim'"
              (Yojson.Basic.to_string (`String valid.init_data))));
    ignore (eval_js sess "document.getElementById('mini-refresh').click();'clicked'");
    let first = settle sess 12.0 in
    let topics = int_of first "topics" in
    if topics > 1 then begin
      ignore
        (eval_js sess
           "(()=>{const t=document.getElementById('mini-topic');t.value=t.options[1].value;t.dispatchEvent(new Event('change'));return t.value})()");
      let after_topic = settle sess 12.0 in
      ignore (eval_js sess "document.getElementById('mini-live').click();'live'");
      pump sess 5.5;
      let during = Yojson.Basic.from_string (eval_js sess probe_js) in
      let live_calls =
        List.length
          (List.filter (fun (m, u, _, _) -> m = "POST" && String.length u >= 18 && String.sub u (String.length u - 18) 18 = "/mini-app/api/data") sess.fetched)
      in
      ignore (eval_js sess "document.getElementById('mini-live').click();'stop'");
      pump sess 0.5;
      let stopped = Yojson.Basic.from_string (eval_js sess probe_js) in
      let shot = Filename.concat screens "15-zenoh-live-refresh.png" in
      let bytes = screenshot sess shot in
      `Assoc
        [ ("page", `String "/mini-app/zenoh"); ("topics_offered", `Int topics);
          ("after_topic_status", `String (str after_topic "status")); ("live_status_during", `String (str during "live"));
          ("api_calls_observed_in_session", `Int live_calls); ("live_status_after_stop", `String (str stopped "live"));
          ("screenshot", `String shot); ("screenshot_bytes", `Int bytes);
          ("verdict", `String (if live_calls >= 2 && str stopped "live" = "Live refresh stopped." then "LIVE_REFRESH_OK" else "LIVE_REFRESH_INCOMPLETE")) ]
    end
    else `Assoc [ ("page", `String "/mini-app/zenoh"); ("topics_offered", `Int topics); ("verdict", `String "NO_TOPICS_OFFERED"); ("status_text", `String (str first "status")) ]
  in
  (* negative cases on the dashboard *)
  let negative name init_data_opt expect_text expect_api =
    let url = !base ^ "/mini-app/dashboard" ^ (match init_data_opt with Some d -> "#tgWebAppData=" ^ pct_encode d ^ "&tgWebAppVersion=7.10&tgWebAppPlatform=weba" | None -> "") in
    sess.responses <- [];
    sess.fetched <- [];
    (if !set_content then
       let hp = match init_data_opt with Some d -> "#tgWebAppData=" ^ pct_encode d ^ "&tgWebAppVersion=7.10&tgWebAppPlatform=weba" | None -> "" in
       ignore (load_by_content sess ~instance_host:host ~instance_port:port ~path:"/mini-app/dashboard" ~hash_param:hp)
     else ignore (navigate sess url));
    pump sess 0.6;
    ignore (eval_js sess "document.getElementById('mini-refresh').click();'clicked'");
    let settled = settle sess 10.0 in
    let status = str settled "status" in
    let calls =
      List.filter_map
        (fun (m, u, s, _) -> if m = "POST" && String.length u >= 18 && String.sub u (String.length u - 18) 18 = "/mini-app/api/data" then Some (u, s) else None)
        sess.fetched
    in
    let api_status, api_field, _ = match init_data_opt with Some d -> api_probe host port d "/mini-app/dashboard" | None -> (0, "not_sent", 0) in
    let shot = Filename.concat screens ("neg-" ^ name ^ ".png") in
    ignore (screenshot sess shot);
    let text_ok = String.length status >= String.length expect_text && String.sub status 0 (String.length expect_text) = expect_text in
    let api_ok = expect_api = 0 || api_status = expect_api in
    `Assoc
      [ ("case", `String name); ("status_text", `String status); ("expected_text_prefix", `String expect_text);
        ("browser_api_calls", `Int (List.length calls)); ("browser_api_status", `Int (match calls with (_, s) :: _ -> s | [] -> 0));
        ("direct_api_status", `Int api_status); ("direct_api_body_status", `String api_field); ("expected_api_status", `Int expect_api);
        ("rendered_fields", `Int (int_of settled "fields")); ("screenshot", `String shot);
        ("verdict", `String (if text_ok && api_ok then "REFUSED_AS_EXPECTED" else "UNEXPECTED")) ]
  in
  let tampered = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix ()) ~tamper:true () in
  let expired = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix () - 3600) () in
  let foreign = mint_init_data ~token ~user_id:(!user_id + 1) ~auth_date:(now_unix ()) () in
  let userless = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix ()) ~omit_user:true () in
  let future = mint_init_data ~token ~user_id:!user_id ~auth_date:(now_unix () + 900) () in
  let negatives =
    [ negative "tampered-hash" (Some tampered.init_data) "Authentication expired or access is not allowed." 401;
      negative "expired-auth-date" (Some expired.init_data) "Authentication expired or access is not allowed." 401;
      negative "future-auth-date" (Some future.init_data) "Authentication expired or access is not allowed." 401;
      negative "user-not-allowlisted" (Some foreign.init_data) "Authentication expired or access is not allowed." 401;
      negative "missing-user" (Some userless.init_data) "Authentication expired or access is not allowed." 401;
      negative "no-init-data" None "Telegram authentication is unavailable." 0 ]
  in
  (* direct API hostile inputs, no browser *)
  let direct name meth path headers body expect =
    let r = http_try host port meth path ~headers ~timeout:10.0 body in
    let st = match r with Some r -> r.status | None -> 0 in
    (* any 4xx is a refusal; the expected code is recorded, a different 4xx is still fail-closed *)
    let verdict = if st = expect then "REFUSED_AS_EXPECTED" else if st >= 400 && st < 500 then "REFUSED_OTHER_4XX" else "UNEXPECTED" in
    `Assoc [ ("case", `String name); ("http_status", `Int st); ("expected", `Int expect); ("verdict", `String verdict) ]
  in
  let json_h = [ ("content-type", "application/json") ] in
  let directs =
    [ direct "GET-on-data-api" "GET" "/mini-app/api/data" [] "" 405;
      direct "unknown-page-path" "POST" "/mini-app/api/data" json_h (Yojson.Basic.to_string (`Assoc [ ("init_data", `String valid.init_data); ("path", `String "/mini-app/nope") ])) 400;
      direct "oversize-init-data" "POST" "/mini-app/api/data" json_h (Yojson.Basic.to_string (`Assoc [ ("init_data", `String (String.make 9000 'a')); ("path", `String "/mini-app/dashboard") ])) 401;
      direct "malformed-json" "POST" "/mini-app/api/data" json_h "{not json" 400;
      direct "unknown-mini-page" "GET" "/mini-app/does-not-exist" [] "" 404;
      direct "nul-byte-init-data" "POST" "/mini-app/api/data" json_h (Yojson.Basic.to_string (`Assoc [ ("init_data", `String (valid.init_data ^ "\000")); ("path", `String "/mini-app/dashboard") ])) 401 ]
  in
  (* finish the screencast and build the video *)
  pump sess 0.5;
  ignore (cdp sess "Page.stopScreencast" []);
  sess.screencast <- false;
  close_session !cdp_port sess;
  kill_tree chrome_pid;
  let video = Filename.concat out "mini-app-journey.mp4" in
  let video_ok =
    sess.frames > 0
    &&
    let pid =
      create_process !ffmpeg
        [| !ffmpeg; "-y"; "-loglevel"; "error"; "-framerate"; "3"; "-i"; Filename.concat frames "frame-%05d.jpg"; "-c:v"; "libx264";
           "-pix_fmt"; "yuv420p"; "-vf"; "scale=trunc(iw/2)*2:trunc(ih/2)*2"; video |]
        stdin stderr stderr
    in
    match waitpid [] pid with _, WEXITED 0 -> Sys.file_exists video | _ -> false
  in
  let artifact path =
    if Sys.file_exists path then
      let d = read_file path in
      `Assoc [ ("path", `String path); ("bytes", `Int (String.length d)); ("sha256", `String (sha256_hex d)) ]
    else `Assoc [ ("path", `String path); ("missing", `Bool true) ]
  in
  let pages_json = List.rev !page_results in
  let count v = List.length (List.filter (fun p -> str p "verdict" = v) pages_json) in
  let unexpected = List.length (List.filter (fun n -> str n "verdict" = "UNEXPECTED") (negatives @ directs)) in
  let finished = now_s () in
  let receipt =
    `Assoc
      [ ("schema", `String "uos-mini-app-browser-verify/v1"); ("run_id", `String !run_id); ("started_at", `String (utc_iso started));
        ("finished_at", `String (utc_iso finished)); ("base", `String !base); ("candidate", `String !candidate);
        ("chrome", `String chrome_version); ("cdp_port", `Int !cdp_port); ("user_id", `Int !user_id);
        ("token", `String "verification-only, random, never persisted"); ("zenoh_control", `String zenoh_control);
        ("zenoh_key_prefix", `String zk); ("zenoh_page_puts_ok", `Int !zenoh_put_ok); ("zenoh_page_readbacks_ok", `Int !zenoh_get_ok);
        ("auth_sources", `List (List.map (fun s -> `String s) (List.sort_uniq compare !auth_sources)));
        ("pages", `List pages_json); ("interactive", interactive); ("negative_cases", `List negatives); ("direct_api_cases", `List directs);
        ("screencast_frames", `Int sess.frames); ("video", artifact video);
        ("screenshots", `List (List.map (fun p -> artifact (str p "screenshot")) pages_json));
        ("summary",
          `Assoc
            [ ("pages_total", `Int (List.length pages_json)); ("observed", `Int (count "OBSERVED"));
              ("fail_closed_unavailable", `Int (count "FAIL_CLOSED_UNAVAILABLE")); ("stale", `Int (count "STALE"));
              ("load_timeouts", `Int (count "LOAD_TIMEOUT")); ("no_status", `Int (count "NO_STATUS"));
              ("refused", `Int (List.length (List.filter (fun p -> let v = str p "verdict" in String.length v > 8 && String.sub v 0 8 = "REFUSED:") pages_json)));
              ("negative_unexpected", `Int unexpected); ("video_ok", `Bool video_ok) ]);
        ("authority", `String "observed test evidence; grants no admission") ]
  in
  let receipt_path = Filename.concat out "receipt.json" in
  write_file receipt_path (Yojson.Basic.pretty_to_string receipt ^ "\n");
  ignore (zenoh_put !zenoh (zk ^ "/summary") (Yojson.Basic.to_string (member "summary" receipt)));
  print_endline (Yojson.Basic.to_string (member "summary" receipt));
  let ok =
    count "LOAD_TIMEOUT" = 0 && count "NO_STATUS" = 0 && unexpected = 0 && video_ok
    && List.for_all (fun p -> int_of p "screenshot_bytes" > 0) pages_json
  in
  log "receipt %s" receipt_path;
  finish (if ok then 0 else 1)
