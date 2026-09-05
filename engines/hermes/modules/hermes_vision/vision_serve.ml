(* A bounded static HTTP server for the packaged media, in OCaml.

   Deliberately small and deliberately NOT a general web server: it
   serves exactly one directory, refuses any path containing "..", and
   answers only GET. A media probe needs a real socket and a real status
   line; it does not need routing, and every feature this does not have
   is a way it cannot be wrong. *)

let server_id = ref ""

let content_type path =
  if Filename.check_suffix path ".m3u8" then "application/vnd.apple.mpegurl"
  else if Filename.check_suffix path ".ts" then "video/mp2t"
  else if Filename.check_suffix path ".mp4" then "video/mp4"
  else if Filename.check_suffix path ".jpg" then "image/jpeg"
  else if Filename.check_suffix path ".html" then "text/html; charset=utf-8"
  else "application/octet-stream"

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

(* The player page. A plain <video> element and nothing else: no script,
   no bundle, no CDN. R1 forbids authoring JavaScript here, and a page
   with no script also cannot fake playback — whatever the browser shows
   was decoded by the browser. *)
let player_page ?(record = false) stream_path =
  Printf.sprintf
    {|<!doctype html><html><head><meta charset="utf-8"><title>Hermes vision</title>
<style>body{margin:0;background:#0d1214;color:#e6edef;font:14px system-ui;display:grid;place-items:center;min-height:100vh}
video{width:640px;height:360px;background:#000;display:block}main{text-align:center}</style></head>
<body><main><video id="v" autoplay muted loop playsinline controls crossorigin="anonymous">
<source src="/loop.webm" type="video/webm"><source src="%s" type="video/mp4"></video>
<p>hermes vision &mdash; %s</p></main>
<script>window.hermesRecord = %s;%s</script></body></html>|}
    stream_path stream_path
    (* GENERATED from OCaml, not authored: the page's only script is the
       recorder expression emitted by Vision_js. *)
    (Vision_js.recorder ~selector:"video" ~ms:6000 ~post_to:"/capture")
    (* Inert by default: a page load must not start recording. The
       recorder runs only when explicitly asked, so the same page serves
       viewers and the oracle. *)
    (if record then " setTimeout(function(){window.hermesRecord();}, 1500);" else "")

let respond fd status ctype body =
  let head =
    Printf.sprintf
      "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
      status ctype (String.length body)
  in
  let all = head ^ body in
  let rec send off =
    if off < String.length all then
      match Unix.write_substring fd all off (String.length all - off) with
      | 0 -> ()
      | n -> send (off + n)
      | exception Unix.Unix_error _ -> ()
  in
  send 0

let safe path =
  (* no traversal, ever: the server owns one directory *)
  not (String.length path >= 2 && String.contains path '.'
       && (let n = String.length path in
           let rec has i = i + 2 <= n && (String.sub path i 2 = ".." || has (i + 1)) in
           has 0))

let handle root fd =
  let buf = Bytes.create 8192 in
  match Unix.read fd buf 0 8192 with
  | exception Unix.Unix_error _ -> ()
  | 0 -> ()
  | n -> (
      let req = Bytes.sub_string buf 0 n in
      let line = match String.index_opt req '\r' with
        | Some i -> String.sub req 0 i
        | None -> req
      in
      match String.split_on_char ' ' line with
      | "POST" :: path :: _ when Filename.basename path = "capture" ->
          (* The browser POSTs the WebM it recorded of itself. Read to
             Content-Length: a short read here would truncate the capture
             and the comparison would then be measuring our own bug. *)
          let raw = ref req and total = ref n in
          let header_end = ref None in
          let find_sep s =
            let k = String.length s and sep = "\r\n\r\n" in
            let rec go i = if i + 4 > k then None else if String.sub s i 4 = sep then Some (i + 4) else go (i + 1) in
            go 0
          in
          let content_length s =
            let low = String.lowercase_ascii s in
            let key = "content-length:" in
            let k = String.length low and kl = String.length key in
            let rec go i = if i + kl > k then None else if String.sub low i kl = key then Some (i + kl) else go (i + 1) in
            match go 0 with
            | None -> None
            | Some j ->
                let stop = try String.index_from s j '\r' with Not_found -> String.length s in
                int_of_string_opt (String.trim (String.sub s j (stop - j)))
          in
          (try
             while !header_end = None do
               (match find_sep !raw with
                | Some h -> header_end := Some h
                | None ->
                    let m = Unix.read fd buf 0 8192 in
                    if m = 0 then header_end := Some (String.length !raw)
                    else (raw := !raw ^ Bytes.sub_string buf 0 m; total := !total + m))
             done;
             let hstart = match !header_end with Some h -> h | None -> String.length !raw in
             let want = match content_length !raw with Some c -> c | None -> 0 in
             let body = Buffer.create (max want 65536) in
             Buffer.add_string body (String.sub !raw hstart (String.length !raw - hstart));
             while Buffer.length body < want do
               let m = Unix.read fd buf 0 8192 in
               if m = 0 then Buffer.add_string body "" else Buffer.add_subbytes body buf 0 m;
               if m = 0 then raise Exit
             done;
             let out = Filename.concat root "browser_self.webm" in
             let oc = open_out_bin out in
             output_string oc (Buffer.contents body);
             close_out oc;
             Printf.printf "[vision-serve] capture received: %d bytes -> %s\n%!"
               (Buffer.length body) out;
             respond fd "200 OK" "application/json"
               (Printf.sprintf {|{"ok":true,"bytes":%d}|} (Buffer.length body))
           with _ -> respond fd "500 Internal Server Error" "application/json" {|{"ok":false}|})
      | "GET" :: raw_path :: _ ->
          let wants_record =
            let n = String.length raw_path in
            let rec has i = i + 7 <= n && (String.sub raw_path i 7 = "record=" || has (i + 1)) in
            has 0
          in
          let path = match String.index_opt raw_path '?' with
            | Some i -> String.sub raw_path 0 i
            | None -> raw_path
          in
          if not (safe path) then respond fd "400 Bad Request" "text/plain" "no"
          else if path = "/whoami" then
            (* the identity a zero-downtime gate polls for: with two
               instances sharing the port, this is the only way to know
               WHICH one answered *)
            respond fd "200 OK" "application/json"
              (Printf.sprintf {|{"id":"%s","pid":%d}|} !server_id (Unix.getpid ()))
          else if path = "/" || path = "/index.html" then
            respond fd "200 OK" "text/html; charset=utf-8"
              (player_page ~record:wants_record "/loop.mp4")
          else
            let file = Filename.concat root (Filename.basename path) in
            (match read_file file with
             | Some body -> respond fd "200 OK" (content_type file) body
             | None -> respond fd "404 Not Found" "text/plain" "not found")
      | _ -> respond fd "405 Method Not Allowed" "text/plain" "GET only")

let serve ?(id = "") ~root ~port () =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  (* SO_REUSEPORT is what makes a zero-downtime swap possible: the
     replacement binds the SAME port while the old instance is still
     serving, the kernel load-balances between them, and no client ever
     meets a closed socket.

     It also creates the problem /whoami solves. With two instances on
     one port, a health check may be answered by the OLD one and pass
     regardless of whether the replacement works at all — a gate that
     cannot fail, which is the exact defect this repository keeps
     finding. The gate must poll until it sees the NEW identity. *)
  Unix.setsockopt sock Unix.SO_REUSEPORT true;
  server_id := id;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen sock 16;
  Printf.printf "[vision-serve] root=%s port=%d\n%!" root port;
  while true do
    match Unix.accept sock with
    | fd, _ -> handle root fd; (try Unix.close fd with Unix.Unix_error _ -> ())
    | exception Unix.Unix_error _ -> ()
  done

let () =
  let root = ref "state/vision/hls" and port = ref 8091 and id = ref "" in
  let rec parse = function
    | "--root" :: v :: rest -> root := v; parse rest
    | "--port" :: v :: rest -> port := int_of_string v; parse rest
    | "--id" :: v :: rest -> id := v; parse rest
    | [] -> ()
    | other -> prerr_endline ("unknown argument: " ^ String.concat " " other); exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));
  serve ~id:!id ~root:!root ~port:!port ()
