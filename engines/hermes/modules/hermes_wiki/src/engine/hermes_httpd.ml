(* The read-only static server. See hermes_httpd.mli.

   Zero dependency (Unix only — Dream is not installed on this host, R14
   says mirror the shape not the library). The route table IS the built
   site's page list: an unknown path can never become a filesystem read,
   so traversal is impossible by construction rather than by sanitizing. *)

type response = { status : int; content_type : string; body : string }

let html = "text/html; charset=utf-8"

let strip_query path =
  match String.index_opt path '?' with
  | Some i -> String.sub path 0 i
  | None -> path

let respond ~pages ~meth ~path =
  match meth with
  | "GET" | "HEAD" -> (
      let target = strip_query path in
      let name = if target = "/" || target = "" then "index.html"
        else if String.length target > 1 && target.[0] = '/' then
          String.sub target 1 (String.length target - 1)
        else target
      in
      (* Only exact page names route. Anything with a separator or a dot
         segment cannot match a page name, so it 404s without touching
         the disk. *)
      match List.assoc_opt name pages with
      | Some body ->
          { status = 200; content_type = html;
            body = (if meth = "HEAD" then "" else body) }
      | None ->
          { status = 404; content_type = html;
            body = "<h1>404</h1><p>No such page. <a href=\"/\">index</a></p>" })
  | _ ->
      { status = 405; content_type = html;
        body = "<h1>405</h1><p>This surface is read-only.</p>" }

let parse_request_line line =
  let line = String.trim line in
  match String.split_on_char ' ' line with
  | meth :: target :: _ when meth <> "" && target <> "" -> Some (meth, target)
  | _ -> None

let status_text = function
  | 200 -> "200 OK"
  | 404 -> "404 Not Found"
  | 405 -> "405 Method Not Allowed"
  | code -> string_of_int code ^ " Unknown"

(* R15: the surface must be reachable over Tailscale. The parse is pure
   over an interface listing; only obtaining the listing is IO, and it
   never raises — an absent tool is simply "no fabric", which the caller
   turns into a refusal. *)
let parse_tailscale listing =
  let is_tailscale address =
    (* Tailscale hands out 100.64.0.0/10 (CGNAT). A 100.x address outside
       that range belongs to something else and must not be trusted. *)
    match String.split_on_char '.' address with
    | [ "100"; second; _; _ ] -> (
        match int_of_string_opt second with
        | Some n -> n >= 64 && n <= 127
        | None -> false)
    | _ -> false
  in
  let candidates =
    List.concat_map
      (fun line ->
        let words =
          String.split_on_char ' ' (String.trim line)
          |> List.filter (fun w -> w <> "")
        in
        let rec after = function
          | "inet" :: value :: _ ->
              let address =
                match String.index_opt value '/' with
                | Some i -> String.sub value 0 i
                | None -> value
              in
              if is_tailscale address then [ address ] else []
          | value :: rest ->
              (* a bare "tailscale ip -4" line is just the address *)
              (if is_tailscale (String.trim value) then [ String.trim value ] else [])
              @ after rest
          | [] -> []
        in
        after words)
      (String.split_on_char '\n' listing)
  in
  match candidates with address :: _ -> Some address | [] -> None

let tailscale_address () =
  let read command =
    try
      let channel = Unix.open_process_in command in
      Fun.protect
        ~finally:(fun () -> ignore (Unix.close_process_in channel))
        (fun () ->
          let buffer = Buffer.create 4096 in
          (try
             while true do
               Buffer.add_channel buffer channel 1
             done
           with End_of_file -> ());
          Buffer.contents buffer)
    with _ -> ""
  in
  match parse_tailscale (read "ip -4 addr show 2>/dev/null") with
  | Some address -> Some address
  | None -> parse_tailscale (read "tailscale ip -4 2>/dev/null")

(* The MagicDNS name is the CANONICAL handle (R15): a Tailscale address can
   change when a node re-registers; the name does not. Parsed from the
   status JSON's Self.DNSName, trailing dot stripped. *)
let parse_fqdn text =
  let needle = "\"DNSName\":" in
  let n = String.length text and m = String.length needle in
  let rec find i =
    if i + m > n then None
    else if String.sub text i m = needle then
      match String.index_from_opt text (i + m) '"' with
      | None -> None
      | Some open_quote -> (
          match String.index_from_opt text (open_quote + 1) '"' with
          | None -> None
          | Some close_quote ->
              let value =
                String.sub text (open_quote + 1) (close_quote - open_quote - 1)
              in
              let value =
                if String.length value > 0 && value.[String.length value - 1] = '.' then
                  String.sub value 0 (String.length value - 1)
                else value
              in
              (* A MagicDNS name is host.tailnet.ts.net — require the suffix
                 so a stray field can never masquerade as one. *)
              let has_suffix suffix =
                String.length value > String.length suffix
                && String.sub value (String.length value - String.length suffix)
                     (String.length suffix)
                   = suffix
              in
              if has_suffix ".ts.net" then Some value else find (i + m))
    else find (i + 1)
  in
  find 0

let tailscale_fqdn () =
  let read command =
    try
      let channel = Unix.open_process_in command in
      Fun.protect
        ~finally:(fun () -> ignore (Unix.close_process_in channel))
        (fun () ->
          let buffer = Buffer.create 65536 in
          (try
             while true do
               Buffer.add_channel buffer channel 1
             done
           with End_of_file -> ());
          Buffer.contents buffer)
    with _ -> ""
  in
  parse_fqdn (read "tailscale status --json 2>/dev/null")

let banner ~port =
  match (tailscale_fqdn (), tailscale_address ()) with
  | Some fqdn, _ ->
      Printf.sprintf
        "hermes site: http://%s:%d/ (tailscale FQDN, R15) | http://127.0.0.1:%d/ (local)"
        fqdn port port
  | None, Some address ->
      Printf.sprintf
        "hermes site: http://%s:%d/ -- DEGRADED: tailscale address only, no MagicDNS \
         name (R15 disclosed) | http://127.0.0.1:%d/ (local)"
        address port port
  | None, None ->
      Printf.sprintf
        "hermes site: http://127.0.0.1:%d/ -- DEGRADED: no tailscale fabric (R15 disclosed)"
        port

let serve ~pages ~port =
  let listener = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt listener Unix.SO_REUSEADDR true;
  (* R15: bind ALL interfaces so the Tailscale address answers. Authority
     is unchanged — GET/HEAD only, and the route table is the page list. *)
  Unix.bind listener (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen listener 16;
  Printf.printf "%s (%d pages, read-only)\n%!" (banner ~port) (List.length pages);
  let rec accept_loop () =
    let client, _ = Unix.accept listener in
    (try
       let buffer = Bytes.create 8192 in
       let n = Unix.read client buffer 0 8192 in
       let text = Bytes.sub_string buffer 0 n in
       let first =
         match String.index_opt text '\n' with
         | Some i -> String.sub text 0 i
         | None -> text
       in
       let response =
         match parse_request_line first with
         | Some (meth, target) -> respond ~pages ~meth ~path:target
         | None -> { status = 405; content_type = html; body = "" }
       in
       let head =
         Printf.sprintf
           "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n\
            Cache-Control: no-store\r\n\
            Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; \
            img-src 'self' data:; base-uri 'none'; form-action 'none'\r\n\
            X-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n\
            Referrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
           (status_text response.status) response.content_type
           (String.length response.body)
       in
       let payload = head ^ response.body in
       ignore (Unix.write_substring client payload 0 (String.length payload))
     with _ -> ());
    (try Unix.close client with _ -> ());
    accept_loop ()
  in
  accept_loop ()
