(* OTel-shaped structured logging — see wiki_otel.mli. Emitter only (R4). *)

type severity = Trace | Debug | Info | Warn | Error_

let severity_number = function Trace -> 1 | Debug -> 5 | Info -> 9 | Warn -> 13 | Error_ -> 17

let severity_text = function
  | Trace -> "TRACE"
  | Debug -> "DEBUG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Error_ -> "ERROR"

type record = {
  ts : string;
  severity : severity;
  body : string;
  attrs : (string * string) list;
}

let record ~ts ~severity ~body ~attrs = { ts; severity; body; attrs }

let escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let render r =
  let attrs =
    String.concat ","
      (List.map (fun (k, v) -> Printf.sprintf "\"%s\":\"%s\"" (escape k) (escape v)) r.attrs)
  in
  Printf.sprintf
    "{\"ts\":\"%s\",\"severity_number\":%d,\"severity_text\":\"%s\",\"body\":\"%s\",\"attributes\":{%s}}"
    (escape r.ts) (severity_number r.severity) (severity_text r.severity) (escape r.body) attrs

let of_verdict ~ts = function
  | Ratchet.Held { gauge; at } ->
      record ~ts ~severity:Info ~body:"ratchet held"
        ~attrs:[ ("gauge", gauge); ("at", string_of_int at) ]
  | Ratchet.Improved { gauge; previous; current } ->
      record ~ts ~severity:Info ~body:"ratchet improved (re-pin invited)"
        ~attrs:
          [ ("gauge", gauge); ("previous", string_of_int previous);
            ("current", string_of_int current) ]
  | Ratchet.Breached { gauge; previous; current } ->
      record ~ts ~severity:Warn ~body:"RATCHET BREACHED"
        ~attrs:
          [ ("gauge", gauge); ("previous", string_of_int previous);
            ("current", string_of_int current) ]

let state_transition ~ts ~actor ~from_ ~to_ =
  record ~ts ~severity:Info ~body:"state transition"
    ~attrs:[ ("actor", actor); ("from", from_); ("to", to_) ]
