(* Stage observations published over Zenoh. See vision_telemetry.mli. *)

type outcome = Published of string | Refused of string | Disabled of string

let outcome_name = function
  | Published _ -> "PUBLISHED"
  | Refused _ -> "REFUSED"
  | Disabled _ -> "DISABLED"

let is_published = function Published _ -> true | _ -> false

let key_for stage =
  "hermes/vision/" ^ String.lowercase_ascii (Vision_ontology.stage_name stage)

(* JSON by hand rather than through a serializer: the payload is six
   scalar fields, and the only thing that could go wrong is an unescaped
   quote in a detail string, which is handled here. *)
let terminal = ref false
let published_any = ref false

let contains hay needle =
  let n = String.length hay and k = String.length needle in
  let rec go i = i + k <= n && (String.sub hay i k = needle || go (i + 1)) in
  k > 0 && go 0

(* Anything shaped like configuration rather than observation. The mesh
   fans out to every subscriber, so this is the last point at which a
   credential can be stopped. Deliberately blunt: a redacted observation
   is still useful, a leaked key is not recoverable. *)
let secret_markers =
  [ "password="; "passwd="; "api_key="; "apikey="; "secret="; "token=";
    "authorization:"; "bearer "; "ssh-rsa"; "begin rsa"; "begin openssh"; "begin private" ]

let redact s =
  let low = String.lowercase_ascii s in
  if List.exists (fun m -> contains low m) secret_markers then
    "[redacted: looked like configuration]"
  else s

let publishable s = redact s == s

let escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let payload ~run_id (o : Vision_controller.observation) =
  let why = match o.verdict with Live s | Absent s | Unknown s -> s in
  Printf.sprintf
    {|{"run_id":"%s","stage":"%s","verdict":"%s","why":"%s","level":"%s","origin":"%s","detail":"%s","elapsed_ms":%.3f}|}
    (escape run_id)
    (escape (Vision_ontology.stage_name o.stage))
    (Vision_controller.verdict_name o.verdict)
    (escape why)
    (escape (Fractal_diagnostic.level_name o.level))
    (escape (Fractal_diagnostic.origin_name o.origin))
    (* the last point at which a credential can be stopped before the
       mesh fans it out to every subscriber *)
    (escape (redact o.detail)) o.elapsed_ms

let publish ~run_id o =
  published_any := true;
  let key = key_for o.Vision_controller.stage in
  if not (Hermes_zenoh.enabled ()) then Disabled "HERMES_ZENOH=0"
  else if not (Hermes_zenoh.valid_key key) then Refused ("invalid key expression: " ^ key)
  else
    match Hermes_zenoh.publish ~key ~payload:(payload ~run_id o) with
    | Ok () -> Published key
    | Error detail -> Refused detail

let publish_all ~run_id obs = List.map (publish ~run_id) obs

let render outs =
  let b = Buffer.create 512 in
  List.iter
    (fun o ->
      let d = match o with Published k -> k | Refused d -> d | Disabled d -> d in
      Buffer.add_string b (Printf.sprintf "  %-9s %s\n" (outcome_name o) d))
    outs;
  let missed = List.length (List.filter (fun o -> not (is_published o)) outs) in
  Buffer.add_string b
    (Printf.sprintf "telemetry: %d/%d published%s\n"
       (List.length outs - missed) (List.length outs)
       (* the number that matters: a partially published run means the
          mesh view of this pipeline is incomplete, and saying so is the
          difference between telemetry and decoration *)
       (if missed > 0 then Printf.sprintf " — %d NOT published, mesh view incomplete" missed
        else ""));
  Buffer.contents b

let note_terminal () = terminal := true
let terminal_published () = !terminal

let () =
  at_exit (fun () ->
      if !published_any && not !terminal then
        prerr_endline
          "[vision-telemetry] WARNING: observations were published and no terminal observation \
           was — the mesh's last view of this run may be a healthy one it never closed")
