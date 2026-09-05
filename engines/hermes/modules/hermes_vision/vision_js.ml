(* JavaScript generated from OCaml. See vision_js.mli. *)

type expr =
  | Str of string
  | Int of int
  | Bool of bool
  | Ident of string
  | Field of expr * string
  | Call of expr * string * expr list
  | Obj of (string * expr) list
  | Arrow of string list * expr
  | Seq of expr list
  | Ternary of expr * expr * expr

let str s = Str s
let int_ n = Int n
let bool_ b = Bool b
let raw_ident s = Ident s
let field e n = Field (e, n)
let call e m args = Call (e, m, args)
let obj kvs = Obj kvs
let arrow ps b = Arrow (ps, b)
let seq es = Seq es
let ternary c t f = Ternary (c, t, f)

(* The whole point of the module: a string literal can never terminate
   the expression it sits in. *)
let quote s =
  let b = Buffer.create (String.length s + 8) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '<' -> Buffer.add_string b "\\u003c"  (* never close a <script> *)
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let ident_ok n =
  n <> ""
  && (match n.[0] with 'a' .. 'z' | 'A' .. 'Z' | '_' | '$' -> true | _ -> false)
  && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '$' -> true | _ -> false) n

let rec render = function
  | Str s -> quote s
  | Int n -> string_of_int n
  | Bool b -> if b then "true" else "false"
  | Ident s -> s
  | Field (e, n) ->
      (* a property name that is not an identifier still emits correctly,
         rather than producing source that parses as something else *)
      if ident_ok n then Printf.sprintf "%s.%s" (render e) n
      else Printf.sprintf "%s[%s]" (render e) (quote n)
  | Call (e, m, args) ->
      Printf.sprintf "%s(%s)" (render (Field (e, m)))
        (String.concat ", " (List.map render args))
  | Obj kvs ->
      Printf.sprintf "{%s}"
        (String.concat ", "
           (List.map (fun (k, v) -> Printf.sprintf "%s: %s" (quote k) (render v)) kvs))
  | Arrow (ps, body) -> Printf.sprintf "(%s) => (%s)" (String.concat ", " ps) (render body)
  | Seq es -> Printf.sprintf "(%s)" (String.concat ", " (List.map render es))
  | Ternary (c, t, f) -> Printf.sprintf "(%s ? %s : %s)" (render c) (render t) (render f)

let frame_probe ~selector ~ms ~max_frames =
  let doc = raw_ident "document" in
  let v = raw_ident "v" in
  let meta = raw_ident "meta" in
  let frames = raw_ident "frames" in
  let tick = raw_ident "tick" in
  (* one sample per composited frame: presentedFrames is a real paint
     count, unlike readyState, which a stalled player reports happily *)
  let sample =
    obj [ ("presented", field meta "presentedFrames");
          ("mediaTime", field meta "mediaTime");
          ("width", field meta "width");
          ("height", field meta "height") ]
  in
  let push = call frames "push" [ sample ] in
  let again =
    ternary
      (raw_ident (Printf.sprintf "frames.length < %d" max_frames))
      (call v "requestVideoFrameCallback" [ tick ])
      (raw_ident "null")
  in
  let tick_fn = arrow [ "now"; "meta" ] (seq [ push; again ]) in
  let quality = call v "getVideoPlaybackQuality" [] in
  let result =
    obj [ ("frames", frames);
          ("width", field v "videoWidth");
          ("height", field v "videoHeight");
          ("readyState", field v "readyState");
          ("paused", field v "paused");
          ("dropped", field quality "droppedVideoFrames");
          ("total", field quality "totalVideoFrames") ]
  in
  Printf.sprintf
    "() => new Promise((resolve) => { const v = %s; if (!v) return resolve(%s); if \
     (!v.requestVideoFrameCallback) return resolve(%s); const frames = []; const tick = %s; \
     v.requestVideoFrameCallback(tick); setTimeout(() => resolve(%s), %d); })"
    (render (call doc "querySelector" [ str selector ]))
    (render (obj [ ("error", str "no video element") ]))
    (render (obj [ ("error", str "no requestVideoFrameCallback") ]))
    (render tick_fn) (render result) ms

(* MediaRecorder over captureStream: the page records ITSELF.

   This is the capture path that needs no X server, no Playwright
   driver, and no dune-scope change — the three things that blocked
   every other route. captureStream() taps the element's own decoded
   output, so what is recorded is what the browser actually painted,
   not a screen grab of a window that may never have composited. *)
let recorder ~selector ~ms ~post_to =
  let v = raw_ident "v" in
  let stream = call v "captureStream" [] in
  Printf.sprintf
    "() => new Promise((resolve) => { const v = %s; if (!v) return resolve(%s); if \
     (!v.captureStream) return resolve(%s); const s = %s; const rec = new \
     MediaRecorder(s, { mimeType: \"video/webm\" }); const chunks = []; \
     rec.ondataavailable = (e) => (e.data.size > 0 ? chunks.push(e.data) : null); \
     rec.onstop = () => { const blob = new Blob(chunks, { type: \"video/webm\" }); \
     fetch(%s, { method: \"POST\", body: blob }).then((r) => resolve({ \"bytes\": blob.size, \
     \"status\": r.status, \"presented\": %s })).catch((e) => resolve({ \"error\": String(e) })); \
     }; rec.start(); setTimeout(() => rec.stop(), %d); })"
    (render (call (raw_ident "document") "querySelector" [ str selector ]))
    (render (obj [ ("error", str "no video element") ]))
    (render (obj [ ("error", str "captureStream unsupported") ]))
    (render stream) (render (str post_to))
    (render (field (call v "getVideoPlaybackQuality" []) "totalVideoFrames"))
    ms
