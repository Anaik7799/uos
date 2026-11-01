(* Unicode-aware corpus generator for the differential oracle.

   The ASCII generator deliberately removed the byte/grapheme question. This one
   puts it back, and the design question recorded as a limit — "what does it
   sample, scalars, graphemes or bytes?" — is answered by sampling *units from
   named categories* and letting the oracle report where the two engines
   disagree, rather than by picking one notion up front.

   Categories, with their scalar and grapheme counts, which is the whole point:

     ascii          1 scalar  / 1 grapheme
     precomposed    1 scalar  / 1 grapheme   (e.g. U+00E4)
     combining      2 scalars / 1 grapheme   (e.g. 'e' U+0301)
     astral         1 scalar  / 1 grapheme   (e.g. U+1F600)
     regional       2 scalars / 1 grapheme   (flag: two regional indicators)
     zwj            5 scalars / 1 grapheme   (family: emoji ZWJ emoji ZWJ emoji)

   Forecast H2 predicts at least one divergence beyond the known offset class.

   OCaml per the repository helper-language rule. Deterministic: reproducible
   from (seed, count). *)

let state = ref 0

let next () =
  state := (1103515245 * !state + 12345) land 0x3FFFFFFF;
  !state

(* High bits: the low bits of this LCG have very short periods. *)
let pick n = ((next ()) lsr 12) mod n

type unit_kind = Ascii | Precomposed | Combining | Astral | Regional | Zwj

let kind_name = function
  | Ascii -> "ascii" | Precomposed -> "precomposed" | Combining -> "combining"
  | Astral -> "astral" | Regional -> "regional" | Zwj -> "zwj"

(* UTF-8 byte sequences, written out so the file has no encoding ambiguity. *)
let units_of = function
  | Ascii       -> [| "a"; "b"; "c" |]
  | Precomposed -> [| "\xc3\xa4"; "\xc3\xa9"; "\xc3\xb1" |]          (* ä é ñ *)
  | Combining   -> [| "e\xcc\x81"; "a\xcc\x88"; "o\xcc\x83" |]       (* e+́ a+̈ o+̃ *)
  | Astral      -> [| "\xf0\x9f\x98\x80"; "\xf0\x9f\x9a\x80" |]      (* 😀 🚀 *)
  | Regional    -> [| "\xf0\x9f\x87\xac\xf0\x9f\x87\xa7";            (* 🇬🇧 *)
                      "\xf0\x9f\x87\xaf\xf0\x9f\x87\xb5" |]          (* 🇯🇵 *)
  | Zwj         -> [| "\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7" |]
                                                                      (* 👨‍👩‍👧 *)

let all_kinds = [| Ascii; Precomposed; Combining; Astral; Regional; Zwj |]

(* A word of n units drawn from one chosen category, so each case has a clear
   category label and a divergence points at a category rather than a soup. *)
let rand_word kind lo hi =
  let pool = units_of kind in
  let n = lo + pick (hi - lo + 1) in
  let b = Buffer.create 32 in
  for _ = 1 to n do Buffer.add_string b pool.(pick (Array.length pool)) done;
  Buffer.contents b

let () =
  let seed = int_of_string Sys.argv.(1) in
  let count = int_of_string Sys.argv.(2) in
  state := seed;
  for _ = 1 to count do
    let kind = all_kinds.(pick (Array.length all_kinds)) in
    (* Seeds stay short: these units are up to 25 bytes each, and the engine's
       seed guard is 128 bytes. *)
    let s = rand_word kind 1 3 in
    let nrules = 1 + pick 2 in
    let rules =
      List.init nrules (fun _ ->
        let lhs = rand_word kind 1 1 in
        (* Right-hand sides stay ASCII so a rewrite's effect is legible and the
           result length cannot explode past the 256-byte per-state bound. *)
        let rhs = if pick 4 = 0 then "" else rand_word Ascii 1 2 in
        lhs ^ ">" ^ rhs)
    in
    let steps = 1 + pick 3 in
    (* The category is echoed as a comment-free 4th column would break the
       shared format, so it is folded into the source branch name instead:
       both harnesses ignore anything past the third tab-separated field. *)
    ignore (kind_name kind);
    Printf.printf "%s\t%s\t%d\n" s (String.concat "," rules) steps
  done
