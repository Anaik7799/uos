(* json_embed — JSON as a typed value, and its ONE embedding into an HTML
   script element.

   THE DEFECT THIS REPLACES. Three routes built JSON by string concatenation and
   spliced it into a script body. `/vegalite` interpolated SQLite values with no
   escaping at all; `/grid` used a local escaper handling exactly backslash and
   double-quote. Neither handled a control character (a raw newline is illegal
   inside a JSON string and breaks the parse) and neither handled the sequence
   that actually matters in this context: an end-script tag inside a string
   value terminates the script ELEMENT early, because HTML tokenizes script
   content before JavaScript ever sees it. The value is then markup.

   WHY THE ENCODER IS CUSTOM AND THE PARSER IS NOT. Yojson is already a
   dependency of this project, and it is the parser here. It is NOT the
   encoder, for a reason that was measured rather than assumed:

     Yojson.Safe.to_string (`Assoc ["x", `String "</script>&<"])
       =  {"x":"</script>&<"}

   Yojson emits the end-script tag raw, which is precisely the hazard. So the
   WRITER is ours and the READER is Yojson's — and that split is better than
   owning both, because an oracle written by the same author shares that
   author's misconceptions. (The same reasoning the HTML tokenizer slice
   recorded in DIVERGENCE 760.) A first version of this module shipped a
   hand-written parser; it accepted `01` and round-tripped integral floats as
   integers. Both were caught by the laws, and both are defects Yojson does not
   have.

   Ontology
     Carrier      `t` — the JSON value grammar of RFC 8259.
     Denotation   a byte string that is valid JSON AND inert inside a script
                  element.
     Operations   the constructors, and `to_string`.
     Observations `Yojson.Safe.from_string`, the independent oracle.

   ORACLE vs FINAL. `to_string` is the final encoding; Yojson is the oracle.
   The specification is `Yojson.Safe.from_string (to_string v) = to_yojson v`
   for every `v` — a reader that shares none of the writer's code recovers
   exactly what the writer meant.

   SAFE BY CONSTRUCTION, NOT BY DISCIPLINE. There is no second, faster,
   unescaped encoder to reach for by accident: `<`, `>` and `&` are ALWAYS
   emitted as `\uXXXX`. That is semantically identical JSON — every parser
   decodes it to the same string — so the safe form costs nothing and the
   unsafe form does not exist. U+2028 and U+2029 are escaped for the same
   reason: they terminate a JavaScript string literal even though JSON permits
   them raw.

   DISCLOSED LENIENCY OF THE ORACLE. Yojson ACCEPTS a raw control character
   inside a string, which RFC 8259 forbids. That does not weaken the round-trip
   (this encoder never emits one — `LAW NO-RAW-CONTROL` proves it), but it means
   `reencode_json_bytes` will admit a file this module would not itself produce.
   Stated here rather than discovered later.

   Scope: encoding only. No IO, no HTML. The caller decides where the bytes go. *)

type t =
  | Null
  | Bool of bool
  | Int of int
  | Float of float
  | Str of string
  | Arr of t list
  | Obj of (string * t) list

(* ---------- the escaping, which is the whole point ---------------------- *)

let escape_into buf s =
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    (match c with
     | '"' -> Buffer.add_string buf "\\\""
     | '\\' -> Buffer.add_string buf "\\\\"
     | '\b' -> Buffer.add_string buf "\\b"
     | '\012' -> Buffer.add_string buf "\\f"
     | '\n' -> Buffer.add_string buf "\\n"
     | '\r' -> Buffer.add_string buf "\\r"
     | '\t' -> Buffer.add_string buf "\\t"
     (* The script-context set. Escaping any ONE of these would be enough to
        stop an end-script tag, but all three are escaped so that no HTML
        construct — a comment open, a nested script open, an entity — can be
        spelled inside a JSON string at all. *)
     | '<' -> Buffer.add_string buf "\\u003c"
     | '>' -> Buffer.add_string buf "\\u003e"
     | '&' -> Buffer.add_string buf "\\u0026"
     | c when Char.code c < 0x20 ->
         Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
     | c ->
         (* U+2028 LINE SEPARATOR / U+2029 PARAGRAPH SEPARATOR are valid in a
            JSON string but terminate a JavaScript string literal. UTF-8:
            e2 80 a8 / e2 80 a9. *)
         if Char.code c = 0xe2 && !i + 2 < n
            && Char.code s.[!i + 1] = 0x80
            && (Char.code s.[!i + 2] = 0xa8 || Char.code s.[!i + 2] = 0xa9)
         then begin
           Buffer.add_string buf
             (if Char.code s.[!i + 2] = 0xa8 then "\\u2028" else "\\u2029");
           i := !i + 2
         end
         else Buffer.add_char buf c);
    incr i
  done

(* JSON has no NaN and no infinity. Emitting `null` for them is the only
   truthful option — the alternative is a token no parser accepts. This is the
   ONE case where the round-trip does not hold, and `LAW NON-FINITE-IS-NULL`
   states it rather than leaving it to be discovered.

   The trailing `.0` matters and is not cosmetic. Without it an integral float
   encodes as `10000000000`, which every JSON reader — Yojson included —
   recovers as an INTEGER. The round-trip law caught exactly that, and Yojson
   itself emits `10000000000.0` for the same value, so this now agrees with the
   oracle's own convention. *)
let float_to_string f =
  if not (Float.is_finite f) then "null"
  else
    let shortest =
      let s = Printf.sprintf "%.15g" f in
      if float_of_string s = f then s else Printf.sprintf "%.17g" f
    in
    let looks_float =
      String.exists (fun c -> c = '.' || c = 'e' || c = 'E' || c = 'n') shortest
    in
    if looks_float then shortest else shortest ^ ".0"

let rec write buf = function
  | Null -> Buffer.add_string buf "null"
  | Bool true -> Buffer.add_string buf "true"
  | Bool false -> Buffer.add_string buf "false"
  | Int i -> Buffer.add_string buf (string_of_int i)
  | Float f -> Buffer.add_string buf (float_to_string f)
  | Str s ->
      Buffer.add_char buf '"';
      escape_into buf s;
      Buffer.add_char buf '"'
  | Arr xs ->
      Buffer.add_char buf '[';
      List.iteri (fun i x -> if i > 0 then Buffer.add_char buf ','; write buf x) xs;
      Buffer.add_char buf ']'
  | Obj kvs ->
      Buffer.add_char buf '{';
      List.iteri
        (fun i (k, v) ->
          if i > 0 then Buffer.add_char buf ',';
          Buffer.add_char buf '"';
          escape_into buf k;
          Buffer.add_string buf "\":";
          write buf v)
        kvs;
      Buffer.add_char buf '}'

let to_string (v : t) : string =
  let buf = Buffer.create 1024 in
  write buf v;
  Buffer.contents buf

(* The same writer over Yojson's tree, so bytes that arrive from OUTSIDE can be
   re-emitted with this module's guarantees WITHOUT a lossy trip through `t`.
   `Intlit` — an integer too large for OCaml's int — is preserved as its own
   literal rather than being coerced to a float, which converting through `t`
   would have silently done. *)
let rec write_yojson buf (y : Yojson.Safe.t) =
  match y with
  | `Null -> Buffer.add_string buf "null"
  | `Bool true -> Buffer.add_string buf "true"
  | `Bool false -> Buffer.add_string buf "false"
  | `Int i -> Buffer.add_string buf (string_of_int i)
  | `Intlit s -> Buffer.add_string buf s
  | `Float f -> Buffer.add_string buf (float_to_string f)
  | `String s ->
      Buffer.add_char buf '"';
      escape_into buf s;
      Buffer.add_char buf '"'
  | `List xs ->
      Buffer.add_char buf '[';
      List.iteri (fun i x -> if i > 0 then Buffer.add_char buf ','; write_yojson buf x) xs;
      Buffer.add_char buf ']'
  | `Assoc kvs ->
      Buffer.add_char buf '{';
      List.iteri
        (fun i (k, v) ->
          if i > 0 then Buffer.add_char buf ',';
          Buffer.add_char buf '"';
          escape_into buf k;
          Buffer.add_string buf "\":";
          write_yojson buf v)
        kvs;
      Buffer.add_char buf '}'

(* the projection into the oracle's own representation, so the round-trip law
   compares values rather than bytes *)
let rec to_yojson (v : t) : Yojson.Safe.t =
  match v with
  | Null -> `Null
  | Bool b -> `Bool b
  | Int i -> `Int i
  | Float f -> if Float.is_finite f then `Float f else `Null
  | Str s -> `String s
  | Arr xs -> `List (List.map to_yojson xs)
  | Obj kvs -> `Assoc (List.map (fun (k, x) -> (k, to_yojson x)) kvs)

(* ---------- admission of bytes we did not write ------------------------- *)

(* Embed JSON that arrived as BYTES (a generated file on disk). It is parsed by
   Yojson and RE-EMITTED by this module's writer rather than pasted, so the
   output carries the escaping guarantees regardless of how the file was
   written. A file that does not parse is rejected: embedding unvalidated bytes
   into a script element is exactly the hazard this module removes, so it fails
   closed. *)
let reencode_json_bytes (raw : string) : (string, string) result =
  match Yojson.Safe.from_string raw with
  | y ->
      let buf = Buffer.create (String.length raw + 64) in
      write_yojson buf y;
      Ok (Buffer.contents buf)
  | exception Yojson.Json_error m -> Error m
  | exception _ -> Error "malformed JSON"

(* the same, keeping the parsed value so a caller can inspect its shape *)
let parse_yojson (raw : string) : (Yojson.Safe.t, string) result =
  match Yojson.Safe.from_string raw with
  | y -> Ok y
  | exception Yojson.Json_error m -> Error m
  | exception _ -> Error "malformed JSON"

let yojson_to_script_json (y : Yojson.Safe.t) : string =
  let buf = Buffer.create 1024 in
  write_yojson buf y;
  Buffer.contents buf
