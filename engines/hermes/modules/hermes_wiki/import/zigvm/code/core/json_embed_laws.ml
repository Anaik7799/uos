(* Laws for the JSON embedding algebra.

   The specification is the ROUND-TRIP against Yojson: an encoder is right when
   a reader that shares NONE of its code recovers exactly what the writer meant.
   Everything else here is about the second guarantee — that the bytes are inert
   inside a script element — which round-tripping alone does not give you,
   because `{"x":"</script>"}` is perfectly valid JSON, round-trips perfectly,
   and still ends the element. *)

module J = Json_embed

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl > 0 && go 0

(* Every byte a string field can carry that has ever mattered: the script
   terminator, an HTML comment open, a quote, a backslash, a raw newline and
   tab, a NUL, and the two JavaScript line terminators. *)
let hostile = "</script><!--\"\\\n\t\000 & > < \226\128\168\226\128\169 é"

let corpus =
  [ J.Null; J.Bool true; J.Bool false; J.Int 0; J.Int (-42); J.Int 1073741823;
    J.Float 0.5; J.Float (-1.25); J.Float 1e10; J.Float 3.0;
    J.Str ""; J.Str "plain"; J.Str hostile;
    J.Arr []; J.Arr [ J.Int 1; J.Str hostile; J.Null ];
    J.Obj []; J.Obj [ ("k", J.Str hostile); (hostile, J.Int 7) ];
    J.Obj [ ("nested", J.Arr [ J.Obj [ ("deep", J.Str hostile) ] ]) ] ]

(* a seeded generator, so a failure names the seed that produced it *)
let gen seed =
  let st = ref seed in
  let next () = st := (!st * 1103515245 + 12345) land 0x3FFFFFFF; !st in
  let pick n = next () mod n in
  let str () =
    let alphabet =
      [| "a"; "</script>"; "\""; "\\"; "\n"; "&"; "<"; ">"; "\000"; "\226\128\168"; "ü" |]
    in
    let len = pick 4 in
    let b = Buffer.create 16 in
    for _ = 1 to len do Buffer.add_string b alphabet.(pick (Array.length alphabet)) done;
    Buffer.contents b
  in
  let rec go depth =
    match pick (if depth > 2 then 5 else 7) with
    | 0 -> J.Null
    | 1 -> J.Bool (pick 2 = 0)
    | 2 -> J.Int (pick 100000 - 50000)
    | 3 -> J.Float (float_of_int (pick 1000) /. 8.)
    | 4 -> J.Str (str ())
    | 5 -> J.Arr (List.init (pick 4) (fun _ -> go (depth + 1)))
    | _ -> J.Obj (List.init (pick 4) (fun _ -> (str (), go (depth + 1))))
  in
  go 0

(* THE ORACLE. Yojson parses; this module wrote. No shared code. *)
let oracle_recovers v =
  match Yojson.Safe.from_string (J.to_string v) with
  | y -> y = J.to_yojson v
  | exception _ -> false

let run () : (string * bool) list =
  let out = ref [] in
  let check name ok = out := (name, ok) :: !out in

  (* LAW ROUND-TRIP — the specification, against an INDEPENDENT reader. *)
  check "LAW ROUND-TRIP: Yojson recovers exactly what this encoder wrote"
    (List.for_all oracle_recovers corpus);

  (* The case the round-trip law actually caught: `Float 1e10` encoded as
     `10000000000`, which every JSON reader recovers as an INTEGER, silently
     changing the value's type. Yojson emits `10000000000.0` for the same
     value, so the encoder now agrees with the oracle's own convention. *)
  check "LAW FLOAT-STAYS-FLOAT: an integral float does not come back an integer"
    (oracle_recovers (J.Float 1e10) && oracle_recovers (J.Float 3.0)
    && Yojson.Safe.from_string (J.to_string (J.Int 3)) = `Int 3);
  (* The ONE documented case where the round-trip does NOT hold, stated rather
     than left to be discovered: JSON has no NaN and no infinity. *)
  check "LAW NON-FINITE-IS-NULL: NaN and infinity encode as null, and it is disclosed"
    (J.to_string (J.Float nan) = "null" && J.to_string (J.Float infinity) = "null"
    && Yojson.Safe.from_string (J.to_string (J.Float nan)) = `Null);

  (* LAW SCRIPT-INERT — the guarantee round-tripping does NOT give. A value
     carrying an end-script tag is valid JSON and would still close the element;
     the encoder must make that unspellable. *)
  check "LAW SCRIPT-INERT: no encoding contains a raw <, > or &"
    (List.for_all
       (fun v ->
         let s = J.to_string v in
         (not (String.contains s '<')) && (not (String.contains s '>'))
         && not (String.contains s '&'))
       corpus);
  check "LAW NO-SCRIPT-CLOSE: an end-script tag inside a string cannot survive"
    (let s = J.to_string (J.Obj [ ("x", J.Str "</script><script>alert(1)</script>") ]) in
     (not (contains s "</script")) && not (contains s "<script"));
  (* Non-vacuity: the payload must be PRESENT, escaped — an encoder that dropped
     string contents entirely would satisfy both laws above. *)
  check "GUARD NON-VACUOUS: the payload is encoded, not discarded"
    (let s = J.to_string (J.Str "</script>") in
     contains s "\\u003c" && contains s "script"
     && Yojson.Safe.from_string s = `String "</script>");

  (* LAW NO-RAW-CONTROL — a raw byte below 0x20 is illegal inside a JSON string.
     The old hand-escaper handled backslash and quote and nothing else, so a
     node name containing a newline produced invalid JSON.

     Note this is a law about the ENCODER, not the reader: Yojson ACCEPTS a raw
     control character on input. The encoder is the stricter of the two, which
     is the right direction. *)
  check "LAW NO-RAW-CONTROL: no encoding contains a raw byte below 0x20"
    (List.for_all
       (fun v ->
         let s = J.to_string v in
         let bad = ref false in
         String.iter (fun c -> if Char.code c < 0x20 then bad := true) s;
         not !bad)
       corpus);

  (* LAW JS-LINE-TERMINATORS — U+2028/U+2029 are legal in JSON and terminate a
     JavaScript string literal. Valid JSON is not automatically valid JS source. *)
  check "LAW JS-LINE-TERMINATORS: U+2028 and U+2029 are escaped"
    (let s = J.to_string (J.Str "a\226\128\168b\226\128\169c") in
     contains s "\\u2028" && contains s "\\u2029"
     && (not (contains s "\226\128\168"))
     && Yojson.Safe.from_string s = `String "a\226\128\168b\226\128\169c");

  (* Seeded fuzz over both guarantees. A failure reports the seed. *)
  let fuzz_bad = ref (-1) and fuzz_unsafe = ref (-1) in
  for seed = 1 to 400 do
    let v = gen seed in
    let s = J.to_string v in
    if (not (oracle_recovers v)) && !fuzz_bad < 0 then fuzz_bad := seed;
    if (String.contains s '<' || String.contains s '>' || String.contains s '&')
       && !fuzz_unsafe < 0
    then fuzz_unsafe := seed
  done;
  if !fuzz_bad >= 0 then
    Printf.printf "        json-embed FUZZ round-trip failed at seed %d\n" !fuzz_bad;
  if !fuzz_unsafe >= 0 then
    Printf.printf "        json-embed FUZZ script-inert failed at seed %d\n" !fuzz_unsafe;
  check "LAW FUZZ-ROUND-TRIP: 400 seeded values survive the oracle" (!fuzz_bad < 0);
  check "LAW FUZZ-SCRIPT-INERT: 400 seeded values encode with no raw markup byte"
    (!fuzz_unsafe < 0);

  (* LAW REENCODE-FAIL-CLOSED — bytes from disk are parsed and re-emitted, never
     pasted. A file that does not parse is REJECTED. *)
  check "LAW REENCODE-FAIL-CLOSED: unparseable bytes are rejected, not embedded"
    (List.for_all
       (fun bad -> match J.reencode_json_bytes bad with Error _ -> true | Ok _ -> false)
       [ "{ this is not json }"; ""; "{"; "tru"; "01"; "[1,]"; "{} trailing"; "\"\\q\"" ]);
  check "LAW REENCODE-SANITISES: a parseable file with an end-script tag is neutralised"
    (match J.reencode_json_bytes "{\"t\":\"</script>\"}" with
     | Ok s ->
         (not (contains s "</script"))
         && Yojson.Safe.from_string s = `Assoc [ ("t", `String "</script>") ]
     | Error _ -> false);
  (* Big integers survive admission. Converting through the typed carrier would
     have coerced an `Intlit` to a float and silently lost precision; the writer
     walks Yojson's tree directly so it does not. *)
  check "LAW REENCODE-PRESERVES-BIGINT: an integer beyond OCaml's int is not coerced"
    (match J.reencode_json_bytes "{\"n\":123456789012345678901234567890}" with
     | Ok s -> contains s "123456789012345678901234567890"
     | Error _ -> false);

  List.rev !out
