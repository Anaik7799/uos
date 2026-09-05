(* OpenTelemetry emission. See the .mli. *)

type span = {
  trace_id : string;
  span_id : string;
  name : string;
  status : string;
  attributes : (string * string) list;
  duration_ms : float;
}

(* Derived, never random: a random trace id makes every run's output
   differ, which defeats the expect test guarding this format and makes
   a diff unreadable. Same run, same structure, same ids. *)
let hex_of s n = String.sub (Digest.to_hex (Digest.string s)) 0 n

let status_of = function
  | Vision_controller.Live _ -> "OK"
  | Vision_controller.Absent _ -> "ERROR"
  (* UNSET, never OK. Folding Unknown into OK is the same lie the third
     verdict exists to prevent, in someone else's vocabulary. *)
  | Vision_controller.Unknown _ -> "UNSET"

let span_of ~run_id (o : Vision_controller.observation) =
  let stage = Vision_ontology.stage_name o.Vision_controller.stage in
  let why = match o.Vision_controller.verdict with
    | Vision_controller.Live s | Vision_controller.Absent s | Vision_controller.Unknown s -> s
  in
  { trace_id = hex_of run_id 32;
    span_id = hex_of (run_id ^ "/" ^ stage) 16;
    name = "vision." ^ String.lowercase_ascii stage;
    status = status_of o.Vision_controller.verdict;
    attributes =
      [ ("hermes.run_id", run_id);
        ("hermes.stage", stage);
        ("hermes.verdict", Vision_controller.verdict_name o.Vision_controller.verdict);
        ("hermes.fractal_level", Fractal_diagnostic.level_name o.Vision_controller.level);
        ("hermes.rca_origin", Fractal_diagnostic.origin_name o.Vision_controller.origin);
        (* the FPP channel this metric is carried on — a span without one
           is a metric nothing can receive *)
        ("hermes.fpp_channel",
         "vision_" ^ String.lowercase_ascii stage ^ "_verdict");
        ("hermes.why", Vision_telemetry.redact why) ];
    duration_ms = o.Vision_controller.elapsed_ms }

let esc s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let attrs_json a =
  String.concat ","
    (List.map
       (fun (k, v) ->
         Printf.sprintf {|{"key":"%s","value":{"stringValue":"%s"}}|} (esc k) (esc v))
       a)

let span_json s =
  Printf.sprintf
    {|{"traceId":"%s","spanId":"%s","name":"%s","kind":"SPAN_KIND_INTERNAL","status":{"code":"STATUS_CODE_%s"},"durationMs":%.3f,"attributes":[%s]}|}
    s.trace_id s.span_id (esc s.name) s.status s.duration_ms (attrs_json s.attributes)

let to_otlp ~run_id obs =
  let spans = List.map (span_of ~run_id) obs in
  Printf.sprintf
    {|{"resourceSpans":[{"resource":{"attributes":[%s]},"scopeSpans":[{"scope":{"name":"hermes_vision"},"spans":[%s]}]}]}|}
    (attrs_json
       [ ("service.name", "hermes_vision"); ("hermes.run_id", run_id);
         ("hermes.fpp_instance_base", Printf.sprintf "0x%x" Vision_fpp.instance_base) ])
    (String.concat "," (List.map span_json spans))

let undeclared_channels spans =
  let declared = Vision_fpp.declared_channels () in
  List.filter_map
    (fun s ->
      match List.assoc_opt "hermes.fpp_channel" s.attributes with
      | Some c when not (List.mem c declared) -> Some c
      | _ -> None)
    spans

let append_jsonl ~path ~run_id obs =
  let spans = List.map (span_of ~run_id) obs in
  match undeclared_channels spans with
  (* refuse rather than emit a metric nothing can receive *)
  | c :: _ -> Error ("span names an undeclared FPP channel: " ^ c)
  | [] -> (
      match open_out_gen [ Open_append; Open_creat ] 0o644 path with
      | exception Sys_error e -> Error e
      | oc ->
          Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
              List.iter (fun s -> output_string oc (span_json s ^ "\n")) spans);
          Ok (List.length spans))
