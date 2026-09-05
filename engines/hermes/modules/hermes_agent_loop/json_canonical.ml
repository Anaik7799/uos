(* The canonical wire form of a JSON value — a faithful OCaml reproduction of
   the frozen loop's json.dumps(json.loads(s), separators=(",",":"),
   sort_keys=True) with CPython's defaults:

     - object keys sorted (UTF-8 byte order IS code-point order, so
       String.compare matches Python's sort);
     - duplicate keys collapse LAST-wins, as json.loads does before dumps
       ever sees the object;
     - compact separators, no spaces;
     - ensure_ascii: every non-ASCII character is a \uXXXX escape (lowercase
       hex, astral characters as surrogate pairs), control characters use
       json.dumps's shorthands (\n \t \r \b \f) then \u00xx;
     - ints print as ints. Floats are NOT reproduced (Python repr vs OCaml
       float formatting is a genuine cross-language swamp); the measuring
       scenario's domain excludes them, and this emitter prints them via
       Yojson only so out-of-domain input fails loudly in comparison rather
       than crashing. *)

let escape_string buffer text =
  Buffer.add_char buffer '"';
  let add_u cp = Buffer.add_string buffer (Printf.sprintf "\\u%04x" cp) in
  let length = String.length text in
  let rec go i =
    if i < length then begin
      let byte = Char.code text.[i] in
      if byte < 0x80 then begin
        (match text.[i] with
         | '"' -> Buffer.add_string buffer "\\\""
         | '\\' -> Buffer.add_string buffer "\\\\"
         | '\n' -> Buffer.add_string buffer "\\n"
         | '\t' -> Buffer.add_string buffer "\\t"
         | '\r' -> Buffer.add_string buffer "\\r"
         | '\b' -> Buffer.add_string buffer "\\b"
         | '\012' -> Buffer.add_string buffer "\\f"
         | c when byte < 0x20 -> ignore c; add_u byte
         | c -> Buffer.add_char buffer c);
        go (i + 1)
      end
      else if byte < 0xE0 && i + 1 < length then begin
        (* 2-byte sequence *)
        add_u (((byte land 0x1F) lsl 6) lor (Char.code text.[i + 1] land 0x3F));
        go (i + 2)
      end
      else if byte < 0xF0 && i + 2 < length then begin
        (* 3-byte sequence — includes WTF-8-encoded lone surrogates, which
           escape to the same \udxxx form json.dumps produces for them *)
        add_u
          (((byte land 0x0F) lsl 12)
          lor ((Char.code text.[i + 1] land 0x3F) lsl 6)
          lor (Char.code text.[i + 2] land 0x3F));
        go (i + 3)
      end
      else if i + 3 < length then begin
        (* 4-byte sequence: astral plane, emitted as a surrogate pair *)
        let cp =
          ((byte land 0x07) lsl 18)
          lor ((Char.code text.[i + 1] land 0x3F) lsl 12)
          lor ((Char.code text.[i + 2] land 0x3F) lsl 6)
          lor (Char.code text.[i + 3] land 0x3F)
        in
        let reduced = cp - 0x10000 in
        add_u (0xD800 lor (reduced lsr 10));
        add_u (0xDC00 lor (reduced land 0x3FF));
        go (i + 4)
      end
      else
        (* truncated tail: emit the byte as an escape so the divergence is
           visible instead of producing invalid output silently *)
        (add_u byte; go (i + 1))
    end
  in
  go 0;
  Buffer.add_char buffer '"'

let rec write buffer (value : Yojson.Safe.t) =
  match value with
  | `Null -> Buffer.add_string buffer "null"
  | `Bool true -> Buffer.add_string buffer "true"
  | `Bool false -> Buffer.add_string buffer "false"
  | `Int n -> Buffer.add_string buffer (string_of_int n)
  | `Intlit literal -> Buffer.add_string buffer literal
  | `Float f ->
      (* out of the measured domain; see the header *)
      Buffer.add_string buffer (Yojson.Safe.to_string (`Float f))
  | `String text -> escape_string buffer text
  | `List items ->
      Buffer.add_char buffer '[';
      List.iteri
        (fun index item ->
          if index > 0 then Buffer.add_char buffer ',';
          write buffer item)
        items;
      Buffer.add_char buffer ']'
  | `Assoc fields ->
      (* last-wins dedup, then sort by key *)
      let deduped =
        List.fold_left
          (fun acc (key, v) -> (key, v) :: List.remove_assoc key acc)
          [] fields
      in
      let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) deduped in
      Buffer.add_char buffer '{';
      List.iteri
        (fun index (key, v) ->
          if index > 0 then Buffer.add_char buffer ',';
          escape_string buffer key;
          Buffer.add_char buffer ':';
          write buffer v)
        sorted;
      Buffer.add_char buffer '}'

let to_wire value =
  let buffer = Buffer.create 256 in
  write buffer value;
  Buffer.contents buffer

(* The full frozen round-trip: parse the arguments string, emit canonically.
   Raises on malformed input exactly as json.loads does — the frozen caller
   falls back to a repair pass this module deliberately does not model. *)
let canonicalize_arguments arg_str = to_wire (Yojson.Safe.from_string arg_str)
